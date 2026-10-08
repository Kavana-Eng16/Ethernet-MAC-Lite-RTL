# Ethernet MAC (Lite) - RTL Design and Verification

Verilog HDL implementation of a lightweight full-duplex Ethernet MAC with a 2-bit
RMII interface, built as Project 7 of the **L&T EduTech - VLSI Principles, RTL Design &
Verification** program. Verified in simulation with a self-checking, PHY-loopback testbench.

## My contribution
Started from the course design (see `docs/Ethernet_MAC_Lite_Project.pdf`), ran it in
Icarus Verilog, found that it failed, debugged it with waveforms and a Python CRC-32 reference,
fixed the RTL, and extended the testbench from 5 to 12 self-checking tests that also compare
received data against transmitted data. All fixes are listed under *Bugs found and fixed*.

## Features
- Full-duplex MAC, RMII 2-bit interface at 50 MHz (100 Mbps)
- TX path: 7-byte preamble (0x55), SFD (0xD5), FIFO read, CRC-32 FCS append, 96-bit-time inter-frame gap
- RX path: preamble/SFD detection, dibit-to-byte deserialiser, CRC-32 residue check (0xC704DD7B)
- IEEE 802.3 CRC-32 engine (polynomial 0x04C11DB7)
- Runt (<64 B) and giant (>1518 B) frame detection, CRC error flag
- 2-FF synchroniser on RMII RX inputs

## Architecture
`mac_top` instantiates `mac_tx` and `mac_rx`; each contains its own `crc32` engine.

| File | Purpose |
|------|---------|
| `rtl/crc32.v` | Byte-serial IEEE 802.3 CRC-32 |
| `rtl/mac_tx.v` | TX FSM: IDLE, PREAMBLE, SFD, DATA, FCS, IFG |
| `rtl/mac_rx.v` | RX FSM: IDLE, PREAM, DATA, STATUS |
| `rtl/mac_top.v` | Top-level integration |
| `tb/tb_mac_top.v` | Self-checking PHY-loopback testbench |

Frame format: Preamble (7 B) | SFD (1 B) | DA (6 B) | SA (6 B) | EtherType (2 B) | Payload (46-1500 B) | FCS (4 B)

## Verification results
Simulator: Icarus Verilog 12.0. Each test transmits a frame, loops it back, then checks the
error flags, the received byte count, and every received byte against what was sent.

| # | Test | Result |
|---|------|--------|
| 1 | Minimum frame (46-byte payload) | PASS |
| 2 | 100-byte payload | PASS |
| 3 | Maximum frame (1500-byte payload) | PASS |
| 4 | All-zero payload | PASS |
| 5 | All-0xFF payload | PASS |
| 6-7 | Back-to-back frames (2 frames, each checked) | PASS |
| 8 | CRC error injection (1 flipped dibit) -> `crc_error = 1` | PASS |
| 9 | Runt frame (<64 bytes) -> `frame_error = 1` | PASS |
| 10 | Giant frame (>1518 bytes) -> `frame_error = 1` | PASS |
| 11 | Reset during TX -> `rmii_tx_en = 0`, `tx_busy = 0` | PASS |
| 12 | Frame sent correctly after reset | PASS |

**12 PASS / 0 FAIL.**

Independent check: the FCS of every transmitted frame was compared with Python's
`zlib.crc32`, and all complete frames matched. Measured inter-frame gap is 50 clock
cycles (required minimum: 48 cycles = 96 bit times at 2 bits per clock).

```
PASS: Min frame (46-byte payload)
PASS: 100-byte payload
PASS: Max frame (1500-byte payload)
PASS: All-zero payload
PASS: All-0xFF payload
PASS: Back-to-back frame 1
PASS: Back-to-back frame 2
PASS: CRC error injection
PASS: Runt frame (<64 bytes)
PASS: Giant frame (>1518 bytes)
PASS: Reset during TX
PASS: Frame after reset

=== Results: 12 PASS / 0 FAIL ===
```

### Waveforms
![Full frame](sim/waveform_frame1_full.png)
![Preamble and SFD](sim/waveform_preamble_sfd.png)

## Bugs found and fixed
Running the original design failed on the first test (`crc=x frame_err=1`) and then hung.
The fixes:

1. **RX SFD alignment.** 0xD5 is sent LSB first (01 01 01 11), so the `11` dibit is the *last* SFD dibit. The RX treated it as the first and dropped one data dibit, so every byte was misaligned. The RX now starts data capture right after `11`.
2. **RX CRC timing.** The CRC engine was fed `byte_shift` before the final dibit had shifted in. It now receives the completed byte.
3. **TX data/CRC pipeline.** `byte_reg` was driven from two `always` blocks, the CRC was computed over the *next* FIFO byte instead of the byte being sent, and each FCS byte was loaded and sent in the same cycle (so the old value went out). The TX datapath is rewritten with a single `cur_byte` register and the CRC enabled on the byte being transmitted.
4. **FCS byte order.** `crc_fcs` reflected each byte but did not swap byte order. It now reflects the full 32-bit register as 802.3 requires.
5. **Inter-frame gap.** 24 cycles was only 48 bit times. RMII sends 2 bits per clock, so 96 bit times is 48 cycles.
6. **Stale FCS index.** `fcs_byte_idx` was not cleared between frames, corrupting the first FCS byte of every frame after the first.
7. **Testbench.** Frames had no 14-byte header, so the "minimum frame" was a runt. The testbench also did not wait for `tx_done`, so the next frame's start was missed during the gap. It now builds full frames, waits for the gap, and compares data.

## Known limitations / future work
- Verified in simulation only; **FPGA validation has not been done**
- "False start (no SFD)" case is not yet tested
- TX and RX share no CRC engine (each has its own)
- No host-side FIFO RTL; FIFOs are behavioural models in the testbench

## How to run
```bash
iverilog -o sim/mac_sim rtl/crc32.v rtl/mac_tx.v rtl/mac_rx.v rtl/mac_top.v tb/tb_mac_top.v
cd sim && vvp mac_sim
gtkwave mac_sim.vcd
```

## Tools
Icarus Verilog, GTKWave, Python (reference CRC check)

## Author
Kavana N | Sir MVIT, Bengaluru
