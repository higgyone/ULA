----------------------------------------------------------------------
-- bit3_counter_tb — single-UUT testbench with a TB-internal golden model
--
-- WHY NOT A DUAL-INSTANCE ORACLE: instantiating two copies of
-- bit3_counter in one testbench (e.g. Structural + Reference side by
-- side) triggers an xsim 2025.2 defect that transposes each instance's
-- clk/reset ports — both counters then clock once and freeze. Proven
-- unavoidable with named, positional, renamed, buffered, and distinct-
-- delay port connections (see CLAUDE.md "bit3_counter verification").
-- A SINGLE instance binds correctly, so this TB instantiates exactly
-- one UUT and compares it against a golden count computed *inside the
-- testbench* (a process + variable, not a second entity). No second
-- instance => the xsim bug cannot occur.
--
-- WHICH ARCHITECTURE IS TESTED: edit the `uut` instantiation line below
-- — `(Structural)`, `(T_Structure)`, or `(Reference)` — and re-run.
-- Each must match the golden model identically.
--
-- TIMING: the UUT is falling-edge triggered. The Structural arch's
-- d_ff_nor cells carry `after TG` (1 ns) gate delays, so the UUT output
-- settles a few ns AFTER each falling edge. The golden updates in delta
-- time on the same falling edge. The checker therefore samples at the
-- *rising* edge (mid-period, t = 5+10n) where the UUT is fully settled
-- and the golden is stable — a clean, race-free comparison point.
--
-- CHECKS (every rising edge, once outputs have left 'U'):
--   1. output   = golden count          (functional equivalence)
--   2. overflow = '1' iff output = "110" (overflow invariant)
--
-- STIMULUS:
--   * Phase 1 — power-on reset, 45 ns (settles the d_ff_nor network).
--   * Phase 2 — 200 ns free run (cycles all 7 states many times).
--   * Phase 3 — reset asserted from each non-zero state K = 1..6,
--     checking synchronous-clear from an arbitrary state.
--   * Phase 4 — final free run, then end-of-sim coverage report.
--   Reset transitions are timed to land on rising clk edges.
--
-- NOT testable through entity ports: the illegal-state "111" self-
-- correction (would need a backdoor write into the d_ff_nor cells).
-- Argued instead from the +1-rule analysis in bit3_counter.vhd.
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity bit3_counter_tb is
end bit3_counter_tb;

architecture Behavioral of bit3_counter_tb is
    constant T : time := 10 ns;

    signal sysclk : std_logic;
    signal sysrst : std_logic;

    -- UUT outputs.
    signal out_uut : std_logic_vector(2 downto 0);
    signal ov_uut  : std_logic;

    -- Golden model (computed in this testbench, not a second entity).
    signal exp_out : std_logic_vector(2 downto 0);
    signal exp_ov  : std_logic;

    -- Coverage: bit k set once the UUT has been observed in state k.
    signal states_visited : std_logic_vector(6 downto 0) := (others => '0');

    -- End-of-sim flag — gates the final coverage report.
    signal sim_done : boolean := false;
begin

    -- Single UUT. Edit the architecture name to verify each in turn:
    --   (Structural)  — three d_ff_nor cells + next-state logic
    --   (T_Structure) — trc_ff/trce_ff carry-chain (schematic-faithful)
    --   (Reference)   — behavioural unsigned +1 (the spec)
    uut : entity work.bit3_counter(Structural)
        port map ( clk      => sysclk,
                   reset    => sysrst,
                   output   => out_uut,
                   overflow => ov_uut );

    -- Free-running 10 ns clock. Falling edges at t = 10, 20, 30, ...
    process
    begin
        sysclk <= '0';
        wait for T / 2;
        sysclk <= '1';
        wait for T / 2;
    end process;

    -- Reset stimulus. Every transition lands on a rising clk edge.
    process
    begin
        -- Phase 1: hold reset 45 ns (settles the d_ff_nor network).
        sysrst <= '1';
        wait for 45 ns;

        -- Phase 2: 200 ns free run.
        sysrst <= '0';
        wait for 200 ns;

        -- Phase 3: reset-from-state-K for K = 1..6.
        for k in 1 to 6 loop
            sysrst <= '1';
            wait for 30 ns;
            sysrst <= '0';
            wait for k * T;
        end loop;

        -- Phase 4: one more clear, then a final free run.
        sysrst <= '1';
        wait for 30 ns;
        sysrst <= '0';
        wait for 200 ns;

        sim_done <= true;
        wait;
    end process;

    -- Golden model: modulo-7 counter with synchronous reset, falling-edge
    -- triggered — the behavioural spec the UUT must match. Computed here
    -- as a process + variable so there is no second entity instance.
    golden : process(sysclk)
        variable cnt : unsigned(2 downto 0) := "000";
    begin
        if falling_edge(sysclk) then
            if sysrst = '1' then
                cnt := "000";
            elsif cnt = "110" then
                cnt := "000";
            else
                cnt := cnt + 1;
            end if;
            exp_out <= std_logic_vector(cnt);
            exp_ov  <= '1' when cnt = "110" else '0';
        end if;
    end process;

    -- Checker: sample mid-period (rising edge) where the UUT is settled.
    -- Gated until both UUT and golden have left their 'U' startup state.
    check : process(sysclk)
    begin
        if rising_edge(sysclk) then
            if (out_uut /= "UUU") and (exp_out /= "UUU") then
                assert out_uut = exp_out
                    report "FUNCTIONAL mismatch: UUT output /= golden count."
                    severity error;

                assert (ov_uut = '1') = (out_uut = "110")
                    report "OVERFLOW invariant broken: overflow vs output."
                    severity error;
            end if;
        end if;
    end process;

    -- Coverage tracker: latch each legal state the UUT visits (mid-period).
    cover : process(sysclk)
    begin
        if rising_edge(sysclk) then
            if    out_uut = "000" then states_visited(0) <= '1';
            elsif out_uut = "001" then states_visited(1) <= '1';
            elsif out_uut = "010" then states_visited(2) <= '1';
            elsif out_uut = "011" then states_visited(3) <= '1';
            elsif out_uut = "100" then states_visited(4) <= '1';
            elsif out_uut = "101" then states_visited(5) <= '1';
            elsif out_uut = "110" then states_visited(6) <= '1';
            end if;
        end if;
    end process;

    -- End-of-sim coverage report. Warns (not errors) on any missed state.
    report_cov : process(sim_done)
    begin
        if sim_done then
            for k in 0 to 6 loop
                assert states_visited(k) = '1'
                    report "Coverage gap: state " & integer'image(k) &
                           " was never visited."
                    severity warning;
            end loop;
            report "bit3_counter_tb: simulation complete." severity note;
        end if;
    end process;

end Behavioral;
