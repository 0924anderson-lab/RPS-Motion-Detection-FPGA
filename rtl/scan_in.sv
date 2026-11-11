module scan_in (
    input  logic clk,
    input  logic rst,
    input  logic buf_sel,
    input  logic fpga_capture_en,
    input  logic scan_out,
    output logic accept_count_at_195,

    // MMIO 195-bit Buffer A, B, connecting to HPS, which gets the scan-out package through the bridge (32-bits)
    output logic [194:0] scan_in_buf_A, scan_in_buf_B
);

    // Counter for tracking the number of accepted scan inputs
    logic [7:0] scan_cnt;

    always_ff @(negedge clk) begin
        if (rst) begin
            scan_in_buf_A <= 195'd0;
            scan_in_buf_B <= 195'd0;
            scan_cnt <= 8'd0;
        end
        else begin
            if (fpga_capture_en && !accept_count_at_195) begin
                scan_cnt <= scan_cnt + 8'd1;

                if (!buf_sel) scan_in_buf_A <= {scan_in_buf_A[193:0], scan_out};
                else scan_in_buf_B <= {scan_in_buf_B[193:0], scan_out};
            end

            // Reset the scan_cnt when it counts at 195, which means the last bit being received.
            if (accept_count_at_195) scan_cnt <= 8'd0;
        end
    end

    assign accept_count_at_195 = (scan_cnt == 8'd195);

endmodule
