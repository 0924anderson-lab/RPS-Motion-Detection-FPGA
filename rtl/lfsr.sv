module lfsr(
    input clk,
    input rst,
    input lfsr_en,
    output [1:0] lfsr_out
);

    logic [7:0] lfsr_state;

    always_ff @(posedge clk) begin
        if (rst) lfsr_state <= 8'h1;
        else if (lfsr_en) begin
            lfsr_state <= {lfsr_state[6:0], lfsr_state[7] ^ lfsr_state[5] ^ lfsr_state[4] ^ lfsr_state[3]};
        end
        else lfsr_state <= lfsr_state;
    end

    assign lfsr_out = 2'(lfsr_state % 8'h3); // lfsr_out will only have three conditions: 2'b00, 2'b01, 2'b10

endmodule
