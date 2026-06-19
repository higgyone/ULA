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

### Horizontal timing block (`horiz_timing`)
- Owns the `master_horiz_counter` instance and derives `hsync_5c` / `hsync_6c` / `nHblank` from the C0–C8 taps
- Also exposes `clk_hc6` and `hc_rst` outward so the vertical counter can be clocked from them
- All combinational logic in NOR-with-inverted-inputs style (Chris Smith pg 90)

### Video sync top level (`video_sync`)
- Instantiates `horiz_timing` (which brings in the MHC) and `Vert_Line_counter`
- Derives `nBorder` and `sVsync` from V counter taps; passes `hsync_5c`/`hsync_6c`/`nHblank` through from `horiz_timing`; combines hsync+vsync into composite `sync_5c`/`sync_6c`
- All vertical-region combinational logic uses named intermediate signals (`VBorderLower`, `VBorderUpper`, `v3_n`..`v7_n`) matching the schematic
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

**BUG 4 — `video_sync.vhd`** *(fixed)*: `Vrst` port of `Vert_Line_counter` now wired as `Vrst => open` in the `vlc` port map. Replace `open` with a real consumer signal when Phase 5 needs the wrap pulse for the flash / frame counter.

**BUG 5 — `Vert_Line_counter.vhd`** *(fixed)*: `v_max` and `Vrst` port comments now state that the counter wraps at 311 and that 312 lines per PAL frame is achieved via 312 states (0..311).

## Verified Correct — Do Not Change

The following combinational logic in `video_sync.vhd` has been verified against the Chris Smith book spec and must not be altered:

- `blank1`, `blank2`, `nHblank` (horizontal blanking 320–415)
- `nHSyncA_5c`, `nHSyncB_5c`, `sHsync_5c` (hsync 5c pulse 336–367)
- `nHSyncA_6c`, `nHSyncB_6c`, `X`, `sHsync_6c` (hsync 6c pulse 344–375)
- `nHSyncSelect`, `sync_5c`, `sync_6c`
- `nBorder` (border: HIGH lines 0–191, LOW lines 192–311)
- `sVsync` (vsync pulse lines 248–251, 4 lines wide; the `not(v5)` vs `(not v4)` bracket inconsistency is cosmetic only)

## Vivado-PC TODO list

Things that must be done in Vivado on the Vivado PC, because they require touching `ULA.xpr` through the IDE (raw edits to the project file are risky):

- **Delete stale auto-disabled imports duplicates** of testbenches. Currently in the repo and `ULA.xpr` as auto-disabled (Vivado isn't using them):
  - `ULA.srcs/sources_1/imports/new/master_horiz_counter_tb.vhd` — duplicate of `ULA.srcs/sim_1/new/master_horiz_counter_tb.vhd`. Only difference was `T := 143 ns` vs `10 ns`; the 143 ns value (real 7 MHz period) is now captured as a comment in the active testbench.
  - `ULA.srcs/sim_1/imports/new/horiz_timing_tb.vhd` — likely the same auto-disabled-duplicate situation; check `ULA.xpr` for the `AutoDisabled` flag and confirm it's a copy of the version in `sim_1/new/`.

  In Vivado: right-click each file in the Sources panel → *Remove File from Project*, then `git rm` the file on disk and commit. Doing it any other way risks leaving `ULA.xpr` out of sync.

## Current status (as of this commit)

- Timing backbone (Phases 1–4) is complete and verified against the Chris Smith spec.
- Target board switched from Nexys4 DDR to Arty A7-35T; master XDC is in place but pin assignments are still commented out (waits on the top-level `ULA.vhd` ports being defined).
- VS Code + VHDL LS tooling configured on the non-Vivado PC; testbenches normalised (`Nns` → `N ns`, BOMs stripped).
- **All five original bugs resolved.**
- **`video_sync` slimmed down**: hsync/blanking logic now lives in `horiz_timing` (which was previously dead code). `video_sync` instantiates `horiz_timing` rather than inlining the equations. Single MHC instance across the design.
- **`nBorder` and `sVsync` converted to NOR-faithful form** with named intermediates (`VBorderLower`, `VBorderUpper`, `v3_n`..`v7_n`).
- Open verification tasks before declaring the timing backbone done:
  - Cross-check `bit3_counter` Structural vs Behavioural waveforms in Vivado.
  - Re-run `video_sync_tb` after the `horiz_timing` extraction; confirm `hsync_5c`/`hsync_6c`/`nHblank`/`sync_5c`/`sync_6c`/`vsync`/`nBorder` waveforms are identical to pre-refactor.
- Next design work is Phase 5 (border register, pixel/attribute fetch, colour mux, video output).
- **FF library now fully structural on `d_ff_nor`**: `clk_div_2`, `trc_ff`, `tce_ff`, `trce_ff` all wrap `d_ff_nor` with a d-input mux. `trce_ff.enable` no longer has a default (`:= '1'` removed — gate-accurate design has no implicit drives).
- **`bit3_counter` converted to structural**: three `d_ff_nor` cells + per-bit next-state combinational logic (binary +1 rule + wrap suppression at `"110"` + sync reset). `master_horiz_counter` instantiation updated to `(Structural)`.
- **`bit3_counter_tb` upgraded to oracle pattern (in progress)**: TB now instantiates both `bit3_counter(Structural)` and `bit3_counter(Reference)` in parallel off the same `clk`/`reset`, with a `process(clk)` self-check that asserts `out_s = out_r` AND `ov_s = ov_r` on every falling edge. The Reference architecture (behavioural `unsigned` arithmetic with sync reset) was reinstated as `architecture Reference of bit3_counter` (lives in the same `.vhd` file as Structural). Coverage tracker logs every legal state visited; end-of-sim report warns about any state not reached.

### bit3_counter verification — WIP cliffhanger

Mid-debugging session interrupted. Reached a working sim that reproduces a real divergence, but the root cause is still open. Sequence of steps to pick up from:

1. **Oscillation at t=45 ns** when TB used `wait until rising_edge(clk)`-style stimulus — xsim hit the 10000-delta iteration limit. Diagnosed as a delta-cycle ordering quirk in xsim with the cross-coupled NOR slave latch.
2. **Fixed** by switching TB stimulus back to `wait for X ns;` with offsets that land every reset transition on a rising edge of clk (clk='1' phase, half a period of settling time before the next falling edge). Phase 1: 45 ns. Phase 2: 200 ns. Phase 3 loop: `wait for 30 ns` (not 25 ns) inside, plus `wait for k*T`. Phase 4 mirrors Phase 1.
3. **Then** the FF still never resolved out of `'U'` — out_s stayed `"UUU"` for the whole sim, all 7 coverage warnings fired, asserts gated off. Diagnosed as xsim failing to trigger U→defined re-evaluation on the d_ff_nor's cross-coupled NORs.
4. **Fixed** by initialising all six internal signals of `d_ff_nor` to the Case A stable state (`a_o=0, b_o=1, c_o=0, d_o=1, e_o=0, f_o=1` — corresponds to "d=0 captured, clk='0' phase, q=0"). Documented in source as gate-modelling only (synthesis ignores).
5. **Then** the sim runs cleanly but throws oracle mismatches at every Phase 2 falling edge (t=50, 60, 70, ...).
6. **Investigation revealed**: Structural's `q` correctly transitions `"000" → "001"` at t=50, but Reference's `outputint` stays at `"000"` for the entire simulation. Reference simply isn't counting.
7. **CURRENT clue — possible port-binding bug**: user observed in the waveform that `/bit3_counter_tb/uut_ref/clk` shows the *reset* signal's behaviour (1 until t=45, then 0) and `/bit3_counter_tb/uut_ref/reset` shows the *clock* signal's behaviour (10 ns square wave). I.e. the ports inside `uut_ref` appear to be swapped relative to the TB-level signals — even though the port map in `bit3_counter_tb.vhd` is named (`clk => clk`, `reset => reset`) which should be order-independent. Identical syntax in `uut_struct`'s port map works correctly. Unconfirmed whether this is a real port-binding bug, a Vivado waveform display issue, or a user signal-row misread.

**Next step when resuming**: run these in the Vivado Tcl Console with the sim paused, paste the output to disambiguate:

```tcl
get_value /bit3_counter_tb/clk
get_value /bit3_counter_tb/reset
get_value /bit3_counter_tb/uut_struct/clk
get_value /bit3_counter_tb/uut_struct/reset
get_value /bit3_counter_tb/uut_ref/clk
get_value /bit3_counter_tb/uut_ref/reset
report_objects -recursive /bit3_counter_tb/uut_ref
```

If `uut_ref/clk` differs from `uut_struct/clk` → real binding bug. If they match → waveform display issue, look elsewhere (the Reference process not firing for some other reason).

**Files relevant to this WIP**:
- `ULA.srcs/sim_1/new/bit3_counter_tb.vhd` (oracle TB)
- `ULA.srcs/sources_1/new/bit3_counter.vhd` (both `architecture Structural` and `architecture Reference`)
- `ULA.srcs/sources_1/new/d_ff_nor.vhd` (init values added)

## Walk-through progress (mentor-mode log)

Files covered so far, in order, by the post-`6e59d6e` walk-through:
- `D_FF.vhd` (Bug 1) — async-vs-sync, concurrent-vs-process patterns
- `trc_ff.vhd` — behavioural → structural d_ff_nor, sync reset via d-mux
- `tce_ff.vhd` — enable as a d-mux, hold-via-self-loopback pattern
- `trce_ff.vhd` — three-way d-mux with priority (reset > enable)
- `bit3_counter.vhd` — per-bit binary +1 rule + wrap suppression + sync reset; structural conversion derived from a state table

**Next on the list:** `clk_div_2` (simplest structural composition — `d_ff_nor` + a single inverted feedback wire).

## What Needs Building Next

Remaining work in order:
**Phase 4 - Real bit3_counter**
- make bit3_counter equivalent to the book with tcr_ff for c6, trce_ff for c7 and trce_ff for c8
- add resets to the t flip flops
- NOR the two trce_ffs q bar to create HCrst
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
