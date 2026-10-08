// ============================================================
// Module : mac_top.v
// Purpose : Top-level Ethernet MAC Lite Controller
// ============================================================
module mac_top (
    // Global
    input  wire       clk,            // 50 MHz
    input  wire       rst_n,          // Active-low sync reset
    // RMII PHY interface - TX
    output wire [1:0] rmii_txd,
    output wire       rmii_tx_en,
    // RMII PHY interface - RX
    input  wire [1:0] rmii_rxd,
    input  wire       rmii_crs_dv,
    // TX FIFO interface (host)
    input  wire [7:0] tx_fifo_data,
    input  wire       tx_fifo_empty,
    output wire       tx_fifo_rd,
    input  wire       tx_start,
    output wire       tx_busy,
    output wire       tx_done,
    // RX FIFO interface (host)
    output wire [7:0] rx_fifo_data,
    output wire       rx_fifo_wr,
    output wire       rx_done,
    output wire       crc_error,
    output wire       frame_error
);
    // Transmitter
    mac_tx u_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .rmii_txd      (rmii_txd),
        .rmii_tx_en    (rmii_tx_en),
        .tx_fifo_data  (tx_fifo_data),
        .tx_fifo_empty (tx_fifo_empty),
        .tx_fifo_rd    (tx_fifo_rd),
        .tx_start      (tx_start),
        .tx_busy       (tx_busy),
        .tx_done       (tx_done)
    );

    // Receiver
    mac_rx u_rx (
        .clk          (clk),
        .rst_n        (rst_n),
        .rmii_rxd     (rmii_rxd),
        .rmii_crs_dv  (rmii_crs_dv),
        .rx_fifo_data (rx_fifo_data),
        .rx_fifo_wr   (rx_fifo_wr),
        .rx_done      (rx_done),
        .crc_error    (crc_error),
        .frame_error  (frame_error)
    );
endmodule
