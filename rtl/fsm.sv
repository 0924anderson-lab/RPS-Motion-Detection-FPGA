module fsm (
    input logic clk,
    input logic rst,

    // To addr_gen module
    // Control signals for SAD reference address generator
    output logic posedge_negedge,
    output logic addr_gen_en,

    // Control signals for image loading and BRAM selection
    output logic load_image,
    output logic bram_sel,

    // Control signals for configuration and weight loading
    output logic cfg_wt_en,
    output logic [1:0] load_cfg_wt,

    // To lfsr module, control signal for enabling the LFSR
    output logic lfsr_en,

    // To compare module, control signal for enabling the comparison process
    input logic delay_count_3,
    output logic compare_en,

    // To scan_in module, control signal for enabling the scan-in process
    input logic accept_count_at_195,
    output logic fpga_capture_en,
    output logic buf_sel,

    // To core_clk_gen and 32to16 modules, control signals for enabling the core clock generation and 32-to-16 conversion
    output logic buffer_not_ready,

    // From SAD module, status signals indicating the completion of SAD calculation
    input logic SAD_DONE,
    input logic count_at_30,

    // From the chip, status signals indicating the completion of various processes
    input logic load_valid,
    input logic load_ready,
    input logic load_last,
    input logic busy,
    input logic predict_valid,
    input logic core_clk_disable,
    output logic load_sel,
    output logic scan_en,

    // From MMIO register, control signals for FSM operation
    input logic scan_en_reg,                  // Scan FSM path is turned on
    input logic load_done_reg,                // HPS has finished loading configuration and weights
    input logic load_en_reg,                  // Start loading configuration and weights
    input logic hps_vf_done_reg,              // HPS has finished vector field calculation
    input logic start_load_image_reg,         // Start loading image
    input logic load_image_done_reg,          // HPS has finished loading image
    input logic buf_A_valid_reg,              // Scan in buffer A is valid, reset by HPS after reading
    input logic buf_B_valid_reg,              // Scan in buffer B is valid, reset by HPS after reading

    // FSM clean signals
    output logic load_done_clean,
    output logic load_en_clean,
    output logic hps_vf_done_clean,
    output logic start_load_image_clean,
    output logic load_image_done_clean,
    output logic game_status_clean, 

    // FSM write signals, used to generate pulses
    output logic game_status,
    output logic buf_A_valid,
    output logic buf_B_valid,
    output logic scan_done,
    output logic game_done
);

    typedef enum logic [4:0] {
        IDLE,

        // State for loading configuration or weights
        LOAD_CFG, BUFFER, LOAD_WT, WAIT_DONE,

        // State for SAD calculation and loading image data to chip
        LOAD_REF, READY_LOAD_BRAMB, LOAD_SAD_1, WAIT_SAD_1,
        READY_LOAD_BRAMA, LOAD_SAD_2, WAIT_SAD_2, FPGA2CHIP_IN_1,
        FPGA2CHIP_IN_2, WAIT_PREDICT, COMPARE, DONE,

        // State for scan chain
        CHIP_SCAN_2_BUF_A, FPGA_CAPTURE_A, WAIT_SCAN_DONE_A,
        CHIP_SCAN_2_BUF_B, FPGA_CAPTURE_B, WAIT_SCAN_DONE_B,
        CHIP_SCAN_2_BUF_A_2, FPGA_CAPTURE_A_2, WAIT_SCAN_DONE_A_2,
        CHIP_SCAN_2_BUF_B_2, FPGA_CAPTURE_B_2, WAIT_SCAN_DONE_B_2,
        SCAN_DONE, WAIT_HPS_VF_DONE
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk) begin
        if (rst) state <= IDLE;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;

        case (state)
            // IDLE state transit to LOAD_CFG or LOAD_REF (SAD process) based on MMIO control reg set by HPS
            IDLE: begin
                if (load_done_reg && load_en_reg) next_state = LOAD_CFG;
                if (start_load_image_reg) next_state = LOAD_REF;
            end

            //////////////////////////////////// LOAD CFG AND WEIGHTS ////////////////////////////////////
            LOAD_CFG: if (load_valid && load_ready && load_last) next_state = BUFFER;

            BUFFER: next_state = LOAD_WT;

            LOAD_WT: if (load_valid && load_ready && load_last) next_state = WAIT_DONE;

            WAIT_DONE: if (!busy) next_state = IDLE;

            //////////////////////////////////// SAD CALCULATION AND IMAGE LOADING ////////////////////////////////////
            LOAD_REF: if (load_image_done_reg) next_state = READY_LOAD_BRAMB;

            READY_LOAD_BRAMB: if (start_load_image_reg) next_state = LOAD_SAD_1;

            LOAD_SAD_1: if (load_image_done_reg) next_state = WAIT_SAD_1;

            WAIT_SAD_1: begin
                if (SAD_DONE && !count_at_30) next_state = READY_LOAD_BRAMA;
                if (SAD_DONE && count_at_30 && !scan_en_reg) next_state = FPGA2CHIP_IN_1;
                if (SAD_DONE && count_at_30 && scan_en_reg) next_state = CHIP_SCAN_2_BUF_A;
            end

            READY_LOAD_BRAMA: if (start_load_image_reg) next_state = LOAD_SAD_2;

            LOAD_SAD_2: if (load_image_done_reg) next_state = WAIT_SAD_2;

            WAIT_SAD_2: begin
                if (SAD_DONE && !count_at_30) next_state = READY_LOAD_BRAMB;
                if (SAD_DONE && count_at_30 && !scan_en_reg) next_state = FPGA2CHIP_IN_2;
                if (SAD_DONE && count_at_30 && scan_en_reg) next_state = CHIP_SCAN_2_BUF_A_2;
            end

            FPGA2CHIP_IN_1: if (load_valid && load_ready && load_last) next_state = WAIT_PREDICT;

            FPGA2CHIP_IN_2: if (load_valid && load_ready && load_last) next_state = WAIT_PREDICT;

            WAIT_PREDICT: if (predict_valid) next_state = COMPARE;

            COMPARE: if (delay_count_3) next_state = DONE;

            DONE: next_state = IDLE;

            //////////////////////////////////// SCAN MODE ////////////////////////////////////
            // FSM branch from WAIT_SAD_1 for scan mode
            CHIP_SCAN_2_BUF_A: begin
                if (core_clk_disable) next_state = FPGA_CAPTURE_A;
                if (predict_valid) next_state = SCAN_DONE;
            end

            FPGA_CAPTURE_A: if (accept_count_at_195) next_state = WAIT_SCAN_DONE_A;

            WAIT_SCAN_DONE_A: if (!buf_B_valid_reg && !core_clk_disable) next_state = CHIP_SCAN_2_BUF_B;

            CHIP_SCAN_2_BUF_B: begin
                if (core_clk_disable) next_state = FPGA_CAPTURE_B;
                if (predict_valid) next_state = SCAN_DONE;
            end

            FPGA_CAPTURE_B: if (accept_count_at_195) next_state = WAIT_SCAN_DONE_B;

            WAIT_SCAN_DONE_B: if (!buf_A_valid_reg && !core_clk_disable) next_state = CHIP_SCAN_2_BUF_A;

            // FSM branch from WAIT_SAD_2 for scan mode
            CHIP_SCAN_2_BUF_A_2: begin
                if (core_clk_disable) next_state = FPGA_CAPTURE_A_2;
                if (predict_valid) next_state = SCAN_DONE;
            end

            FPGA_CAPTURE_A_2: if (accept_count_at_195) next_state = WAIT_SCAN_DONE_A_2;

            WAIT_SCAN_DONE_A_2: if (!buf_B_valid_reg && !core_clk_disable) next_state = CHIP_SCAN_2_BUF_B_2;

            CHIP_SCAN_2_BUF_B_2: begin
                if (core_clk_disable) next_state = FPGA_CAPTURE_B_2;
                if (predict_valid) next_state = SCAN_DONE;
            end

            FPGA_CAPTURE_B_2: if (accept_count_at_195) next_state = WAIT_SCAN_DONE_B_2;

            WAIT_SCAN_DONE_B_2: if (!buf_A_valid_reg && !core_clk_disable) next_state = CHIP_SCAN_2_BUF_A_2;

            // Common path
            SCAN_DONE: next_state = WAIT_HPS_VF_DONE;
            WAIT_HPS_VF_DONE: if (hps_vf_done_reg) next_state = IDLE;

        endcase
    end

    // Control signals for the FSM
    always_comb begin
        start_load_image_clean = 1'b0;
        load_image_done_clean  = 1'b0;
        game_status_clean      = 1'b0;
        buf_A_valid            = 1'b0;
        buf_B_valid            = 1'b0;
        game_done              = 1'b0;
        scan_done              = 1'b0;
        posedge_negedge        = 1'b0;
        addr_gen_en            = 1'b0;
        load_image             = 1'b0;
        bram_sel               = 1'b0;
        cfg_wt_en              = 1'b0;
        load_cfg_wt            = 2'b00;
        lfsr_en                = 1'b0;
        compare_en             = 1'b0;
        fpga_capture_en        = 1'b0;
        buf_sel                = 1'b0;
        load_sel               = 1'b0;
        scan_en                = 1'b0;
        load_done_clean        = 1'b0;
        load_en_clean          = 1'b0;
        hps_vf_done_clean      = 1'b0;
        game_status            = 1'b0;

        case (state)
            IDLE: begin
                game_status_clean = 1'b1;  // To the MMIO, indicating the chip prediction is not active
                hps_vf_done_clean = 1'b1;
                // DONE_REG = 1'b0;  HPS reset the done signal
            end

            LOAD_CFG: begin
                load_sel = 1'b0;  // To the chip, indicating to load the configuration or weights
                cfg_wt_en = 1'b1;  // To the addr_gen, indicating to load the base address for the configuration or weights
                load_cfg_wt = 2'b01;  // Base address selection for the configuration, and the threshold selection for last loaded address

                // Clean the MMIO registers
                load_done_clean = 1'b1;
                load_en_clean = 1'b1;
            end

            BUFFER: begin
                cfg_wt_en = 1'b0;  // To the addr_gen, just to regenerate the enable signal pulse
                load_cfg_wt = 2'b00;
            end

            LOAD_WT: begin
                load_sel = 1'b0;  
                cfg_wt_en = 1'b1;  
                load_cfg_wt = 2'b10;  // Base address selection for the weights, and the threshold selection for last loaded address
            end

            WAIT_DONE: begin
                cfg_wt_en = 1'b0;
                load_cfg_wt = 2'b00;
            end

            LOAD_REF: begin
                start_load_image_clean = 1'b1;  // To the MMIO, reset the start signal
            end

            READY_LOAD_BRAMB: begin
                load_image_done_clean = 1'b1;
            end

            LOAD_SAD_1: begin
                start_load_image_clean = 1'b1;
                posedge_negedge = 1'b1;  // To the addr_gen, indicating to generate the BRAM A address to bram_mem
                addr_gen_en = 1'b1;  // To the addr_gen, indicating to enable the address generation
            end

            WAIT_SAD_1: begin
                load_image_done_clean = 1'b1;
                addr_gen_en = 1'b0;  // To the addr_gen, indicating to disable the address generation
            end

            LOAD_SAD_2: begin
                start_load_image_clean = 1'b1;
                posedge_negedge = 1'b0;  // To the addr_gen, indicating to generate the BRAM B address to bram_mem
                addr_gen_en = 1'b1;
            end

            WAIT_SAD_2: begin
                load_image_done_clean = 1'b1;
                addr_gen_en = 1'b0;
            end

            FPGA2CHIP_IN_1: begin
                game_status = 1'b1;  // To the MMIO, indicating the chip prediction is active
                load_sel = 1'b1;  // To the chip, indicating to load the input data
                bram_sel = 1'b1;  // Base address selection for BRAM B, and the threshold selection for last loaded address
                load_image = 1'b1;  // To the addr_gen, indicating to load the base address for the input data of BRAM A or B
                lfsr_en = 1'b1;  // To the lfsr, indicating to enable the LFSR
            end

            FPGA2CHIP_IN_2: begin
                game_status = 1'b1;  
                load_sel = 1'b1;  
                bram_sel = 1'b0;  // Base address selection for BRAM A, and the threshold selection for last loaded address
                load_image = 1'b1; 
                lfsr_en = 1'b1;
            end

            WAIT_PREDICT: begin
                load_image = 1'b0;  // To the addr_gen, to reset the load signal for the input data of BRAM A or B
                lfsr_en = 1'b0;  // To the lfsr, indicating to disable the LFSR, but the final result was stored in the compare module
                load_sel = 1'b0;  // To the chip, indicating to stop loading the input data
            end

            COMPARE: begin
                compare_en = 1'b1;  // To the compare, indicating to start the comparison process and the delay up counting
            end

            DONE: begin
                game_done = 1'b1;  // To the MMIO, indicating the process is done
                compare_en = 1'b0;  // To the compare, indicating to disable the comparison process, and reset the delay up counter
            end

            CHIP_SCAN_2_BUF_A: begin
                game_status = 1'b1;  // To the MMIO, indicating the chip prediction is active
                load_sel = 1'b1;  // To the chip, indicating to load the input data
                bram_sel = 1'b1;  // Base address selection for BRAM B, and the threshold selection for last loaded address
                load_image = 1'b1;  // To the addr_gen, indicating to load the base address for the input data of BRAM A or B
                scan_en = 1'b1;  // To the chip, indicating to enable the scan process, and scan chain operation
            end

            FPGA_CAPTURE_A: begin
                game_status = 1'b1;
                fpga_capture_en = 1'b1;  // To the scan_in, indicating to enable the FPGA capture process, and capture new bit data at falling edge
                buf_sel = 1'b0;  // To the scan_in, indicating to select buffer A for loading the captured data
                load_sel = 1'b1;
                bram_sel = 1'b1;
                load_image = 1'b1;
                scan_en = 1'b1;
            end

            WAIT_SCAN_DONE_A: begin
                // SCAN_READY_REG = 1'b1;  To the MMIO, indicating the scan process is ready
                game_status = 1'b1;
                buf_A_valid = 1'b1;  // To the MMIO, indicating buffer A is valid, can be taken by HPS
                fpga_capture_en = 1'b0;  // To the scan_in, indicating to disable the FPGA capture process
                load_sel = 1'b1;
                bram_sel = 1'b1;
                load_image = 1'b1;
                scan_en = 1'b1;
            end

            CHIP_SCAN_2_BUF_B: begin
                game_status = 1'b1;
                load_sel = 1'b1;
                bram_sel = 1'b1;
                load_image = 1'b1;
                scan_en = 1'b1;
            end

            FPGA_CAPTURE_B: begin
                game_status = 1'b1;
                fpga_capture_en = 1'b1;
                buf_sel = 1'b1;  // To the scan_in, indicating to select buffer B for loading the captured data
                load_sel = 1'b1;
                bram_sel = 1'b1;
                load_image = 1'b1;
                scan_en = 1'b1;
            end

            WAIT_SCAN_DONE_B: begin
                // SCAN_READY_REG = 1'b1;  
                game_status = 1'b1;
                buf_B_valid = 1'b1;  // To the MMIO, indicating buffer B is valid, can be taken by HPS
                fpga_capture_en = 1'b0;
                load_sel = 1'b1;
                bram_sel = 1'b1;
                load_image = 1'b1;
                scan_en = 1'b1;
            end

            CHIP_SCAN_2_BUF_A_2: begin
                game_status = 1'b1;  // To the MMIO, indicating the chip prediction is active
                load_sel = 1'b1;  // To the chip, indicating to load the input data
                bram_sel = 1'b0;  // Base address selection for BRAM A, and the threshold selection for last loaded address
                load_image = 1'b1;  // To the addr_gen, indicating to load the base address for the input data of BRAM A or B
                scan_en = 1'b1;  // To the chip, indicating to enable the scan process, and scan chain operation
            end

            FPGA_CAPTURE_A_2: begin
                game_status = 1'b1;
                fpga_capture_en = 1'b1;  // To the scan_in, indicating to enable the FPGA capture process, and capture new bit data at falling edge
                buf_sel = 1'b0;  // To the scan_in, indicating to select buffer A for loading the captured data
                load_sel = 1'b1;
                bram_sel = 1'b0;
                load_image = 1'b1;
                scan_en = 1'b1;
            end

            WAIT_SCAN_DONE_A_2: begin
                // SCAN_READY_REG = 1'b1;  To the MMIO, indicating the scan process is ready
                game_status = 1'b1;
                buf_A_valid = 1'b1;  // To the MMIO, indicating buffer A is valid, can be taken by HPS
                fpga_capture_en = 1'b0;  // To the scan_in, indicating to disable the FPGA capture process
                load_sel = 1'b1;
                bram_sel = 1'b0;
                load_image = 1'b1;
                scan_en = 1'b1;
            end     

            CHIP_SCAN_2_BUF_B_2: begin
                game_status = 1'b1;
                load_sel = 1'b1;
                bram_sel = 1'b0;
                load_image = 1'b1;
                scan_en = 1'b1;
            end

            FPGA_CAPTURE_B_2: begin
                game_status = 1'b1;
                fpga_capture_en = 1'b1;
                buf_sel = 1'b1;  // To the scan_in, indicating to select buffer B for loading the captured data
                load_sel = 1'b1;
                bram_sel = 1'b0;
                load_image = 1'b1;
                scan_en = 1'b1;
            end

            WAIT_SCAN_DONE_B_2: begin
                // SCAN_READY_REG = 1'b1;  
                game_status = 1'b1;
                buf_B_valid = 1'b1;
                fpga_capture_en = 1'b0;
                load_sel = 1'b1;
                bram_sel = 1'b0;
                load_image = 1'b1;
                scan_en = 1'b1;
            end

            SCAN_DONE: begin
                scan_done = 1'b1;
                load_sel = 1'b1;
                scan_en = 1'b1;
            end

            WAIT_HPS_VF_DONE: begin
                load_sel = 1'b1;
                scan_en = 1'b1;
            end
        endcase
    end

    assign buffer_not_ready = (state == WAIT_SCAN_DONE_A && buf_B_valid_reg) || (state == WAIT_SCAN_DONE_B && buf_A_valid_reg) 
    || (state == WAIT_SCAN_DONE_A_2 && buf_B_valid_reg) || (state == WAIT_SCAN_DONE_B_2 && buf_A_valid_reg);

endmodule
