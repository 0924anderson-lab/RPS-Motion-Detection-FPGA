module bram_wrapper (
    input  logic        clk,
    input  logic        rst,

    // Avalon-MM write-only slave. Set addressUnits=WORDS and
    // waitrequestAllowance=0 in Platform Designer.
    input  logic [11:0] avs_address,
    input  logic [31:0] avs_writedata,
    input  logic [3:0]  avs_byteenable,
    input  logic        avs_write,
    output logic        avs_waitrequest,

    // High when every required write-event consumer has capacity.
    // Tie high if all consumers can accept one write every cycle.
    input  logic        write_accept_ready,

    // Accepted write event, sampled on the same rising edge as RAM writes.
    // These are not buffered: consume only when write_fire is high.
    output logic        write_fire,
    output logic [11:0] write_addr,
    output logic [31:0] write_data,

    // Native read request from addr_gen; no read-side backpressure.
    input  logic        bram_read_en,
    input  logic [11:0] bram_read_addr,
    input  logic        bram_read_is_ref,
    output logic [31:0] bram_rdata,
    output logic        sad_valid,
    output logic        load_rvalid
);

    logic ram_read_en;

    assign avs_waitrequest = rst || !write_accept_ready;
    assign write_fire      = avs_write && !avs_waitrequest;
    assign write_addr      = avs_address;
    assign write_data      = avs_writedata;

    assign ram_read_en = bram_read_en && !rst;

    // Data and valid update together after the read-request clock edge.
    // A downstream always_ff captures them at the following rising edge.
    always_ff @(posedge clk) begin
        if (rst) begin
            sad_valid <= 1'b0;
            load_rvalid <= 1'b0;
        end
        else begin
            sad_valid <= ram_read_en && bram_read_is_ref;
            load_rvalid <= ram_read_en && !bram_read_is_ref;
        end
    end

    bram_mem u_bram_mem (
        .clk        (clk),
        .write_en   (write_fire),
        .write_addr (avs_address),
        .write_data (avs_writedata),
        .byte_en    (avs_byteenable),
        .read_en    (ram_read_en),
        .read_addr  (bram_read_addr),
        .read_data  (bram_rdata)
    );

endmodule
