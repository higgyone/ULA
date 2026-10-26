## ============================================================================
## ula_clocks.xdc - timing constraints for the ULA (clocks only, no pins)
##
## Static timing analysis needs to know every clock. Vivado follows a clock
## through wires and gates (LUTs) by itself, but STOPS at a flip-flop output:
## a Q pin is data to it. The ULA is a ripple design, so wherever a flip-flop
## output is used AS A CLOCK (the source of the edges, not just an enable)
## it is declared here with create_generated_clock.
##
## Cell names come from synthesis (gate_model.fpga_model.s_q_reg = the FPGA
## branch of a storage primitive). Never guess them: look them up with
## get_cells / report_clock_networks. A pin that no longer matches makes
## the constraint silently do nothing (Vivado warns "No pins matched").
##
## Each generated clock:
##   -source  = where the MASTER clock is DEFINED: the port for clk_14, or the
##              Q pin a generated master was created on. Then -edges simply
##              count the master's own waveform as report_clocks shows it.
##              (First tried: the dividing flip-flop's own C pin. Vivado then
##              numbers the master's edges as seen at that pin, after the
##              gates on the way; for V8 that came out shifted half a c5_clk
##              period and check_timing flagged the clock "not connected to a
##              clock source". With the master's own pin: all connected and
##              every waveform where the hardware puts it.)
##   target   = the dividing flip-flop's OUTPUT pin (Q): where the clock comes out
##   -edges   = which master edges make the new clock's rise, fall, next rise
##              (master edges numbered from 1; odd = rising, even = falling).
##              Used instead of -divide_by wherever the flip-flop triggers on
##              the master's FALLING edge (-divide_by aligns to rising edges
##              and would put the clock half a master cycle early), and for
##              clocks that are not 50 % duty (v8_clk).
## ============================================================================

## ---- Primary clock: NOT here -------------------------------------------------------
## clk_14 is declared where the ULA's clock comes from, not inside the ULA:
##   * ULA as the top (out-of-context timing runs): ula_standalone.xdc, which
##     creates clk_14 on the ULA's own clk_14 port;
##   * ULA inside a board top (arty_top): the Clocking Wizard's MMCM output,
##     which Vivado derives automatically from the board clock and which flows
##     into the ULA's clk_14 pin.
## Either way every generated clock below uses -source [get_ports clk_14] and
## so hangs off whichever clock arrives there. (A conditional create_clock was
## tried: XDC does not support 'if'.)
##
## This file is SCOPED to the ula entity (SCOPED_TO_REF ula, or
## read_xdc -ref ula): Vivado applies it inside every instance of ula, so the
## paths below start at the ULA's own hierarchy (timing_subsystem/...) and
## get_ports means the ULA's ports, wherever the ULA sits.

## ---- clk_7: the 14 -> 7 MHz divider (clk_div_2 master_clock) ----------------
## Toggles on clk_14's RISING edge (crystal inverted by the book's common-
## emitter stage, then a falling-edge flip-flop: the inversions cancel), so
## -divide_by 2 (rising-aligned) is right here. Waveform {0 71.429}.
create_generated_clock -name clk_7 -source [get_ports clk_14] -divide_by 2 [get_pins timing_subsystem/master_clock/ff/gate_model.fpga_model.s_q_reg/Q]

## ---- C0..C3: NO new clocks (gated clocks) --------------------------------------
## C0 = clk_7, C1 = c0.clk_7, C2 = c0.c1.clk_7, C3 = c0.c1.c2.clk_7: the
## EDGES come from clk_7; c0..c2 only enable them. Vivado propagates clk_7
## through the gates by itself (checked: all four clock pins report clk_7).

## ---- c3_clk: C3's output clocks C4 (and, gated by c4, C5) ---------------------
## C3 is bit 3: it changes every 8 clk_7 cycles, so the period is 16 cycles
## (2285.728 ns). The counter advances on clk_7's FALLING edge, so the edges
## are master edges 2, 18, 34 (falling, +8 cycles, +8 cycles), not
## -divide_by 16 (which put them 71 ns early). Waveform {71.429 1214.293}.
create_generated_clock -name c3_clk -source [get_pins timing_subsystem/master_clock/ff/gate_model.fpga_model.s_q_reg/Q] -edges {2 18 34} [get_pins timing_subsystem/video_timing/ht/mhc/count_3/ff/gate_model.fpga_model.s_q_reg/Q]

## ---- C4: NO new clock --------------------------------------------------------
## c4 only gates c3 into C5's clock (C5 clock = c3 AND c4) and reaches the
## pal_v_burst parity latch's enable through the sync decode. It is never
## the source of edges; a c4_clk would give C5's clock pin two clocks.

## ---- c5_clk: C5's output = clk_hc6, clocks C6..C8 and V0..V8 -------------------
## clk_hc6 = NOR(tclk_a, c5_n) = c5 in normal use (tclk_a is the wafer test
## clock, '0' unless test mode A). C5 is bit 5: changes every 2 periods of
## c3_clk, on c3's falling edge (C5's clock is c3 AND c4, falling-edge
## flip-flop). Master c3_clk edges 2, 6, 10. Period 64 clk_7 = 9142.912 ns,
## waveform {1214.293 5785.749}. Checked: C6..C8 and V0..V8 all report c5_clk.
create_generated_clock -name c5_clk -source [get_pins timing_subsystem/video_timing/ht/mhc/count_3/ff/gate_model.fpga_model.s_q_reg/Q] -edges {2 6 10} [get_pins timing_subsystem/video_timing/ht/mhc/count_5/ff/gate_model.fpga_model.s_q_reg/Q]

## ---- Test modes off: tclk_a = tclk_b = '0' -------------------------------------
## The wafer test clocks (test_modes) are only active with MREQ and IORQ low
## together, which a real Z80 never does; in normal use both are '0'. Without
## this Vivado sees rd_n / wr_n / mreq_n / ioreq_n as possible clocks for C6..C8
## (clk_hc6 = NOR(tclk_a, c5_n)) and the FLASH divider (NOR(v8_n, tclk_b)).
## The constant goes on the INTERNAL test-clock pins, not on the CPU ports:
## fixing a port would switch off real CPU paths. Needs the hierarchy kept
## (synth with -flatten_hierarchy none) for these pins to exist.
set_case_analysis 0 [get_pins timing_subsystem/test_clocks/tclk_a]
set_case_analysis 0 [get_pins timing_subsystem/test_clocks/tclk_b]

## ---- v8_clk: V8 clocks the FLASH divider -----------------------------------------
## The vertical counter runs 0..311, so V8 (bit 8) is NOT 50 % duty: low on
## lines 0..255, high on lines 256..311 (56 lines), period 312 lines = one
## frame (19.968 ms, 50.08 Hz). Master c5_clk ticks 7 times per line
## (448 / 64 pixels) = 14 edge numbers per line; V0..V8 change on its FALLING
## edge (even numbers). Rise at edge 2; fall after the HIGH time, 56 x 14 =
## 784 later = 786; next rise one frame on, 312 x 14 = 4368 later = 4370.
## Waveform {5785.749 3589807.250}.
create_generated_clock -name v8_clk -source [get_pins timing_subsystem/video_timing/ht/mhc/count_5/ff/gate_model.fpga_model.s_q_reg/Q] -edges {2 786 4370} [get_pins timing_subsystem/video_timing/vlc/v_count_8/ff/gate_model.fpga_model.s_q_reg/Q]

## ---- flash0_clk .. flash3_clk: the FLASH ripple divider (flash_clock) --------
## clock_in = NOR(v8_n, tclk_b) = v8. Five falling-edge toggle stages, each
## clocked by the one before: each is a /2 of its master on the master's
## FALLING edge, {2 4 6} (like C4 off c3). ripple0 toggles at V8's fall = the
## 311 -> 0 frame wrap. ripple4's output is the FLASH data (flash_clk into the
## pixel mux), not a clock, so it gets none. flash3_clk ~ 320 ms.
create_generated_clock -name flash0_clk -source [get_pins timing_subsystem/video_timing/vlc/v_count_8/ff/gate_model.fpga_model.s_q_reg/Q] -edges {2 4 6} [get_pins colour_subsystem/flash/ripple0/gate_model.fpga_model.s_q_reg/Q]
create_generated_clock -name flash1_clk -source [get_pins colour_subsystem/flash/ripple0/gate_model.fpga_model.s_q_reg/Q] -edges {2 4 6} [get_pins colour_subsystem/flash/ripple1/gate_model.fpga_model.s_q_reg/Q]
create_generated_clock -name flash2_clk -source [get_pins colour_subsystem/flash/ripple1/gate_model.fpga_model.s_q_reg/Q] -edges {2 4 6} [get_pins colour_subsystem/flash/ripple2/gate_model.fpga_model.s_q_reg/Q]
create_generated_clock -name flash3_clk -source [get_pins colour_subsystem/flash/ripple2/gate_model.fpga_model.s_q_reg/Q] -edges {2 4 6} [get_pins colour_subsystem/flash/ripple3/gate_model.fpga_model.s_q_reg/Q]

## ---- pdl_clk / adl_clk / aol_clk: the data-latch strobes ------------------------
## The registered strobes (latch_and_shift_reg_control_clks, architecture
## synchronous) are flip-flops on clk_14's rising edge whose OUTPUT is the
## enable (G) of the 8-bit pixel, attribute and attribute-output latches:
## a flip-flop output used as a clock. Active LOW, a tick or two at a time:
##   tick = one clk_14 cycle, 16 per character; tick k starts at clk_14 edge
##   3 + 2(k - 2) (tick 2 starts as clk_7 falls, at 71.429 = clk_14 edge 3).
##   rise = where the low pulse ends, fall = where the next one starts,
##   next rise = one period after the rise.
## pixel_data_latch_n   low tick 2 (and 10): fall 3, rise 5, period 8 ticks
##                      -> {5 19 21}, 571.432 ns, waveform {142.858 642.861}
## attr_data_latch_n    low tick 6 (and 14): fall 11, rise 13, period 8 ticks
##                      -> {13 27 29}, 571.432 ns
## attr_output_latch_n  low ticks 8, 9: fall 15, rise 19, period 16 ticks
##                      -> {19 47 51}, 1142.864 ns
## Which pixel of the character "tick 2" is cannot be pinned (the counter's
## start value is arbitrary to timing); what matters is that the edges sit on
## the right clk_7 phase, since the latch outputs feed the pixel shift
## register. In the display the strobes fire only inside the fetch window;
## timing analysis treats them as periodic, which is the worst case.
create_generated_clock -name pdl_clk -source [get_ports clk_14] -edges {5 19 21} [get_pins video_fetch_subsystem/latch_shift_clks/s_pixel_data_latch_n_reg/Q]
create_generated_clock -name adl_clk -source [get_ports clk_14] -edges {13 27 29} [get_pins video_fetch_subsystem/latch_shift_clks/s_attr_data_latch_n_reg/Q]
create_generated_clock -name aol_clk -source [get_ports clk_14] -edges {19 47 51} [get_pins video_fetch_subsystem/latch_shift_clks/s_attr_output_latch_n_reg/Q]

## ---- ras_clk: the video RAS register, enable of the row-A0 latch -------------------
## s_ras_r_reg (ras_cas_generation, synchronous) is a clk_14 register; through
## vid_ras_n its output enables video_address_generation's row_a0_latch.
## Its own time base: tick = c1 c0 clk_7, 0..7 per 4-pixel DRAM cycle; tick k
## starts at clk_14 edge 3 + 2k. The decode sets RAS for ticks 0..5, but a
## register is ONE TICK LATE (at the edge that starts tick k, clk_7 and the
## counter bits still show tick k-1), so the OUTPUT is high in ticks 1..6 and
## low in 7 and 0 (the precharge gap across the cycle boundary).
## rise = tick 1 = edge 5, fall = tick 7 = edge 17, next rise 5 + 16 = 21.
## Period 8 ticks = 571.432 ns, waveform {142.858 571.432}.
create_generated_clock -name ras_clk -source [get_ports clk_14] -edges {5 17 21} [get_pins video_fetch_subsystem/strobe_generation/s_ras_r_reg/Q]

## ---- Clocks that leak into logic ------------------------------------------------
## Several clock nets are ALSO data (C3 and V8 are address / decode inputs,
## RAS feeds the row-A0 latch). Vivado follows a clock through ANY logic, so
## they leaked into latch enables built from decodes (multiple_clock: c3_clk,
## ras_clk, v8_clk all on the border latch's G). The fix is to declare the
## REAL clock where the enable is formed: a clock defined on a pin BLOCKS the
## clocks arriving from upstream at that pin.

## ---- sync_clk: composite sync = enable of pal_v_burst's line-parity latch ------
## sync_n is decoded from the counters, so it changes on clk_7's falling edges.
## Line = 448 pixels = 896 clk_7 edge numbers; low 32 pixels (the hsync pulse),
## high 416: rise 2, fall 2 + 832 = 834, next rise 2 + 896 = 898. In the four
## vsync lines sync_n differs, but its edges stay on the same clk_7 phase, so
## the repeating-hsync model is safe. Waveform {71.429 59500.359}. Target is
## our own hierarchical pin (ula_timing's output), not a synthesis LUT name.
create_generated_clock -name sync_clk -source [get_pins timing_subsystem/master_clock/ff/gate_model.fpga_model.s_q_reg/Q] -edges {2 834 898} [get_pins timing_subsystem/sync_6c_n]

## ---- cpu_clk: the Z80 clock latch (contention_handler_3) -------------------------
## cpuclk = c0 or (cpuclk and H): c0 = clk_7 / 2 (3.5 MHz) on clk_7's falling
## edges, so {2 4 6}. Contention only STRETCHES it (held high), so the plain
## 3.5 MHz waveform is its fastest = the worst case to time. Declared on the
## latch's OUTPUT; it reaches the two contention mask latches' enables.
create_generated_clock -name cpu_clk -source [get_pins timing_subsystem/master_clock/ff/gate_model.fpga_model.s_q_reg/Q] -edges {2 4 6} [get_pins memory_cpu_subsystem/cpu_contention/gate_model.fpga_model.s_q_reg/Q]

## ---- port_wr_clk: the CPU's port 0xFE write strobe ------------------------------
## Enables the border and MIC / speaker latches. With no Z80 in a ULA-only
## analysis it is driven from outside (CPU pins), so it is a PRIMARY clock on
## an internal pin: the port decoder's output, which feeds both latch groups.
## Period = 4 T-states, a stand-in; the clock groups below make it irrelevant.
create_clock -name port_wr_clk -period 1142.857 [get_pins io_port_subsystem/io_decode/port_wr_n]

## ---- Clock groups: the CPU writes are asynchronous to the video ---------------
## Every other clock is derived from clk_14, so they are RELATED and the paths
## between them must be timed (that is why they are generated clocks). A CPU
## port write happens whenever the program says, with no fixed edge
## relationship to the video (a mid-line border write changes colour mid-line:
## that is how border effects work), so no timing between the two groups.
## Must be LAST: -filter collects the clocks that exist when this line is read.
## Never use async groups just to quieten a report: related clocks put in
## separate groups hide real failures. Revisit in the Spectrum repo, where
## port_wr comes from the Z80 core's clock (cpu_clk) and is related.
set_clock_groups -asynchronous -group [get_clocks port_wr_clk] -group [get_clocks -filter {NAME != port_wr_clk}]

## ---- The CPU clock latch's own enable: stop the leaking clocks -------------------
## Its gate is built from counter bits (the contention window) and the border,
## so c3_clk and v8_clk leak into it. That latch IS a clock generator (its
## output is cpu_clk); its inputs are data deciding when the clock stops.
## Left alone, the leaked clocks loop round through the mask latches it clocks
## and CRASH Vivado's timing engine (access violation at the first timing
## update). Blocking them here fixes that; cpu_clk itself is unaffected, and
## check_timing then lists this one G pin under no_clock (it is the clock
## generator: honest).
set_clock_sense -stop_propagation -clocks [get_clocks {c3_clk v8_clk}] [get_pins memory_cpu_subsystem/cpu_contention/gate_model.fpga_model.s_q_reg/G]

## ============================================================================
## Timing exceptions. Each is a PROMISE about the design; a false promise
## hides real failures. Each one names what proves it.
## ============================================================================

## ---- Multicycle: sload -> pixel shift register (hold) -------------------------
## By default Vivado assumes sload can change on EVERY clk_14 edge, so it checks
## hold against the clk_7 falling edge at the same instant (the shift register
## clocks then): requirement 0 ns, and the pixel clock arrives ~2 ns after
## clk_14 (through the divider), so -1.2 ns. But sload only changes on clk_14
## edges where clk_7 RISES (ticks 7 and 9), never on the load edge (tick 8).
## So the hold check moves back ONE clk_14 cycle (-start = count on the launch
## clock): requirement -71.429 ns, slack +70.2. Setup is unchanged (71.4 ns,
## real). -end would count on clk_7 and move it two ticks: too far.
## Proof: latch_and_shift_reg_control_clks_sync_tb's race check (sload stable
## +/-20 ns around every falling pixel-clock edge, 86 898 edges).
set_multicycle_path -hold 1 -start -from [get_cells video_fetch_subsystem/latch_shift_clks/s_sload_reg] -to [get_clocks clk_7]

## ---- False path (hold only): pixel data latch -> pixel shift register ----------
## The pixel latch opens in tick 2, on a clk_7 falling edge, i.e. just as the
## shift register clocks, so Vivado sees a hold race (-0.06 ns). But the latch
## output only reaches the shift cells' D through the load / shift mux, which
## selects it only while sload = 1 (ticks 7, 8); in tick 2 sload is 0 and the
## mux passes the neighbour's bit. By tick 7 the latch has been closed since
## tick 3. A change on this path can never be captured -> no hold check.
## SETUP stays checked (the load does need the latch data in time: +120.9 ns).
## Proof: the strobe tick windows (header of latch_and_shift_reg_control_clks,
## checked by its sync TB).
## Written -through the latch's q_n output PIN (a port of data_latch_1_bit, so
## it exists from the start) rather than -from the latch CELL: inside a top,
## the file is read while synthesis is still building the latches, and the
## cell is not a valid startpoint yet ("no valid startpoints").
set_false_path -hold -through [get_pins colour_subsystem/attr_select_mux/pix_serial/data_latch_8/latch_*/q_n] -to [get_clocks clk_7]

## ============================================================================
## Known, understood hold reports (NOT fixed): the ripple chain, 12 paths
## ============================================================================
## After the above, setup is met everywhere and 12 hold paths still fail, all
## of one shape: a clock-making flip-flop's OUTPUT feeding a flip-flop clocked
## by that stage's MASTER, e.g. C5's own toggle (Q -> D, -7.5 ns), V8 into the
## c5_clk domain (-4.4 .. -9.1), each FLASH stage into the one before
## (-11 .. -30 ns). They are an artefact of how Vivado times ripple clocks:
## for the LATEST arrival of a generated clock it also follows the gating
## ENABLE inputs, e.g. c3_clk via C0 -> C1 -> C2 (c3's clock is
## c0.c1.c2.clk_7), adding ~8.8 ns per stage that the real edge never has (the
## edge always comes from clk_7; the enables are stable long before it). The
## launch side uses the short, real route, so a false skew appears. In the
## real circuit these are ordinary toggles and counter feedbacks, and the
## gate-level simulations (counter TBs, ula_tb) run them at full speed.
## Decision (2026-10-25): document, don't fight Vivado's ripple model; if the
## Arty smoke test misbehaves, these paths are the first place to look.
## Fixing it properly would mean synchronous counters on clk_14 with enables
## (gives up the gate-level structure of the backbone).
## ---- Latch timing: the video_en latch (gd_latch) ---------------------------
## A latch has a WINDOW, not an edge: open (transparent) while c3 = 1 here,
## closed when c3 falls. By default Vivado lets data arrive any time up to the
## close and carry on through ("time borrowing", up to the whole 1143 ns
## window), then checks the next stage: video_en -> sload (71 ns) failed by
## -1085 ns, and -584 ns into the attribute output latches.
## The facts: border_n (its input) = NOR(c8, v8, v6.v7) changes ONLY at pixel
## 0 / 256 and at line changes, i.e. counter wraps where C3 FALLS = exactly
## when this latch CLOSES. The ULA wants the OLD value there, and gets it: V8 /
## C8 change tens of ns after C3 (ripple). So:
##  1. while open the input never changes -> no borrowing (max_time_borrow 0:
##     treat it like a flip-flop at its OPENING edge);
##  2. the change at the close belongs to the NEXT window -> setup checked
##     against the next opening, one c3 period (1143 ns) later: -setup 2.
##     Moving setup by N moves hold too, so -hold N-1 (= 1) puts it back:
##     the standard pair.
## -through the latch's d PIN (exists from the start; the cell does not while
## synthesis is still building it). Result: these paths pass (+1128 ns).
## Proof: the border_n equation (every term changes only at a C3-falling wrap);
## the border edges are checked by video_sync_tb and the sync-strobe TB.
set_max_time_borrow 0 [get_cells video_fetch_subsystem/latch_shift_clks/gd_latch/gate_model.fpga_model.s_q_reg]
set_multicycle_path -setup 2 -through [get_pins video_fetch_subsystem/latch_shift_clks/gd_latch/d]
set_multicycle_path -hold  1 -through [get_pins video_fetch_subsystem/latch_shift_clks/gd_latch/d]
