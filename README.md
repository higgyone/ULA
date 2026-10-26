# ULA for the ZX Spectrum

Gate-accurate VHDL recreation of the Ferranti/Amstrad ULA (6C001E-7) used in
the **ZX Spectrum 48K**, targeting a Digilent **Arty A7-35T** FPGA board
(Artix-7 XC7A35T) and developed in **Vivado**.

The implementation follows Chris Smith's book *The ZX Spectrum ULA*, as closely as possible. 
Buy the book, it is great!

## Status: complete

The whole ULA is built, verified in simulation and **running on the Arty**:

- **Timing:** 14 MHz crystal → 7 MHz pixel clock; 9-bit horizontal counter
  (448 pixels, 64 µs line) and 9-bit vertical counter (312 lines, 50.08 Hz
  frame), both ripple counters as in the original; hsync (5C and 6C), vsync,
  composite sync, blanking, border.
- **Video:** display and attribute fetch from the lower 16K DRAM (RAS/CAS,
  the scrambled screen address on A0–A6), the pixel shift register, the
  attribute double buffer, FLASH, the border colour, and the analogue
  **/Y, U, V** outputs with the PAL colour burst.
- **CPU interface:** memory and ROM decode, the DRAM strobe merge (including
  the 6C001's RAS release in the border), CPU clock contention, the frame
  interrupt, port 0xFE (keyboard, EAR, border colour, MIC and speaker), and
  the wafer test modes.

### How it is verified

- **Block testbenches:** every block has a self-checking testbench (39 in
  `ULA.srcs/sim_1/new/`), run in Vivado's xsim and in GHDL.
- **System testbench `ula_tb`:** drives only the 40 pins through a model of
  the Spectrum board (crystal, DRAM with a test screen, pull-ups) and checks
  every display pixel of a frame, the border, `/INT`, the CPU clock, a port
  read and the RAS release. It found five bugs no block testbench could see.
- **On the board:** `arty_top` runs the ULA on the Arty and was measured with
  an oscilloscope: `/INT` every 19.97 ms, 9.14 µs (64 pixels) wide; video
  `/RAS` bursts in the display part of each 64 µs line; the CPU clock at
  3.5 MHz.

## One design, two builds

The book's flip-flops and latches are cross-coupled NOR gates. They simulate
faithfully, but on an FPGA they become combinational loops that cannot be
timed. Every storage cell therefore has two versions, chosen by one constant:

| Package file | `fpga_build` | Used for |
|---|---|---|
| `ula_build_pkg_sim.vhd` | `false` | simulation: the book's NOR gates |
| `ula_build_pkg_fpga.vhd` | `true` | synthesis: real FPGA flip-flops and latches |

Everything above the storage cells is the same gates in both builds, and the
system testbench passes with either package.

## Repository layout

```
ULA.srcs/
  sources_1/new/        the VHDL: ULA.vhd (top), six subsystems, blocks,
                        primitives, ula_build_pkg_*.vhd, arty_top.vhd
  sources_1/ip/         clk_wiz_14 (Clocking Wizard: 100 -> 14 MHz)
  sim_1/new/            testbenches (ula_tb is the system test)
  arty_35/new/          ula_clocks.xdc (timing), ula_standalone.xdc
  arty_35/imports/      Arty-A7-35-Master.xdc (board pins)
docs/
  pinout.md             all 40 pins: cell, pad type, board circuit, owner
  ula_interface.md      how to use the ULA in a larger design
diagram/                video sync timing diagram
CLAUDE.md               the detailed design log: decisions, bugs, verification
```

### The top level

`ULA.vhd` has one port per pin of the real chip and instantiates six
subsystems plus the interrupt:

| Subsystem | Contents |
|---|---|
| `ula_timing` | clock input and divider, `video_sync` (counters, sync, border), test modes |
| `ula_video_fetch` | fetch strobes, video RAS/CAS, video address |
| `ula_colour` | FLASH clock, pixel and attribute datapath, /Y U V output |
| `ula_memory_cpu` | memory / ROM decode, DRAM strobes, CPU clock contention |
| `ula_io_port` | port 0xFE decode, keyboard, border register |
| `ula_sound` | MIC, speaker, EAR (pin 28) |

## Building and simulating

The Vivado project is `ULA.xpr` (Vivado 2025.2). Generated folders
(`ULA.runs`, `ULA.gen`, ...) are not in git; Vivado recreates them.

- **Simulate:** set a testbench as the active simulation source, then
  *Simulation → Run Simulation → Run Behavioral Simulation*. All files are
  VHDL-2008. `ula_tb` takes a few minutes (about 21 ms of gate-level time).
- **Build for the Arty:** the synthesis top is `arty_top`. Run *Generate
  Bitstream*; the result is `ULA.runs/impl_2/arty_top.bit`. Program it with
  the Hardware Manager over the PROG/UART micro-USB port.
- **What the Arty shows:** LD5 on (clock locked), LD4 blinking once a second
  (one frame interrupt every 50 frames). Pmod JA carries `/INT`, `/phicpu`,
  `/RAS`, `/CAS` and the blink for a scope. `/phicpu` is open collector like
  the real pin 32: fit a ~1 kΩ pull-up from Pmod pin 2 to pin 6 (3.3 V).

### Timing constraints

`ula_clocks.xdc` declares the ULA's 16 clocks (the ripple counters make
clocks out of flip-flop outputs), the test-mode case analysis, the CPU-write
clock group, and a few exceptions, each commented with the reason and what
proves it. It is scoped to the `ula` entity, so it works wherever the ULA is
instantiated; `ula_standalone.xdc` adds the 14 MHz clock when the ULA itself
is the top. In the routed `arty_top`, hold is met everywhere; the remaining
setup reports are a known artefact of how Vivado times ripple clocks,
documented in the file, and the board shows they are harmless.

## Using the ULA elsewhere

A ZX Spectrum (Z80 core, ROM, RAM, video out) is planned as a separate
project. [`docs/ula_interface.md`](docs/ula_interface.md) covers what to
import, the clock, every port at the FPGA level, the DRAM protocol, and what
an all-FPGA system needs to add.

## Reference

- Chris Smith, *The ZX Spectrum ULA: How to Design a Microcomputer*
  (ZX Design and Media, 2010)
- Target board: [Digilent Arty A7-35T](https://digilent.com/reference/programmable-logic/arty-a7/start)

## Licence

MIT; see [LICENSE](LICENSE).
