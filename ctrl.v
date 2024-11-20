module ctrl #(
    parameter IN_WIDTH = 8,
    parameter OUT_WIDTH = 16,
    parameter ROWS = 4,
    parameter COLS = 4,
    parameter MULT_LAT = 1,
    parameter ACC_LAT = 1
)(
    input clk,
    input rst,
    input stall,
    input input_rst_accumulator,
    input input_stream_out_rdy,
    output [COLS-1:0] rst_accumulator,
    output [COLS-1:0] stream_out_rdy
);

    localparam MULTIPLIER_DELAY_SLOTS = (MULT_LAT < 1 ? 2 : MULT_LAT + 1);
    wire comparator_out;

    // 1st mac accumulator rst delay 
    // the pass from comparator to rst_accumulator_reg_0 is 1 clock cycle
    reg [MULTIPLIER_DELAY_SLOTS-1:0] rst_accumulator_reg_0;
    reg [COLS-2:0] rst_accumulator_reg_1_to_rest;


    // making sure full array cycles is went through for the 1st run after reset
    // TODO: this is very specific to sync with the test bench
    assign comparator_out = input_rst_accumulator;

    // rst accumulator logic
    // Triggers reset for the accumulators in the first column, going downwards by row
    always @(posedge clk) begin
        if (rst) begin
            rst_accumulator_reg_0 <= 0;
        end
        else if (stall )begin
            rst_accumulator_reg_0[0] <= rst_accumulator_reg_0[0];
        end
        else begin
            rst_accumulator_reg_0[0] <= comparator_out;
        end
    end
    
    // Delays the reset signal based on multiplier latency by propogating the
    // signal through the register array
    generate
        genvar j;
        for (j = 1; j <= MULTIPLIER_DELAY_SLOTS-1; j = j + 1) begin: rst_accumulator_reg_gen
            always @(posedge clk) begin
                if (rst) begin
                    rst_accumulator_reg_0[j] <= 0;
                end
                else if (stall) begin
                    rst_accumulator_reg_0[j] <= rst_accumulator_reg_0[j];
                end
                else begin
                    rst_accumulator_reg_0[j] <= rst_accumulator_reg_0[j-1];
                end
            end
        end
    endgenerate

    // rst for different columns
    // First column is first to receive reset signal
    generate 
        assign rst_accumulator[0] = rst_accumulator_reg_0[MULTIPLIER_DELAY_SLOTS-1];
    endgenerate

    // Continue to propagate the reset signal from column 1 to column 2
    always @(posedge clk) begin
        if (rst) begin
            rst_accumulator_reg_1_to_rest[0] <= 0;
        end
        else if (stall) begin
            rst_accumulator_reg_1_to_rest[0] <= rst_accumulator_reg_1_to_rest[0];
        end
        else begin
            rst_accumulator_reg_1_to_rest[0] <= rst_accumulator_reg_0[MULTIPLIER_DELAY_SLOTS-1];
        end
    end


    // Propogate reset signal from column 2 to remaining columns
    generate
        genvar l;
        for (l = 1; l < COLS-1; l = l + 1) begin: rst_accumulator_out_reg_gen
            always @(posedge clk) begin
                if (rst) begin
                    rst_accumulator_reg_1_to_rest[l] <= 0;
                end
                else if (stall) begin
                    rst_accumulator_reg_1_to_rest[l] <= rst_accumulator_reg_1_to_rest[l];
                end
                else begin
                    rst_accumulator_reg_1_to_rest[l] <= rst_accumulator_reg_1_to_rest[l-1];
                end
            end
        end
    endgenerate

    // Output all the reset signals
    assign rst_accumulator[COLS-1:1] = rst_accumulator_reg_1_to_rest;

    // Stream out signaled by reset of accumulator
    reg [MULT_LAT+ACC_LAT+COLS-1:0] stream_out_rdy_delay;
    always @(posedge clk) begin
        if (rst) begin
            stream_out_rdy_delay[0] <= 0;
        end
        else if (stall) begin
            stream_out_rdy_delay[0] <= stream_out_rdy_delay[0];
        end
        else begin
            stream_out_rdy_delay[0] <= input_stream_out_rdy;
        end
    end
    generate
        for (l = 1; l < MULT_LAT+ACC_LAT+COLS; l = l + 1) begin
            always @(posedge clk) begin
                if (rst) begin
                    stream_out_rdy_delay[l] <= 0;
                end
                else if (stall) begin
                    stream_out_rdy_delay[l] <= stream_out_rdy_delay[l];
                end
                else begin
                    stream_out_rdy_delay[l] <= stream_out_rdy_delay[l-1];
                end
            end
        end
    endgenerate

    // Output stream_out_rdy signals
    reg [COLS-1:0] stream_out_rdy_reg;
    always @(posedge clk) begin
        if (rst) begin
            stream_out_rdy_reg <= 0;
        end else if (stall) begin
            stream_out_rdy_reg <= stream_out_rdy_reg;
        end else begin
            stream_out_rdy_reg <= {COLS{stream_out_rdy_delay[MULT_LAT+ACC_LAT+COLS-1]}};
        end
    end
    assign stream_out_rdy = stream_out_rdy_reg;

endmodule