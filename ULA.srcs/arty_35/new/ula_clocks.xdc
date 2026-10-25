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

## ---- Primary clock: the 14 MHz crystal (pin 39) -----------------------------
## 1 / 14 MHz = 71.429 ns; default waveform {0 35.715} = 50 % duty.
create_clock -name clk_14 -period 71.429 [get_ports clk_14]

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

## ---- Still to do ------------------------------------------------------------
##  - latches enabled by registered strobes (pixel / attribute data latches)
##  - latches enabled by counter decodes (video_en on c3_n, burst parity on
##    sync_n, row A0 on vid_ras_n)
##  - CPU-side latches (border, MIC / speaker, CPU clock hold)
