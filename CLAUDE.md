# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Gate-accurate VHDL recreation of the Ferranti/Amstrad ULA chip used in the ZX Spectrum 48K, targeting a Digilent Arty A7-35T FPGA (Artix-7 XC7A35T). Development is done in Vivado. Implementation follows Chris Smith's book "The ZX Spectrum ULA" (schematic pages 90 and 92).

GitHub: https://github.com/higgyone/ULA

## Working style — mentor, don't do

The user is learning VHDL and FPGA design through this project. From here on, work in **mentor mode**:

- Explain *what* the change should be and *why*, then let the user make the edit themselves.
- When the user proposes a fix, review it and explain whether it's right, what's missing, or what they could improve — don't pre-emptively rewrite their code.
- If they hit a compile or simulation error, walk them through how to read it and find the cause rather than jumping in with a patched file.
- Diagrams, truth tables, and references to the Chris Smith book are encouraged.
- Direct edits are still OK for **non-learning chores**: docs (this file, README), tooling config (`vhdl_ls.toml`, `.gitignore`, `.gitattributes`), and mechanical bulk fixes (e.g. the `ns` whitespace pass). Anything that's actually VHDL design intent → guide, don't write.
- When in doubt, ask: "do you want me to walk you through this, or just apply it?"

## Multi-PC setup

This project is developed across more than one PC. The Vivado project file (`ULA.xpr`) is tracked in git, but the generated Vivado directories (`ULA.cache/`, `ULA.runs/`, `ULA.sim/`, `ULA.hw/`, `ULA.ip_user_files/`, `ULA.gen/`) are gitignored and regenerated locally on each machine.

Implications:
- Synthesis, simulation, and bitstream generation happen on the PC that has Vivado installed — not necessarily the PC running Claude.
- On a fresh checkout, opening `ULA.xpr` in Vivado will reconstruct the cache/runs/sim directories from `ULA.srcs/`.

## Toolchain

- **IDE/Synthesis**: Xilinx Vivado (no CLI build scripts — synthesis, simulation, and bitstream generation are done through the Vivado GUI or Tcl console)
- **Simulation**: Vivado's built-in simulator (xsim) via the testbenches in `ULA.srcs/sim_1/new/`
- **Constraints**: `ULA.srcs/arty_35/imports/constraints/Arty-A7-35-Master.xdc` — Digilent's master XDC for the Arty A7-35T (Rev. D/E). All pins are commented out by default; uncomment and rename ports as the top-level design grows.
- **Editor (non-Vivado PC)**: VS Code with `puorc.awesome-vhdl` (syntax) + `hbohlin.vhdl-ls` (language server). The repo ships a [`vhdl_ls.toml`](vhdl_ls.toml) at the root that puts every `.vhd` in `ULA.srcs/sources_1/new/` and `ULA.srcs/sim_1/new/` into a library called `defaultlib` (VHDL LS reserves `work` as the "current library" alias, so the actual library name must be different).

### VHDL LS gotchas
- **Time literals require whitespace** between the integer and the unit. `wait for 50ns;` is rejected as "Invalid integer character 'n'" — write `wait for 50 ns;`. Vivado tolerates the no-space form but VHDL LS is strict. All testbenches have been normalised.
- **No BOMs.** PowerShell 5.1's `Set-Content -Encoding utf8` adds a UTF-8 BOM that some HDL tools choke on. Use `.NET`'s `UTF8Encoding($false)` when rewriting files from PS, or use VS Code (UTF-8 without BOM by default).

To run a simulation in Vivado: set the target testbench as the active simulation source, then run *Simulation → Run Simulation → Run Behavioral Simulation*.

## Architecture

### Clock hierarchy
- 14 MHz master input → `clk_div_2` → 7 MHz pixel clock (`clk7`)
- `clk7` drives `master_horiz_counter`, which uses NOR-gated ripple clocking (not synchronous) to match the original ULA schematic exactly
- `tclk_a` is always tied to `'0'` in this implementation

### Horizontal counter (`master_horiz_counter`)
- 9-bit ripple counter C0–C8, 448 counts per line at 7 MHz = 64 µs PAL
- C0–C5 are chained `clk_div_2` instances gated by NOR logic; C6–C8 are a `bit3_counter` clocked by `clk_hc6` (= C5)
- Emits `hc_rst` (overflow/reset pulse) and `clk_hc6` for the vertical counter

### Vertical counter (`Vert_Line_counter`)
- 9-bit synchronous counter V0–V8, increments on falling edge of `Clk_HC6` when `HCrst_Enable` (= `hc_rst`) is asserted
- Counts 0–311 (312 lines per frame); emits `Vrst` on wrap
- `v_max = "100110111"` = 311 decimal (counts 0–311 = 312 states — the comment in the file saying "312 lines" is misleading)

### Video sync top level (`video_sync`)
- Instantiates `master_horiz_counter` and `Vert_Line_counter`
- Derives `nHblank`, `hsync_5c`/`hsync_6c`, `vsync`, `nBorder`, `sync_5c`/`sync_6c` purely from combinational logic on C0–C8 and V0–V8
- The 5c/6c suffix refers to issue 5 and issue 6 ULA chips with slightly different hsync timing

### Primitive flip-flops
| Entity | File | Role |
|--------|------|------|
| `d_ff` | `D_FF.vhd` | D flip-flop, falling edge, q and q_bar outputs |
| `clk_div_2` | `clk_div_2.vhd` | Divide-by-2 used for C0–C5 ripple chain |
| `d_ff_nor` | `d_ff_nor.vhd` | Structural D FF built from NOR gates |
| `trc_ff` | `trc_ff.vhd` | T FF with reset and carry |
| `tce_ff` | `tce_ff.vhd` | T FF with enable and carry |
| `trce_ff` | `trce_ff.vhd` | T FF with reset, enable and carry |
| `bit3_counter` | `bit3_counter.vhd` | 3-bit counter 0–6 (7 states) for C6–C8 |

## Known Bugs

**BUG 1 — `D_FF.vhd`** *(fixed in 21e216a)*: `q` and `q_bar` assignments moved outside the process.

**BUG 2 — `trc_ff.vhd`, `tce_ff.vhd`, `trce_ff.vhd`** *(resolved — kept as documented alias)*: `carry` is now explicitly aliased to `qbar` with a header comment. Port retained so existing port maps still compile; future code should prefer `qbar`.

**BUG 3 — `3_bit counter.vhd`** *(fixed)*: file deleted. Removed from Vivado's project file too.

**BUG 4 — `video_sync.vhd`** *(unfixed)*: `Vrst` port of `Vert_Line_counter` is not connected in the port map. Fix: add `Vrst => open` to the `vlc` port map.

**BUG 5 — `Vert_Line_counter.vhd`** *(unfixed)*: Comment on `v_max` says "312 lines" but the value `"100110111"` = 311 decimal. The logic is correct (0–311 = 312 states); only the comment is wrong.

## Verified Correct — Do Not Change

The following combinational logic in `video_sync.vhd` has been verified against the Chris Smith book spec and must not be altered:

- `blank1`, `blank2`, `nHblank` (horizontal blanking 320–415)
- `nHSyncA_5c`, `nHSyncB_5c`, `sHsync_5c` (hsync 5c pulse 336–367)
- `nHSyncA_6c`, `nHSyncB_6c`, `X`, `sHsync_6c` (hsync 6c pulse 344–375)
- `nHSyncSelect`, `sync_5c`, `sync_6c`
- `nBorder` (border: HIGH lines 0–191, LOW lines 192–311)
- `sVsync` (vsync pulse lines 248–251, 4 lines wide; the `not(v5)` vs `(not v4)` bracket inconsistency is cosmetic only)

## Current status (as of this commit)

- Timing backbone (Phases 1–4) is complete and verified against the Chris Smith spec.
- Target board switched from Nexys4 DDR to Arty A7-35T; master XDC is in place but pin assignments are still commented out (waits on the top-level `ULA.vhd` ports being defined).
- VS Code + VHDL LS tooling configured on the non-Vivado PC; testbenches normalised (`Nns` → `N ns`, BOMs stripped).
- Bugs 1, 2, 3 resolved. Bugs 4 (`Vrst => open` in `video_sync.vhd`) and 5 (`v_max` comment) still open — both are one-line edits, deferred until next session in front of Vivado.

## What Needs Building Next

Remaining work in order:

**Phase 5 — Video output**
- `border_reg.vhd` — port 0xFE write, capture bits 2:0 as border colour
- `pixel_fetch.vhd` — VRAM address generation using C/V counters; ZX scrambled address format
- `colour_mux.vhd` — INK/PAPER/BRIGHT/FLASH decode; flash toggle from V counter (25 Hz)
- `video_out.vhd` — mux between pixel colour, border colour, and blank using `nHblank`/`nBorder`

**Phase 6 — CPU interface**
- `keyboard.vhd` — port 0xFE read; A8–A15 select one of 8 half-rows
- `contention.vhd` — WAIT signal for 0x4000–0x7FFF; 5,5,4,4,3,3,2,2 pattern using C0–C2
- `audio.vhd` — port 0xFE bit 4 write (speaker), bit 6 read (EAR)

**Phase 7 — Top level**
- `ULA.vhd` — instantiates all sub-modules; full Z80 bus; wired to the Arty A7-35T XDC
- Full system testbench with Z80 bus model, multi-frame video timing verification
