// ============================================================
// Module : mac_rx.v
// Purpose : Ethernet MAC Receiver - RMII interface
// ============================================================
module mac_rx (
    input  wire       clk,           // 50 MHz RMII clock
    input  wire       rst_n,
    // RMII PHY interface
    input  wire [1:0] rmii_rxd,      // 2-bit RX data from PHY
    input  wire       rmii_crs_dv,   // Carrier sense / data valid
    // FIFO interface (host side)
    output reg  [7:0] rx_fifo_data,  // Byte to RX FIFO
    output reg        rx_fifo_wr,    // Write strobe
    // Status
    output reg        rx_done,       // Frame complete (good or bad)
    output reg        crc_error,     // FCS mismatch
    output reg        frame_error    // Runt / giant frame
);
    localparam IDLE   = 3'd0;
    localparam PREAM  = 3'd1;
    localparam SFD    = 3'd2;
    localparam DATA   = 3'd3;
    localparam STATUS = 3'd4;

    localparam MIN_BYTES = 12'd60;    // Min payload (excl. FCS)
    localparam MAX_BYTES = 12'd1514;  // Max payload (excl. FCS)

    reg [2:0]  state;
    reg [1:0]  rxd_s1, rxd_s2;        // 2-FF synchroniser
    reg        dv_s1, dv_s2;
    reg [1:0]  dibit_cnt;
    reg [7:0]  byte_shift;
    reg [11:0] byte_cnt;              // Bytes received in DATA state

    // CRC engine
    reg         crc_init;
    wire [7:0]  full_byte = {rxd_s2, byte_shift[7:2]};   // byte completed on 4th dibit
    wire        crc_en    = (state == DATA) && dv_s2 && (dibit_cnt == 2'd3);
    wire [31:0] crc_out, crc_fcs;

    crc32 u_crc (
        .clk(clk), .rst_n(rst_n),
        .init(crc_init), .en(crc_en),
        .data_in(full_byte),
        .crc_out(crc_out), .crc_fcs(crc_fcs)
    );

    // 2-FF synchroniser for RMII inputs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_s1 <= 2'b0; rxd_s2 <= 2'b0;
            dv_s1  <= 1'b0; dv_s2  <= 1'b0;
        end else begin
            rxd_s1 <= rmii_rxd;    rxd_s2 <= rxd_s1;
            dv_s1  <= rmii_crs_dv; dv_s2  <= dv_s1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= IDLE;
            dibit_cnt   <= 2'd0;
            byte_cnt    <= 12'd0;
            rx_fifo_wr  <= 1'b0;
            rx_done     <= 1'b0;
            crc_error   <= 1'b0;
            frame_error <= 1'b0;
            crc_init    <= 1'b0;
            byte_shift  <= 8'd0;
            rx_fifo_data<= 8'd0;
        end else begin
            rx_fifo_wr  <= 1'b0;
            rx_done     <= 1'b0;
            crc_error   <= 1'b0;
            frame_error <= 1'b0;
            crc_init    <= 1'b0;

            case (state)
                IDLE: begin
                    if (dv_s2 && rxd_s2 == 2'b01) begin
                        // First preamble dibit detected
                        dibit_cnt <= 2'd1;
                        state     <= PREAM;
                    end
                end

                PREAM: begin
                    if (!dv_s2) begin
                        state <= IDLE;
                    end else if (rxd_s2 == 2'b01) begin
                        dibit_cnt <= dibit_cnt + 1;  // keep counting 0x55 dibits
                    end else if (rxd_s2 == 2'b11) begin
                        // 0xD5 is sent LSB first (01 01 01 11): the 11 dibit is
                        // the LAST SFD dibit, so the next dibit is frame data.
                        crc_init  <= 1'b1;
                        byte_cnt  <= 12'd0;
                        dibit_cnt <= 2'd0;
                        state     <= DATA;
                    end else
                        state <= IDLE;  // invalid
                end

                DATA: begin
                    if (!dv_s2) begin
                        // End of frame - check byte count
                        state <= STATUS;
                    end else begin
                        // Shift dibits into byte (LSB first)
                        byte_shift <= {rxd_s2, byte_shift[7:2]};
                        dibit_cnt  <= dibit_cnt + 1;
                        if (dibit_cnt == 2'd3) begin
                            rx_fifo_data <= full_byte;
                            rx_fifo_wr   <= 1'b1;
                            byte_cnt     <= byte_cnt + 1;
                        end
                    end
                end

                STATUS: begin
                    rx_done <= 1'b1;
                    // CRC-32 residue over data+FCS must equal 0xC704DD7B
                    crc_error <= (crc_out != 32'hC704DD7B);
                    // Frame size check (byte_cnt includes 4 FCS bytes)
                    frame_error <= (byte_cnt < (MIN_BYTES + 4)) ||
                                   (byte_cnt > (MAX_BYTES + 4));
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
