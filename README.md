# ULA

Gate-accurate VHDL recreation of the Ferranti/Amstrad ULA chip used in the **ZX Spectrum 48K**, targeting a Digilent **Arty A7-35T** FPGA board (Artix-7 XC7A35T) and developed in **Vivado**.

The implementation follows Chris Smith's book *The ZX Spectrum ULA*, mirroring the schematics on pages 90 (horizontal timing) and 92 (vertical timing).

## Status

The timing backbone is complete:

- 14 MHz → 7 MHz pixel clock
- 9-bit horizontal counter (C0–C8), 448 pixels per line, 64 µs PAL
- 9-bit vertical line counter (V0–V8), 312 lines per frame
- HSync (5c and 6c variants), VSync, composite sync
- Horizontal blanking and vertical border signals

Still to build: border colour register, pixel/attribute fetch, colour mux, video output, keyboard decoder, memory contention, audio, and the top-level ULA entity. See [`CLAUDE.md`](CLAUDE.md) for the full roadmap.

## Repository layout

```
ULA.srcs/
  sources_1/new/           VHDL source files
  sim_1/new/               Testbenches (Vivado xsim)
  constrs_1/imports/       Nexys4_DDR.xdc pin constraints
CLAUDE.md                  Architecture notes, known bugs, roadmap
```

## Key modules

| Module | Role |
|--------|------|
| `clk_div_2` | Divide-by-2, used for the C0–C5 ripple counter chain |
| `bit3_counter` | 3-bit counter for C6–C8 |
| `master_horiz_counter` | 9-bit horizontal counter, NOR-gated ripple to match the original ULA |
| `Vert_Line_counter` | 9-bit synchronous vertical line counter |
| `horiz_timing` | Derives hsync and nHblank from C counter bits |
| `video_sync` | Top-level timing: combines horizontal + vertical, outputs hsync/vsync/sync/nBorder |

Lower-level primitives (`d_ff`, `d_ff_nor`, `trc_ff`, `tce_ff`, `trce_ff`) implement the flip-flop variants used in the schematic.

## Building and simulating

Open the project in Vivado, set the desired testbench as the active simulation source, then run *Simulation → Run Simulation → Run Behavioral Simulation*. There is no command-line build script — synthesis, simulation, and bitstream generation are driven through the Vivado GUI or its Tcl console.

## Reference

- Chris Smith, *The ZX Spectrum ULA: How to Design a Microcomputer* (ZX Design and Media, 2010)
- Target board: [Digilent Arty A7-35T](https://digilent.com/reference/programmable-logic/arty-a7/start)

## Licence

See [LICENSE](LICENSE).
