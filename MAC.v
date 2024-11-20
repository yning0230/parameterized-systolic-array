module mac #(
    parameter IN_WIDTH = 8,
    parameter IN_FRAC = 0,
    parameter OUT_WIDTH = 8,
    parameter OUT_FRAC = 0,
    parameter MULT_LAT = 3,
    parameter ADD_LAT = 1,
    parameter K = 1,
    parameter ROWS = 1,
    parameter COLS = 1,
    parameter COLS_IDX = 1,
    parameter ROWS_IDX = 1,
    parameter FIFO_DEPTH = 2
)(
    input                      clk,
    input                      rst,
    input                      rst_accumulator_in,
    input                      stream_out_rdy_in,
    input       [IN_WIDTH-1:0] row_data_in,
    input       [IN_WIDTH-1:0] col_data_in,
    input       [IN_WIDTH-1:0] bypass_data_in, 
    input                      bypass_data_in_vld,
    input                      stall,
    input                      mac_read_stall,
    output                     mac_full_flag,
    output reg  [IN_WIDTH-1:0] row_data_out,
    output reg  [IN_WIDTH-1:0] col_data_out,
    output reg                 rst_accumulator_out,
    output reg                 stream_out_rdy_out,
    output reg [OUT_WIDTH-1:0] psum_out,
    output reg                 psum_out_vld

);

    // psum will be max possible size of K
    localparam COLS_WIDTH = $clog2(COLS);
    reg [OUT_WIDTH-1:0] psum [0:(1 << COLS_WIDTH)-1];
    reg [OUT_WIDTH-1:0] mult_out;

    wire [OUT_WIDTH-1:0]    multiplier_out;
    wire                    multiplier_done;

    wire [IN_WIDTH-1:0]     adder_in_A;
    wire [IN_WIDTH-1:0]     adder_in_B;
    wire [OUT_WIDTH-1:0]    adder_out;
    wire                    adder_done;

    wire                    fifo_full;
    wire                    fifo_empty;
    wire [OUT_WIDTH-1:0]    fifo_out;

    // Bypass controls
    wire bypass_en;
    wire [31:0] temp = COLS - 1;
    wire [$clog2(COLS)-1:0] bypass_counter_max = temp[$clog2(COLS)-1:0];
    reg  [$clog2(COLS)-1:0] bypass_counter;
    
    // Fix-point multiplier
    wire [IN_WIDTH-1:0] mul_in_A = row_data_in;
    wire [IN_WIDTH-1:0] mul_in_B = col_data_in;
    multiplier #(
        .INPUT_A_WIDTH(IN_WIDTH),
        .INPUT_B_WIDTH(IN_WIDTH),
        .INPUT_A_FRAC(IN_FRAC),
        .INPUT_B_FRAC(IN_FRAC),
        .OUTPUT_WIDTH(OUT_WIDTH),
        .OUTPUT_FRAC(OUT_FRAC),
        .DELAY(MULT_LAT)
    ) mul (
        .clk(clk),
        .reset(rst),
        .stall(stall),
        .en(~rst),
        .a_in(mul_in_A),
        .b_in(mul_in_B),
        .out(multiplier_out),
        .done(multiplier_done)
    );

    // Fix-point adder
    assign adder_in_A = mult_out;
    assign adder_in_B = (rst_accumulator_in ? '0 : adder_out);

    adder #(
        .INPUT_A_WIDTH(IN_WIDTH),
        .INPUT_B_WIDTH(IN_WIDTH),
        .INPUT_A_FRAC(IN_FRAC),
        .INPUT_B_FRAC(IN_FRAC),
        .OUTPUT_WIDTH(OUT_WIDTH),
        .OUTPUT_FRAC(OUT_FRAC),
        .DELAY(ADD_LAT)
    ) add(
        .clk(clk),
        .reset(rst),
        .stall(stall),
        .en(~rst && multiplier_done),
        .a_in(adder_in_A),
        .b_in(adder_in_B),
        .out(adder_out),
        .done(adder_done)
    );

    // Output queue
    synchronous_fifo #(
        .DEPTH(FIFO_DEPTH),
        .DATA_WIDTH(IN_WIDTH)
    ) output_fifo(
        .clk(clk),
        .rst_n(rst),
        .w_en(stream_out_rdy_in && !stall),
        .r_en(!bypass_en && !fifo_empty && !mac_read_stall),
        .data_in(psum[K]),
        .data_out(fifo_out),
        .full(fifo_full),
        .half_full(),
        .empty(fifo_empty)
    );

    assign mac_full_flag = stream_out_rdy_in & fifo_full;

    //pass the row/col/rst/stream_out data 1 clock cycle later
    always @(posedge clk) begin
        if (rst) begin
            row_data_out        <= 0;
            col_data_out        <= 0;
            rst_accumulator_out <= 0;
            stream_out_rdy_out  <= 0;
        end
        else if (stall) begin
            row_data_out        <= row_data_out;
            col_data_out        <= col_data_out;
            rst_accumulator_out <= rst_accumulator_out;
            stream_out_rdy_out  <= stream_out_rdy_out;
        end
        else begin
            row_data_out        <= row_data_in;
            col_data_out        <= col_data_in;
            rst_accumulator_out <= rst_accumulator_in;
            stream_out_rdy_out  <= stream_out_rdy_in;
        end
    end

    //mult 1 clock cycle later
    always @(posedge clk) begin
        if (rst) begin
            mult_out <= 0;
        end 
        else if (stall) begin
            mult_out <= mult_out;
        end 
        else if (multiplier_done) begin
            mult_out <= multiplier_out;
        end 
        else begin
            // mult_out <= row_data_in * col_data_in;
            mult_out <= 0;
        end
    end

    //accumulate 1 clock cycle later
    always @(posedge clk) begin
        if (rst) begin
            psum[0] <= 0;
        end
        else if (stall) begin
            psum[0] <= psum[0];
        end
        else begin
            psum[0] <= adder_out;
        end
    end

    // propagate the psum
    // The delay is to wait for all macs inside the array to be ready and is
    // determined by K.
    generate
        genvar i;
        for (i = 0; i < (1 << COLS_WIDTH) - 1; i = i + 1) begin: psum_propagate
            always @(posedge clk) begin
                if (rst) begin
                    psum[i+1] <= 0;
                end
                else if (stall) begin
                    psum[i+1] <= psum[i+1];
                end
                else begin
                    psum[i+1] <= psum[i];
                end
            end
        end
    endgenerate

    assign bypass_en = (bypass_counter != 0);

    always @(posedge clk) begin
        if (rst) begin
            bypass_counter <= '0;
        end else if (mac_read_stall) begin
            bypass_counter <= bypass_counter;
        end else if (bypass_counter == bypass_counter_max) begin
            bypass_counter <= '0;
        end else if (~fifo_empty || bypass_en) begin
            bypass_counter <= bypass_counter + 1;
        end else begin
            bypass_counter <= '0;
        end
    end


    //output the psum; if bypass_en is high, output the bypass_data_in, otherwise output the latest psum
    always @(posedge clk) begin
        if (rst) begin
            psum_out     <= '0;
            psum_out_vld <= '0;
        end
        else if (mac_read_stall) begin
            psum_out     <= psum_out;
            psum_out_vld <= psum_out_vld;
        end
        else if (!fifo_empty && !bypass_en) begin
            psum_out     <= fifo_out;
            psum_out_vld <= 1;
        end
        else if (bypass_en) begin
            psum_out     <= bypass_data_in;
            psum_out_vld <= bypass_data_in_vld;
        end else begin
            psum_out     <= '0;
            psum_out_vld <= '0;
        end
    end

endmodule
