module SAD (
    input  logic  clk,
    input  logic  rst,

    // SAD computation interface signals
    input  logic  write_fire,
    input  logic  signed [31:0] data_in,
    input  logic  sad_valid,
    input  logic  signed [31:0] ref_in,
    output logic  sad_ready,
    output logic  sad_done,
    output logic  count_at_30,

    // MMIO defines the sad_threshold (can be set by HPS), read by SAD module
    input logic [19:0] sad_threshold
);
    //////////////////// Internal synchronous FIFO ////////////////////
    // FIFO capacity (8 entries)
    logic signed [31:0] fifo_data [0:7];

    // FIFO write and read pointers
    logic [3:0] wr_ptr;
    logic [3:0] rd_ptr;

    // FIFO to downstream logic interface
    logic signed [31:0] fifo_data_out;
    logic fifo2sad_ready;
    logic fifo2sad_valid;

    // FIFO to upstream logic interface
    logic fifo2wrapper_ready;

    // FIFO status signals
    logic fifo_full;
    logic fifo_empty;

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 4'd0;
            rd_ptr <= 4'd0;
        end
        else begin
            if (write_fire) begin
                fifo_data[wr_ptr[2:0]] <= data_in;
                wr_ptr <= wr_ptr + 4'd1;
            end

            if (fifo2sad_valid && fifo2sad_ready) rd_ptr <= rd_ptr + 4'd1;
        end
    end
    
    assign fifo_full = (wr_ptr[3] == ~rd_ptr[3]) && (wr_ptr[2:0] == rd_ptr[2:0]);
    assign fifo_empty = wr_ptr == rd_ptr;
    assign fifo2wrapper_ready = !fifo_full;  // FIFO is not full, upstream logic can write data
    assign fifo2sad_valid = !fifo_empty;  // FIFO is not empty, downstream logic can read data
    assign fifo_data_out = fifo_data[rd_ptr[2:0]];

    // Connect the FIFO control signals to the interface
    assign sad_ready = fifo2wrapper_ready;
    assign fifo2sad_ready = sad_valid;

    //////////////////// SAD operation ////////////////////
    logic signed [31:0] reg_A, reg_B;  // Register data_in to reg_A and ref_in to reg_B for SAD computation
    logic [19:0] tp_out;  // Accumulated absolute difference for the SAD computation
    logic [4:0] stable_count;  // Determine wether the accumulating 30 stable counts has been reached

    // Combinational Circuits: SAD computation for 32-bit inputs, resulting in a 20-bit absolute difference sum
    logic signed [8:0] rs0, rs1, rs2, rs3;  // signed numbers for each 8-bit of reg_A minus reg_B, extended by 1 bit for sign
    logic [19:0] d_in;  // Accumulated absolute difference for the SAD computation. First convert the signed 9-bit to unsigned, then sum them up by 4096 times.
    logic signed [20:0] sad_out;  // Signed output of the SAD computation, representing the difference between the accumulated absolute difference and the SAD threshold.
    
    // Control Signals
    logic done;  // One pulse generated when the SAD computation is done (sad_cnt reaches 1024)
    logic done_d;  // Internal signal to generate done signal
    logic sad_valid_d;
    logic [10:0] sad_cnt;  // Counter for the number of SAD computations performed

    always_comb begin
        // Compute the signed differences for each 8-bit segment of reg_A and reg_B
        rs0 = $signed(reg_A[7:0]) - $signed(reg_B[7:0]);
        rs1 = $signed(reg_A[15:8]) - $signed(reg_B[15:8]);
        rs2 = $signed(reg_A[23:16]) - $signed(reg_B[23:16]);
        rs3 = $signed(reg_A[31:24]) - $signed(reg_B[31:24]);

        // Compute the accumulated absolute difference of one 32-bit word (4 bytes) for the SAD computation 
        d_in = (rs0[8] ? ~rs0 + 9'sd1 : rs0) + (rs1[8] ? ~rs1 + 9'sd1 : rs1) + 
        (rs2[8] ? ~rs2 + 9'sd1 : rs2) + (rs3[8] ? ~rs3 + 9'sd1 : rs3);

        // Compute SAD output based on the done signal. First convert the accumulated absolute difference to a signed 21-bit number, then subtract the SAD threshold.
        sad_out = done ? ($signed({1'b0, tp_out}) - $signed({1'b0, sad_threshold})) : 21'sd0;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            reg_A <= 32'sd0;
            reg_B <= 32'sd0;
            sad_valid_d <= 1'b0;
            tp_out <= 20'd0;  // temporary output reset
            stable_count <= 5'd0;  // stable_count reset
            sad_cnt <= 11'd0;
            done_d <= 1'b0;
            sad_done <= 1'b0;
        end
        else begin
            sad_valid_d <= fifo2sad_valid && sad_valid;
            sad_done <= done;

            // Update the  SAD computation counter
            if (sad_cnt < 11'd1024) begin
                if (sad_valid_d) sad_cnt <= sad_cnt + 11'd1;
            end

            if (sad_done) sad_cnt <= 11'd0;

            // Update the done_d signal
            done_d <= sad_cnt == 11'd1024;

            // Handshake with the FIFO to register the data: capture data when both valid and ready are asserted
            if (fifo2sad_valid && fifo2sad_ready) begin
                reg_A <= fifo_data_out;
                reg_B <= ref_in;
            end
            else begin
                reg_A <= 32'sd0;
                reg_B <= 32'sd0;
            end

            // SAD computation updates
            if (sad_done) tp_out <= 20'd0;
            else begin
                if (sad_valid_d) tp_out <= d_in + tp_out;
                else tp_out <= tp_out;
            end

            // Stable_count updates
            if (sad_done && count_at_30) stable_count <= 5'd0;
            else begin
                if (!done) stable_count <= stable_count;
                else begin
                    if (sad_out <= 21'sd0) stable_count <= stable_count + 5'd1;
                    else stable_count <= 5'd0;
                end
            end
        end
    end

    // Generate the one-pulse done signal when sad_cnt reaches 1024
    assign done = !done_d && (sad_cnt == 11'd1024);

    // Generate a signal indicating that the stable_count has reached 30
    assign count_at_30 = stable_count == 5'd30;
 
endmodule
