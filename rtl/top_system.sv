// FPGA fabric integration, not a DE1-SoC pin/HPS subsystem wrapper.
// Connect the two Avalon-MM slaves below to the generated Platform Designer
// interconnect at distinct base addresses. Both use WORDS addressing and
// waitrequestAllowance=0; the MMIO slave also uses readLatency=0.
// clk is the free-running 50 MHz FPGA clock. rst is active-high synchronous
// reset (scan_in samples it on the falling edge); hold reset across both edges.
// ASIC status/data inputs must meet the timing of the corresponding FPGA edge.
module top_system (
    input  logic        clk,
    input  logic        rst,

    // HPS writes to the shared 4096 x 32-bit RAM through this slave.
    input  logic [11:0] bram_avs_address,
    input  logic [31:0] bram_avs_writedata,
    input  logic [3:0]  bram_avs_byteenable,
    input  logic        bram_avs_write,
    output logic        bram_avs_waitrequest,

    // HPS control/status and scan-buffer readback through this slave.
    input  logic [3:0]  mmio_avs_address,
    input  logic [31:0] mmio_avs_writedata,
    input  logic [3:0]  mmio_avs_byteenable,
    input  logic        mmio_avs_write,
    input  logic        mmio_avs_read,
    output logic [31:0] mmio_avs_readdata,
    output logic        mmio_avs_waitrequest,
    output logic        irq,

    // ASIC interface. load_sel retains the existing FSM's one-bit encoding.
    input  logic        load_ready,
    input  logic        busy,
    input  logic        predict_valid,
    input  logic [1:0]  predict_class,
    input  logic        core_clk_disable,
    input  logic        scan_out,
    output logic        core_clk,
    output logic signed [15:0] load_data,
    output logic        load_valid,
    output logic        load_last,
    output logic        load_sel,
    output logic        scan_en,

    // Results for a board-specific display block, which is not in this repo.
    output logic [1:0]  win_lose,
    output logic        win_lose_en
);

    // FSM control of the datapath.
    logic posedge_negedge;
    logic addr_gen_en;
    logic load_image;
    logic bram_sel;
    logic cfg_wt_en;
    logic [1:0] load_cfg_wt;
    logic lfsr_en;
    logic compare_en;
    logic fpga_capture_en;
    logic buf_sel;
    logic buffer_not_ready;

    // MMIO settings and command acknowledgements.
    logic scan_en_reg;
    logic load_done_reg;
    logic load_en_reg;
    logic hps_vf_done_reg;
    logic start_load_image_reg;
    logic load_image_done_reg;
    logic buf_A_valid_reg;
    logic buf_B_valid_reg;
    logic [19:0] sad_threshold_reg;
    logic load_done_clean;
    logic load_en_clean;
    logic hps_vf_done_clean;
    logic start_load_image_clean;
    logic load_image_done_clean;
    logic game_status_clean;
    logic game_status;
    logic buf_A_valid;
    logic buf_B_valid;
    logic scan_done;
    logic game_done;

    // BRAM write events and read requests/responses.
    logic bram_write_fire;
    logic [11:0] bram_write_addr;
    logic [31:0] bram_write_data;
    logic bram_write_accept_ready;
    logic bram_read_en;
    logic [11:0] bram_read_addr;
    logic bram_read_is_ref;
    logic [31:0] bram_rdata;
    logic sad_valid;
    logic load_rvalid;
    logic addr_32to16_valid;
    logic addr_32to16_ready;

    // SAD, scan and comparison status.
    logic sad_ready;
    logic addr_gen_ready;
    logic sad_done;
    logic count_at_30;
    logic [194:0] scan_in_buf_A;
    logic [194:0] scan_in_buf_B;
    logic accept_count_at_195;
    logic [1:0] lfsr_out;
    logic delay_count_3;

    // BRAM write acceptance requires both the address generator and SAD to be ready.
    assign bram_write_accept_ready = addr_gen_ready && sad_ready;

    fsm u_fsm (
        .clk                    (clk),
        .rst                    (rst),
        .posedge_negedge        (posedge_negedge),
        .addr_gen_en            (addr_gen_en),
        .load_image             (load_image),
        .bram_sel               (bram_sel),
        .cfg_wt_en              (cfg_wt_en),
        .load_cfg_wt            (load_cfg_wt),
        .lfsr_en                (lfsr_en),
        .delay_count_3          (delay_count_3),
        .compare_en             (compare_en),
        .accept_count_at_195    (accept_count_at_195),
        .fpga_capture_en        (fpga_capture_en),
        .buf_sel                (buf_sel),
        .buffer_not_ready       (buffer_not_ready),
        .SAD_DONE               (sad_done),
        .count_at_30            (count_at_30),
        .load_valid             (load_valid),
        .load_ready             (load_ready),
        .load_last              (load_last),
        .busy                   (busy),
        .predict_valid          (predict_valid),
        .core_clk_disable      (core_clk_disable),
        .load_sel               (load_sel),
        .scan_en                (scan_en),
        .scan_en_reg            (scan_en_reg),
        .load_done_reg          (load_done_reg),
        .load_en_reg            (load_en_reg),
        .hps_vf_done_reg         (hps_vf_done_reg),
        .start_load_image_reg   (start_load_image_reg),
        .load_image_done_reg    (load_image_done_reg),
        .buf_A_valid_reg        (buf_A_valid_reg),
        .buf_B_valid_reg        (buf_B_valid_reg),
        .load_done_clean        (load_done_clean),
        .load_en_clean          (load_en_clean),
        .hps_vf_done_clean       (hps_vf_done_clean),
        .start_load_image_clean (start_load_image_clean),
        .load_image_done_clean  (load_image_done_clean),
        .game_status_clean      (game_status_clean),
        .game_status            (game_status),
        .buf_A_valid            (buf_A_valid),
        .buf_B_valid            (buf_B_valid),
        .scan_done              (scan_done),
        .game_done              (game_done)
    );

    mmio_reg u_mmio_reg (
        .clk                    (clk),
        .rst                    (rst),
        .irq                    (irq),
        .avs_address            (mmio_avs_address),
        .avs_writedata          (mmio_avs_writedata),
        .avs_byteenable         (mmio_avs_byteenable),
        .avs_write              (mmio_avs_write),
        .avs_read               (mmio_avs_read),
        .avs_readdata           (mmio_avs_readdata),
        .avs_waitrequest        (mmio_avs_waitrequest),
        .buf_A_scan_in          (scan_in_buf_A),
        .buf_B_scan_in          (scan_in_buf_B),
        .load_done_clean        (load_done_clean),
        .load_en_clean          (load_en_clean),
        .hps_vf_done_clean       (hps_vf_done_clean),
        .start_load_image_clean (start_load_image_clean),
        .load_image_done_clean  (load_image_done_clean),
        .game_status_clean      (game_status_clean),
        .game_status            (game_status),
        .buf_A_valid            (buf_A_valid),
        .buf_B_valid            (buf_B_valid),
        .scan_done              (scan_done),
        .game_done              (game_done),
        .scan_en_reg            (scan_en_reg),
        .load_done_reg          (load_done_reg),
        .load_en_reg            (load_en_reg),
        .hps_vf_done_reg         (hps_vf_done_reg),
        .start_load_image_reg   (start_load_image_reg),
        .load_image_done_reg    (load_image_done_reg),
        .buf_A_valid_reg        (buf_A_valid_reg),
        .buf_B_valid_reg        (buf_B_valid_reg),
        .sad_threshold_reg      (sad_threshold_reg)
    );

    bram_wrapper u_bram_wrapper (
        .clk                (clk),
        .rst                (rst),
        .avs_address        (bram_avs_address),
        .avs_writedata      (bram_avs_writedata),
        .avs_byteenable     (bram_avs_byteenable),
        .avs_write          (bram_avs_write),
        .avs_waitrequest    (bram_avs_waitrequest),
        .write_accept_ready (bram_write_accept_ready),
        .write_fire         (bram_write_fire),
        .write_addr         (bram_write_addr),
        .write_data         (bram_write_data),
        .bram_read_en       (bram_read_en),
        .bram_read_addr     (bram_read_addr),
        .bram_read_is_ref   (bram_read_is_ref),
        .bram_rdata         (bram_rdata),
        .sad_valid          (sad_valid),
        .load_rvalid        (load_rvalid)
    );

    addr_gen u_addr_gen (
        .clk                (clk),
        .rst                (rst),
        .load_image         (load_image),
        .bram_sel           (bram_sel),
        .cfg_wt_en          (cfg_wt_en),
        .load_cfg_wt        (load_cfg_wt),
        .addr_32to16_ready  (addr_32to16_ready),
        .write_fire         (bram_write_fire && addr_gen_en),
        .addr_in            (bram_write_addr),
        .posedge_negedge    (posedge_negedge),
        .addr_gen_en        (addr_gen_en),
        .addr_32to16_valid  (addr_32to16_valid),
        .bram_read_en       (bram_read_en),
        .bram_read_addr     (bram_read_addr),
        .bram_read_is_ref   (bram_read_is_ref),
        .addr_gen_ready     (addr_gen_ready)
    );

    streaming_32to16 u_streaming_32to16 (
        .clk                (clk),
        .rst                (rst),
        .load_rvalid        (load_rvalid),
        .rdata_in           (bram_rdata),
        .load_ready         (load_ready),
        .core_clk_disable   (core_clk_disable),
        .fsm_ctrl           (buffer_not_ready),
        .addr_32to16_valid  (addr_32to16_valid),
        .load_cfg_wt        (load_cfg_wt),
        .load_image         (load_image),
        .load_data          (load_data),
        .load_valid         (load_valid),
        .load_last          (load_last),
        .addr_32to16_ready  (addr_32to16_ready)
    );

    SAD u_SAD (
        .clk           (clk),
        .rst           (rst),
        .write_fire    (bram_write_fire && addr_gen_en),
        .data_in       (bram_write_data),
        .sad_valid     (sad_valid),
        .ref_in        (bram_rdata),
        .sad_ready     (sad_ready),
        .sad_done      (sad_done),
        .count_at_30   (count_at_30),
        .sad_threshold(sad_threshold_reg)
    );

    scan_in u_scan_in (
        .clk                 (clk),
        .rst                 (rst),
        .buf_sel             (buf_sel),
        .fpga_capture_en     (fpga_capture_en),
        .scan_out            (scan_out),
        .accept_count_at_195 (accept_count_at_195),
        .scan_in_buf_A       (scan_in_buf_A),
        .scan_in_buf_B       (scan_in_buf_B)
    );

    lfsr u_lfsr (
        .clk      (clk),
        .rst      (rst),
        .lfsr_en  (lfsr_en),
        .lfsr_out (lfsr_out)
    );

    compare u_compare (
        .clk           (clk),
        .rst           (rst),
        .lfsr_out      (lfsr_out),
        .compare_en    (compare_en),
        .predict_valid (predict_valid),
        .predict_class (predict_class),
        .win_lose      (win_lose),
        .win_lose_en   (win_lose_en),
        .delay_count_3 (delay_count_3)
    );

    core_clk_gen u_core_clk_gen (
        .clk              (clk),
        .core_clk_disable (core_clk_disable),
        .fsm_ctrl         (buffer_not_ready),
        .core_clk         (core_clk)
    );

endmodule
