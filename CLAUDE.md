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

**BUG 2 — `trc_ff.vhd`, `tce_ff.vhd`, `trce_ff.vhd`** *(resolved — `carry` redefined as a real carry-out)*: `carry` was formerly aliased to `qbar` and unused. It is now the stage carry-out `carry = enable AND q` (for `trc_ff`, which has no enable, `carry = q`), built gate-faithfully as `NOR(not enable, qbar)`. It is consumed by `bit3_counter(T_Structure)` to chain C6 → C7 → C8 (each stage's `carry` drives the next stage's `enable`). Headers/truth tables updated. The three FF unit TBs are stimulus-only (no asserts on `carry`), so nothing else needed changing.

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
- Open verification task before declaring the timing backbone done:
  - Re-run `video_sync_tb` after the `horiz_timing` extraction; confirm `hsync_5c`/`hsync_6c`/`nHblank`/`sync_5c`/`sync_6c`/`vsync`/`nBorder` waveforms are identical to pre-refactor.
- Next design work is Phase 5 (border register, pixel/attribute fetch, colour mux, video output).
- **FF library now fully structural on `d_ff_nor`**: `clk_div_2`, `trc_ff`, `tce_ff`, `trce_ff` all wrap `d_ff_nor` with a d-input mux. `trce_ff.enable` no longer has a default (`:= '1'` removed — gate-accurate design has no implicit drives). `d_ff_nor` has Case-A init values + `after TG` (1 ns) gate delays for clean simulation.
- **`bit3_counter` ✅ VERIFIED — all three architectures** (`Structural`, `T_Structure`, `Reference`) match a golden modulo-7 model in xsim. `master_horiz_counter` instantiates `(T_Structure)` — the schematic-faithful chained-T-FF carry-chain — for gate-accuracy. See the "bit3_counter verification" section below for the single-UUT + TB-golden testbench design and the xsim caveats.

### bit3_counter verification — ✅ VERIFIED (all three architectures)

All three architectures of `bit3_counter` are verified in xsim against a
golden modulo-7 model: they count 0→6, wrap, and assert `overflow` only at
"110", with all 7 states covered and no functional/invariant mismatches.

- **T_Structure** (schematic-faithful `trc_ff`→`trce_ff`→`trce_ff` carry chain)
  — matches the golden at every sample point, with transient ripple glitches
  between states during the carry settle. The glitches are physically correct
  (gate-delayed ripple, like the real ULA) and harmless: downstream logic
  samples mid-period, long after they settle. **This is the arch instantiated
  by `master_horiz_counter`** (chosen for schematic fidelity).
- **Structural** (three `d_ff_nor` cells + parallel next-state logic) — clean,
  no glitches; behaviourally equivalent, kept as an alternative.
- **Reference** (behavioural `unsigned +1`) — matches the golden exactly with
  no delay (confirms the golden/checker are sound).

**Testbench design (`bit3_counter_tb.vhd`): single UUT + TB-internal golden.**
The natural "oracle" pattern — two `bit3_counter` instances (e.g. Structural vs
Reference) compared side by side — is *unusable* here: xsim 2025.2 transposes
the `clk`/`reset` ports whenever two instances of the same entity share clock/
reset nets, so both counters freeze. Proven unavoidable via named, positional,
renamed, plain-buffered, and distinct-delay connections; a SINGLE instance
binds correctly. So the TB instantiates ONE `uut` and compares it against a
golden count computed *in a TB process* (no second entity → bug can't occur).
Edit the `uut` architecture line to verify each arch in turn.

**Two fixes that made simulation work (keep these):**
1. `d_ff_nor.vhd` — all six NOR gates carry `after TG` (`TG = 1 ns`). Without a
   gate delay the cross-coupled NOR latches are zero-delay and xsim spins to the
   10000-delta iteration limit (t=0 hang). `after` is sim-only (synthesis
   ignores it) and physically faithful. Six internal signals also have Case-A
   init values (`a_o=0,b_o=1,c_o=0,d_o=1,e_o=0,f_o=1`) so the latch starts
   defined instead of 'U'.
2. The checker/coverage sample on the **rising** edge (mid-period). The FFs are
   falling-edge triggered; the Structural arch's `after TG` delays mean its
   output settles a few ns after the edge, so mid-period sampling is the
   race-free comparison point.

**Hard-won tooling lesson (xsim 2025.2 incremental compile):** after any source
edit, `restart` does NOT recompile — it re-runs the *existing* snapshot. Always
`close_sim -force; launch_simulation` and confirm `[VRFC 10-163] Analyzing ...`
for the file you changed. Most of this debugging session was wasted on stale
snapshots that silently reused old compiled objects. A planted `report` marker
is the only reliable freshness proof. Also: breakpoints set in the gutter on a
*concurrent* assignment halt every `run` at t≈0 — clear them (`remove_bps -all`)
or `get_value` reads garbage.

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
**Phase 4 - Real bit3_counter** ✅ *COMPLETE — all three architectures verified.*
- `architecture T_Structure of bit3_counter` built from `trc_ff` (C6) + two `trce_ff` (C7, C8). Enable-chaining via the `carry` out (`carry6=q6 → C7.enable`; `carry7=q6·q7 → C8.enable`). `s_HCrst <= not(qbar7 or qbar8)` (= q7·q8); `s_ff_rst <= reset or s_HCrst` feeds all three FF resets; `output <= q8&q7&q6`; `overflow <= s_HCrst`. Modulo-7, matches `Reference`.
- VERIFIED in xsim against the TB golden model: `Structural`, `T_Structure`, and `Reference` all count 0→6 with correct wrap/overflow (see "bit3_counter verification" section). `T_Structure` shows physically-correct ripple glitches between states that settle before the mid-period sample.
- `master_horiz_counter` now instantiates `(T_Structure)` for schematic fidelity. **✅ VERIFIED in xsim** (eyeballed `master_horiz_counter_tb`, run 10 us): C0–C5 count 0→63, C6–C8 count 0→6 then wrap, full line 0→447, `hc_rst` high across the C6–C8="110" window. Integration correct.
  - **`hc_rst` ripple glitch — analysed, HARMLESS.** With T_Structure, `hc_rst = q7·q8` glitches high briefly at the C6–C8 `3→4` transition (`011→100`: q8 rises before q7 falls, so both are momentarily 1). This is a real, physically-faithful ripple hazard (the Structural arch's parallel overflow didn't have it). It does NOT corrupt anything because the only consumer, `Vert_Line_counter`, is **edge-sampled**: it reads `hc_rst` only at the falling edge of `Clk_HC6`, and the `after TG` delays mean the glitch appears *after* that edge and is gone (640 ns in fast TB) long before the next sample. The vert counter therefore reads the clean *pre-edge* value at every block boundary and increments exactly once per line, at the 6→0 wrap edge (where it samples the settled state-6 `hc_rst=1`). Lesson: a combinational decode of a ripple counter glitches, but a synchronous edge-sampled consumer is immune — exactly how the real ULA tolerates the ripple. (Caveat: keep `hc_rst` away from any *level-sensitive* consumer; only the vert-counter enable uses it, which is safe.)
  - **`master_horiz_counter_tb` is now self-checking.** The checker samples the 9-bit tap concat `c8..c0` (= `c_upper*64 + c_lower`) on the falling `clk7` edge, locks onto the actual count after reset, then asserts it increments by exactly 1 (mod 448) every `clk7` — catches skips/stuck-bits/wrong-wrap without depending on the start phase. "line complete" heartbeat each 447→0 wrap.
    - **MUST run at the real 7 MHz period (`T = 143 ns`, set in the TB).** The FF library's `after TG` gate delays make the worst-case 64-boundary settle path (lower gated-ripple → `clk_hc6` → T_Structure C6–C8 after-TG) ~15–20 ns — *longer than a 10 ns clock*, so a fast clock samples mid-ripple garbage at the boundaries and the check false-fails. At 143 ns, T/2 = 71 ns ≫ settle, clean. Don't drop below ~50 ns.
    - One line = 448 × 143 ns ≈ 64 µs, so `run 200 us` (~3 lines) to exercise C6–C8 fully. Pass = no `MHC count mismatch`, with `line complete` notes.
  - Still TODO: re-run `video_sync_tb` after the T_Structure switch to confirm hsync/blank/vsync/border waveforms are unchanged (also re-checks the `hc_rst` → vert-counter path end to end).
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
