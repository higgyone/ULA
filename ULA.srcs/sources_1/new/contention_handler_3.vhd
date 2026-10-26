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
--               (s_a_out / s_b_out = the two NOR legs; NOR(s_a_out, s_b_out) = trigger)
--   window    = c2 OR c3 (s_c_out = NOR(c2, c3) is the "outside" leg)
--               6 T-states of every 8: the span of the 6,5,4,3,2,1,0,0 pattern.
--   s_e_out     = checking enabled: NOT border, NOT mreqt23, NOT ioreqtw3, and
--               only in one phase of the clock (s_cpuclk_n = '0').
--   s_d_out     = trigger AND window AND s_e_out        memory / address hold
--   s_f_out     = ioreq AND window AND NOT border AND NOT ioreqtw3 AND
--               (s_cpuclk_n = '0')                  ULA-port I/O hold
--   s_g_out     = NOR(s_d_out, c0, s_f_out)               the clock, or held at '0'
--
--   s_d_out feeds back through s_g_out -> s_cpuclk_n -> s_e_out -> s_d_out: once a hold
--   starts it keeps itself on until the trigger or the window goes away. The
--   hold can only START in the phase where s_e_out is enabled, so it stretches a
--   clock level that is already there and never cuts a pulse short.
--
-- ── The masks: mreqt23 and ioreqtw3 ──────────────────────────────────
--   Two data_latch_1_bit latches, enabled by the clock (s_g_out_n), sample mreq_n
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
--     s_g_out -NOT-> cpuclk -[ULA peripheral transistor]-> pin 32 = phicpu_n
--                          -[PCB transistor]-----------> Z80 clock = cpuclk
--
--   cpuclk is the ULA's INTERNAL clock: NOT s_g_out = c0 while running, held
--   '1' during a hold. It does not leave the chip directly. The ULA's output
--   stage on pin 32 is a PERIPHERAL TRANSISTOR (part of the chip's pad
--   circuitry, not the gate array) that inverts it, so the pin carries
--   phicpu_n. The PCB's own transistor inverts again before the Z80, so the
--   Z80 runs on cpuclk itself (= c0) and is held HIGH with it. The PCB
--   transistor belongs outside the ULA (testbench / top level).
--
--   Pin 32's pad is an INVERTING OPEN COLLECTOR with NO on-chip pull-up: the
--   transistor is on, pulling the pin to '0', while cpuclk = '1', and lets go
--   ('Z') while cpuclk = '0'. The high level comes from a 1k pull-up to 5 V on
--   the PCB. Modelled as phicpu_n = '0' / 'Z', so this block presents the real
--   pin. On the PCB:
--
--     pin 32 ─┬─ 1k ── 5 V
--             └─▶ base, NPN common emitter: collector = Z80 CLK, 180 ohm to 5 V
--
--     cpuclk = '1' -> pin 32 low  -> NPN off -> Z80 CLK high (180 ohm)
--     cpuclk = '0' -> pin 32 high -> NPN on  -> Z80 CLK low
--
--   The NPN and its strong 180 ohm pull-up give the Z80 the near-5 V clock
--   swing its CLK input needs, which TTL levels do not reach.
--
--   This phasing is what makes the rest of the circuit work:
--     - checking (s_e_out, s_f_out) is enabled only while s_g_out = '0', i.e. while
--       cpuclk and the Z80's clock are HIGH: the first half of each T-state,
--       once the address is valid, so a hold stretches a high level;
--     - the mask latches are open while cpuclk = '0', the Z80's LOW half.
--       MREQ falls in T1's low half, so mreqt23 is high in the T2 and T3
--       checking phases. IORQ falls just after T2's rising edge, while the
--       latch is CLOSED, so the ULA-port hold (s_f_out) fires first and
--       ioreqtw3 only masks from TW on.
--   With one net inversion instead, IORQ would arrive while the latch is open
--   and port 0xFE would never be contended (see contention_handler_3_tb).
--
-- ── Ports ────────────────────────────────────────────────────────────
--   c0_n        horizontal counter bit 0, inverted (the 3.5 MHz source)
--   c2, c3      horizontal counter bits 2 and 3 (the contention window)
--   a14, a15    Z80 address bits 14 and 15
--   ioreq_n     I/O request to the ULA port, active low: a ULA PIN. It is
--               the Z80's /IORQ OR'd with A0 OFF-CHIP, on the PCB, so it is
--               low only for an I/O cycle to an even address. Nothing inside
--               the ULA generates it (the testbench models the PCB gate).
--   mreq_n      Z80 /MREQ, active low
--   border      ACTIVE HIGH: '1' in the border (video_sync's border output,
--               the complement of border_n)
--   cpuclk      internal CPU clock: c0 when running, held '1' during a hold
--   phicpu_n    pin 32: cpuclk through the inverting peripheral transistor,
--               open collector: '0' while cpuclk = '1', else 'Z' (1k PCB
--               pull-up). The PCB transistor inverts it back for the Z80.
--   ioreqtw3_n  ULA-port I/O access in T2 / TW / T3, active low; read by
--               io_port_decode_0xfe (via ula_memory_cpu -> ula_io_port)
--
-- ── Two models: gate_model (simulation) / fpga_cpuclk_latch (FPGA) ───
--   The CPU clock hold is a loop in plain gates: cpuclk feeds back into
--   s_e_out and s_f_out. On an FPGA that is a combinational loop (two LUTs,
--   the last LUTLP-1 in the design once the primitives had FPGA branches).
--   So, as in d_ff_nor / data_latch_1_bit, two generate branches picked by
--   fpga_build from ula_build_pkg (sim: false, synthesis: true).
--
--   Multiplying the gates out gives one equation:
--     cpuclk(next) = c0  or  (cpuclk and H)
--     H = (c2 or c3) and (not border) and (not s_ioreqtw3)
--         and ( ioreq or (a14 and not a15 and not s_mreqt23) )
--   (De Morgan on each NOR; (X+Y)(X+Z) = X+YZ on the address legs; then
--   absorption.) H is "a hold is wanted": in the window, not in the border,
--   and ULA-port I/O not past T2, or contended memory (0x4000..0x7FFF) not
--   already under way. It contains no cpuclk, so it is plain logic.
--   The equation is a set-dominant latch:
--     c0 = '1'            -> '1'  (follows c0)
--     c0 = '0', H = '0'   -> '0'  (follows c0)
--     c0 = '0', H = '1'   -> holds: once high, the clock stays high = the
--                                   Z80 is held (contention)
--
--   fpga_build = false  the gates, unchanged (gate_model branch).
--   fpga_build = true   s_hold = H and a latch process on (s_c0, s_hold):
--                       if c0 = '1' -> '1', elsif H = '0' -> '0', no else.
--                       It drives s_cpuclk and s_g_out_n (= cpuclk, the mask
--                       latches' enable). Vivado reports "inferring latch".
--
--   Shared by both builds, outside the generate: the input inverters and the
--   feed-forward gates (s_a_out .. s_c_out), cpuclk / phicpu_n, and the two
--   mask latches. Rule: every signal has exactly one driver in each build,
--   so anything read outside the branches (s_cpuclk, s_g_out_n) is driven in
--   BOTH branches. The FPGA build still feeds back (s_q -> mask latch enable
--   -> s_ioreqtw3 / s_mreqt23 -> H), but through real latches, which Vivado
--   can time. contention_handler_3_tb passes with both packages (64 cycle
--   checks, 1110 clock phases checked for runts).
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use work.ula_build_pkg.all;

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

    signal s_a_out   : std_logic;
    signal s_b_out   : std_logic;
    signal s_c_out   : std_logic;
    signal s_d_out   : std_logic;
    signal s_e_out   : std_logic;
    signal s_e_out_n : std_logic;
    signal s_f_out   : std_logic;
    signal s_g_out   : std_logic;
    signal s_g_out_n : std_logic;

    signal s_hold : std_logic;        -- H: a hold is wanted (FPGA branch)
    signal s_q    : std_logic := '0'; -- the CPU clock latch (FPGA branch)

begin

    s_c0    <= not(c0_n) after tg;
    s_ioreq <= not(ioreq_n) after tg;
    s_a15_n <= not(a15) after tg;

    -- trigger legs: NOR(s_a_out, s_b_out) = (a14 AND NOT a15) OR ioreq
    s_a_out <= not(a14 or s_ioreq) after tg;
    s_b_out <= not(s_ioreq or s_a15_n) after tg;

    -- outside the contention window: c2 = c3 = '0'
    s_c_out <= not(c2 or c3) after tg;

    gate_model : if not fpga_build generate

        -- memory / address hold
        s_d_out <= not(s_a_out or s_b_out or s_c_out or s_e_out_n) after tg;

        -- checking enabled
        s_e_out   <= not(border or s_ioreqtw3 or s_mreqt23 or s_cpuclk_n) after tg;
        s_e_out_n <= not(s_e_out) after tg;

        -- ULA-port I/O hold
        s_f_out <= not(s_c_out or border or s_cpuclk_n or ioreq_n or s_ioreqtw3) after tg;

        -- the clock: follows c0, held at '0' by either hold
        s_g_out    <= not(s_d_out or s_c0 or s_f_out) after tg;
        s_g_out_n  <= not(s_g_out) after tg;
        s_cpuclk_n <= not(s_g_out_n) after tg;
        s_cpuclk   <= not(s_g_out) after tg;

    else fpga_model : generate

        -- H: hold the clock high (derivation: c2/c3 window, not border,
        -- I/O not past T2, and ULA I/O or contended memory not under way)
        s_hold <= (c2 or c3)
                  and (not border)
                  and (not s_ioreqtw3)
                  and (s_ioreq or (a14 and (not a15) and (not s_mreqt23)));

        -- cpuclk(next) = c0 or (cpuclk and H): a latch, set by c0,
        -- cleared when c0 is low and no hold is wanted, otherwise held
        fpga_cpuclk_latch : process (s_c0, s_hold) is
        begin

            if (s_c0 = '1') then
                s_q <= '1';
            elsif (s_hold = '0') then
                s_q <= '0';
            end if;

        end process fpga_cpuclk_latch;

        s_cpuclk  <= s_q;
        s_g_out_n <= s_q; -- = cpuclk: the mask latches' enable

    end generate gate_model;

    -- ── shared again: everything below only reads s_cpuclk / s_g_out_n ──
    cpuclk <= s_cpuclk;

    -- pin 32: the ULA's inverting peripheral (output) transistor
    phicpu_n <= '0' after tg when s_cpuclk = '1' else
                'Z' after tg;

    -- ioreqtw3: ULA-port I/O access under way (T2 onwards)
    latch_0 : entity work.data_latch_1_bit
        port map (
            e   => s_g_out_n,
            d   => ioreq_n,
            q   => ioreqtw3_n,
            q_n => s_ioreqtw3
        );

    -- mreqt23: memory access under way (T2, T3)
    latch_1 : entity work.data_latch_1_bit
        port map (
            e   => s_g_out_n,
            d   => mreq_n,
            q   => open,
            q_n => s_mreqt23
        );

end architecture structural;
