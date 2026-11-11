module core_clk_gen (
    input clk,
    input core_clk_disable,
    input fsm_ctrl,
    output core_clk
);

    logic core_clk_en;

    always_ff @(negedge clk) begin
        core_clk_en <= !core_clk_disable && !fsm_ctrl;
    end

    assign core_clk = clk & core_clk_en;

endmodule
