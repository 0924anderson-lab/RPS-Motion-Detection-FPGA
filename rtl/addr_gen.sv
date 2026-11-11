module addr_gen (
    input logic clk,
    input logic rst,
    input logic load_image,  // Load image enable signal
    input logic bram_sel, // BRAM select signal; 0 chooses BRAM A, 1 chooses BRAM B
    input logic cfg_wt_en,  // Configuration and weight enable signal
    input logic [1:0] load_cfg_wt,  // Load configuration and weight selector; 2'b01 for configuration, 2'b10 for weight, 2'b00 for IDLE
    input logic addr_32to16_ready,

    // Reference address generator for SAD calculation
    input logic write_fire,
    input logic [11:0] addr_in,
    input logic posedge_negedge,  // Decides refernce addresss are image A or B; 1 for image A (minus 1024), 0 for image B (plus 1024)
    input logic addr_gen_en,  // FSM tells addr_gen to start generating reference addresses

    output logic addr_32to16_valid,
    output logic bram_read_en,
    output logic [11:0] bram_read_addr,
    output logic bram_read_is_ref,
    output logic addr_gen_ready
);

    // Base addresses for different memory regions in BRAM
    localparam [11:0] CFG_BASE = 12'd0;
    localparam [11:0] WT_BASE = 12'd48;
    localparam [11:0] IMG_A_BASE = 12'd561;
    localparam [11:0] IMG_B_BASE = 12'd1585;

    // Pulse signal for loading base address
    logic base_addr_load_pulse;  
    logic base_addr_load_pulse_d;  

    // Internal address register for BRAM read operations
    logic [11:0] q_addr;
    logic [11:0] load_addr;
    logic read_en1;  // Read enable signal to BRAM for loading cfg, wt, or image data

    // Internal signal to indicate the last address to send to 32to16 block, and to reset the addr_gen
    logic [9:0] load_last_threshold;
    logic [9:0] transaction_count;
    logic addr_32to16_last;

    // Reference address generator for SAD calculation
    logic read_en2;  // Read enable signal to BRAM for reference-address data
    logic [11:0] ref_addr;

    always_ff @(posedge clk) begin
        if (rst) begin
            base_addr_load_pulse_d <= 1'b0;
            q_addr <= CFG_BASE;
            load_addr <= CFG_BASE;
            read_en1 <= 1'b0;
            addr_32to16_valid <= 1'b0;
            transaction_count <= 10'd0;

            // Initialize reference address generator signals
            ref_addr <= CFG_BASE;
            read_en2 <= 1'b0;
        end
        else begin
            // Edge-detector for base_addr_load_pulse
            base_addr_load_pulse_d <= cfg_wt_en || load_image;

            // Generate a delayed write_fire signal by one cycle
            read_en2 <= write_fire && addr_gen_en;

            // Generate reference address based on the input address and the posedge_negedge signal
            if (write_fire && addr_gen_en) begin
                if (posedge_negedge) ref_addr <= addr_in - 12'd1024;
                else ref_addr <= addr_in + 12'd1024;
            end
            else ref_addr <= CFG_BASE;

            // base_addr_load_pulse triggers loading of the base address into q_addr; 
            if (base_addr_load_pulse) begin
                case ({load_cfg_wt, bram_sel})
                    3'b01_0: q_addr <= CFG_BASE;
                    3'b10_0: q_addr <= WT_BASE;
                    3'b00_0: q_addr <= IMG_A_BASE;
                    3'b00_1: q_addr <= IMG_B_BASE;
                    default: q_addr <= CFG_BASE;
                endcase
            end
            else begin
                if (addr_32to16_last && addr_32to16_valid && addr_32to16_ready) q_addr <= CFG_BASE;
                else begin
                    if (addr_32to16_valid && addr_32to16_ready) q_addr <= q_addr + 12'd1;
                    else q_addr <= q_addr;
                end
            end

            // Only when addr_gen and 32to16 handshakes then update the BRAM read address, and enable BRAM read signal
            if (addr_32to16_valid && addr_32to16_ready) begin
                load_addr <= q_addr;
                read_en1 <= 1'b1;
            end
            else begin
                load_addr <= CFG_BASE;
                read_en1 <= 1'b0;
            end

            // base_addr_load_pulse toggles addr_32to16_valid to 1, valid BRAM requesting address is also ready at q_addr
            if (base_addr_load_pulse) addr_32to16_valid <= 1'b1;

            // Update transaction_count based on addr_gen and 32to16 handshake
            if (addr_32to16_valid && addr_32to16_ready) transaction_count <= transaction_count + 10'd1;

             // addr_32to16_last handshake toggles addr_32to16_valid back to 0, and reset addr_gen
            if (addr_32to16_last && addr_32to16_valid && addr_32to16_ready) begin
                addr_32to16_valid <= 1'b0;
                transaction_count <= 10'd0;
            end

        end
    end

    // Combinational circuits load_last_threshold selection
    always_comb begin
        load_last_threshold = 10'd0;
        case ({load_cfg_wt, load_image})
            3'b001: load_last_threshold = 10'd1023; // No matter is loading image A or B, both are 1024 words
            3'b010: load_last_threshold = 10'd47;
            3'b100: load_last_threshold = 10'd512;
            default: load_last_threshold = 10'd0;
        endcase
    end

    // addr_32to16_last is detected when the transaction_count reaches the load_last_threshold and when addr_32to16_valid is high
    assign addr_32to16_last = addr_32to16_valid && (transaction_count == load_last_threshold);

    // base_addr_load_pulse is a one-cycle pulse generated when cfg_wt_en or load_image is asserted and base_addr_load_pulse_d is low
    assign base_addr_load_pulse = !base_addr_load_pulse_d && (cfg_wt_en || load_image); 

    // OR two read enable signals and read addresses from two systems for BRAM
    assign bram_read_en = read_en1 | read_en2;
    assign bram_read_addr = ref_addr | load_addr;

    // 0：sent to 32to16；1：sent to SAD
    assign bram_read_is_ref = read_en2;

    // Address generator is always ready for SAD calculation
    assign addr_gen_ready = 1'b1;

endmodule
