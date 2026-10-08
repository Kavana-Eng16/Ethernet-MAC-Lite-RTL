// ============================================================
// Module : tb_mac_top.v
// Purpose : Self-checking Ethernet MAC testbench - PHY loopback
//           TX output is looped back to RX input.
//           Every frame = 14-byte header + payload (+4-byte FCS added by MAC)
// ============================================================
`timescale 1ns/1ps
module tb_mac_top;
    parameter CLK_PERIOD = 20;  // 50 MHz -> 20 ns

    reg clk, rst_n;

    // TX FIFO model (first-word-fall-through)
    reg  [7:0]  tx_mem [0:2047];
    reg  [10:0] tx_wr_ptr, tx_rd_ptr;
    wire [7:0]  tx_fifo_data;
    wire        tx_fifo_empty;
    wire        tx_fifo_rd;
    reg         tx_start;
    wire        tx_busy, tx_done;

    // RMII loopback with optional single-dibit error injection
    wire [1:0] rmii_txd;
    wire       rmii_tx_en;
    reg        inject_en;
    integer    txen_cnt;
    wire       flip = inject_en && (txen_cnt == 100);
    wire [1:0] rmii_rxd = rmii_txd ^ {1'b0, flip};

    // RX FIFO model
    reg  [7:0]  rx_mem [0:2047];
    reg  [10:0] rx_wr_ptr;
    wire [7:0]  rx_fifo_data;
    wire        rx_fifo_wr;
    wire        rx_done, crc_error, frame_error;

    integer pass_cnt = 0, fail_cnt = 0;

    assign tx_fifo_data  = tx_mem[tx_rd_ptr];
    assign tx_fifo_empty = (tx_wr_ptr == tx_rd_ptr);

    always @(posedge clk) begin
        if (!rst_n) tx_rd_ptr <= 0;
        else if (tx_fifo_rd) tx_rd_ptr <= tx_rd_ptr + 1;
    end

    always @(posedge clk) begin
        if (!rst_n) rx_wr_ptr <= 0;
        else if (rx_fifo_wr) begin
            rx_mem[rx_wr_ptr] <= rx_fifo_data;
            rx_wr_ptr <= rx_wr_ptr + 1;
        end
    end

    always @(posedge clk)
        if (rmii_tx_en) txen_cnt <= txen_cnt + 1; else txen_cnt <= 0;

    // Latch RX status (flags are 1-cycle pulses)
    reg lat_crc, lat_frm, got_rx;
    always @(posedge clk) begin
        if (rx_done) begin
            lat_crc <= crc_error;
            lat_frm <= frame_error;
            got_rx  <= 1'b1;
        end
    end

    mac_top dut (
        .clk(clk), .rst_n(rst_n),
        .rmii_txd(rmii_txd), .rmii_tx_en(rmii_tx_en),
        .rmii_rxd(rmii_rxd), .rmii_crs_dv(rmii_tx_en),   // PHY loopback
        .tx_fifo_data(tx_fifo_data), .tx_fifo_empty(tx_fifo_empty),
        .tx_fifo_rd(tx_fifo_rd), .tx_start(tx_start),
        .tx_busy(tx_busy), .tx_done(tx_done),
        .rx_fifo_data(rx_fifo_data), .rx_fifo_wr(rx_fifo_wr),
        .rx_done(rx_done), .crc_error(crc_error), .frame_error(frame_error)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task report;
        input [255:0] name;
        input         ok;
        begin
            if (ok) begin $display("PASS: %0s", name); pass_cnt = pass_cnt + 1; end
            else    begin $display("FAIL: %0s", name); fail_cnt = fail_cnt + 1; end
        end
    endtask

    // Send one frame and check it.
    //   pattern: 0 = incrementing, 1 = all 0x00, 2 = all 0xFF
    //   exp_crc / exp_frm: expected error flags
    task run_frame;
        input [255:0] name;
        input integer payload_len;
        input integer pattern;
        input         inject;
        input         exp_crc;
        input         exp_frm;
        integer i, total, mism;
        begin
            total = 14 + payload_len;
            for (i = 0; i < 6;  i = i + 1) tx_mem[i] = 8'hFF;            // DA
            for (i = 0; i < 6;  i = i + 1) tx_mem[6+i] = 8'h10 + i;      // SA
            tx_mem[12] = 8'h08; tx_mem[13] = 8'h00;                      // EtherType
            for (i = 14; i < total; i = i + 1)
                tx_mem[i] = (pattern == 1) ? 8'h00 :
                            (pattern == 2) ? 8'hFF : i[7:0];
            tx_wr_ptr = total; tx_rd_ptr = 0; rx_wr_ptr = 0;
            got_rx = 0; inject_en = inject;
            @(negedge clk); tx_start = 1;
            @(negedge clk); tx_start = 0;
            wait (got_rx);
            wait (tx_done);            // let the inter-frame gap finish
            @(posedge clk);
            inject_en = 0;
            mism = 0;
            if (!inject)
                for (i = 0; i < total; i = i + 1)
                    if (rx_mem[i] !== tx_mem[i]) mism = mism + 1;
            report(name, (lat_crc === exp_crc) && (lat_frm === exp_frm) &&
                         (mism == 0) && (rx_wr_ptr == total + 4));
        end
    endtask

    initial begin
        $dumpfile("mac_sim.vcd");
        $dumpvars(0, tb_mac_top);
        rst_n = 0; tx_start = 0; inject_en = 0; got_rx = 0;
        lat_crc = 0; lat_frm = 0;
        tx_wr_ptr = 0; tx_rd_ptr = 0; rx_wr_ptr = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        //          name                              payload pattern inj  crc  frm
        run_frame("Min frame (46-byte payload)",          46, 0, 0, 0, 0);
        run_frame("100-byte payload",                    100, 0, 0, 0, 0);
        run_frame("Max frame (1500-byte payload)",      1500, 0, 0, 0, 0);
        run_frame("All-zero payload",                     46, 1, 0, 0, 0);
        run_frame("All-0xFF payload",                     46, 2, 0, 0, 0);
        run_frame("Back-to-back frame 1",                 64, 0, 0, 0, 0);
        run_frame("Back-to-back frame 2",                 64, 0, 0, 0, 0);
        run_frame("CRC error injection",                  64, 0, 1, 1, 0);
        run_frame("Runt frame (<64 bytes)",               20, 0, 0, 0, 1);
        run_frame("Giant frame (>1518 bytes)",          1501, 0, 0, 0, 1);

        // Reset during TX: MAC must return to IDLE with tx_en = 0
        begin : rst_test
            integer i;
            for (i = 0; i < 74; i = i + 1) tx_mem[i] = i[7:0];
            tx_wr_ptr = 74; tx_rd_ptr = 0;
            @(negedge clk); tx_start = 1;
            @(negedge clk); tx_start = 0;
            repeat(60) @(posedge clk);
            rst_n = 0;
            repeat(3) @(posedge clk);
            #1;
            report("Reset during TX", (rmii_tx_en == 0) && (tx_busy == 0));
            rst_n = 1;
            repeat(5) @(posedge clk);
        end

        // Frame after reset still works
        run_frame("Frame after reset",                    46, 0, 0, 0, 0);

        $display("\n=== Results: %0d PASS / %0d FAIL ===", pass_cnt, fail_cnt);
        #1000;
        $finish;
    end

    initial begin
        #100_000_000;
        $display("TIMEOUT");
        $finish;
    end
endmodule
