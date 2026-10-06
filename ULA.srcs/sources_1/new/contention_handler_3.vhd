----------------------------------------------------------------------------------
-- contention_handler_3 — CPU clock and contention (issue 3 ULA, 6C001)
--
-- Makes the Z80's 3.5 MHz clock from c0 and HOLDS it when the CPU tries to use
-- the lower 16K DRAM (or the ULA's own I/O port) while the ULA needs the DRAM for
-- a video fetch.
--
-- ── How it decides ───────────────────────────────────────────────────
--   The ULA works on the opposite clock edge to the Z80, so it sees each
--   T-state half a T-state early and can stop the clock before the Z80 moves.
--
--   trigger   = a14 AND NOT a15 (0x4000..0x7FFF)  OR  ioreq (ULA port I/O)
--               The ADDRESS alone, not MREQ: the address is valid at T1,
--               before any control signal, and the decision is due before then.
--               (a_out / b_out = the two NOR legs; NOR(a_out, b_out) = trigger)
--   window    = c2 OR c3 (c_out = NOR(c2, c3) is the "outside" leg)
--               6 T-states of every 8: the span of the 6,5,4,3,2,1,0,0 pattern.
--   e_out     = checking enabled: NOT border, NOT mreqt23, NOT ioreqtw3, and
--               only in one phase of the clock (s_cpuclk_n = '0').
--   d_out     = trigger AND window AND e_out        memory / address hold
--   f_out     = ioreq AND window AND NOT border AND NOT ioreqtw3 AND
--               (s_cpuclk_n = '0')                  ULA-port I/O hold
--   g_out     = NOR(d_out, c0, f_out)               the clock, or held at '0'
--
--   d_out feeds back through g_out -> s_cpuclk_n -> e_out -> d_out: once a hold
--   starts it keeps itself on until the trigger or the window goes away. The
--   hold can only START in the phase where e_out is enabled, so it stretches a
--   clock level that is already there and never cuts a pulse short.
--
-- ── The masks: mreqt23 and ioreqtw3 ──────────────────────────────────
--   Two data_latch_1_bit latches, enabled by the clock (g_out_n), sample mreq_n
--   and ioreq_n:
--     mreqt23   high for T2 and T3 of a memory access: turns contention
--               checking OFF once the access has started, so the clock is only
--               ever held at the START of an access, never part-way through.
--     ioreqtw3  the same for an I/O access to the ULA port (T2 onwards).
--   I/O to other addresses in 0x4000..0x7FFF has no MREQ, so nothing masks it:
--   it can be held at every T-state (the documented C:1, C:1, C:1, C:1).
--
-- ── Gate delays (load-bearing) ───────────────────────────────────────
--   Every gate carries `after tg` (1 ns). The hold is a feedback loop, and with
--   zero-delay gates a change can circulate it forever within one instant:
--   GHDL stops at its delta-cycle limit as soon as a contended address
--   appears. The 1 ns delays let the loop settle, as in data_latch_1_bit's
--   cross-coupled NORs. Simulation only: synthesis ignores `after`.
--
-- ── The clock path to the Z80: two inversions that cancel ────────────
--
--     g_out -NOT-> cpuclk -[ULA peripheral transistor]-> pin 32 = phicpu_n
--                          -[PCB transistor]-----------> Z80 clock = cpuclk
--
--   cpuclk is the ULA's INTERNAL clock: NOT g_out = c0 while running, held
--   '1' during a hold. It does not leave the chip directly. The ULA's output
--   stage on pin 32 is a PERIPHERAL TRANSISTOR (part of the chip's pad
--   circuitry, not the gate array) that inverts it, so the pin carries
--   phicpu_n. That transistor is modelled here as the final NOT, so this block
--   presents the real pin. The PCB's own transistor inverts again before the
--   Z80, so the Z80 runs on cpuclk itself (= c0) and is held HIGH with it.
--   The PCB transistor belongs outside the ULA (testbench / top level).
--
--   This phasing is what makes the rest of the circuit work:
--     - checking (e_out, f_out) is enabled only while g_out = '0', i.e. while
--       cpuclk and the Z80's clock are HIGH: the first half of each T-state,
--       once the address is valid, so a hold stretches a high level;
--     - the mask latches are open while cpuclk = '0', the Z80's LOW half.
--       MREQ falls in T1's low half, so mreqt23 is high in the T2 and T3
--       checking phases. IORQ falls just after T2's rising edge, while the
--       latch is CLOSED, so the ULA-port hold (f_out) fires first and
--       ioreqtw3 only masks from TW on.
--   With one net inversion instead, IORQ would arrive while the latch is open
--   and port 0xFE would never be contended (see contention_handler_3_tb).
--
-- ── Ports ────────────────────────────────────────────────────────────
--   c0_n        horizontal counter bit 0, inverted (the 3.5 MHz source)
--   c2, c3      horizontal counter bits 2 and 3 (the contention window)
--   a14, a15    Z80 address bits 14 and 15
--   ioreq_n     I/O request to the ULA port = a0 OR iorq_n, active low
--               (the OR gate is not built yet)
--   mreq_n      Z80 /MREQ, active low
--   border      ACTIVE HIGH: '1' in the border (only nborder exists so far,
--               so the wiring stage needs an inverter)
--   cpuclk      internal CPU clock: c0 when running, held '1' during a hold
--   phicpu_n    pin 32: cpuclk through the inverting peripheral transistor.
--               The PCB transistor inverts it back for the Z80.
--   ioreqtw3_n  ULA-port I/O access in T2 / TW / T3, active low (no consumer
--               yet)
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity contention_handler_3 is
    port (
        c0_n       : in    std_logic;
        a14        : in    std_logic;
        ioreq_n    : in    std_logic;
        a15        : in    std_logic;
        c2         : in    std_logic;
        c3         : in    std_logic;
        border     : in    std_logic;
        mreq_n     : in    std_logic;
        cpuclk     : out   std_logic;
        phicpu_n   : out   std_logic;
        ioreqtw3_n : out   std_logic
    );
end entity contention_handler_3;

architecture structural of contention_handler_3 is

    constant tg : time := 1 ns; -- modelled gate delay (sim only), see header

    signal s_c0       : std_logic;
    signal s_ioreq    : std_logic;
    signal s_cpuclk_n : std_logic;
    signal s_ioreqtw3 : std_logic;
    signal s_a15_n    : std_logic;
    signal s_mreqt23  : std_logic;
    signal s_cpuclk   : std_logic;

    signal a_out   : std_logic;
    signal b_out   : std_logic;
    signal c_out   : std_logic;
    signal d_out   : std_logic;
    signal e_out   : std_logic;
    signal e_out_n : std_logic;
    signal f_out   : std_logic;
    signal g_out   : std_logic;
    signal g_out_n : std_logic;

begin

    s_c0    <= not(c0_n) after tg;
    s_ioreq <= not(ioreq_n) after tg;
    s_a15_n <= not(a15) after tg;

    -- trigger legs: NOR(a_out, b_out) = (a14 AND NOT a15) OR ioreq
    a_out <= not(a14 or s_ioreq) after tg;
    b_out <= not(s_ioreq or s_a15_n) after tg;

    -- outside the contention window: c2 = c3 = '0'
    c_out <= not(c2 or c3) after tg;

    -- memory / address hold
    d_out <= not(a_out or b_out or c_out or e_out_n) after tg;

    -- checking enabled
    e_out   <= not(border or s_ioreqtw3 or s_mreqt23 or s_cpuclk_n) after tg;
    e_out_n <= not(e_out) after tg;

    -- ULA-port I/O hold
    f_out <= not(c_out or border or s_cpuclk_n or ioreq_n or s_ioreqtw3) after tg;

    -- the clock: follows c0, held at '0' by either hold
    g_out      <= not(d_out or s_c0 or f_out) after tg;
    g_out_n    <= not(g_out) after tg;
    s_cpuclk_n <= not(g_out_n) after tg;
    s_cpuclk   <= not(g_out) after tg;
    cpuclk     <= s_cpuclk;

    -- pin 32: the ULA's inverting peripheral (output) transistor
    phicpu_n <= not(s_cpuclk) after tg;

    -- ioreqtw3: ULA-port I/O access under way (T2 onwards)
    latch_0 : entity work.data_latch_1_bit
        port map (
            e     => g_out_n,
            d     => ioreq_n,
            q     => ioreqtw3_n,
            q_bar => s_ioreqtw3
        );

    -- mreqt23: memory access under way (T2, T3)
    latch_1 : entity work.data_latch_1_bit
        port map (
            e     => g_out_n,
            d     => mreq_n,
            q     => open,
            q_bar => s_mreqt23
        );

end architecture structural;
