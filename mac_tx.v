// ============================================================
// Module : mac_tx.v
// Purpose : Ethernet MAC Transmitter - RMII interface
// FSM     : IDLE -> PREAMBLE -> SFD -> DATA -> FCS -> IFG
// FIFO    : first-word-fall-through (tx_fifo_data is the head byte;
//           tx_fifo_rd pops it)
// ============================================================
module mac_tx (
    input  wire       clk,          // 50 MHz system / RMII clock
    input  wire       rst_n,        // Active-low sync reset
    // RMII PHY interface
    output reg  [1:0] rmii_txd,     // 2-bit TX data to PHY
    output reg        rmii_tx_en,   // TX enable to PHY
    // FIFO interface (host side)
    input  wire [7:0] tx_fifo_data, // Head byte of TX FIFO
    input  wire       tx_fifo_empty,
    output reg        tx_fifo_rd,   // Pop strobe
    // Control / status
    input  wire       tx_start,     // Begin transmission
    output reg        tx_busy,
    output reg        tx_done
);
    localparam IDLE     = 3'd0;
    localparam PREAMBLE = 3'd1;
    localparam SFD      = 3'd2;
    localparam DATA     = 3'd3;
    localparam FCS      = 3'd4;
    localparam IFG      = 3'd5;
    localparam IFG_CYCLES = 48;   // 96 bit times / 2 bits per RMII clock

    reg [2:0] state;
    reg [4:0] preamble_cnt;   // 0..6 (7 preamble bytes)
    reg [1:0] dibit_cnt;      // 0..3 (4 dibits per byte)
    reg [7:0] cur_byte;       // Byte currently being serialised
    reg [5:0] ifg_cnt;
    reg [2:0] fcs_byte_idx;   // number of FCS bytes already loaded

    // CRC engine (enabled once per data byte)
    reg         crc_init;
    wire        crc_en = (state == DATA) && (dibit_cnt == 2'd0);
    wire [31:0] crc_out, crc_fcs;

    crc32 u_crc (
        .clk(clk), .rst_n(rst_n),
        .init(crc_init), .en(crc_en),
        .data_in(cur_byte),
        .crc_out(crc_out), .crc_fcs(crc_fcs)
    );

    reg [7:0] fcs_byte;
    always @(*) begin
        case (fcs_byte_idx)
            3'd0:    fcs_byte = crc_fcs[7:0];
            3'd1:    fcs_byte = crc_fcs[15:8];
            3'd2:    fcs_byte = crc_fcs[23:16];
            default: fcs_byte = crc_fcs[31:24];
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state        <= IDLE;
            rmii_txd     <= 2'b00;
            rmii_tx_en   <= 1'b0;
            tx_fifo_rd   <= 1'b0;
            tx_busy      <= 1'b0;
            tx_done      <= 1'b0;
            crc_init     <= 1'b0;
            preamble_cnt <= 5'd0;
            dibit_cnt    <= 2'd0;
            ifg_cnt      <= 6'd0;
            fcs_byte_idx <= 3'd0;
            cur_byte     <= 8'd0;
        end else begin
            tx_done    <= 1'b0;
            tx_fifo_rd <= 1'b0;
            crc_init   <= 1'b0;

            case (state)
                IDLE: begin
                    rmii_tx_en <= 1'b0;
                    rmii_txd   <= 2'b00;
                    tx_busy    <= 1'b0;
                    if (tx_start && !tx_fifo_empty) begin
                        crc_init     <= 1'b1;
                        preamble_cnt <= 5'd0;
                        dibit_cnt    <= 2'd0;
                        fcs_byte_idx <= 3'd0;   // new frame: FCS byte 0 first
                        tx_busy      <= 1'b1;
                        state        <= PREAMBLE;
                    end
                end

                PREAMBLE: begin                 // 7 x 0x55 = 28 dibits of 01
                    rmii_tx_en <= 1'b1;
                    rmii_txd   <= 2'b01;
                    dibit_cnt  <= dibit_cnt + 1;
                    if (dibit_cnt == 2'd3) begin
                        if (preamble_cnt == 5'd6)
                            state <= SFD;
                        else
                            preamble_cnt <= preamble_cnt + 1;
                    end
                end

                SFD: begin                      // 0xD5 LSB first: 01 01 01 11
                    rmii_tx_en <= 1'b1;
                    rmii_txd   <= (dibit_cnt == 2'd3) ? 2'b11 : 2'b01;
                    dibit_cnt  <= dibit_cnt + 1;
                    if (dibit_cnt == 2'd3) begin
                        cur_byte   <= tx_fifo_data;   // first data byte
                        tx_fifo_rd <= 1'b1;           // pop it
                        state      <= DATA;
                    end
                end

                DATA: begin
                    rmii_tx_en <= 1'b1;
                    rmii_txd   <= cur_byte[{dibit_cnt, 1'b0} +: 2];  // LSB first
                    dibit_cnt  <= dibit_cnt + 1;
                    if (dibit_cnt == 2'd3) begin
                        if (tx_fifo_empty) begin      // last byte is going out
                            cur_byte     <= fcs_byte; // FCS byte 0
                            fcs_byte_idx <= 3'd1;
                            state        <= FCS;
                        end else begin
                            cur_byte   <= tx_fifo_data;
                            tx_fifo_rd <= 1'b1;
                        end
                    end
                end

                FCS: begin
                    rmii_tx_en <= 1'b1;
                    rmii_txd   <= cur_byte[{dibit_cnt, 1'b0} +: 2];
                    dibit_cnt  <= dibit_cnt + 1;
                    if (dibit_cnt == 2'd3) begin
                        if (fcs_byte_idx == 3'd4) begin
                            ifg_cnt <= 6'd0;
                            state   <= IFG;
                        end else begin
                            cur_byte     <= fcs_byte;
                            fcs_byte_idx <= fcs_byte_idx + 1;
                        end
                    end
                end

                IFG: begin
                    rmii_tx_en <= 1'b0;
                    rmii_txd   <= 2'b00;
                    ifg_cnt    <= ifg_cnt + 1;
                    if (ifg_cnt == IFG_CYCLES - 1) begin
                        tx_done <= 1'b1;
                        state   <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
