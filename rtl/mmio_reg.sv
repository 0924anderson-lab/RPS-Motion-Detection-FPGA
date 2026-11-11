module mmio_reg (
    input logic clk,
    input logic rst,
    output logic irq,                         // Interrupt request signal

    // Avalon-MM slave: WORDS addressing, readLatency=0,
    // waitrequestAllowance=0. All interfaces use clk.
    input logic [3:0] avs_address,
    input logic [31:0] avs_writedata,
    input logic [3:0] avs_byteenable,
    input logic avs_write,
    input logic avs_read,
    output logic [31:0] avs_readdata,
    output logic avs_waitrequest,

    // Buffers are stored by scan_in; keep each stable until HPS clears valid.
    input logic [194:0] buf_A_scan_in,
    input logic [194:0] buf_B_scan_in,

    // FSM clean signals
    input logic load_done_clean,
    input logic load_en_clean,
    input logic hps_vf_done_clean,
    input logic start_load_image_clean,
    input logic load_image_done_clean,
    input logic game_status_clean,

    // FSM write signals, used to generate pulses
    input logic game_status,
    input logic buf_A_valid,
    input logic buf_B_valid,
    input logic scan_done,
    input logic game_done,

    //////////////////////// MMIO register declarations ////////////////////////
    //////////////////////// Control registers ////////////////////////
    //// Only HPS write (byte 0)
    output logic scan_en_reg,                 // Tell FSM that scan FSM path is turned on

    //// HPS write and FSM send clean signal (byte 1)
    output logic load_done_reg,               // Tell FSM that HPS has finished loading configuration and weights
    output logic load_en_reg,                 // Tell FSM to start loading configuration and weights
    output logic hps_vf_done_reg,             // Tell FSM that HPS has finished vector field calculation
    output logic start_load_image_reg,        // Tell FSM to start loading image
    output logic load_image_done_reg,         // Tell FSM that HPS has finished loading image

    //// FSM write and HPS clean (byte 3)
    output logic buf_A_valid_reg,             // Tell HPS that scan in buffer A is valid, reset by HPS after reading
    output logic buf_B_valid_reg,             // Tell HPS that scan in buffer B is valid, reset by HPS after reading

    //////////////////////// Data registers ////////////////////////
    output logic [19:0] sad_threshold_reg     // SAD threshold
);

    ////////////////// MMIO register declarations (packaged to HPS) ////////////
    //// Only FSM write (byte 2) (pulse gen to set, and FSM clean)
    logic game_status_reg;                    // Tell HPS the current game status, 1 to stop preprocessing
    
    //// FSM write and HPS clean (byte 3)
    logic scan_ready_reg;                     // Tell HPS that scan out package is ready
    logic scan_done_reg;                      // Tell HPS that all scan packages have been read
    logic game_done_reg;                      // Tell HPS that the game has finished

    logic write_fire;

    assign avs_waitrequest = rst;
    assign write_fire = avs_write && !avs_waitrequest;

    // game status register change flag, used to generate interrupt to HPS when game status changes
    logic game_status_reg_changed_flag;
    logic game_status_reg_prev;               // Previous value of game status register, used to detect changes

    //////////////////////// Pulse generation for FSM writing ////////////////////////
    logic pulse_gen_buf_A_valid;
    logic pulse_gen_buf_B_valid;
    logic pulse_gen_scan_done;
    logic pulse_gen_game_done;
    logic pulse_gen_game_status;
    logic signal_d_buf_A_valid;
    logic signal_d_buf_B_valid;
    logic signal_d_scan_done;
    logic signal_d_game_done;
    logic signal_d_game_status;

    //////////////////////// MMIO register address schedule ////////////////////////
    localparam logic [3:0] CONTROL_ADDR = 4'd0;          // Byte 0 RW, byte 1 W1S, byte 2 RO, byte 3 W1C
    localparam logic [3:0] SAD_THRESHOLD_ADDR = 4'd1;    // Use the [19:0] of data for SAD threshold
    localparam logic [3:0] BUF_A_SCAN_IN_ADDR_0 = 4'd2;  // 32 bits of data represents for buf A [31:0]
    localparam logic [3:0] BUF_A_SCAN_IN_ADDR_1 = 4'd3;  // 32 bits of data represents for buf A [63:32]
    localparam logic [3:0] BUF_A_SCAN_IN_ADDR_2 = 4'd4;  // 32 bits of data represents for buf A [95:64]
    localparam logic [3:0] BUF_A_SCAN_IN_ADDR_3 = 4'd5;  // 32 bits of data represents for buf A [127:96]
    localparam logic [3:0] BUF_A_SCAN_IN_ADDR_4 = 4'd6;  // 32 bits of data represents for buf A [159:128]
    localparam logic [3:0] BUF_A_SCAN_IN_ADDR_5 = 4'd7;  // 32 bits of data represents for buf A [191:160]
    localparam logic [3:0] BUF_A_SCAN_IN_ADDR_6 = 4'd8;  // Only use [2:0] of data, which has 32 bits, for buf A [194:192]
    localparam logic [3:0] BUF_B_SCAN_IN_ADDR_0 = 4'd9;  // 32 bits of data represents for buf B [31:0]
    localparam logic [3:0] BUF_B_SCAN_IN_ADDR_1 = 4'd10; // 32 bits of data represents for buf B [63:32]
    localparam logic [3:0] BUF_B_SCAN_IN_ADDR_2 = 4'd11; // 32 bits of data represents for buf B [95:64]
    localparam logic [3:0] BUF_B_SCAN_IN_ADDR_3 = 4'd12; // 32 bits of data represents for buf B [127:96]
    localparam logic [3:0] BUF_B_SCAN_IN_ADDR_4 = 4'd13; // 32 bits of data represents for buf B [159:128]
    localparam logic [3:0] BUF_B_SCAN_IN_ADDR_5 = 4'd14; // 32 bits of data represents for buf B [191:160]
    localparam logic [3:0] BUF_B_SCAN_IN_ADDR_6 = 4'd15; // Only use [2:0] of data, which has 32 bits, for buf B [194:192]

    // Pulse generation for FSM writing, only one pulse per write operation
    always_ff @(posedge clk) begin
        if (rst) begin
            signal_d_buf_A_valid <= 1'b0;
            signal_d_buf_B_valid <= 1'b0;
            signal_d_scan_done <= 1'b0;
            signal_d_game_done <= 1'b0;
            signal_d_game_status <= 1'b0;
        end
        else begin
            signal_d_buf_A_valid <= buf_A_valid;
            signal_d_buf_B_valid <= buf_B_valid;
            signal_d_scan_done <= scan_done;
            signal_d_game_done <= game_done;
            signal_d_game_status <= game_status;
        end
    end

    assign pulse_gen_buf_A_valid = !signal_d_buf_A_valid && buf_A_valid;
    assign pulse_gen_buf_B_valid = !signal_d_buf_B_valid && buf_B_valid;
    assign pulse_gen_scan_done = !signal_d_scan_done && scan_done;
    assign pulse_gen_game_done = !signal_d_game_done && game_done;
    assign pulse_gen_game_status = !signal_d_game_status && game_status;
    
    // Register update for FSM and HPS control signals
    always_ff @(posedge clk) begin
        if (rst) begin
            scan_en_reg <= 1'b0;
            load_done_reg <= 1'b0;
            load_en_reg <= 1'b0;
            hps_vf_done_reg <= 1'b0;
            start_load_image_reg <= 1'b0;
            load_image_done_reg <= 1'b0;
            buf_A_valid_reg <= 1'b0;
            buf_B_valid_reg <= 1'b0;
            scan_done_reg <= 1'b0;
            game_done_reg <= 1'b0;
            game_status_reg <= 1'b0;

            // Game status register change flag
            game_status_reg_prev <= 1'b0;
            game_status_reg_changed_flag <= 1'b0;

            // SAD threshold register
            sad_threshold_reg <= 20'b0;
        end
        else begin
            // Game status register change flag
            game_status_reg_prev <= game_status_reg;

            // HPS write and clean datapath
            if (write_fire) begin
                if (avs_address == CONTROL_ADDR) begin
                    // Each byte-enable bit is independent; multiple bytes may be enabled.
                    // Byte 0: HPS write only
                    if (avs_byteenable[0]) scan_en_reg <= avs_writedata[0];

                    // Byte 1: HPS write and FSM send clean signal
                    if (avs_byteenable[1]) begin
                        if (avs_writedata[8]) load_done_reg <= 1'b1;
                        if (avs_writedata[9]) load_en_reg <= 1'b1;
                        if (avs_writedata[10]) hps_vf_done_reg <= 1'b1;
                        if (avs_writedata[11]) start_load_image_reg <= 1'b1;
                        if (avs_writedata[12]) load_image_done_reg <= 1'b1;
                    end

                    // Byte 2: FSM write only
                    // After HPS read the game status register, clear the change flag (game_status_reg stays unchanged)
                    if (avs_byteenable[2]) begin
                        if (avs_writedata[16]) game_status_reg_changed_flag <= 1'b0;
                    end

                    // Byte 3: FSM write and HPS clean
                    if (avs_byteenable[3]) begin
                        if (avs_writedata[25]) buf_A_valid_reg <= 1'b0;
                        if (avs_writedata[26]) buf_B_valid_reg <= 1'b0;
                        if (avs_writedata[27]) scan_done_reg <= 1'b0;
                        if (avs_writedata[28]) game_done_reg <= 1'b0;
                    end
                end

                if (avs_address == SAD_THRESHOLD_ADDR) begin
                    if (avs_byteenable[0]) sad_threshold_reg[7:0] <= avs_writedata[7:0];
                    if (avs_byteenable[1]) sad_threshold_reg[15:8] <= avs_writedata[15:8];
                    if (avs_byteenable[2]) sad_threshold_reg[19:16] <= avs_writedata[19:16];
                end
            end

            // FSM clean datapath
            if (load_done_clean) load_done_reg <= 1'b0;
            if (load_en_clean) load_en_reg <= 1'b0;
            if (hps_vf_done_clean) hps_vf_done_reg <= 1'b0;
            if (start_load_image_clean) start_load_image_reg <= 1'b0;
            if (load_image_done_clean) load_image_done_reg <= 1'b0;
            if (game_status_clean) game_status_reg <= 1'b0;

            // FSM write datapath, pulse to set the register
            if (pulse_gen_buf_A_valid) buf_A_valid_reg <= 1'b1;
            if (pulse_gen_buf_B_valid) buf_B_valid_reg <= 1'b1;
            if (pulse_gen_scan_done) scan_done_reg <= 1'b1;
            if (pulse_gen_game_done) game_done_reg <= 1'b1;
            if (pulse_gen_game_status) game_status_reg <= 1'b1;

            // A newly detected status change wins over a simultaneous HPS clear.
            if (game_status_reg_prev != game_status_reg)
                game_status_reg_changed_flag <= 1'b1;
        end
    end

    assign scan_ready_reg = buf_A_valid_reg || buf_B_valid_reg;

    // Readback is non-destructive; HPS clears event flags with a W1C write.
    always_comb begin
        avs_readdata = 32'd0;

        if (avs_read && !rst) begin
            case (avs_address)
                CONTROL_ADDR: begin
                    avs_readdata[0] = scan_en_reg;
                    avs_readdata[8] = load_done_reg;
                    avs_readdata[9] = load_en_reg;
                    avs_readdata[10] = hps_vf_done_reg;
                    avs_readdata[11] = start_load_image_reg;
                    avs_readdata[12] = load_image_done_reg;

                    // HPS read datapath, set by FSM
                    avs_readdata[16] = game_status_reg_changed_flag;
                    avs_readdata[17] = game_status_reg;
                    avs_readdata[24] = scan_ready_reg;
                    avs_readdata[25] = buf_A_valid_reg;
                    avs_readdata[26] = buf_B_valid_reg;
                    avs_readdata[27] = scan_done_reg;
                    avs_readdata[28] = game_done_reg;
                end

                SAD_THRESHOLD_ADDR: avs_readdata = {12'd0, sad_threshold_reg};

                BUF_A_SCAN_IN_ADDR_0: avs_readdata = buf_A_scan_in[31:0];
                BUF_A_SCAN_IN_ADDR_1: avs_readdata = buf_A_scan_in[63:32];
                BUF_A_SCAN_IN_ADDR_2: avs_readdata = buf_A_scan_in[95:64];
                BUF_A_SCAN_IN_ADDR_3: avs_readdata = buf_A_scan_in[127:96];
                BUF_A_SCAN_IN_ADDR_4: avs_readdata = buf_A_scan_in[159:128];
                BUF_A_SCAN_IN_ADDR_5: avs_readdata = buf_A_scan_in[191:160];
                BUF_A_SCAN_IN_ADDR_6: avs_readdata = {29'd0, buf_A_scan_in[194:192]};

                BUF_B_SCAN_IN_ADDR_0: avs_readdata = buf_B_scan_in[31:0];
                BUF_B_SCAN_IN_ADDR_1: avs_readdata = buf_B_scan_in[63:32];
                BUF_B_SCAN_IN_ADDR_2: avs_readdata = buf_B_scan_in[95:64];
                BUF_B_SCAN_IN_ADDR_3: avs_readdata = buf_B_scan_in[127:96];
                BUF_B_SCAN_IN_ADDR_4: avs_readdata = buf_B_scan_in[159:128];
                BUF_B_SCAN_IN_ADDR_5: avs_readdata = buf_B_scan_in[191:160];
                BUF_B_SCAN_IN_ADDR_6: avs_readdata = {29'd0, buf_B_scan_in[194:192]};

                default: avs_readdata = 32'd0;
            endcase
        end
    end

    assign irq = scan_ready_reg || buf_A_valid_reg || buf_B_valid_reg || scan_done_reg || game_done_reg || game_status_reg_changed_flag;

endmodule
