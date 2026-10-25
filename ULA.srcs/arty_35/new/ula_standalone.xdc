## ============================================================================
## ula_standalone.xdc - the ULA's clock when the ULA ITSELF is the top
##
## Only for running the ULA on its own (synth_design -top ula -mode
## out_of_context, as in the timing lessons). Then nothing feeds clk_14, so it
## is declared here as the primary clock: the 14 MHz crystal (pin 39),
## 1 / 14 MHz = 71.429 ns, default waveform {0 35.715}.
##
## DISABLED in the project, whose top is arty_top: there the Clocking Wizard's
## MMCM output reaches the ULA's clk_14 pin, and declaring clk_14 again would
## make a second, unrelated clock on the same wire. ula_clocks.xdc (scoped to
## ula) holds everything else and works in both cases.
##
## Read it BEFORE ula_clocks.xdc (the generated clocks need their master).
## ============================================================================
create_clock -name clk_14 -period 71.429 [get_ports clk_14]
