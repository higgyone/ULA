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
##   -source  = the dividing flip-flop's CLOCK INPUT pin (C): the clock as it
##              actually arrives there (through any inverter or gate)
##   target   = its OUTPUT pin (Q): where the new clock comes out
##   -edges   = which master edges make the new clock's rise, fall, next rise
##              (master edges numbered from 1; odd = rising, even = falling).
##              Used instead of -divide_by wherever the flip-flop triggers on
##              the master's FALLING edge: -divide_by always aligns to rising
##              edges and would put the clock half a master cycle early.
## ============================================================================

## ---- Primary clock: the 14 MHz crystal (pin 39) -----------------------------
## 1 / 14 MHz = 71.429 ns; default waveform {0 35.715} = 50 % duty.
create_clock -name clk_14 -period 71.429 [get_ports clk_14]

## ---- clk_7: the 14 -> 7 MHz divider (clk_div_2 master_clock) ----------------
## Toggles on clk_14's RISING edge (crystal inverted by the book's common-
## emitter stage, then a falling-edge flip-flop: the inversions cancel), so
## -divide_by 2 (rising-aligned) is right here. Waveform {0 71.429}.
create_generated_clock -name clk_7 -source [get_pins timing_subsystem/master_clock/ff/gate_model.fpga_model.s_q_reg/C] -divide_by 2 [get_pins timing_subsystem/master_clock/ff/gate_model.fpga_model.s_q_reg/Q]

## ---- C0..C3: NO new clocks (gated clocks) --------------------------------------
## C0 = clk_7, C1 = c0.clk_7, C2 = c0.c1.clk_7, C3 = c0.c1.c2.clk_7: the
## EDGES come from clk_7; c0..c2 only enable them. Vivado propagates clk_7
## through the gates by itself (checked: all four clock pins report clk_7).

## ---- c3_clk: C3's output clocks C4 (and, gated by c4, C5) ---------------------
## C3 is bit 3: it changes every 8 clk_7 cycles, so the period is 16 cycles
## (2285.728 ns). The counter advances on clk_7's FALLING edge, so the edges
## are master edges 2, 18, 34 (falling, +8 cycles, +8 cycles), not
## -divide_by 16 (which put them 71 ns early). Waveform {71.429 1214.293}.
create_generated_clock -name c3_clk -source [get_pins timing_subsystem/video_timing/ht/mhc/count_3/ff/gate_model.fpga_model.s_q_reg/C] -edges {2 18 34} [get_pins timing_subsystem/video_timing/ht/mhc/count_3/ff/gate_model.fpga_model.s_q_reg/Q]

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
create_generated_clock -name c5_clk -source [get_pins timing_subsystem/video_timing/ht/mhc/count_5/ff/gate_model.fpga_model.s_q_reg/C] -edges {2 6 10} [get_pins timing_subsystem/video_timing/ht/mhc/count_5/ff/gate_model.fpga_model.s_q_reg/Q]

## ---- Still to do ------------------------------------------------------------
##  - test modes: tclk_a / tclk_b make rd_n, wr_n, mreq_n look like clocks
##    (set_case_analysis)
##  - V-counter outputs as clocks (FLASH divider off v8, ...)
##  - latches enabled by registered strobes (pixel / attribute data latches)
##  - latches enabled by counter decodes (video_en on c3_n, burst parity on
##    sync_n, row A0 on vid_ras_n)
##  - CPU-side latches (border, MIC / speaker, CPU clock hold)
