// Single-clock simple dual-port RAM: 4096 words x 32 bits.
// Quartus synthesis must be checked to confirm M10K implementation.
// Memory contents and read_data are not reset; qualify reads with rvalid.
// Avoid simultaneous read/write to the same address in this architecture.
module bram_mem (
    input  logic        clk,
    input  logic        write_en,
    input  logic [11:0] write_addr,
    input  logic [31:0] write_data,
    input  logic [3:0]  byte_en,
    input  logic        read_en,
    input  logic [11:0] read_addr,
    output logic [31:0] read_data
);

    // Memory array declaration with M10K style for Quartus synthesis
    /*
    (* ramstyle = "M10K" *) logic [31:0] mem [0:4095];

    always_ff @(posedge clk) begin
        if (write_en) begin
            for (int i = 0; i < 4; i++) begin
                if (byte_en[i])
                    mem[write_addr][8*i +: 8] <= write_data[8*i +: 8];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (read_en)
            read_data <= mem[read_addr];
    end
    */

    // 4096 words，每個 word 包含 4 個 8-bit bytes
    (* ramstyle = "M10K" *)
    logic [3:0][7:0] mem [0:4095];

    always_ff @(posedge clk) begin
        if (write_en) begin
            if (byte_en[0])
                mem[write_addr][0] <= write_data[7:0];

            if (byte_en[1])
                mem[write_addr][1] <= write_data[15:8];

            if (byte_en[2])
                mem[write_addr][2] <= write_data[23:16];

            if (byte_en[3])
                mem[write_addr][3] <= write_data[31:24];
        end

        if (read_en)
            read_data <= mem[read_addr];
    end

endmodule
