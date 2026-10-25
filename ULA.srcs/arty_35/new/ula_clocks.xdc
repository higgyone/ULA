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

## ---- Known exception: multiple_clock (1) on the CPU clock latch's own G -------
## Its gate is built from counter bits (the contention window) and the border,
## so c3_clk and v8_clk leak into it. That latch IS a clock generator (its
## output is cpu_clk); its inputs are data deciding when the clock stops.
## set_clock_sense -stop_propagation on G was tried: it also cut cpu_clk off
## from its master. Left as this one documented warning.
