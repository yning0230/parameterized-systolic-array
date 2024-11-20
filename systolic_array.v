module systolic_array #(
    parameter IN_WIDTH          = 8,
    parameter IN_FRAC           = 0,
    parameter OUT_WIDTH         = 8,
    parameter OUT_FRAC          = 0,
    parameter MULT_LAT          = 3,                 // Multiplication latency
    parameter ACC_LAT           = 1,                 // Addition latency (<=1, not support pipelined acc)
    parameter ROWS              = 4,                 // Row number of systolic array
    parameter K                 = 4,
    parameter COLS              = 4                  // Column number of systolic array
)(
    input                       clk,
    input                       rst,
    input                       en,
    input                       flush,               // If 1, flush the pipeline
    input                       rst_accumulator_rdy, // If 1, reset accumulator in array
    input                       stream_out_rdy,      // If 1, stream acc result out
    input [IN_WIDTH*ROWS-1:0]   row_data_in,         // AXIS row_data_in
    input                       row_data_in_vld,
    output                      row_data_in_rdy,
    input [IN_WIDTH*COLS-1:0]   col_data_in,         // AXIS col_data_in
    input                       col_data_in_vld,
    output                      col_data_in_rdy,
    output [OUT_WIDTH*ROWS-1:0] row_data_out,        // AXIS row_data_out
    output                      row_data_out_vld,
    input                       row_data_out_rdy
);
    
    // rst_accumulator wires 
    wire            rst_accumulator_in  [0:ROWS][0:COLS];
    wire            rst_accumulator_out [0:ROWS][0:COLS];
    wire [COLS-1:0] control_rst_accumulator_rdy;
    
    // stream_out_rdy wires
    wire            stream_out_rdy_in   [0:ROWS][0:COLS];
    wire            stream_out_rdy_out  [0:ROWS][0:COLS];
    wire [COLS-1:0] control_stream_out_rdy;

    // row data for macs [column number][row number]
    // data starts from first column and propogates through columns
    // cannot use COLS-1 or ROWS-1 as for multiples of 4, will wrap around and overrite first value
    wire [IN_WIDTH-1:0] mac_row_data_in  [0:COLS][0:ROWS];
    wire [IN_WIDTH-1:0] mac_row_data_out [0:COLS][0:ROWS];

    // column data for macs [row number][column number]
    // data starts from first row and propogates through rows
    // cannot use COLS-1 or ROWS-1 as for multiples of 4, will wrap around and overrite first value
    wire [IN_WIDTH-1:0] mac_col_data_in  [0:ROWS][0:COLS];
    wire [IN_WIDTH-1:0] mac_col_data_out [0:ROWS][0:COLS];

    // wires for bypass data [row number][column number]
    // only needed between rows and columns, last one not used
    // cannot use COLS-1 or ROWS-1 as for multiples of 4, will wrap around and overrite first value
    wire  [IN_WIDTH-1:0] bypass_data_in      [0:ROWS][0:COLS];
    wire                 bypass_data_in_vld  [0:ROWS][0:COLS];
    wire [OUT_WIDTH-1:0] bypass_data_out     [0:ROWS][0:COLS];
    wire                 bypass_data_out_vld [0:ROWS][0:COLS];

    wire                 mac_array_full_flag [0:ROWS][0:COLS];
    wire                 flag_found;

    wire [ROWS*COLS-1:0] flat_array;

    genvar i, j;
    generate
        for (i = 0; i < ROWS; i = i + 1) begin
            for (j = 0; j < COLS; j = j + 1) begin
                assign flat_array[i*COLS + j] = mac_array_full_flag[i][j];
            end
        end
    endgenerate

    // Apply the reduction OR operator to the flattened array
    assign flag_found = |flat_array;

    // wires receiving bypass data
    wire           [ROWS-1:0] row_data_out_tmp_vld;
    wire [OUT_WIDTH*ROWS-1:0] row_data_out_tmp;
    
    // input fifo queue signals
    wire                      fifoin_a_full;
    wire                      fifoin_a_half_full;
    wire                      fifoin_a_empty;
    wire                      fifoin_b_full; 
    wire                      fifoin_b_half_full;
    wire                      fifoin_b_empty;
    
    // output fifo queue signals
    wire                      fifoout_empty [0:ROWS];
    wire                      fifoout_full  [0:ROWS];
    wire                      fifoout_half_full  [0:ROWS];
    wire [OUT_WIDTH-1:0]      fifoout_out  [0:ROWS];
    wire                      fifoout_half_full_any;
    wire  [ROWS-1:0]          fifoout_half_full_tmp;

    // input signals from input fifo queues
    wire [ROWS*IN_WIDTH-1:0] row_data_in_reg;
    wire                     row_data_in_vld_reg;
    wire [COLS*IN_WIDTH-1:0] col_data_in_reg;
    wire                     col_data_in_vld_reg;
    wire                     rst_accumulator_rdy_reg;
    wire                     stream_out_rdy_reg;
    
    // Sync row and col and consider output fifo slots which is related to row_data_out_rdy
    wire inputs_all_valid = !fifoin_a_empty && !fifoin_b_empty && row_data_in_vld_reg && col_data_in_vld_reg && !stall;
    
    // Input queue (deal with vld signals)
    synchronous_fifo #(
        .DEPTH(8),
        .DATA_WIDTH(IN_WIDTH*ROWS + 3)
    ) input_a_fifo (
        .clk(clk),
        .rst_n(rst),
        .w_en(row_data_in_vld && !fifoin_a_half_full),
        .r_en(inputs_all_valid),
        .data_in({stream_out_rdy, rst_accumulator_rdy, row_data_in_vld, row_data_in}),
        .data_out({stream_out_rdy_reg, rst_accumulator_rdy_reg, row_data_in_vld_reg, row_data_in_reg}),
        .full(fifoin_a_full),
        .half_full(fifoin_a_half_full),
        .empty(fifoin_a_empty)
    );

    // Input queue (deal with vld signals)
    synchronous_fifo #(
        .DEPTH(8),
        .DATA_WIDTH(IN_WIDTH*COLS + 1)
    ) input_b_fifo (
        .clk(clk),
        .rst_n(rst),
        .w_en(col_data_in_vld && !fifoin_b_half_full),
        .r_en(inputs_all_valid),
        .data_in({col_data_in_vld, col_data_in}),
        .data_out({col_data_in_vld_reg, col_data_in_reg}),
        .full(fifoin_b_full),
        .half_full(fifoin_b_half_full),
        .empty(fifoin_b_empty)
    );

    

    assign row_data_out_vld = &(row_data_out_tmp_vld);
    assign row_data_out     = row_data_out_tmp;
    assign fifoout_half_full_any = |(fifoout_half_full_tmp);

    assign row_data_in_rdy = !fifoin_a_half_full;
    assign col_data_in_rdy = !fifoin_b_half_full;
    
    // TODO: need to deal with high fanout
    wire stall          = !flush && (fifoout_half_full_any || flag_found);
    wire mac_read_stall = !flush && fifoout_half_full_any;

    generate
        genvar row, col;
        
        // assign row/column data
        for (row = 0; row < ROWS; row = row + 1) begin: assign_col_data_in
            for (col = 0; col < COLS; col = col + 1) begin: assign_col_data_in
                if (row == 0) begin
                    assign mac_col_data_in[0][col]     = (inputs_all_valid) ? col_data_in_reg[IN_WIDTH*col +: IN_WIDTH] : 0;
                    assign rst_accumulator_in[0][col]  = control_rst_accumulator_rdy[col];
                    assign stream_out_rdy_in[0][col]   = control_stream_out_rdy[col];
                end else begin
                    assign mac_col_data_in[row][col]     = mac_col_data_out[row-1][col];
                    assign rst_accumulator_in[row][col]  = rst_accumulator_out[row-1][col];
                    assign stream_out_rdy_in[row][col]   = stream_out_rdy_out[row-1][col];
                end
                if (col == 0) begin
                    assign mac_row_data_in[0][row] = (inputs_all_valid) ? row_data_in_reg[IN_WIDTH*row +: IN_WIDTH] : 0;
                end else begin
                    assign mac_row_data_in[col][row] = mac_row_data_out[col-1][row];
                end
                assign bypass_data_in[row][col]     = bypass_data_out[row][col+1];
                assign bypass_data_in_vld[row][col] = bypass_data_out_vld[row][col+1];
            end
          //  assign row_data_out_tmp[OUT_WIDTH*row +: OUT_WIDTH] = bypass_data_out[row][0];
          //  assign row_data_out_tmp_vld[row] = bypass_data_out_vld[row][0];
        end

        // instantiate MAC array
        for (row = 0; row < ROWS; row = row + 1) begin: instantiate_mac_rows
            for (col = 0; col < COLS; col = col + 1) begin: instantiate_mac_cols
                mac #(
                    .IN_WIDTH(IN_WIDTH),
                    .IN_FRAC(IN_FRAC),
                    .OUT_WIDTH(OUT_WIDTH),
                    .OUT_FRAC(OUT_FRAC),
                    .MULT_LAT(MULT_LAT),
                    .ADD_LAT(ACC_LAT),
                    .K(COLS - col - 1),
                    .COLS(COLS),
                    .ROWS(ROWS),
                    .COLS_IDX(col),
                    .ROWS_IDX(row),
                    .FIFO_DEPTH(2)
                ) mac (
                    .clk(clk),
                    .rst(rst),
                    .stall(stall),
                    .mac_read_stall(mac_read_stall),
                    .rst_accumulator_in(rst_accumulator_in[row][col]),
                    .stream_out_rdy_in(stream_out_rdy_in[row][col]),
                    .row_data_in(mac_row_data_in[col][row]),
                    .col_data_in(mac_col_data_in[row][col]),
                    .bypass_data_in(bypass_data_in[row][col]),
                    .bypass_data_in_vld(bypass_data_in_vld[row][col]),
                    .rst_accumulator_out(rst_accumulator_out[row][col]),
                    .stream_out_rdy_out(stream_out_rdy_out[row][col]),
                    .row_data_out(mac_row_data_out[col][row]),
                    .col_data_out(mac_col_data_out[row][col]),
                    .psum_out(bypass_data_out[row][col]),
                    .psum_out_vld(bypass_data_out_vld[row][col]),
                    .mac_full_flag(mac_array_full_flag[row][col])
                );
            end
        end

        for (row = 0; row < ROWS; row = row + 1) begin: data_out
            synchronous_fifo #(
                // if half full, still able to flush remaining stages and hold results
                    .DEPTH(2*(MULT_LAT+ACC_LAT+(COLS*ROWS/K))), // double the pipeline depth
                    .DATA_WIDTH(OUT_WIDTH)
                ) output_row_fifo (
                    .clk(clk),
                    .rst_n(rst),
                    .w_en(bypass_data_out_vld[row][0] && !fifoout_full[row] && !mac_read_stall),
                    .r_en(row_data_out_rdy && !fifoout_empty[row] && &(row_data_out_tmp_vld)),
                    .data_in(bypass_data_out[row][0]),
                    .data_out(fifoout_out[row]),
                    .full(fifoout_full[row]),
                    .half_full(fifoout_half_full[row]),
                    .empty(fifoout_empty[row])
                );
            assign row_data_out_tmp[OUT_WIDTH*row +: OUT_WIDTH] = fifoout_out[row];
            assign row_data_out_tmp_vld[row] = !fifoout_empty[row];
            assign fifoout_half_full_tmp[row] = fifoout_half_full[row];
        end
    endgenerate

    


    // generate rst accmulator and bypass enable control signals
    ctrl #(
        .IN_WIDTH(IN_WIDTH),
        .OUT_WIDTH(OUT_WIDTH),
        .ROWS(ROWS),
        .COLS(COLS),
        .MULT_LAT(MULT_LAT),
        .ACC_LAT(ACC_LAT)
    ) ctrl_0(
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .input_rst_accumulator(rst_accumulator_rdy_reg && inputs_all_valid),
        .input_stream_out_rdy(stream_out_rdy_reg && inputs_all_valid),
        .rst_accumulator(control_rst_accumulator_rdy),
        .stream_out_rdy(control_stream_out_rdy)
    );


    // // Debug
    // always @(posedge clk) begin
    //     $display("----------------------------");
    //     $display("output (fifo stat: %b %b %b, w:%d, r:%d, hs: %d, diff: %d, %x) row_out (%d %b %x, %d %x) input: (%x %d %x %d)", 
    //         fifoout_half_full, fifoout_full, fifoout_empty, output_fifo.w_ptr, output_fifo.r_ptr, 
    //         output_fifo.half_size, output_fifo.difference, output_fifo.data_out, 
    //         row_data_out_rdy, row_data_out_tmp_vld, row_data_out_tmp, row_data_out_vld, row_data_out,
    //         row_data_in, row_data_in_vld, col_data_in, col_data_in_vld);
    //     $display("Input: rst: %b -> %b, out: %b -> %b, row_vld: %d, col_vld: %d", 
    //         rst_accumulator_rdy, control_rst_accumulator_rdy, stream_out_rdy, control_stream_out_rdy, 
    //         row_data_in_vld, col_data_in_vld);
    // end

    // generate
    //     genvar x,y;
    //     for (x = 0; x < ROWS; x=x+1) begin
    //         for (y = 0; y < COLS; y=y+1) begin
    //             always @(posedge clk) begin
    //                 $write("(%02d, %02d, %d %d, %d %d) %s", 
    //                     mac_row_data_in[y][x], 
    //                     mac_col_data_in[x][y], 
    //                     rst_accumulator_in[x][y],
    //                     stream_out_rdy_in[x][y],
    //                     bypass_data_out[x][y],
    //                     bypass_data_out_vld[x][y],
    //                     y==COLS-1 ? "\n" : " ");
    //             end
    //         end
    //     end
    // endgenerate

endmodule
