module streaming_32to16 (
    input  logic clk,
    input  logic rst,
    input  logic load_rvalid, // BRAM wrapper tells 32to16 this rdata_in is valid
    input  logic signed [31:0] rdata_in, // BRAM wrapper send BRAM to 32to16
    input  logic load_ready,
    input  logic core_clk_disable,
    input  logic fsm_ctrl,
    input  logic addr_32to16_valid,
    input  logic [1:0] load_cfg_wt,
    input  logic load_image,
    output logic signed [15:0] load_data,
    output logic load_valid,
    output logic load_last,
    output logic addr_32to16_ready
);

    // Internal buffers to store incoming 32-bit data before converting to 16-bit output
    logic signed [31:0] buffer1, buffer2, buffer3, buffer4;

    // Control signals for loading buffer selection and output management
    logic buffer_12_sel;
    logic buffer_13_sel;
    logic buffer_24_sel;
    logic high_low_half;
    logic buffer3_empty;
    logic buffer4_empty;
    logic last_low_half_buffer_13;
    logic last_low_half_buffer_24;
    logic buffer_12_out;

    // Free_slot means the number of free 32-bit buffer slots available to load new data into; pkg_count means the number of 16-bit packages ready to be output
    logic [1:0] free_slot;
    logic [2:0] pkg_count;

    // Load_last threshold selection; 
    logic [10:0] load_last_threshold;
    logic [10:0] transaction_count;

    // Combined load_ready signal with FSM control and core clock disable to become load_ready_all
    logic load_ready_all;

    assign load_ready_all = load_ready && !core_clk_disable && !fsm_ctrl;

    // Loading buffer architecture and buffer_12_sel management
    always_ff @(posedge clk) begin
        if (rst) begin
            buffer_12_sel <= 1'b0;
            high_low_half <= 1'b0;
            buffer_12_out <= 1'b0;
            buffer3_empty <= 1'b1;
            buffer4_empty <= 1'b1;
            last_low_half_buffer_13 <= 1'b0;
            last_low_half_buffer_24 <= 1'b0;
            {buffer1, buffer2, buffer3, buffer4} <= 128'sd0;
            free_slot <= 2'd2;
            pkg_count <= 3'd0;
            transaction_count <= 11'd0;
        end
        else begin
            if (load_rvalid) begin
                if (!buffer_12_sel) begin
                    if (!buffer_13_sel) buffer1 <= rdata_in;
                    else begin
                        buffer3 <= rdata_in;
                        buffer3_empty <= 1'b0;
                    end
                end
                else begin
                    if (!buffer_24_sel) buffer2 <= rdata_in;
                    else begin
                        buffer4 <= rdata_in;
                        buffer4_empty <= 1'b0;
                    end
                end
                buffer_12_sel <= ~buffer_12_sel;
            end

            // Toggle high_low_half when a load transaction handshakes successfully to chip, start from low-half
            if (load_valid && load_ready_all) high_low_half <= ~high_low_half;

            // Toggle buffer_12_out when the high half of the current buffer is being output and a load transaction handshakes successfully
            if (high_low_half && load_valid && load_ready_all) buffer_12_out <= ~buffer_12_out;

            // Reset buffer3_empty to 1 when buffer3 upper-half being output successfully
            if (!buffer_12_out && last_low_half_buffer_13 && high_low_half && load_valid && load_ready_all) begin
                buffer3_empty <= 1'b1; 

                // Reset last_low_half_buffer_13 to 0 when the upper half of buffer3 is being output successfully
                last_low_half_buffer_13 <= 1'b0;
            end

            // Reset buffer4_empty to 1 when buffer4 upper-half being output successfully
            if (buffer_12_out && last_low_half_buffer_24 && high_low_half && load_valid && load_ready_all) begin
                buffer4_empty <= 1'b1; 

                // Reset last_low_half_buffer_24 to 0 when the upper half of buffer4 is being output successfully
                last_low_half_buffer_24 <= 1'b0;
            end

            // Set last_low_half_buffer_13 to 1 when the upper half of buffer1 is being output successfully and buffer3 is not empty
            if (!buffer_12_out && !last_low_half_buffer_13 && high_low_half && load_valid && load_ready_all && !buffer3_empty) last_low_half_buffer_13 <= 1'b1;

            // Set last_low_half_buffer_24 to 1 when the upper half of buffer2 is being output successfully and buffer4 is not empty
            if (buffer_12_out && !last_low_half_buffer_24 && high_low_half && load_valid && load_ready_all && !buffer4_empty) last_low_half_buffer_24 <= 1'b1;

            // Free_slot decreases by 1 when 32to16 and addr_gen handshake, and increases by 1 when each 32-bit slot is loaded to chip successfully
            case ({addr_32to16_valid && addr_32to16_ready, !high_low_half && load_valid && load_ready_all}) 
                2'b00: free_slot <= free_slot;
                2'b01: free_slot <= free_slot + 2'd1;
                2'b10: free_slot <= free_slot - 2'd1;
                2'b11: free_slot <= free_slot;
                default: free_slot <= free_slot;
            endcase

            // Update pkg_count based on rvalid and load_valid & load_ready handshake
            case({load_rvalid, load_valid && load_ready_all})
                2'b00: pkg_count <= pkg_count;
                2'b01: pkg_count <= pkg_count - 3'd1;
                2'b10: pkg_count <= pkg_count + 3'd2;
                2'b11: pkg_count <= pkg_count + 3'd1;
                default: pkg_count <= pkg_count;
            endcase

            // Update transaction_count based on load_valid & load_ready handshake
            if (load_valid && load_ready_all) transaction_count <= transaction_count + 11'd1;

            // Reset all the control signals, buffers, and the transaction up counter when the last transaction handshakes
            if (load_last && load_valid && load_ready_all) begin
                buffer_12_sel <= 1'b0;
                high_low_half <= 1'b0;
                buffer_12_out <= 1'b0;
                buffer3_empty <= 1'b1;
                buffer4_empty <= 1'b1;
                last_low_half_buffer_13 <= 1'b0;
                last_low_half_buffer_24 <= 1'b0;
                {buffer1, buffer2, buffer3, buffer4} <= 128'sd0;
                free_slot <= 2'd2;
                pkg_count <= 3'd0;
                transaction_count <= 11'd0;
            end
        end
    end

    assign buffer_13_sel = !buffer_12_out && high_low_half && !(load_valid && load_ready_all) && buffer3_empty;
    assign buffer_24_sel = buffer_12_out && high_low_half && !(load_valid && load_ready_all) && buffer4_empty;

    // Assign low/high half of buffer1, buffer2, buffer3, and buffer4 to load_data based on output control signals, then downstream chip can store the data right after handshake.
    assign load_data = buffer_12_out ? (last_low_half_buffer_24 ? (high_low_half ? buffer4[31:16] : buffer4[15:0]) : (high_low_half ? buffer2[31:16] : buffer2[15:0])) : 
    (last_low_half_buffer_13 ? (high_low_half ? buffer3[31:16] : buffer3[15:0]) : (high_low_half ? buffer1[31:16] : buffer1[15:0])) ;

    // Load_valid and addr_32to16_ready signals
    assign addr_32to16_ready = free_slot != 2'd0;
    assign load_valid = pkg_count != 3'd0;

    // Load_last signal indicates the last transaction based on the transaction count and load_last_threshold
    always_comb begin
        load_last_threshold = 11'd0;
        case({load_cfg_wt, load_image})
            3'b001: load_last_threshold = 11'd2047;
            3'b010: load_last_threshold = 11'd95;
            3'b100: load_last_threshold = 11'd1025;
            default: load_last_threshold = 11'd0;
        endcase
    end

    assign load_last = load_valid && (transaction_count == load_last_threshold);

endmodule
