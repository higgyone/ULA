# Using the ULA in another design

How to take this ULA into a larger design: the planned ZX Spectrum repo
(Z80 core, ROM, RAM, video out), or anything else that needs a 6C001.
For every pin's cell, pad type and board circuit, see
[`pinout.md`](pinout.md). This page covers what a *user* of the ULA needs:
what to import, how to clock it, what each port means at the FPGA level, and
what still has to change before it drops into an all-FPGA Spectrum.

## What to import

- **All of `ULA.srcs/sources_1/new/`.** The top entity is `ula`
  (`ULA.vhd`). It instantiates six subsystems (`ula_timing`,
  `ula_video_fetch`, `ula_colour`, `ula_memory_cpu`, `ula_io_port`,
  `ula_sound`) plus `interrupt`. The rest are their blocks and primitives.
- **Exactly one of the two `ula_build_pkg` files per flow.** Both declare
  package `ula_build_pkg`:

  | File | `fpga_build` | Use for |
  |---|---|---|
  | `ula_build_pkg_sim.vhd` | `false` | simulation: the book's NOR-gate storage cells, gate-accurate |
  | `ula_build_pkg_fpga.vhd` | `true` | synthesis: real FPGA flip-flops and latches |

  Compiling both into one library is an error (two packages with the same
  name), and compiling neither leaves the primitives with nothing to select.
  In Vivado, mark the sim file "simulation only" and the fpga file
  "synthesis only" (`used_in_synthesis` / `used_in_simulation`), as this
  repo's `ULA.xpr` does. To simulate exactly what synthesis builds, compile
  the fpga file into the simulation instead.
- **VHDL-2008** for every file. Several blocks read their own `out` ports,
  which VHDL-93 rejects.
- **Recommended:** add this repo as a **git submodule** and point the new
  project at `ULA.srcs/sources_1/new/`, so ULA fixes stay in one place.
  Copying the folder works too, but then fixes have to be carried over by
  hand.
- **Regression gate:** `ULA.srcs/sim_1/new/ula_tb.vhd` drives the ULA through
  a board model (crystal, DRAM, pull-ups) and checks every display pixel of a
  frame, the border, `/INT`, the Z80 clock, port 0xFE and the RAS release.
  Run it after any change to the ULA, with both packages.

## Clock and reset

| Port | Requirement |
|---|---|
| `clk_14` | **14.000 MHz**, the only clock input. On the Arty A7 (100 MHz oscillator): an MMCM with ×7 / ÷50 gives exactly 14.000 MHz. |
| `reset` | **Simulation only.** The real chip has no reset. Tie it to `'0'` in hardware: every flip-flop and latch powers up at `'0'` from its initial value in the bitstream, which is the state the simulation starts from. |

Everything else is derived inside: `clk_7` by a flip-flop divider (never
take `clk_7` from an MMCM: the strobe logic relies on it changing just after
`clk_14`'s edge, see CLAUDE.md), then the ripple counters, the pixel clock
and the FLASH clock. Timing constraints for those derived clocks are step 2
of the "ULA complete" list: until that XDC exists, Vivado cannot time the
ULA.

## Ports

### CPU side

| Port | Dir | Meaning |
|---|---|---|
| `a14`, `a15` | in | Z80 address bits 14, 15 (contended range = 0x4000..0x7FFF) |
| `mreq_n`, `rd_n`, `wr_n` | in | Z80 strobes, active low |
| `ioreq_n` | in | ULA port select, active low. **Not** the Z80's `/IORQ`: on the PCB it is `/IORQ OR A0`, so it is low only for an even port address. Make that gate in the new design. |
| `a0` | inout | the DRAM address pin A0, which the ULA also reads as CPU A0 for the port decode (see below) |
| `int_n` | out | `/INT`, once per frame (line 248, 64 pixels = 32 T-states). Open collector: `'0'` or `'H'`. |
| `phicpu_n` | out | pin 32, the Z80 clock **inverted** (3.5 MHz, stretched by contention). Open collector: `'0'` or `'Z'`; the PCB has a 1k pull-up and an NPN that inverts it back. |

### DRAM side (lower 16K, 4116-style multiplexed)

| Port | Dir | Meaning |
|---|---|---|
| `ras_n` | out | RAS for CPU and video accesses. Tri-state: `'Z'` while the ULA releases it in border ROM-area cycles (6C001 behaviour). |
| `cas_n`, `we_n` | out | CAS and write enable |
| `rom_cs_n` | out | ROM chip select (0x0000..0x3FFF) |
| `a0`..`a6` | out (`a0` inout) | the ULA drives the video row then column during its fetches; otherwise the PCB's '157 muxes drive the CPU address (row while `ras_n` is high, column once it falls) |
| `d0`..`d7` | inout (`d5` in) | the data bus. The ULA **reads** it during video fetches (pixel and attribute bytes) and port writes, and **drives** `d0`..`d4` and `d6` on a port 0xFE read (open collector). It never drives `d7`. |

The DRAM protocol the ULA expects is exactly the board model in `ula_tb`:
row latched on `ras_n` falling, column on `cas_n` falling, data on the bus
**40 ns** after CAS falls and released (`'Z'`) when CAS rises. A block-RAM
model must meet that 40 ns: a synchronous RAM clocked fast enough to answer
within it, or one that reads on the RAS/column edge and presents the byte by
then.

### Keyboard, tape, sound

| Port | Dir | Meaning |
|---|---|---|
| `k1`..`k4` | in | keyboard columns, active low (the 8×5 matrix and half-row select are on the PCB) |
| `k0` | inout | keyboard column 0; in wafer test mode B the ULA drives v8 out on it (open collector) |
| `d5` | in | input only (no output transistor on that pin) |
| `sound` | out | pin 28's level in millivolts (`millivolts_t`, 342..3753 mV): MIC and speaker |
| `tape_mv` | in | the tape signal on pin 28 in millivolts, AC (`integer`, can be negative). The pin is split in two because VHDL cannot resolve two integer drivers. |

### Video

| Port | Dir | Meaning |
|---|---|---|
| `y_n`, `u`, `v` | out | the analogue luminance (inverted) and colour differences, in millivolts (`millivolts_t`, 0..4300). They model the ULA's resistor network for simulation and are **not** FPGA pins: an FPGA needs a DAC, or the digital colour below. |

## What changes for an all-FPGA Spectrum

The `ula` entity models **the 40 pins of the real chip**, with real pad
behaviour (open collector, tri-state, weak pull-ups, analogue levels). That
is right for simulation and for driving a real Spectrum board through IOBUFs,
but not for connecting the ULA to a Z80 core **inside** the same FPGA:

1. **No tri-states or weak pulls inside an FPGA.** `'Z'` and `'H'` only work
   at a real pin (an IOBUF, plus a PULLUP constraint for `'H'`). Inside the
   fabric, `d0`..`d7`, `a0`, `k0`, `int_n`, `ras_n` and `phicpu_n` need
   explicit signals instead: for example `d_in` / `d_out` / `d_oe` per pin,
   with the bus merge done as a mux in the Spectrum top level. Vivado can
   turn some internal tri-states into muxes on its own, but a weak `'H'`
   driver has no meaning in the fabric (it ends up as a constant or a
   multiple-driver error), so this needs a small FPGA-facing wrapper.
   Not yet tried in synthesis: the out-of-context runs so far leave the pins
   as ports.
2. **Digital video out.** For VGA, export the digital colour that
   `ula_colour` already provides (`red`, `green`, `blue`, `hl` = BRIGHT, all
   `'0'` in blanking) plus horizontal and vertical sync (`ula_timing`
   already exports `vsync`; `hsync_6c` comes out of `video_sync` inside it
   but is mapped `open`, so it needs one new port). Today the colour stops
   at internal signals of `ula` (`s_red` ..).
   The 15.6 kHz / 50 Hz video then needs a scan doubler for a VGA monitor
   (720×576@50 timing, 31.25 kHz): Spectrum-repo work.
3. **The CPU clock.** A Z80 core needs a clock-enable or clock, not an
   open-collector pin: export `ula_memory_cpu`'s `cpuclk` (the non-inverted
   3.5 MHz clock, held high during contention), currently left `open`.
4. **Analogue ports.** Leave `y_n`, `u`, `v`, `sound`, `tape_mv` unconnected
   in synthesis (they are integers; synthesis trims what nothing uses), or
   map `sound` to a 1-bit audio output from the speaker / MIC bits.

These are additions on the Spectrum side (a wrapper entity, extra ports), not
changes to the ULA's logic.
