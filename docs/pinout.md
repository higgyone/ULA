# ULA pinout (6C001, 40-pin)

Every pin of the ZX Spectrum ULA, its peripheral cell and pad type (from Chris
Smith's *The ZX Spectrum ULA*), the board circuit around it, and the block in
this design that drives or reads it. Reviewed pin by pin on 2026-10-21. This is
the port list for the Phase 7 top level (`ULA.vhd`).

Status: ✅ matches · ✅ sim = correct in simulation, needs hardware work for the
FPGA · n/a = no VHDL port. Pad fixes 1-4 are done (PR `pad-fixes`); fix 5
belongs to the top level.

## Pad types

| Pad | VHDL model | Pins |
|---|---|---|
| TTL input (voltage divider + emitter follower, TTL → CML, non-inverting) | plain `in std_logic` | `/WR`, `/RD`, `/IOREQ`, A14, A15, `/MREQ` |
| Totem-pole output | plain `out`, drives `'0'` / `'1'` | `/CAS`, `/WE`, `/ROMCS` |
| Tri-state totem-pole output | `'0'` / `'1'` when enabled, else `'Z'` (no pull-up) | `/RAS`, A0–A6 |
| Collector follower (open collector) + **weak** on-chip pull-up, with an emitter-follower input on the same pin | `'0'` or `'H'`; reads the resolved pin | D0–D4, D6, D7 |
| Collector follower + **strong** on-chip pull-up (fast edges) | `'0'` or `'H'` | `/INT` |
| Emitter-follower input + weak on-chip pull-up, biased for the keyboard's reduced voltage swing | `in`, plus a weak `'H'` | K0–K4 |
| Inverting open collector, **no** on-chip pull-up | `'0'` or `'Z'` | `/phicpu` |
| Input only (no output transistor) | `in` | D5 |
| Analogue | `millivolts_t` in simulation | U, V, `/Y`, SOUND |
| Oscillator / supply | — | XTAL, Vcc ×2, GND |

## Pin table

| Pin | Book name | Cell | Pad | Function | Design: drives / reads | Status |
|---|---|---|---|---|---|---|
| 1 | `/CAS` | 18 | totem pole out | lower-16K DRAM column strobe | `cpu_memory_access.cas_n` | ✅ |
| 2 | `/WR` | 17 | TTL in | Z80 write | `wr_n` → `cpu_memory_access`, `io_port_decode_0xfe`, `test_modes` | ✅ |
| 3 | `/RD` | 16 | TTL in | Z80 read | `rd_n` → `cpu_memory_access`, `io_port_decode_0xfe`, `test_modes` | ✅ |
| 4 | `/WE` | 15 | totem pole out | lower-16K DRAM write enable | `cpu_memory_access.we_n` | ✅ |
| 5 | A0 | 14 | tri-state totem pole out + TTL in | multiplexed DRAM address; read for the port decode | out: `video_address_generation.a0`; in: `io_port_decode_0xfe.a0` | ✅ (fix 1 done) |
| 6 | A1 | 13 | tri-state totem pole out | multiplexed DRAM address | `video_address_generation.a1` | ✅ (fix 1 done) |
| 7 | A2 | 12 | tri-state totem pole out | multiplexed DRAM address | `video_address_generation.a2` | ✅ (fix 1 done) |
| 8 | A3 | 11 | tri-state totem pole out | multiplexed DRAM address | `video_address_generation.a3` | ✅ (fix 1 done) |
| 9 | A4 | 10 | tri-state totem pole out | multiplexed DRAM address | `video_address_generation.a4` | ✅ (fix 1 done) |
| 10 | A5 | 9 | tri-state totem pole out | multiplexed DRAM address | `video_address_generation.a5` | ✅ (fix 1 done) |
| 11 | A6 | 8 | tri-state totem pole out | multiplexed DRAM address | `video_address_generation.a6` | ✅ (fix 1 done) |
| 12 | `/INT` | 7 | collector follower + strong on-chip pull-up | Z80 maskable interrupt, once a frame | `interrupt.int_n` | ✅ (fix 4 done) |
| 13 | Vcc (logic) | — | supply | 5 V logic supply | — | n/a |
| 14 | Vcc (I/O) | 5, 6 | supply | 5 V analogue and interface supply | — | n/a |
| 15 | U | 2, 3, 4 | analogue | colour difference | `yuv_video.u` (mV) | ✅ sim |
| 16 | V | 45, 46, 1 | analogue | colour difference | `yuv_video.v` (mV) | ✅ sim |
| 17 | `/Y` | 49, 50 | analogue | inverted luminance + sync | `yuv_video.y_n` (mV) | ✅ sim |
| 18 | D0 | 43 | open collector (weak pull-up) + TTL in | data bus | out: `keyboard_input.do_0`; in: `border_reg.di_0`, video latches bit 0 | ✅ |
| 19 | K0 | 42 | emitter-follower in + weak pull-up; open-collector out (die test) | keyboard column 0 | in: `keyboard_input.k0`; out: `test_modes.k0` (`v8_n` in test mode B) | ✅ |
| 20 | K1 | 41 | emitter-follower in + weak pull-up | keyboard column 1 | `keyboard_input.k1` | ✅ (`in`; pull-up: fix 5) |
| 21 | D1 | 40 | open collector (weak pull-up) + TTL in | data bus | out: `keyboard_input.do_1`; in: `border_reg.di_1`, video latches bit 1 | ✅ |
| 22 | D2 | 39 | open collector (weak pull-up) + TTL in | data bus | out: `keyboard_input.do_2`; in: `border_reg.di_2`, video latches bit 2 | ✅ |
| 23 | K2 | 38 | emitter-follower in + weak pull-up | keyboard column 2 | `keyboard_input.k2` | ✅ (`in`; pull-up: fix 5) |
| 24 | K3 | 37 | emitter-follower in + weak pull-up | keyboard column 3 | `keyboard_input.k3` | ✅ (`in`; pull-up: fix 5) |
| 25 | D3 | 36 | open collector (weak pull-up) + TTL in | data bus | out: `keyboard_input.do_3`; in: `cassette_speaker_out.di_3` (MIC), video latches bit 3 | ✅ |
| 26 | K4 | 35 | emitter-follower in + weak pull-up | keyboard column 4 | `keyboard_input.k4` | ✅ (`in`; pull-up: fix 5) |
| 27 | D4 | 34 | open collector (weak pull-up) + TTL in | data bus | out: `keyboard_input.do_4`; in: `cassette_speaker_out.di_4` (speaker), video latches bit 4 | ✅ |
| 28 | SOUND | 32, 33 | analogue | MIC / speaker out, EAR in, on one pin | `sound_io`: `sound` out, `tape_mv` in (mV); `ear` → `cassette_input`; `mic`/`speaker` from `cassette_speaker_out` | ✅ sim (fix 3 done) |
| 29 | D5 | 31, 28 | **input only** | data bus | never driven; read by the video latches bit 5 | ✅ |
| 30 | D6 | 30 | open collector (weak pull-up) + TTL in | data bus | out: `cassette_input.do_6` (EAR); in: video latches bit 6 | ✅ |
| 31 | D7 | 29 | open collector (weak pull-up) + TTL in | data bus | out: nothing ever pulls it low; in: video latches bit 7 | ✅ |
| 32 | `/phicpu` | 28 | inverting open collector | inverted 3.5 MHz Z80 clock | `contention_handler_3.phicpu_n`: `'0'` / `'Z'` | ✅ (fix 2 done) |
| 33 | `/IOREQ` | 27 | TTL in | I/O port select (board: /IORQ OR A0) | `ioreq_n` → `io_port_decode_0xfe`, `contention_handler_3`, `test_modes` | ✅ |
| 34 | `/ROMCS` | 26 | totem pole out | ROM chip enable (address only, not MREQ-qualified) | `cpu_memory_access.rom_cs_n` | ✅ |
| 35 | `/RAS` | 25 | tri-state totem pole out | lower-16K DRAM row strobe | `cpu_memory_access.ras_n` (released by `rasen_n`) | ✅ (fix 4 done) |
| 36 | A14 | 24 | TTL in | Z80 address | `a14` → `cpu_memory_access`, `contention_handler_3` | ✅ |
| 37 | A15 | 23 | TTL in | Z80 address | `a15` → `cpu_memory_access`, `contention_handler_3` | ✅ |
| 38 | `/MREQ` | 22 | TTL in | Z80 memory request | `mreq_n` → `cpu_memory_access`, `contention_handler_3`, `test_modes` | ✅ |
| 39 | XTAL | 20, 21 | oscillator | 14 MHz crystal | `clk_14` (master clock input) | ✅ sim |
| 40 | GND | 19 | supply | 0 V | — | n/a |

## Notes by pin group

**Address bus A0–A6 (pins 5–11).** Tri-state, enabled only during a video
fetch, when the internal `/AE` (`ae_n`) is active. Otherwise the PCB's '157
multiplexers drive the pins with the CPU address, switched by `/RAS`. A0 is
special: the Z80's A0 reaches pin 5 through the '157 and a **bus-isolating
resistor**, and the ULA buffers it (TTL → CML) for the I/O port decode. A1–A6
have no input buffer.

**`/INT` (pin 12).** A non-inverting collector follower with a **strong** on-chip
pull-up for fast edges. On the board it reaches the Z80's /INT (and the
expansion bus) through **470 Ω**.

**Data bus D0–D7 (pins 18, 21, 22, 25, 27, 29, 30, 31).** Collector-follower
outputs with **weak** on-chip pull-ups, because the bus is shared, plus
emitter-follower input buffers. D5 is input only, because its peripheral cell
(31) is the analogue cassette interface; its logic is in cell 28. Only D0–D4
(keyboard) and D6 (EAR) are ever pulled low by the ULA, so on a port read bits 5
and 7 read `1`. Board: **8k2 pull-ups** on D0–D7, and the Z80's data bus joins
the ULA/DRAM side through **470 Ω** per bit, so a video fetch doesn't disturb
the CPU.

**Keyboard K0–K4 (pins 19, 20, 23, 24, 26).** Emitter-follower inputs with weak
on-chip pull-ups, biased for the smaller swing a key contact and cable give.
Board: **10k pull-ups**. A pressed key in a selected half-row (Z80 A8–A15 low)
sinks current and pulls the column low. K0 also has an open-collector output,
used in wafer test mode B to put `v8_n` on the pin (`test_modes`); outside test
mode it is released.

**SOUND (pin 28).** One analogue pin for MIC out, speaker out and EAR in.
ULA output level, by (speaker = D4, MIC = D3):

| Speaker | MIC | Pin 28 |
|---|---|---|
| 0 | 0 | 0.342 V |
| 0 | 1 | 0.652 V |
| 1 | 0 | 3.591 V |
| 1 | 1 | 3.753 V |

The EAR input is bistable and switches at **0.714 V**. To load a tape the ROM
sets MIC = 1, speaker = 0, biasing the pin at 0.652 V, just under the switch
point, so a small tape signal flips it. With no tape, EAR (bit 6) follows the
speaker bit only (issue 3 behaviour). Board: the speaker is fed through **two
diode drops (~1.4 V)**, so only the speaker bit is heard; MIC socket through
**680 Ω + 100 nF**; EAR socket through **4k1 + 100 nF**; **10 nF** from pin 28
to ground.

**`/phicpu` (pin 32).** Inverting open collector, **1k pull-up to 5 V on the
PCB**. It drives the base of a common-emitter NPN whose collector is the Z80
clock, pulled up by **180 Ω**. Two inversions: Z80 CLK = `cpuclk` (= `c0`, held
high during contention). The transistor and the 180 Ω give the Z80 the full 5 V
clock swing that TTL can't.

**`/IOREQ` (pin 33).** Made off-chip as Z80 /IORQ OR A0, so it only goes low for
even I/O addresses (the ULA's port).

**`/RAS` (pin 35).** Tri-state, released by
`rasen_n = NOR(a14, a15, mreq_n, border_n)` (MREQ in 0x0000–0x3FFF in the border)
so that on issue 1/2 boards the Z80's `/RFSH`, wired to the RAS line through
**330 Ω**, can refresh the DRAM. Issue 3 removed that link. The book calls the
enable an **implementation error**: meant to be enabled only when the video
generator or the Z80 needs the DRAM, it is in fact enabled for most of the
time. The design reproduces the book's gate as built.

## Pad fixes

| # | Change | Where | Status |
|---|---|---|---|
| 1 | Tri-state `a0..a6` on `ae_n`; A0 becomes `inout` at the top level, read by the port decode | `video_address_generation` + TB | ✅ done |
| 2 | `/phicpu` open collector: `'0'` / `'Z'`; TB adds the 1k pull-up and the PCB transistor | `contention_handler_3` + TB | ✅ done |
| 3 | New behavioural `sound_io`: (speaker, mic) → 4 levels in mV; EAR = pin > 714 mV | new block + TB | ✅ done |
| 4 | Header notes: 470 Ω on `/INT`; the `/RAS` "implementation error" | `interrupt`, `cpu_memory_access` | ✅ done |
| 5 | Top-level directions: A0 and K0 `inout`, K1–K4 `in`. The K pull-ups (on-chip weak + PCB 10k) are NOT VHDL drivers: they are `'H'` in the system TB's board model and a `PULLUP` in the XDC | `ULA.vhd`, system TB, XDC | ⏳ Phase 7 |

## Phase 7: board and hardware items

- **DAC boundary** for U, V, `/Y` (and SOUND if kept analogue): `millivolts_t` →
  DAC codes, or PWM / sigma-delta with an RC filter.
- **Clock:** the Arty A7 has a 100 MHz oscillator. An MMCM gives exactly
  14.000 MHz (100 MHz × 7 = 700 MHz VCO, ÷ 50) for `clk_14`, in an FPGA wrapper
  outside the ULA model.
- **Weak `'H'` does not synthesise.** Vivado treats `'H'` as a plain `'1'`, so
  every open-collector output modelled as `'0'` / `'H'` (D0–D4, D6, K0,
  `/INT`) would become a strong push-pull driver on the FPGA and fight the
  bus. For hardware, those pins must release to `'Z'` with a `PULLUP` in the
  XDC (in an FPGA wrapper, or a synthesis-only variant). Simulation is
  unaffected: `'0'` / `'H'` is the right model there.
- **Levels:** the Artix-7's I/O is 3.3 V and not 5 V tolerant; a real Spectrum
  board needs 5 V ↔ 3.3 V level shifting on every signal pin. The keyboard's
  reduced swing must still read as a low.
- **Board model for the system TB:** the series resistors (Z80 data 470 Ω, A0
  '157 isolating resistor, `/RFSH` 330 Ω, `/INT` 470 Ω) as weak links between
  two nets; pull-ups (D 8k2, K 10k, pin 32 1k, Z80 CLK 180 Ω); the pin 32 NPN
  stage; the pin 28 MIC / speaker / EAR network.
