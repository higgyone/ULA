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
- **The non-Vivado (Claude) PC has _no Vivado at all_** — no `xvhdl`/`xelab`/`xsim`, no GUI. Local simulation there is done with **GHDL** (see below). Synthesis and bitstream generation are impossible on that PC; anything needing Vivado is queued for the Vivado PC (see the "Vivado-PC TODO list").

## Toolchain

- **IDE/Synthesis**: Xilinx Vivado (no CLI build scripts — synthesis, simulation, and bitstream generation are done through the Vivado GUI or Tcl console)
- **Simulation (Vivado PC)**: Vivado's built-in simulator (xsim) via the testbenches in `ULA.srcs/sim_1/new/`
- **Simulation (non-Vivado / Claude PC)**: **GHDL 6.0.0 (mcode backend)** for fast CLI regression when Vivado isn't available. Installed via `winget install ghdl.ghdl.ucrt64.mcode`. See "GHDL CLI simulation" below. Testbenches are portable between GHDL and xsim as long as `--std=08` is used and the gate-level FFs keep their init values + `after TG` delays.
- **Constraints**: `ULA.srcs/arty_35/imports/constraints/Arty-A7-35-Master.xdc` — Digilent's master XDC for the Arty A7-35T (Rev. D/E). All pins are commented out by default; uncomment and rename ports as the top-level design grows.
- **Editor (non-Vivado PC)**: VS Code with `puorc.awesome-vhdl` (syntax) + `hbohlin.vhdl-ls` (language server). The repo ships a [`vhdl_ls.toml`](vhdl_ls.toml) at the root that puts every `.vhd` in `ULA.srcs/sources_1/new/` and `ULA.srcs/sim_1/new/` into a library called `defaultlib` (VHDL LS reserves `work` as the "current library" alias, so the actual library name must be different).
- **Linter / formatter**: **VSG (VHDL Style Guide)** — `pip install vsg`, invoked as `vsg.exe` (note: `python -m vsg` has no `__main__`, use the console script). The project has **adopted VSG's default style as the canonical formatter** (like black/gofmt): VSG owns whitespace, indentation, casing, alignment and layout. Config is [`vsg_config.yaml`](vsg_config.yaml) — the only deviations from defaults are **4-space indent** (`rule.global.indent_size: 4`) and **`instantiation_034` disabled** (the design uses direct entity instantiation with explicit architecture selection, e.g. `entity work.vert_line_counter(T_Structure)`). Check: `vsg -f <file> -c vsg_config.yaml`; fix: add `--fix`. An [`.editorconfig`](.editorconfig) mirrors the 4-space indent so the editor Tab key agrees with the formatter. A **pre-commit hook** ([`.pre-commit-config.yaml`](.pre-commit-config.yaml)) runs `vsg --fix` on staged VHDL every commit (VSG pinned + isolated by pre-commit at rev `3.35.0` — note the tag has **no** `v` prefix). Per-PC setup: install the `pre-commit` driver in an isolated venv and put the launcher on PATH (**pipx is broken on the dev box** — a Windows launcher-encoding bug in pipx 1.16, fails regardless of `--backend`; the manual venv is the pipx-equivalent), then `pre-commit install`. See the header of `.pre-commit-config.yaml` for the exact commands.
- **Compile-time lint**: run GHDL analysis with `-Wall -Wunused` for a stronger pass. The whole tree is clean under `-Wall` except two intentional/benign categories: unconnected `OUT` ports left `open` in `video_sync` (`-Wmissing-assoc`) and the `Reference` architecture name colliding with a VHDL-AMS reserved word in `bit3_counter` (`-Wreserved-word`).

### VHDL LS gotchas
- **Time literals require whitespace** between the integer and the unit. `wait for 50ns;` is rejected as "Invalid integer character 'n'" — write `wait for 50 ns;`. Vivado tolerates the no-space form but VHDL LS is strict. All testbenches have been normalised.
- **No BOMs.** PowerShell 5.1's `Set-Content -Encoding utf8` adds a UTF-8 BOM that some HDL tools choke on. Use `.NET`'s `UTF8Encoding($false)` when rewriting files from PS, or use VS Code (UTF-8 without BOM by default).

To run a simulation in Vivado: set the target testbench as the active simulation source, then run *Simulation → Run Simulation → Run Behavioral Simulation*.

### GHDL CLI simulation (non-Vivado PC)

GHDL 6.0.0 (mcode) is installed and on the persistent **user** PATH (winget added it at install). Note: a shell opened *before* the install won't see it — use a fresh terminal. If needed, the binary is at:
`C:\Users\higgy\AppData\Local\Microsoft\WinGet\Packages\ghdl.ghdl.ucrt64.mcode_Microsoft.Winget.Source_8wekyb3d8bbwe\bin\ghdl.exe`

Two-step analyze → run flow (from `ULA.srcs`, keep everything in a scratch workdir so no artefacts land in the repo):

```powershell
$work = "$env:TEMP\ghdl_ula_work"; New-Item -ItemType Directory -Force -Path $work | Out-Null
ghdl -a --std=08 --workdir=$work sources_1/new/<dut>.vhd sim_1/new/<dut>_tb.vhd
ghdl -r --std=08 --workdir=$work <dut>_tb --stop-time=200ns
```

- Analyse **dependencies first** (a DUT's own sub-entities before the DUT, DUT before its TB) — GHDL has no auto-elaboration ordering like Vivado's project manager.
- `--std=08` must match on both `-a` and `-r`. All TBs assume VHDL-2008.
- Self-checking TBs (`assert ... severity failure`) halt the run on the first mismatch and print the message; a clean run prints its `report ... note` lines and `ALL TESTS PASSED`.
- The GHDL `-Whide` warning on a procedure parameter shadowing a signal is cosmetic — rename the formal (e.g. `q` → `qv`) to silence it.
- GHDL is a *second* simulator, not a replacement for xsim. It's great for catching logic/regression bugs quickly, but final sign-off for anything schematic-critical should still be re-run in xsim on the Vivado PC (xsim has its own quirks — see the bit3_counter verification notes).

**✅ `single_bit_shift_register` verified in GHDL** — `single_bit_shift_reg_tb` passes all 7 cases (parallel load, serial shift both directions, hold, and load-overrides-shift), with `q_bar` complementary throughout. The gate-level cell uses the same `d_ff_nor` pattern (Case-A-style init values + `after TG` 1 ns delays) so it simulates cleanly with no t=0 delta-cycle hang.

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
- 9-bit counter V0–V8, increments on falling edge of `Clk_HC6` when `HCrst` (= `hc_rst`) is asserted
- Counts 0–311 (312 lines per frame); emits `Vrst` on wrap
- Exposes both `V0..V8` and complemented `V0_n..V8_n` taps so downstream NOR gates can connect directly without extra inverters
- **`T_Structure`** (primary, matches Smith pg 92): `tce_ff` for V0–V2 (no reset — schematic-faithful), `trce_ff` for V3–V8 with `v3_8_reset`. Reset decode is a NOR on `s_v2_c` (= `HCrst·V0·V1·V2`), `V4_n`, `V5_n`, `V8_n` — fires only at count=311 with `HCrst='1'`. `Vrst` is combinational (high during count=311).
- **`Behavioral`** (reference): `output_cnt + 1` model kept for cross-checking. `Vrst` registered (high during count=0).
- **✅ VERIFIED in xsim** (`vert_line_counter_tb` against `T_Structure`): counts 0→311, holds while `HCrst='0'`, wraps 311→0, `Vrst` high at 311. Matches the TB golden model. See the "Vert_Line_counter verification" section below.

### Horizontal timing block (`horiz_timing`)
- Owns the `master_horiz_counter` instance and derives `hsync_5c` / `hsync_6c` / `nHblank` from the C0–C8 taps
- Also exposes `clk_hc6` and `hc_rst` outward so the vertical counter can be clocked from them
- All combinational logic in NOR-with-inverted-inputs style (Chris Smith pg 90)

### Video sync top level (`video_sync`)
- Instantiates `horiz_timing` (which brings in the MHC) and `Vert_Line_counter(T_Structure)`
- Derives `nBorder` and `sVsync` from V counter taps; passes `hsync_5c`/`hsync_6c`/`nHblank` through from `horiz_timing`; combines hsync+vsync into composite `sync_5c`/`sync_6c`
- All vertical-region combinational logic uses named intermediate signals (`VBorderLower`, `VBorderUpper`, `v3_n`..`v7_n`) matching the schematic. The `v3_n`..`v7_n` complemented taps come straight from the counter's `V3_n..V7_n` (`qbar`) outputs — no local inverters
- ✅ End-to-end verified by the self-checking `video_sync_tb` (see "video_sync verification")
- The 5c/6c suffix refers to issue 5 and issue 6 ULA chips with slightly different hsync timing

### Primitive flip-flops
| Entity | File | Role |
|--------|------|------|
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
- `nHSyncA_5c`, `nHSyncB_5c`, `nHSyncPulses_5c` (hsync 5c pulse 336–367)
- `nHSyncA_6c`, `nHSyncB_6c`, `X`, `nHSyncPulses_6c` (hsync 6c pulse 344–375)
- `nHSyncSelect` (window select); `n_sync_5c`, `n_sync_6c` (composite = NOR(vsync, hsync))
- `s_vsync` (vsync pulse lines 248–251, 4 lines wide; the `not(v5)` vs `(not v4)` bracket inconsistency is cosmetic only) — renamed from `sVsync` in the naming pass; equation unchanged

**⚠ `nBorder` equation CHANGED — re-verify (no longer "do not change"):** it was
vertical-only `NOR(v8, v6·v7)` and now matches the book pg 92 full equation
`nBorder = NOR(c8, v8, v6·v7)` — the `c8` term adds the **horizontal** border
gate (display = central 256 columns, c8=0). `c8` is now an output of
`horiz_timing` (backed by internal `s_c8`) routed into `video_sync`. This is a
real behavioural change, so it must be sim-verified. `video_sync_tb` now does a
**second per-line sample at ~pixel 304 (c8=1) asserting `nBorder='0'`** — the
regression check for the horizontal term (the old vertical-only decode held it
`'1'` there on display lines). Still needs to be RUN on the Vivado PC to confirm
green.

**⚠ `hsync_5c`/`hsync_6c` polarity FIXED — re-verify:** the book (pg 90) gives
`hsync = NOR(nc6, c7, nc8, nhsyncpulses)`, i.e. **active-HIGH** (1 during the
pulse), same polarity as `vsync`. The code had a bare `OR` (`hsync <=
nHSyncSelect or nHSyncPulses`), making hsync **active-LOW** — the complement —
which fed the wrong polarity into `n_sync = NOR(vsync, hsync)` and broke the
composite (vsync suppressed instead of asserted). Fixed to
`hsync <= not(nHSyncSelect or nHSyncPulses)` for both 5c/6c. Knock-on:
`video_sync_tb` phase-lock now waits for `hsync_5c = '0'` (inactive level is now
LOW). vsync and the n_sync equation were already book-correct; only hsync moved.
The `nhsyncpulses` logic = `XNOR(c3·c4, c5)` (6c) was verified to match the book.

## Naming & ordering consistency

> **Formatting is now VSG-owned (2026-07-16).** The whole tree was run through
> `vsg --fix` and reformatted to VSG's default style: **lowercase keywords,
> types and architecture names** (`std_logic`, `entity`, `end entity`,
> `architecture structural`), 4-space indent, VSG alignment, `)` on its own
> line. This supersedes the earlier hand-casing below — architecture *names*
> like `Behavioral`/`T_Structure` still read Pascal-case in this doc for
> readability, but in source they are lowercase (VHDL is case-insensitive, so
> instantiations still bind). Don't hand-fight the formatter; run it. The
> *semantic* conventions below (snake_case identifiers, port ordering, `s_*`/
> `*_n`/`*_c` prefixes, active-low `n`-prefix) still hold — VSG doesn't touch
> those. All sims re-verified green after the reformat.

Cross-cutting cleanup. **Conventions chosen (2026-06-27):** lowercase
`snake_case` for all identifiers; architecture `Behavioral` for the reference
model (plus `Structural` / `T_Structure` / `Reference` where multiple archs
exist); port order `clk, reset, enable, other inputs, then outputs` (applied to
both declarations *and* port maps); `s_*` / `*_n` / `*_c` internal-signal
prefixes. ~~The active-low `n`-prefix names (`nBorder`, `nHblank`, `nHSync*`)
are kept as-is.~~ **Superseded 2026-10-19:** active-low is always a `_n`
suffix — see "Active-low and net naming rules" below.

**Book-schematic port names are an intentional exception to `snake_case`.**
Where a port maps directly to a named net on Chris Smith's schematic, the book's
spelling wins for traceability — e.g. `shift8`'s `Sin` (serial-in) and `SLoad`
(load/shift select) keep the book's mixed-case names rather than becoming
`s_in`/`s_load`. (Bonus: it also avoids the `s_` internal-signal prefix landing
on a port.) `Sin` is **active high** (tied to SLoad; corrected 2026-10-23, see
Phase 7). A future naming pass should **not** "correct"
these — leave book-named ports alone.

**Data-bus port naming (D0–D7) — the book's names.** The ULA's D pins are
shared and bidirectional. Each block's data ports are named for the D bit they
connect to, with the direction **from the ULA's side**, as the book does
(book do0 / di3 → `do_0` / `di_3` in the project's style):
- **`do_N`** — data OUT of the ULA: a pin it **drives** onto the bus, only
  during a port read. `keyboard_input` do_0..do_4, `cassette_input` do_6 (EAR).
  Driven as `'0'` / `'H'` (open-collector pad with a weak on-chip pull-up),
  released to `'H'` outside a read so the CPU or DRAM can drive the pin.
- **`di_N`** — data IN to the ULA: a bus bit it **reads**, latched on a port
  write. `border_reg` di_0..di_2, `cassette_speaker_out` di_3 (MIC), di_4
  (speaker).
- Vectors indexed `(7 downto 0)` with element *n* = D*n*: `pixel_data`,
  `attr_data` (read during video fetches).

**The address pins A0–A6 are bidirectional too.** They are the multiplexed
DRAM address bus. During a video fetch the ULA drives them
(`video_address_generation` a0..a6, enabled by `ae_n`). Otherwise the PCB's
'157 multiplexers drive them with the CPU address, selected by `ras_n`:
`ras_n` high passes the B inputs (CPU A0–A6, the row), `ras_n` low passes the
A inputs (CPU A7–A13, the column). The ULA reads **A0** from this bus:
`io_port_decode_0xfe` uses it, relying on `ras_n` staying high through an I/O
cycle (no /MREQ, so no RAS) so the pin carries CPU A0. At the top level these
pins are `inout`, with `ae_n` deciding when the ULA drives.

What makes it all line up is the **bit number**. At the top level all of these
join one resolved `std_logic_vector(7 downto 0)` bus, bit *n* to every port
numbered *n* (`do_N`, `di_N`, element *n*). D5 is input only (cell 31 is
the analogue cassette interface); nothing in the ULA drives D7. The
**`port_rd_n` / `port_wr_n`** strobes every I/O block takes as an input come from
`io_port_decode_0xfe` (see Phase 6).

### Active-low and net naming rules (decided 2026-10-19)

**Rule 1 — active low is always a `_n` suffix.** The book writes an active-low
net as `/NAME` (or with a bar over it). `/` is not legal in a VHDL identifier
(extended identifiers like `\/border\` compile but are case-sensitive and
badly supported — don't use them), so the mapping is mechanical:
**book `/name` → `name_n`**. `/BORDER` → `border_n`, `/MREQ` → `mreq_n`.
No `n` prefix (`nborder`, `n_vid_ras`), no `_bar`, no `qbar` — flip-flop
complements are `q_n`. `_n` means active low / logical complement and
nothing else.

**Rule 2 — one net, one name.** A port is named after the net it carries at
the top level, so `ULA.vhd` port maps read `name => name`. A line that doesn't
is a signal that something differs (polarity, width) and must be checked. Two
polarities of the same signal are two nets (`border` and `border_n`, `c3` and
`c3_n`), each with its own name; the block that has the inverter exports both,
like `vert_line_counter` does with `v*` / `v*_n`.

**Rule 3 — `s_` is for internal signals only, never on a port.** Every
`signal` declared in a design source starts with `s_`; anonymous gate outputs
are `s_a_out`, `s_b_out`, ... (formerly `a_o` / `a_out` / `a_0`). Testbench
signals are the exception: they keep the DUT's port names so TB port maps also
read `name => name`.

**Exceptions (book names, kept on purpose):**
- `yuv_control_signals` / `yuv` / `pal_v_burst`: the `_n` taps (`green_star_n`,
  `red_ii_n`, `burst_ii_n`, ...) are the raw NOR outputs, so they ARE the
  logical complement and satisfy Rule 1. Their extra meaning (the sign of the
  colour coefficient) is documented in those headers. Leave them.
- `shift8`'s `sin` / `sload` (book's Sin / SLoad, no slash in the book).
- Generic primitives (`d_ff`, `d_ff_nor`, `trc_ff`, `shift8`, latches,
  `clk_div_2`) keep generic port names (`clk`, `d`, `q`, `e`, `enable`); the
  net names apply where they are instantiated.

#### ✅ Port rename table (done 2026-10-19, branch `naming-rules`)

Applied in one commit with every port map and TB, all TBs re-run in GHDL.
`video_sync` gained the `border` output (`not border_n`), and `video_sync_tb`
checks it is the complement of `border_n`. The `border_n` equation itself is
unchanged (only its target is now `s_border_n`). For future renames, keep the
same discipline: entity + every port map + every TB in one commit.

| Net (new name) | Entity | Old port | Notes |
|---|---|---|---|
| `border_n` | `video_sync` | `nborder` (out) | |
| `border_n` | `latch_and_shift_reg_control_clks` | `nborder` (in) | |
| `border` | `video_sync` | — (new out) | `not border_n`; feeds `contention_handler_3` / `video_address_generation`, which already use `border` |
| `hblank_n` | `video_sync`, `horiz_timing` | `nhblank` (out) | |
| `hblank_n` | `attr_output_latch_border_select_mux`, `attr_output_latch_colour_mux` | `h_blank_n` (in) | |
| `vsync` | `interrupt`, `attr_output_latch_border_select_mux`, `attr_output_latch_colour_mux` | `v_sync` (in) | `video_sync` already outputs `vsync` |
| `sync_5c_n` / `sync_6c_n` | `video_sync` | `n_sync_5c` / `n_sync_6c` (out) | consumers keep `sync_n`; the top level picks 5c or 6c |
| `vid_ras_n` | `ras_cas_generation` | `n_vid_ras` (out) | `video_address_generation` already takes `vid_ras_n` |
| `vid_c3_n` | `ras_cas_generation` | `n_vid_c3` (in) | `latch_and_shift_reg_control_clks` already takes `vid_c3_n` |
| `video_en` | `attr_data_latch_paper_border_mux` | `vid_en` (in) | |
| `sload` | `latch_and_shift_reg_control_clks` (out), `attr_output_latch_border_select_mux` (in) | `s_load` | breaks Rule 3; internal `s_s_load` → `s_sload` |
| `border_colour(2 downto 0)` | `attr_output_latch_border_select_mux` | `border_colour_bgr` | bits are (0) blue, (1) red, (2) green, so `_bgr` misleads |
| `tclk_a` | `test_modes` | `tclka_n` (out) | active-high pulse (= NOT `rd_n`); `master_horiz_counter` already takes `tclk_a` |
| `tclk_b` | `test_modes` (out), `flash_clock` (in) | `tclkb_n` | active-high pulse (= NOT `wr_n`) |
| `q_n` | `d_ff`, `data_latch_1_bit`, `shift8`, `single_bit_shift_register` | `q_bar` | primitives |
| `q_n` | `d_ff_nor`, `trc_ff`, `tce_ff`, `trce_ff` | `qbar` | primitives |

**Related open items (not renames):**
- `video_sync` exports no `c*` / `v*` counter taps, but `interrupt`,
  `pal_v_burst`, `video_address_generation`, `flash_clock`,
  `latch_and_shift_reg_control_clks` and `ras_cas_generation` need them. Decide:
  export the taps from `video_sync` (both polarities), or instantiate the
  counters at the top level.
- `master_horiz_counter` outputs only true `c0..c8`; consumers need `c0_n`,
  `c1_n`, `c2_n`, `c3_n`, `c7_n`, `c8_n`.
- `video_sync.tclk_a` is unused (`horiz_timing` ties it to '0'), so test mode A
  can't reach C6..C8 through `video_sync` yet.
- `latch_and_shift_reg_control_clks.vid_cas_pulse` has no consumer
  (`cpu_memory_access` takes `vid_cas_ac` / `vid_cas_bd` from
  `ras_cas_generation`): decide whether it is still needed or maps to `open`.
- Architecture names: `yuv` uses `behavioural` (others `behavioral`);
  `single_bit_shift_register` uses `structure` (others `structural`), and its
  file is `single_bit_shift_reg.vhd`.

**✅ Done on the non-Vivado PC (plain source edits):**
- Architecture typo `Behavourial`→`Behavioral` (`D_FF.vhd` + its consumer
  `D_FF_tb.vhd`, whose own arch `arch`→`Behavioral` too).
- `Vert_Line_counter` ports lowercased (`HCrst`→`hcrst`, `Clk_HC6`→`clk_hc6`,
  `V0..V8`→`v0..v8`, `V*_n`→`v*_n`, `Vrst`→`vrst`); consumers `video_sync.vhd`
  and `vert_line_counter_tb.vhd` updated in the same pass.
- Port ordering applied across all entities + every port map: reordered
  `clk_div_2` (clk_in/reset), `trc_ff` (outputs→q,qbar,carry), `trce_ff`
  (clk,reset,enable,…), `bit3_counter` (clk,reset), `master_horiz_counter` and
  `video_sync` (reset before tclk_a). `d_ff_nor`, `tce_ff`, `horiz_timing` were
  already conformant. Named association throughout, so reorders are safe.
- Internal-signal case/case-style fixes: `s_HCrst`→`s_hcrst` (`bit3_counter`),
  `HC_rst`→`hc_rst` (MHC + horiz_timing TB locals), and the camelCase/Pascal
  `sVsync`→`s_vsync`, `VBorderLower`→`v_border_lower`,
  `VBorderUpper`→`v_border_upper` in `video_sync` (rename only — the equations
  in the "Verified Correct" list are byte-for-byte unchanged).

**✅ Done 2026-10-24:** file `Vert_Line_counter.vhd` → `vert_line_counter.vhd`
(the entity was already lowercase after the VSG pass, so no port maps changed;
`ULA.xpr` re-pointed through Vivado in its own housekeeping commit).
- ~~Rename `D_FF.vhd` / `D_FF_tb`~~ — moot: both **retired 2026-10-23**
  (nothing in the design used `d_ff`; `d_ff_nor` replaced it).
- ~~Retire `b3_tb.vhd`~~ — done in `23e74e2`.

**Caveat — renames touch `ULA.xpr`** and every renamed port/arch must be updated
in all consumers and testbenches in the *same* commit (cf. the
`HCrst_Enable`→`HCrst` rename that once left two stale consumers).

## Vivado-PC TODO list

Things that must be done in Vivado on the Vivado PC, because they require touching `ULA.xpr` through the IDE (raw edits to the project file are risky):

- **Naming-pass file/entity renames — DONE (2026-10-24).** The last one,
  `Vert_Line_counter.vhd` → `vert_line_counter.vhd`, is done; `D_FF` /
  `D_FF_tb` were retired and `b3_tb` deleted.

- **`master_horiz_counter_tb` imports duplicate — DONE.** The stale
  `ULA.srcs/sources_1/imports/new/master_horiz_counter_tb.vhd` (which Vivado was
  actually compiling instead of the real `sim_1/new` copy — that's why golden-check
  edits "didn't show up") has been removed from the project and `git rm`'d. The real
  TB `ULA.srcs/sim_1/new/master_horiz_counter_tb.vhd` is now properly in the sim_1
  fileset. **Lesson:** if edits to a TB never take effect, check `get_files -all
  *name*` — there may be a second copy under `imports/` that's the one actually
  compiled.
- **`horiz_timing_tb` imports duplicate — DONE.** Was an identical copy at
  `sim_1/imports/new/` (referenced by the project) plus an unreferenced `sim_1/new/`
  copy. Switched the project to the conventional `sim_1/new/horiz_timing_tb.vhd` via
  the Tcl console (`remove_files [get_files {*imports/new/horiz_timing_tb.vhd}]`;
  `add_files -fileset sim_1 -norecurse .../sim_1/new/horiz_timing_tb.vhd`; Save
  Project), then `git rm`'d the orphan. **Tip:** `remove_files` with a literal path
  can silently no-match — use `remove_files [get_files {*pattern*}]` instead.
- **Full project audit (complete):** every `.vhd` referenced by `ULA.xpr` now maps
  1:1 to its working copy under `sources_1/new/` or `sim_1/new/`. No `imports/`
  source duplicates remain anywhere (only `arty_35/imports/constraints/` for the XDC).

## Current status (as of this commit)

> **▶ PICK UP HERE (next session):** Timing backbone (Phases 1–4) is **fully
> xsim-verified and done**. Work has moved to a **per-PR feature-branch
> workflow** off `main` (PRs #3 and #4 merged). Current branch:
> **`phase5-video`** (pushed, tracking `origin/phase5-video`). It holds two
> committed-but-**deliberately-not-yet-PR'd** changes: `video_sync` decode-comment
> expansions + `video_sync_tb` waveform instrumentation (`dbg_pixel`/`dbg_line`/
> `dbg_vline` + `dbg_exp_*` flags). **Naming/ordering cleanup (source-edit
> portion) also done this session** — see "Naming & ordering consistency".
>
> **✅ GATE CLEARED (2026-07-03, Vivado PC).** The full backbone regression was
> re-run in xsim 2025.2 via the CLI launchers and all are green: `bit3_counter_tb`,
> `single_bit_shift_reg_tb`, `vert_line_counter_tb`, `master_horiz_counter_tb`,
> `horiz_timing_tb` (eyeball, no asserts — ran clean), `video_sync_tb`, and the
> FF-unit TBs (`trc_ff_tb`, `trce_ff_tb`, `tce_ff_tb`, `clk_div_2_tb`,
> `d_ff_nor_tb`, `D_FF_tb`). The naming/ordering pass + the design changes below
> are confirmed semantics-preserving. **Phase 5 is unblocked.** The file/entity
> renames remain queued separately in the Vivado-PC TODO list.
>
> **Whole project now compiles under `-2008` uniformly.** `bit3_counter_tb`'s
> process label `cover` was a VHDL-2008 reserved word (PSL) — renamed to
> `cover_track`, so `xvhdl -2008` no longer needs that file singled out to 93.
> All 12 sources + 12 TBs analyze clean under one `xvhdl -2008` pass.
>
> **Also bundled in this batch (design fix, NOT just renames): `nBorder` now
> includes the horizontal `c8` term** (`horiz_timing` gained a `c8` output;
> `video_sync` nBorder = `NOR(c8, v8, v6·v7)`) and composite sync renamed
> `sync_5c/6c`→`n_sync_5c/6c`. **`video_sync_tb` now tests both axes** — a second
> per-line sample at ~pixel 304 (c8=1) asserts `nBorder='0'`, the regression
> check for the horizontal term. ✅ Verified — `video_sync_tb` PASS message
> confirms `nBorder: V-edge @192, H-border via c8 @>=256`. See
> "Verified Correct" for details.
>
> **Also: `hsync_5c`/`hsync_6c` polarity fixed** (OR→NOR, now active-HIGH per
> book pg 90) so the composite `n_sync` is correct; `video_sync_tb` lock now
> uses `hsync_5c='0'`. ✅ Verified — the TB phase-locks on `hsync_5c='0'` and the
> composite decode passes end-to-end.
>
> **Phase 5 pixel-data path underway (mentor-mode).** Pixel-path FRONT BLOCK
> complete + GHDL-verified (all with self-checking TBs). **`pixel_serialiser_tb`
> ✅ xsim-verified on the Vivado PC** — that run exercises the whole integrated
> front path (data_latch_8_bit + shift8), so the block is signed off; the
> component TBs (`data_latch_8_bit_tb`, standalone `shift8_tb`) can still be run
> in xsim individually if desired but the integration passes. Modules:
> `single_bit_shift_register`; the 8-bit `shift8` (parallel-load shift-left pixel
> register, chain of 8; merged from `phase5-pixel-shiftreg`); `data_latch_1_bit`
> (video data latch bit — active-low `e = not datalatch`; `q_bar → shift-reg
> `data_n`); `data_latch_8_bit` (8× `data_latch_1_bit`, common active-low
> `enable`); and **`pixel_serialiser`** — the structural wrapper tying them
> together: `data → data_latch_8_bit → (data_out_n, active-low) → shift8.data_n →
> serial_data`, MSB-first; `Sin` tied to `SLoad` per the book schematic; latch
> true output + shift `q_bar` left `open` for now.
>
> **Attribute path started.** `attr_data_latch_paper_border_mux` ✅ built +
> GHDL-verified (self-checking TB, 20 checks): an 8-bit attribute `data_latch_8_bit`
> feeding a per-colour-bit 2:1 NOR-NOR mux that outputs PAPER (attr bits 5:3) in
> the display area or BORDER (`border_colour`, port 0xFE) in the border, selected
> by `vid_en` (shared `vid_en_n` inverter). Also taps INK (attr 2:0, ungated),
> BRIGHT (`al6_hl` = attr6 AND vid_en) and FLASH (`al7_fl` = attr7 AND vid_en).
> Attribute byte layout: b7 FLASH | b6 BRIGHT | b5:3 PAPER | b2:0 INK, colours GRB
> (b0 Blue, b1 Red, b2 Green). **Next design task:** double-buffered attribute
> fetch (prefetch next attr while current displays) + flash toggle from the V
> counter (25 Hz), then wire the serialised pixel bit into the final INK vs
> paper_border mux; then `border_reg.vhd` (port `0xFE` write → border colour bits
> 2:0), and the rest of Phase 5 (`pixel_fetch`, `colour_mux`, `video_out`).
> User wants mentor-mode: offer walk-through vs review-my-sketch before writing.
> Vivado on this PC: `C:\AMDDesignTools\2025.2\Vivado\bin` (not on PATH); CLI sim
> via `xvhdl`/`xelab`/`xsim` works (see "video_sync verification"). Note: `ULA.xpr`
> gets rewritten by Vivado each session — commit as isolated "Vivado housekeeping".

- Timing backbone (Phases 1–4) is complete and verified against the Chris Smith spec.
- Target board switched from Nexys4 DDR to Arty A7-35T; master XDC is in place but pin assignments are still commented out (waits on the top-level `ULA.vhd` ports being defined).
- VS Code + VHDL LS tooling configured on the non-Vivado PC; testbenches normalised (`Nns` → `N ns`, BOMs stripped).
- **All five original bugs resolved.**
- **`video_sync` slimmed down**: hsync/blanking logic now lives in `horiz_timing` (which was previously dead code). `video_sync` instantiates `horiz_timing` rather than inlining the equations. Single MHC instance across the design.
- **`nBorder` and `sVsync` converted to NOR-faithful form** with named intermediates (`VBorderLower`, `VBorderUpper`, `v3_n`..`v7_n`).
- **`Vert_Line_counter(T_Structure)` ✅ VERIFIED in xsim** — gate-faithful 9-bit counter matching Smith pg 92. `vert_line_counter_tb` against `T_Structure` passes (0→311 count, hold on `HCrst='0'`, 311→0 wrap, `Vrst` at 311). See "Vert_Line_counter verification" below.
- Verification tasks for the timing backbone — **✅ ALL COMPLETE:**
  - ~~Run `vert_line_counter_tb` against `T_Structure`~~ ✅ done.
  - ~~Wire `Vert_Line_counter(T_Structure)` into `video_sync` and re-run `video_sync_tb`~~ ✅ done — `video_sync` now instantiates `(T_Structure)` and consumes the counter's `V3_n..V7_n` qbar taps directly (local `not v3..v7` inverters removed). `video_sync_tb` is now self-checking and passes end-to-end (see "video_sync verification" below).
- **Timing backbone (Phases 1–4) is now fully xsim-verified.** Next design work is Phase 5 (border register, pixel/attribute fetch, colour mux, video output).
- **FF library now fully structural on `d_ff_nor`**: `clk_div_2`, `trc_ff`, `tce_ff`, `trce_ff` all wrap `d_ff_nor` with a d-input mux. `trce_ff.enable` no longer has a default (`:= '1'` removed — gate-accurate design has no implicit drives). `d_ff_nor` has Case-A init values + `after TG` (1 ns) gate delays for clean simulation.
- **`bit3_counter` ✅ VERIFIED — all three architectures** (`Structural`, `T_Structure`, `Reference`) match a golden modulo-7 model in xsim. `master_horiz_counter` instantiates `(T_Structure)` — the schematic-faithful chained-T-FF carry-chain — for gate-accuracy. See the "bit3_counter verification" section below for the single-UUT + TB-golden testbench design and the xsim caveats.
- **`single_bit_shift_register` — ✅ GHDL- and xsim-verified.** One gate-accurate cell of the pixel shift register: a negative-edge NOR flip-flop with a 2:1 load/shift input mux (active-low `data_n`/`data_1_n`, `set='1'` loads parallel, `set='0'` shifts in the neighbour). Uses the `d_ff_nor` pattern (init values + `after TG`). `single_bit_shift_reg_tb` passes all 7 cases in GHDL (load, shift both ways, hold, load-overrides-shift, complementary `q_bar`).
  - **✅ GATE CLEARED — `single_bit_shift_reg_tb` re-run in xsim (2026-07-03) and PASSES all 7 cases** (matches the GHDL result; xsim sign-off done).
  - **➡ NEXT (after that gate clears): build the 8-bit shift-**_**left**_** register** by chaining eight `single_bit_shift_register` cells — each cell's `q` feeds the next cell's `data_1_n` shift input (mind the active-low inversion), common `clk`/`set`, eight parallel `data_n` load bits in, serial-out from the MSB end. Then a self-checking TB: parallel-load a byte, clock 8 times, confirm it shifts left one bit per edge. This becomes the ULA video pixel shift register.
- **`data_latch_1_bit` — GHDL-verified, xsim pending.** One bit of the 8-bit ULA
  video data latch that captures the display-RAM byte before it fans out to the
  pixel path (bitmap) and the attribute path. A **transparent D latch** (single
  gated SR-NOR pair — *not* master-slave, so half the network of `d_ff_nor`),
  built on the same `after TG` + init-value hygiene as the rest of the FF library.
  Four NORs: `b_o=NOR(e,d)`, `a_o=NOR(e,b_o)`, cross-coupled `c_o=NOR(a_o,d_o)` /
  `d_o=NOR(b_o,c_o)`; `q=d_o`, `q_bar=c_o`. Enable `e` is **active-low**
  (`e='0'` transparent, `e='1'` hold) and is driven by **`e = not datalatch`** —
  the upstream active-high `datalatch` strobe is transparent-high / hold-low as
  expected; the active-low sense is that inverter absorbed into the interface, not
  a polarity slip. `q_bar` is the active-low tap that feeds the pixel shift
  register's `data_n` load input — the two active-low conventions cancel, so the
  shift register loads the TRUE pixel bit. `data_latch_1_bit_tb` passes all 8 cases
  in GHDL (transparent follow 0/1, latch-and-hold both polarities with `d` changing
  underneath, `q_bar` complementary throughout). User-implemented, Claude-reviewed
  + commented + TB.
  - **⛔ GATE — re-run `data_latch_1_bit_tb` in xsim on the Vivado PC** and add
    both `data_latch_1_bit.vhd` + `data_latch_1_bit_tb.vhd` to `ULA.xpr` (currently
    source-only on the non-Vivado PC).
  - **➡ NEXT: build the 8-bit `data_latch`** — eight `data_latch_1_bit` cells,
    common `e` strobe, `d(7:0)` in, `q(7:0)` / `q_bar(7:0)` out; the eight `q_bar`
    bits fan into the pixel shift register's eight `data_n` load inputs. Then a
    self-checking TB. Same tiling pattern as the 8-bit shift register.

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

**VHDL-2008 note:** the coverage process was originally labelled `cover`, which
is a reserved word in VHDL-2008 (PSL) — `xvhdl -2008` rejects it with
`[VRFC 10-4982] syntax error near 'cover'`. Renamed to `cover_track` (2026-07-03)
so the whole project analyzes under a single `xvhdl -2008` pass. (It only slipped
through before because Vivado defaulted this file to VHDL-93.)

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

### Vert_Line_counter verification — ✅ VERIFIED (T_Structure)

`vert_line_counter_tb` passes against `architecture T_Structure` in xsim:
the gate-faithful 9-bit counter counts 0→311, holds while `HCrst='0'`
(first 3 cycles), wraps 311→0, and drives `Vrst` high for exactly the
count=311 line. Same single-UUT + TB-internal-golden pattern as
`bit3_counter_tb`.

**Three TB fixes were needed to verify T_Structure (the TB was wired for
`Behavioral`):**
1. **Port rename.** The entity port was renamed `HCrst_Enable`→`HCrst` in
   cf653ee, but *two* consumers were left stale: `vert_line_counter_tb.vhd`
   and `video_sync.vhd`. Symptom = `[VRFC 10-719] formal port <hcrst_enable>
   is not declared` + `[VRFC 10-3353] formal port 'hcrst' has no actual`.
   Both fixed.
2. **`Vrst` golden semantics differ by architecture.** `Behavioral` drives
   `Vrst` *registered, high at count=0* (line after wrap); `T_Structure`
   drives it *combinational, high at count=311*. The golden checker's
   `exp_vrst` was moved out of the count-update branch and recomputed from
   the settled count: `exp_vrst := '1' when expected = V_MAX and hc_rst='1'`.
3. **Header/inline comments** updated (Vrst-at-311, gate-level `after TG`
   ripple instead of "purely behavioural").

**Power-on state is 0, not unknown.** Concern that `T_Structure` (no reset on
V0–V2) might power up at a garbage count was unfounded: `d_ff_nor`'s Case-A
init gives `q=0` on every FF, so all of V0–V8 start at 0 — the golden's
`expected := 0` start holds.

**Sim runs at `T = 100 ns` (`T/2 = 50 ns`).** The `after TG` carry-chain
ripple settles in ~9·TG (~9 ns) after each falling edge; the checker samples
on the next rising edge (50 ns later), well clear. Synthetic `Clk_HC6` +
`HCrst` drive reaches the first wrap in ~32 µs (vs ~20 ms through a real MHC).

**CLI xsim flow (no GUI needed).** Vivado 2025.2 batch launchers live in
`C:\AMDDesignTools\2025.2\Vivado\bin\` (not on PATH). Compile + run from a
scratch dir:
```
xvhdl.bat d_ff_nor.vhd tce_ff.vhd trce_ff.vhd trc_ff.vhd \
          vert_line_counter.vhd vert_line_counter_tb.vhd   # -> library work
xelab.bat work.vert_line_counter_tb -s vlc_sim             # elaborate
xsim.bat  vlc_sim -tclbatch run.tcl                         # run.tcl = "run all\nexit"
```
PASS = the `Vert_Line_counter TB PASS` note with no `mismatch` lines. To switch
the arch under test, edit the `entity work.Vert_Line_counter(<arch>)` line in
the TB and re-run (xsim incremental compile reuses stale snapshots — always
re-`xvhdl`/`xelab`, confirm `Analyzing ...` for the edited file).

### video_sync verification — ✅ VERIFIED (full stack, T_Structure)

`video_sync_tb` is now self-checking and passes against the complete
gate-level hierarchy (`video_sync` → `horiz_timing` + `master_horiz_counter`
+ `Vert_Line_counter(T_Structure)` + the FF library) at the real 143 ns
pixel clock. It verifies the **vertical decode** end to end:

- `nBorder` HIGH on lines 0–191, LOW on 192–311 (border edge at V=192).
- `vsync` HIGH only on lines 248–251 (4-line PAL vsync).
- **frame wrap at 312** (V 311→0): decode returns to the line-0 state.

Heartbeat confirmed V=191→192 (nBorder 1→0), V=247→248 (vsync 0→1),
V=251→252 (vsync 1→0), and V=0 again after the wrap. Zero mismatches over
316 lines.

**Golden design.** The TB sees only top-level outputs, so it tracks the line
number by a one-time phase-lock to line 0's `hsync_5c` pulse, then counts
exactly 448 pixel clocks per line. `nBorder`/`vsync` are pure functions of
V0..V8, so they're sampled mid-line (clear of the line-boundary carry
ripple); expected values use `line mod 312`, which is what makes the run past
312 also test the wrap. Only the vertical path is checked here — the
horizontal decode is already covered by `master_horiz_counter_tb` and the
"Verified Correct" combinational list.

**Runtime.** ~20 ms of gate-level sim (316 lines) ran in ~5 s wall — the
`after TG` inertial delays settle fast and signals are stable between line
boundaries, so full-frame runs are cheap. Compile/run exactly like the vert
TB (`xvhdl` the source chain → `xelab work.video_sync_tb` → `xsim ... run all`;
the checker sets `sim_done` to stop the clock so `run all` terminates).

## Walk-through progress (mentor-mode log)

Files covered so far, in order, by the post-`6e59d6e` walk-through:
- `D_FF.vhd` (Bug 1) — async-vs-sync, concurrent-vs-process patterns
- `trc_ff.vhd` — behavioural → structural d_ff_nor, sync reset via d-mux
- `tce_ff.vhd` — enable as a d-mux, hold-via-self-loopback pattern
- `trce_ff.vhd` — three-way d-mux with priority (reset > enable)
- `bit3_counter.vhd` — per-bit binary +1 rule + wrap suppression + sync reset; structural conversion derived from a state table

- `Vert_Line_counter.vhd` — T_Structure implemented (tce_ff/trce_ff carry chain, NOR reset decode at 311, HCrst gating via s_v2_c); V*_n ports added. ✅ xsim-verified.

**Next on the list:** `clk_div_2` (simplest structural composition — `d_ff_nor` + a single inverted feedback wire).

## What Needs Building Next

Remaining work in order:
**Phase 4 - Real bit3_counter** ✅ *COMPLETE — all three architectures verified.*
- `architecture T_Structure of bit3_counter` built from `trc_ff` (C6) + two `trce_ff` (C7, C8). Enable-chaining via the `carry` out (`carry6=q6 → C7.enable`; `carry7=q6·q7 → C8.enable`). `s_HCrst <= not(qbar7 or qbar8)` (= q7·q8); `s_ff_rst <= reset or s_HCrst` feeds all three FF resets; `output <= q8&q7&q6`; `overflow <= s_HCrst`. Modulo-7, matches `Reference`.
- VERIFIED in xsim against the TB golden model: `Structural`, `T_Structure`, and `Reference` all count 0→6 with correct wrap/overflow (see "bit3_counter verification" section). `T_Structure` shows physically-correct ripple glitches between states that settle before the mid-period sample.
- `master_horiz_counter` now instantiates `(T_Structure)` for schematic fidelity. **✅ VERIFIED in xsim** (eyeballed `master_horiz_counter_tb`, run 10 us): C0–C5 count 0→63, C6–C8 count 0→6 then wrap, full line 0→447, `hc_rst` high across the C6–C8="110" window. Integration correct.
  - **`hc_rst` ripple glitch — analysed, HARMLESS.** With T_Structure, `hc_rst = q7·q8` glitches high briefly at the C6–C8 `3→4` transition (`011→100`: q8 rises before q7 falls, so both are momentarily 1). This is a real, physically-faithful ripple hazard (the Structural arch's parallel overflow didn't have it). It does NOT corrupt anything because the only consumer, `Vert_Line_counter`, is **edge-sampled**: it reads `hc_rst` only at the falling edge of `Clk_HC6`, and the `after TG` delays mean the glitch appears *after* that edge and is gone (640 ns in fast TB) long before the next sample. The vert counter therefore reads the clean *pre-edge* value at every block boundary and increments exactly once per line, at the 6→0 wrap edge (where it samples the settled state-6 `hc_rst=1`). Lesson: a combinational decode of a ripple counter glitches, but a synchronous edge-sampled consumer is immune — exactly how the real ULA tolerates the ripple. (Caveat: keep `hc_rst` away from any *level-sensitive* consumer; only the vert-counter enable uses it, which is safe.)
  - **`master_horiz_counter_tb` is self-checking — ✅ PASSES.** The checker samples the 9-bit tap concat `c8..c0` (= `c_upper*64 + c_lower`) on the falling `clk7` edge, locks onto the actual count after reset, then asserts it increments by exactly 1 (mod 448) every `clk7` — catches skips/stuck-bits/wrong-wrap without depending on the start phase. "line complete" heartbeat each 447→0 wrap. Verified: `run 200 us` gives 3 clean `line complete` notes (one per 64,064 ns PAL line), zero mismatches → the T_Structure horizontal counter is fully correct at real timing.
    - **MUST run at the real 7 MHz period (`T = 143 ns`, set in the TB).** The FF library's `after TG` gate delays make the worst-case 64-boundary settle path (lower gated-ripple → `clk_hc6` → T_Structure C6–C8 after-TG) ~15–20 ns — *longer than a 10 ns clock*, so a fast clock samples mid-ripple garbage at the boundaries and the check false-fails. At 143 ns, T/2 = 71 ns ≫ settle, clean. Don't drop below ~50 ns.
    - One line = 448 × 143 ns ≈ 64 µs, so `run 200 us` (~3 lines) to exercise C6–C8 fully. Pass = no `MHC count mismatch`, with `line complete` notes.
  - ~~re-run `video_sync_tb` after the T_Structure switch~~ ✅ done — the self-checking `video_sync_tb` exercises the `hc_rst` → vert-counter → decode path end to end with zero mismatches (see "video_sync verification").
**`Vert_Line_counter` T_Structure** — ✅ xsim-verified standalone (`vert_line_counter_tb`) **and** wired into `video_sync` and verified in the full stack:
- ~~Run `vert_line_counter_tb` against `T_Structure`~~ ✅ done (counts 0→311, holds on `HCrst='0'`, wraps, `Vrst` at 311; ~32 µs synthetic-drive run).
- **`video_sync.vhd` — ✅ DONE:**
  - ~~`HCrst_Enable => hcrst` → `HCrst => hcrst`~~ ✅ done (the entity port rename in cf653ee left both `video_sync` and `vert_line_counter_tb` stale — both now fixed).
  - ~~Switch instantiation from `(Behavioral)` to `(T_Structure)`~~ ✅ done.
  - ~~`V*_n` taps~~ ✅ wired `V3_n..V7_n` straight out of the counter; `video_sync`'s redundant local `not v3..v7` inverters removed, and `VBorderLower` now reads `not(v6_n or v7_n)`. Only the consumed taps (`v2`, `v8` true; `v3_n..v7_n` complemented) are mapped — the rest default to `open`.
  - ~~Re-run `video_sync_tb`~~ ✅ done — self-checking, passes end-to-end.
**Phase 5 — Video output**

Phase 5 has **two strands**, and both live on the `phase5-video` branch — the
branch is the video generator as a whole, digital and analogue (user's call,
2026-09-12).

---

#### Strand A — digital RGB data path

Build order follows the book's video-output **data path** (Chris Smith), not the
old "border_reg first" list. The pipeline, in the order the book presents it:

1. ✅ **Pixel data latch + shift register block** — pixel byte captured in a data
   latch, loaded into an **8-bit shift register**, serialised MSB-first at the
   pixel clock (1 ink/paper-select bit per pixel). `data_latch_1_bit` →
   `data_latch_8_bit`, `single_bit_shift_register` → `shift8`, tied together by
   **`pixel_serialiser`** (xsim, 16 checks).
2. ✅ **Attribute byte fetch + paper/border mux** —
   **`attr_data_latch_paper_border_mux`** (xsim, 19 checks). Input half of the
   double buffer; unpacks the attribute byte into ink / paper-or-border /
   bright / flash, border selected by `vid_en`.
3. ✅ **Flash mode** — **`pixel_flash`** (xsim, 8 checks, exhaustive) produces
   `data_select_n`; **`flash_clock`** (xsim, 12 checks) is the ~1.56 Hz toggle
   (5-stage ripple /32 off `v8`, one edge per frame at the 311→0 wrap).
4. ✅ **Attribute output latch + colour mux + blanking** —
   **`attr_output_latch_colour_mux`** (xsim, 13 checks). Output half of the
   double buffer, ink/paper 2:1 NOR-NOR mux, and the final blanking mux folded
   straight into the colour NORs (`v_sync` / `h_blank` → black).
5. ✅ **Integration wrapper** — **`attr_output_latch_border_select_mux`** (xsim,
   70 checks) wires blocks 1–4 into one datapath. Note its output-latch enable
   is **active-low** (`attr_output_latch_n`), matching what the control-clock
   block emits.
6. ✅ **`border_reg`** (xsim, 82 checks) — port `0xFE` write, bits 2:0 latched
   as the border colour; supplies the wrapper's `border_colour_bgr` input.
   Built in Phase 6 alongside the other port-write blocks.

Supporting logic — all ✅ done:
- **`latch_and_shift_reg_control_clks`** (xsim, 133 checks) — decodes every
  control strobe (`pixel_data_latch_n`, `attr_data_latch_n`, `s_load`,
  `attr_output_latch_n`, `video_en`) from the H-counter low bits.
- **`ras_cas_generation`** (xsim, 40 checks) — DRAM RAS/CAS strobes. **The one
  deliberately non-gate-accurate block in the project** (synchronous rebuild;
  the book's analogue delays have no FPGA equivalent). DRAM cycle is 4 pixels.
- **`video_address_generation`** (xsim, 51 checks) — the `pixel_fetch` work:
  C/V counters → ZX scrambled VRAM row/column address on a6..a0, plus `ae_n`.
- Final **blanking mux** — folded into `attr_output_latch_colour_mux` rather
  than built as a separate block.

---

#### Strand B — analogue video signal generation (colour → Y/U/V levels)

Turning the digital RGB + sync into the three analogue levels the ULA drives to
the PCB's PAL encoder: inverted luminance `y_n` and the colour differences `u`
and `v`. **The ULA's own part of this strand is ✅ complete** (steps 1–4). The
subcarrier modulation and RF stage are done OFF-chip on the real Spectrum (the
LM1889 encoder), so on the FPGA they are board-level work, not ULA work.

1. ✅ **`pal_v_burst`** (xsim, 332 checks) — PAL colour-burst gate with
   line-parity alternation. Burst window `NOR(c4,c5,c6,c7_n,c8_n)` = pixels
   384..399, which lands on the **back porch** (inside h-blank 320..415, after
   the 5c hsync pulse 336..367); 16 px @ 7 MHz = 2.29 µs vs the real ~2.25 µs.
   Line parity is `v0` latched with `e => sync_n`, so it is sampled during sync
   and then frozen for the whole line.
   **⚠ POLARITY TRAP:** `burst_star_n` (ACTIVE LOW, = burst AND q) and
   `burst_star` (ACTIVE HIGH, = burst AND NOT q) are **opposite-polarity, NOT a
   complement pair** — they happen to share a level inside the window. Compare
   *assertions*, never raw levels, when wiring these.
2. ✅ **`yuv_control_signals`** (xsim, 770 checks) — the PAL V-switch (a
   4-NOR XNOR of each colour with `timing`) and the sink-control signals for
   the U and V networks. **The `_n` suffix encodes the SIGN of that colour's
   coefficient**, not an active-low sense:
   `V = +0.615R −0.515G −0.100B`, `U = −0.147R −0.289G +0.436B`. The single
   positive term in each (`red_star`, `blue_ii`) has no `_n` and carries an
   extra buffering inversion. The `not(not(x))` buffers are the book's and are
   deliberate — do not simplify them away.
3. ✅ **`yuv`** (xsim, `yuv_tb` 111 checks) — the Y, U and V output levels.
   **Deliberately NOT gate-accurate** (second exception, with
   `ras_cas_generation`): it models the analogue resistor network behaviourally,
   in **integer millivolts** (`millivolts_t`, package `yuv_levels_pkg` at the top
   of `yuv.vhd`). Each channel is a **current-summing DAC**:
   `output = 4300 − Σ(conducting sink currents) × R`. Key facts — the full
   account is in the `yuv.vhd` header:
   - **Every sink conducts when its input is '1'**, whatever its name.
   - Y: R = 3.1 k; BRIGHT *selects* each colour's current rather than adding
     one, so black is 2449 mV either way; bright white saturates the output
     transistor and is clamped at 259 mV.
   - U: R = 1550 Ω, fixed black-level sink; V: R = 3.1 k, no fixed sink.
   - **U/V zero point** (the book's "black/white"): U 2015 mV, V 1925 mV. Black
     is encoded as white so both land exactly on it.
   - The colour burst is a DC offset in U and V on the back porch: −U on every
     line, ±V alternating (135° even lines, 225° odd lines).
   - **Source of truth is the CURRENTS, not the book's voltage tables**, which
     are inconsistently rounded and contain errors (U's current columns are
     copies of Y's; the V odd-line burst is printed as 3.112 V where the
     currents give ~2.88 V). Do not "correct" the constants to match the book.
4. ✅ **`yuv_video`** (xsim, 6009 checks) — structural wrapper joining
   `pal_v_burst` + `yuv_control_signals` + `yuv` into one block: RGB, BRIGHT,
   sync and the counter taps in; `y_n`, `u`, `v` out. Pure wiring.
   **Caller requirement:** RGB must be `'0'` during horizontal blanking — the
   burst window lies inside it, and a coloured pixel during an even-line burst
   would drive `v` below 0 mV. The colour back-end's blanking provides this;
   confirm it when the two are wired together.
5. ⏳ **DAC boundary module** — convert `millivolts_t` to DAC codes for whichever
   DAC is chosen. Kept separate so the DAC choice stays out of `yuv`.
6. ⏳ **Encoder / modulator (off-ULA)** — the LM1889's job: put U and V on
   quadrature 4.43 MHz subcarriers and add Y and sync. Only needed if the FPGA
   board is to produce composite video itself.

---

**➡ Video next step.** Strands A and B are complete (`border_reg` is done).
Still to do is the **top-level assembly** wiring `video_sync` +
`ras_cas_generation` + `video_address_generation` +
`latch_and_shift_reg_control_clks` + `flash_clock` +
`attr_output_latch_border_select_mux` + `yuv_video` into one video generator.

**✅ DECIDED (2026-10-19) — no resync register for `ras_cas_generation`.**
`clk_7` must be made by **dividing `clk_14` with a flip-flop** (`clk_div_2`),
never as a second MMCM output. Then `clk_7` changes just after each `clk_14`
edge like any register output, so using it as the half-pixel phase bit is an
ordinary synchronous path; and `c0` / `c1` (ripple off `clk_7_n`) settle a few
ns after that edge, ~60 ns before the next `clk_14` sample. So the block reads
`c1 & c0 & clk_7` directly, with no extra register, no 1-tick shift and no
look-ahead on `vid_c3_n`. The XDC must declare `create_generated_clock` for
`clk_7` and the counter's ripple clocks so Vivado proves the margin.
**Revisit if `clk_7` is ever taken from the MMCM** — then a resync stage (and
a one-tick-rotated decode with a look-ahead window gate) would be needed.

**Testbench convention (learned the hard way).** Any NEW self-checking TB with a
free-running clock process **must** call `finish` (`library std; use std.env.all;`)
or gate its clock on a `sim_done` flag. Four TBs previously ended the stimulus
process on a bare `wait;` while the clock kept toggling, so `run all` passed every
check and then span forever — xsim had to be killed (exit code 4), which looks
exactly like a hang. Fixed in `138960f`. Stimulus-only / eyeball TBs are the
exception: they are meant to be run with an explicit `run <time>`.

**xsim is more lenient than GHDL — a pass in xsim is not a pass in GHDL.** Two
cases have bitten this project, both in `yuv_tb`:
- **Port subtype matching.** A TB signal connected to a scalar `out` port must
  have the port's exact subtype (`millivolts_t`, not plain `integer`). GHDL
  rejects a mismatch ("range of formal is different"); xsim accepts it.
- **Integer range checks.** Driving a value outside a constrained integer
  subtype aborts the run in GHDL; xsim does not check and reports a pass.
The Vivado PC has no GHDL, so anything touching constrained integer types should
be re-run in the GHDL regression on the other PC.

**VHDL is case-insensitive.** `v_sync_y` and the constant `V_SYNC_Y` are the same
name. The UPPER-constant / lower-signal convention gives no compiler protection:
a one-letter slip can resolve silently to the wrong object and still compile and
elaborate.

Mentor mode: offer walk-through vs review-my-sketch before writing VHDL.

**Phase 6 — CPU interface** — ✅ all blocks below built and xsim-verified
(re-run together 2026-10-15). Merged via PRs #8 (memory/contention, with
video), #9 (I/O devices), #10 (interrupts) and the `phase6-test-modes` PR.
None is wired into a top level yet. **Phase 6 is complete.**

*Memory and CPU clock*
- ✅ **`cpu_memory_access`** (xsim, 1296 checks) — lower-16K decode
  (`ram_16 = MREQ·a14·¬a15`), ROM chip select, and the CPU+video merge onto
  DRAM `ras_n` / `cas_n` / `we_n` (the merge happens here only;
  `ras_cas_generation` makes just the video strobes). Covers read, early write,
  and RAS-only refresh (the "snow" cycle when I = 0x40..0x7F). The book's RAS→CAS
  delay chains are kept for traceability but are 0 ns in sim.
  - ✅ **`rasen_n` tri-state on the RAS pin (branch `phase6-ras-tristate`, user
    wrote it).** A 6C001 circuit: `rasen_n = NOR(a14, a15, mreq_n, border_n)`
    — note **A14 uninverted**, so it fires on MREQ in **0x0000..0x3FFF while
    in the border** (`border_n` = `nborder`, '0' in the border). That catches
    the Z80's refresh cycles (address `I:R` = 0x3Fxx with the ROM's I = 0x3F)
    and harmless ROM reads. While `rasen_n = '1'` the ULA releases RAS:
    `ras_n <= NOR(ram_16, vid_ras) when rasen_n = '0' else 'Z'`.
    - **Pad: tri-state TOTEM-POLE** — drives strong '0' AND '1' when enabled,
      'Z' when not. Different from the open-collector pins (`do_N`, `int_n`,
      K0: '0' / 'H'). On the FPGA 'Z' needs a real pin (IOBUF), so `ras_n`
      must stay a top-level pin.
    - **Why: DRAM refresh in the border.** The 4116 needs all 128 rows every
      2 ms. Video fetches refresh it in the display, but the border has no
      fetches for 120 lines = **7.68 ms**. On **issue 1/2** boards the Z80's
      `/RFSH` drove the far end of the RAS line while the ULA let go, so Z80
      refresh cycles refreshed the lower 16K. **Issue 3 removed that link**:
      only video fetches refresh, the 7.68 ms gap breaks the 2 ms spec on
      paper, but real 4116s retain data far longer, so it works. With nothing
      on the far end, RAS floats ('Z') in those cycles on issue 3+.
    - **Far end of RAS:** issue 1/2 boards connect the Z80's `/RFSH` to the
      RAS line through a **330 Ω resistor**, so the ULA's totem pole wins
      whenever it drives (`cpu_memory_access_tb` models `/RFSH` as a weak
      'L' / 'H'); issue 3+ → nothing, the line floats ('Z').
    - ✅ `cpu_memory_access_tb` now 2591 checks: exhaustive 512 combinations
      incl. `border_n`, border cycles (issue 3+), the `/RFSH` far end
      (issue 1/2). Verified it fails on an `a14_n` slip in the `rasen_n` gate.
    - Open: check no tri-state while `vid_ras` is active (`nborder` includes
      the side borders via c8, so a ROM access at the display edge could
      coincide with a video fetch).

**ULA chip versions (6C001) and the DRAM interface.** Issue 3 boards used the
**6C001E-6**; issue 4 (the book's schematic) the **6C001E-7**.
- **-7:** the '157 row/column mux select is taken from the DRAM `ras_n`, which
  switches to the column address as soon as RAS falls and so removes the row
  address early, risking tRAH. The issue-4 PCB adds **two NAND gates on the
  `ras_n` line** to delay RAS at the DRAM and hold the row address longer. That
  can leave the column address unsettled at CAS, so the -7 **delays CAS**
  (between `com_cas_n` and `cas_n`).
- **CAS timing:** CPU `rd_n` → CAS↓ = **94 ns (-7)** vs 61 ns (-6); video RAS↓ →
  CAS↓ = **78 ns (-7)** vs 50 ns (-6).
- **Compatibility:** a -7 works on every board issue; an earlier ULA can't be
  used on later boards (the NAND delay eats its RAS→CAS margin).
- **Project target: the -7** (the drop-in that works everywhere; our
  `ras_n`-switched '157 assumption is already the -7 scheme). Current figures:
  video RAS→CAS **71 ns** (one `clk_14` tick in `ras_cas_generation`) — fine for
  the DRAM itself and in sim, but if the FPGA ever drives a REAL issue-4+ board's
  DRAM, the PCB NANDs shrink the effective gap towards the -6's 50 ns. Revisit
  then (two ticks = 143 ns may not fit the 4-pixel DRAM cycle). Irrelevant if
  the FPGA uses its own block RAM.
- ✅ **`contention_handler_3`** (xsim, 64 cycle checks + 1110 clock phases checked
  for runts) — issue 3 (6C001) CPU clock from `c0`, **held** (not WAIT) on
  contended memory (0x4000..0x7FFF) or ULA-port I/O inside the c2/c3 window.
  `mreqt23` / `ioreqtw3` mask latches keep holds to the start of an access.
  Outputs pin 32 `phicpu_n` (inverted; the PCB transistor inverts back). Its
  gates carry `after tg` — the hold is a feedback loop that hits the delta limit
  in zero delay. Also supplies `ioreqtw3_n` to the port decode.

*I/O port (any even address, 0xFE by convention)*
- ✅ **`io_port_decode_0xfe`** (xsim, 86 checks) — `port_rd_n` / `port_wr_n` =
  NOT NOR(a0, ioreq_n, ioreqtw3_n, rd_n / wr_n). `a0` uninverted (inverting it
  would decode odd ports). `ioreq_n` is a ULA pin made off-chip (/IORQ OR A0).
  Interrupt acknowledge (/IORQ with no /RD or /WR) fires neither strobe.
- ✅ **`keyboard_input`** (xsim, 116 checks) — port read: half-row columns
  `k0..k4` (active low) onto `do_0..do_4`, open collector `'0'` / `'H'`. The
  8×5 matrix and A8..A15 half-row select are on the PCB, not in the ULA.
- ✅ **`cassette_input`** (xsim, 110 checks) — port read: EAR level onto `do_6`
  (not inverted), same open-collector pad.
- ✅ **`border_reg`** (xsim, 82 checks) — port write: `di_0..di_2` → border
  colour `b0..b2` (blue, red, green), three `data_latch_1_bit`s enabled by
  `port_wr_n`. Black at power-on.
- ✅ **`cassette_speaker_out`** (xsim, 31 checks) — port write: `di_3` → MIC,
  `di_4` → speaker, same latch pattern. Logic levels only; the analogue
  cassette stage is separate.

*Interrupt*
- ✅ **`interrupt`** (xsim, `interrupt_tb` 131 checks + 4 timed pulses; branch
  `phase6-interrupts`) — the Z80's once-a-frame maskable `/INT`.
  `s_int = NOR(not v_sync, c6, c7, c8, v0, v1, v2)` = **line 248 (first vsync
  line), pixels 0..63** = 32 T-states (1 T-state = 2 pixels). The `v2` term is
  redundant (vsync already implies `v2='0'`) but is in the book's gate, so it
  stays. Inputs: `v0..v2`, `c6..c8`, `v_sync` (all from `video_sync` /
  counters); output `int_n`.
  - **Open-collector pin:** `int_n` is `'0'` or `'H'` (the strong on-chip
    pull-up), so other devices can also pull the shared `/INT` low
    (wired-OR). Same `'0'`/`'H'` modelling as the `do_N` data pins.
  - **`t_int_lag` generic (default 100 ns, SIM ONLY)** — one lumped delay on
    `int_n` modelling measured silicon: the real ULA's propagation + ripple
    lag left only ~42 ns of /INT setup before the Z80's rising edge (spec
    80 ns; an instant `int_n` would give 143 ns). Synthesis ignores `after`, so
    on the FPGA `int_n` arrives at the pixel-0 edge (143 ns setup, in spec)
    and is still **sampled at the same Z80 edge (pixel 1)** — software can't
    tell the difference. Don't add a deliberate hardware delay. The only rule:
    `int_n` must not arrive before the previous rising edge (pixel −1), or the
    interrupt would be taken a T-state early.
  - `interrupt_tb` runs **two instances of the same entity** side by side
    (`dut_real` lag 100 ns, `dut_fpga` lag 0 ns) and checks: exhaustive
    128-combination decode; one 64-pixel pulse per frame at line 248 over the
    real 448 × 312 raster; setup times (REAL 43 ns, FPGA 143 ns); same Z80 edge
    for both; and the shared-line wired-OR. **This two-instance TB binds fine
    in xsim 2025.2** — unlike `bit3_counter_tb`, whose `clk`/`reset` ports got
    transposed. Here the instances share no clock/reset nets (`interrupt` has
    neither), which is consistent with that bug needing shared clock/reset.
  - ⏳ GHDL run still pending (other PC). Not yet wired into a top level.

*Wafer test modes*
- ✅ **`test_modes`** (xsim, `test_modes_tb` 570 checks; branch
  `phase6-test-modes`) — lets the wafer probe clock the slow counters from a
  CPU strobe pin at up to 20 MHz instead of waiting 20 ms per frame / 0.64 s
  per FLASH period. Entered with **MREQ and IORQ low together** (never
  happens on a real Z80); the level of the other strobe picks the mode and
  the free strobe is the test clock:
  - **A** — WR high, `rd_n` clocks: `tclka_n = NOR(ioreq_n, mreq_n, rd_n,
    s_wr)` = NOT `rd_n` → `master_horiz_counter`'s `tclk_a` (clocks C6..C8
    via `clk_hc6 = NOR(tclk_a, c5_n)`, so only while c5 = 1). Line rate
    20 MHz / 7 = 2.86 MHz instead of 15.625 kHz.
  - **B** — RD high, `wr_n` clocks: `tclkb_n = NOR(s_rd, wr_n, ioreq_n,
    mreq_n)` = NOT `wr_n` → `flash_clock`'s `tclkb_n` (`clock_in =
    NOR(v8_n, tclkb_n)`, so only while v8 = 1). FLASH 20 MHz / 32 = 625 kHz
    instead of 1.5625 Hz.
  - **Both test clocks must be `'0'` outside their mode** — each feeds a NOR
    that has to pass c5 / v8 through in normal operation. (A first draft sent
    `tclkb` through an extra inverter, '1' normally, which froze FLASH; the
    TB's normal-mode FLASH check now catches that.)
  - **K0 pin = v8 monitor.** Book gate `k0_n = NOR(v8_n, tclkb)` is the
    *complement* of the pin: an open-collector output pulls K0 low when
    `k0_n = '1'`, otherwise releases it to the weak on-chip pull-up (`'0'` /
    `'H'`). So K0 carries `v8_n` in test B (while `wr_n` is low) and is
    released in normal operation, leaving it to the keyboard. K pins have
    emitter-follower inputs, weak on-chip pull-ups **and** 10k PCB pull-ups —
    model the PCB ones as `'H'` on K1..K4 at board level.
  - TB also instantiates `flash_clock` on `tclkb_n` (normal: 64 frames → 4
    edges; test B: 64 `wr_n` cycles → 4 edges ~800 ns apart, ±2 ns because
    `d_ff_nor` rise/fall paths differ by one gate) and checks K0 shared with a
    key (no `'X'`). Test A is checked at `tclka_n` only, not through
    `master_horiz_counter`.

**Phase 7 — Top level**
- **Pinout: [`docs/pinout.md`](docs/pinout.md)** — all 40 pins (cell, pad type,
  board circuit, which block drives/reads each), reviewed 2026-10-21. It is the
  port list for `ULA.vhd` and lists the outstanding **pad fixes** (A0–A6
  tri-state on `ae_n`, `/phicpu` open collector, the new `sound_io` analogue
  pin model, header notes, K1–K4 on-chip `'H'`) and the board/hardware items
  (DAC boundary, 14 MHz MMCM, 5 V ↔ 3.3 V, board resistor model).
- ✅ **`ULA.vhd`** (branch `ula-wiring`) — the top level: one port per pin
  (`docs/pinout.md`), all 18 blocks wired (user wrote it, reviewed; since grouped into six subsystems, see below). Clock:
  `s_clk_14_n <= not clk_14` (the book's common-emitter stage) → `clk_div_2`
  (reset tied '0') → `s_clk_7` (Q → `ras_cas_generation`) / `s_clk_7_n`
  (/clk7). `latch_and_shift_reg_control_clks` makes the pixel clock
  `s_clk_7_pixel` → the colour mux's `clk_7_pixel` port (renamed from `clk_7`
  so it can't be confused with /clk7). `vid_c3_n` = `border OR c3_n` is now
  GENERATED in `latch_and_shift_reg_control_clks` (where the book draws it)
  and exported to `ras_cas_generation`. Unused outputs `open`: hsync_5c/6c,
  sync_5c_n, vid_cas_pulse, ram_16, cpuclk, ae_n, fl. `yuv_video.sync_n` =
  `s_sync_6c_n` (6C001). `reset` is sim-only (the real chip has none).
  `d7 <= 'H'`: an inout port with NO internal driver leaks its default 'U'
  onto the net (LRM: a port with no sources drives its default value), which
  made D7 — the FLASH bit — 'U' and every pixel 'X'. Any future inout pin
  that the ULA never drives needs the same.
- ✅ **System testbench `ula_tb`** (`sim_1/new`, in `ULA.xpr`) —
  drives only the pins, through a board model: 14 MHz crystal, a 16K DRAM
  preloaded with a test screen (every byte different, ink ≠ paper, no
  FLASH), the '157 as a weak driver on A0..A6, 8k2 data / 10k keyboard
  pull-ups, pin 32's 1k + the NPN with 180 Ω, issue-3 RAS (nothing on the far
  end), no tape. Reads internal RGB / counter nets through VHDL-2008
  **external names** (`<<signal .ula_tb.dut.s_red : std_logic>>`; xsim
  supports them). **ALL TESTS PASSED (2026-10-23):** all 48 640 display
  pixels of frame 0 (lines 2..191; pipeline delay 12 px, measured on line 2),
  border cyan after `OUT (0xFE),5`, side borders + h-blank, Z80 clock 3.5 MHz,
  one /INT at line 248 for 64 px, `IN (0xFE)` key/EAR/pull-ups, RAS released
  ('Z') in a border ROM access, and RAS released during a video RAS **0
  times** (the open vid_ras/border_n question: not seen). ~21 ms of gate-level
  sim, a few minutes; compile with `xvhdl -prj` (the file list is too long for
  one cmd line). Limitation: the Z80 never drives the data bus during a video
  fetch (no 470 Ω model yet).
  **Bugs it found and fixed (none visible to the block TBs):**
  1. Latch strobes glitched 1–3 ns after CAS released the bus (the book's
     24 ns clk7 delay, dropped as unsynthesisable, existed to stop that), so
     the latches caught 0xFF → `latch_and_shift_reg_control_clks` gained
     architecture **`synchronous`**: strobes registered on `clk_14` (new ports
     `clk_14`, `clk_7`, `c2`); `structural` kept as the book's gates. Simply
     restoring a 24 ns delay was tried and broke the attribute strobe.
  2. D7 floating 'U' → `d7 <= 'H'` (above).
  3. A 1 ns **simulation ring** in `single_bit_shift_register`: with every
     gate at exactly `tg`, a start-up glitch circulated forever (an inertial
     `after tg` only rejects pulses SHORTER than tg). Fix: one gate per loop
     `after 2 * tg` (sim only, closer to silicon). The cell TB's margin went
     to 20 ns / 6 ns.
  4. **Sin polarity:** the book ties Sin to the active-high SLoad, so Sin is
     active high; `shift8` fed it straight into an active-LOW input, shifting
     in ink. Invisible in the display (a load every 8 px overwrites the fill
     bits), visible in the BORDER. `shift8` now inverts it (`s_sin_n`).
  5. **Strobe-vs-pixel-clock race:** a registered strobe changes ON the
     clk_14 edge, the pixel clock ~3 ns after it, so a window starting or
     ending at the shift register's clock tick changes 3 ns before the
     sampling edge. Fix: windows CENTRED on their edge — `sload` ticks 7, 8
     (straddling pixel 4's start), `attr_output_latch_n` ticks 8, 9. Rule for
     any future synchronous strobe: never let it change on the tick its
     consumer clocks.
  **Lesson:** block TBs with ideal stimulus can't see start-up glitches,
  races between clock domains, or fill bits; only the integrated system
  can. Keep `ula_tb` as the regression gate for every future change.
- ✅ **`latch_and_shift_reg_control_clks_sync_tb`** (xsim, 1 216 201 checks,
  2026-10-23) tests the `synchronous` architecture; the older
  `latch_and_shift_reg_control_clks_tb` still covers `structural`. Its
  stimulus is the real `ula_timing` (14 MHz clock, divider, gate-level
  counters), so the strobes see chip timing. Every clk_14 tick, sampled
  mid-tick, it checks the four strobes against the header's tick table (gating
  from the previous tick, since a registered strobe lags its decode by one
  tick), plus `vid_c3_n`, `video_en`, `clk_7_pixel`; and the **race rule**:
  `sload` stable 20 ns either side of every falling pixel-clock edge. Runs
  lines 0..193 with coverage asserts (strobes in the display, suppressed in
  the horizontal AND vertical border, sload given and suppressed). Mutation
  check: moving sload back to ticks 8, 9 (the bug-5 race) fails it at once.
- ✅ **Subsystems refactor (2026-10-23).** `ULA.vhd` now instantiates six
  pure-wiring subsystems plus `interrupt`, instead of 18 blocks. `ula_tb` was
  re-run unchanged after each one and stayed ALL TESTS PASSED.
  | Subsystem | Blocks inside |
  |---|---|
  | `ula_timing` | clk_14 inverter, `clk_div_2`, `video_sync`, `test_modes` |
  | `ula_video_fetch` | `latch_and_shift_reg_control_clks(synchronous)`, `ras_cas_generation`, `video_address_generation` |
  | `ula_colour` | `flash_clock`, `attr_output_latch_border_select_mux`, `yuv_video` |
  | `ula_memory_cpu` | `cpu_memory_access`, `contention_handler_3` |
  | `ula_io_port` | `io_port_decode_0xfe`, `keyboard_input`, `border_reg` |
  | `ula_sound` | `cassette_speaker_out`, `sound_io`, `cassette_input` |
  Rules that came out of it:
  - Nets used by one subsystem only stay inside it (`tclk_a`, `vid_c3_n`,
    `vid_ras_n`, `flash_clk`, `mic`, `speaker`, `ear`). Only exported counter
    taps that something reads leave `ula_timing` (26 of 36; the rest `open`).
  - **Output also read inside its own subsystem** → drive an internal `s_`
    signal from the instance, read that, and copy it to the port
    (`clk_7_n <= s_clk_7_n;`). VHDL-93 can't read an `out` port. Used for
    `clk_7_n`, `v8_n`, `red/green/blue/hl`, `port_rd_n/port_wr_n`.
  - **An `out` with no driver is legal VHDL**, so a missing copy line or a
    port map into a dead internal signal compiles clean. Only `ula_tb`
    catches it, so run it after every wrapper.
  - `ula_tb` reads `s_red/green/blue/hl`, `s_clk_7_pixel`, `s_vid_ras`,
    `s_c0..s_c8`, `s_v0..s_v8` via external names, so those must stay
    signals in `ULA.vhd`: `ula_timing` exports `v8` and `ula_colour` exports
    RGB + BRIGHT for that reason (RGB is also the natural FPGA VGA output).
  - Per-pin direction can differ by subsystem: `a0` is `out` in
    `ula_video_fetch` and `in` in `ula_io_port` (the pin is `inout`);
    `d0..d2` are `inout` inside `ula_io_port` (keyboard drives, border reads).
- ✅ **FPGA build: 0 combinational loops (2026-10-24, branch `fpga-standalone`).**
  First synthesis (`synth_design -mode out_of_context`, top `ula`) gave 271
  combinational loops / 145 `LUTLP-1`: every cross-coupled NOR became a LUT
  feeding itself (untimeable, routing-dependent races). Fix (option B):
  - Package **`ula_build_pkg`** in two files: `ula_build_pkg_sim.vhd`
    (`fpga_build = false`, used in **simulation only**) and
    `ula_build_pkg_fpga.vhd` (`true`, **synthesis only**). For CLI xsim runs,
    compile the sim one; swap in the fpga one to simulate the FPGA build.
  - Each storage primitive has `gate_model : if not fpga_build generate ...
    else generate ...`: the book's gates (unchanged) vs a real FPGA element.
    `d_ff_nor` → falling-edge FF; `data_latch_1_bit` → latch (`if e = '0'`,
    no else, `d` in the sensitivity list); `single_bit_shift_register` →
    falling-edge FF with the mux inside the edge block (**invert the
    active-low inputs**: `not data_n` / `not data_1_n`); `contention_handler_3`
    → the CPU clock hold as a set-dominant latch,
    `cpuclk = c0 or (cpuclk and H)`, H derived from the gates (header).
    Every FPGA `s_q` has `:= '0'` (the FPGA power-up value).
  - Rule for a branch: every signal has exactly one driver per build, so
    anything read outside the generate is driven in both branches (a
    double driver on std_logic is not a compile error: sim shows `X`).
  - Results: loops 271 → **0**, `latch_loops` 0; 236 LUTs, **39 FFs + 35
    latches**. Every block TB touched and `ula_tb` pass with BOTH packages.
  - All VHDL files are VHDL-2008 in `ULA.xpr` (synthesis read them as
    VHDL-93 before; `pal_v_burst` reads an `out` port). Synthesis top is
    `ula`. `D_FF` / `D_FF_tb` retired.
  - Left for the XDC step: `no_clock` / `TIMING-17` / `TIMING-20` (no
    clocks declared) and `PLHOLDVIO-2` ×8 (LUT-driven ripple clocks:
    `create_generated_clock` + hold check). `HPDR-2` fixed 2026-10-24:
    `ula_timing.k0` is now `out` (only driven inside; the `ula` pin stays
    `inout`).
- **Scope (2026-10-24):** this repo finishes the ULA; the Z80 + full
  Spectrum (block-RAM memory, VGA scan doubler) is a separate later repo.
  Definition of done: (1) 0 loops ✅; (2) ULA-only XDC + clean OOC timing;
  (3) interface doc for the Spectrum repo; (4) tidy-ups (Vert_Line_counter
  rename, GHDL regression, docs); (5) Arty smoke test (ULA + MMCM, sync /
  taps on LEDs or a Pmod).
- ✅ Step 3: **[`docs/ula_interface.md`](docs/ula_interface.md)** (2026-10-24)
  — what to import (both `ula_build_pkg` files, one per flow; VHDL-2008;
  submodule), clock / reset, every port at the FPGA level, the DRAM protocol
  (`ula_tb`'s board model, data 40 ns after CAS), and what an all-FPGA
  Spectrum must add: in/out/oe signals instead of `'Z'` / `'H'`, digital
  RGB + BRIGHT + syncs for VGA, `cpuclk` exported for the Z80.
- ✅ Step 4 tidy-ups (2026-10-24): `vert_line_counter.vhd` rename,
  `ula_timing.k0` → `out`. ⏳ GHDL regression on the other PC (user).
- ✅ **Step 2: [`ula_clocks.xdc`](ULA.srcs/arty_35/new/ula_clocks.xdc)** (2026-10-25,
  in the `arty_35` constraints set; written by the user lesson by lesson, every
  line commented with its reasoning). Out-of-context synthesis with
  `-flatten_hierarchy none` (the case-analysis pins are hierarchical). Result:
  **setup met everywhere**; `no_clock` 214 → 9 (all one pin: the CPU clock
  latch's own enable, deliberately blocked); `loops 0`.
  - **16 clocks:** `clk_14` (primary) → `clk_7` (÷2) → `c3_clk` → `c5_clk` →
    `v8_clk` → `flash0..3_clk` (the ripple chain); `pdl/adl/aol_clk` (the
    registered data-latch strobes), `ras_clk` (row-A0 latch), `sync_clk`
    (burst parity latch), `cpu_clk` (contention mask latches), `port_wr_clk`
    (border / MIC / speaker; a primary clock on an internal pin, async group).
  - **Rules learned:** `-source` = where the MASTER clock is defined (port or
    the master's `Q`); `-edges` count the master's own waveform (odd = rising,
    even = falling), used for falling-edge flip-flops and non-50 % clocks; a
    registered strobe is one tick late; C0..C3 and C4 are gated clocks (no
    constraint); a clock defined on a pin blocks clocks leaking from upstream.
  - `set_case_analysis 0` on `test_clocks/tclk_a` and `tclk_b` (test modes).
  - `set_clock_sense -stop_propagation` of `c3_clk`/`v8_clk` at the CPU clock
    latch's `G`: without it the leaked clocks loop round and **crash Vivado's
    timing engine** (access violation).
  - Exceptions, each with its proof: multicycle `-hold 1 -start` on `sload` →
    pixel clock; hold-only false path pixel latch → shift cells.
  - **12 hold reports left, documented, not fixed:** ripple-chain artefacts.
    Vivado's late clock arrival for a generated clock follows the gating
    ENABLE inputs (e.g. `c3_clk` via C0 → C1 → C2), adding ~8.8 ns per stage
    that the real edge never has. Revisit if the Arty smoke test misbehaves.
  - **XDC gotchas met:** `get_ports` vs `get_pins`; one `-`, not `--`; the
    file is a script read top to bottom (clock groups last); end the file with
    a newline (an appended line got glued on: "Duplicate option '-from'");
    "Run Synthesis" (a run) ≠ `synth_design` in the console (opens nothing,
    uses the run's settings).
- ✅ **Step 5: Arty smoke test PASSED on the board (2026-10-26).**
  [`arty_top.vhd`](ULA.srcs/sources_1/new/arty_top.vhd): Clocking Wizard IP
  `clk_wiz_14` (100 → 14.000 MHz; the wizard chose ÷5 ×49.875 ÷71.25, VCO
  997.5 MHz), the ULA with CPU inputs inactive (`dont_touch` on the instance
  so the whole ULA is built), a 1 Hz LED from `/INT` (edge detect `"was not
  '0', is '0'"` because open-collector `'H'` ≠ `'1'` in simulation), scope
  signals on Pmod JA. Bitstream `ULA.runs/impl_2/arty_top.bit` (synth_2 /
  impl_2 are the current runs). Measured: MMCM locked; `/INT` 19.97 ms period,
  **9.14 µs** wide (64 px); `/RAS` bursts 35.44 µs every 64 µs (247 px of
  fetch windows, pixel 8.5..255.5); `/phicpu` 3.5 MHz with an **820 Ω
  pull-up** (open collector: fast fall, slow RC rise). The ripple counters
  Vivado reported hold "violations" on run correctly on silicon.
  - **Constraints in a top:** `ula_clocks.xdc` is `SCOPED_TO_REF ula`; the
    `clk_14` primary clock moved to `ula_standalone.xdc` (disabled in the
    project; only for the ULA as top), because inside `arty_top` the MMCM's
    clock flows in (XDC has no `if`). Master XDC: `clk100mhz` lower case (VSG
    lowercased the port; XDC is case-sensitive), its `create_clock` commented
    out (the IP constrains its own input: two clocks on one pin doubled every
    derived clock), unused board groups commented. False path written
    `-through` the latch's `q_n` pin (`-from` the cell had no valid startpoint
    while synthesis was still building it). A tri-state net cannot drive an
    ordinary output (A0 left off the Pmod).
  - **Routed timing:** hold met everywhere (the router fixed the ripple hold
    reports). Setup reports remain: latch **time borrowing** (e.g. the
    `video_en` latch: Vivado assumes data may arrive any time the latch is
    open; its input never changes then) and the ripple-chain artefacts.
- ⏳ Next: the time-borrowing lesson (`set_max_time_borrow 0` where a latch's
  input is stable while it is open), README / docs pass, PR to `main`.
