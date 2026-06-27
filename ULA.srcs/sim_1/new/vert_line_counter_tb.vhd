----------------------------------------------------------------------
-- vert_line_counter_tb — self-checking TB for Vert_Line_counter
--
-- Verifies the vertical counter's full contract against a golden model
-- computed in the TB (no second entity needed):
--   * increments by exactly 1 per ENABLED falling edge of Clk_HC6
--   * HOLDS when HCrst = '0' (no count change)
--   * wraps 311 -> 0 (v_max = 311, 312 states = 312 PAL lines)
--   * Vrst pulses high for exactly the one line where the count is 311
--
-- Synthetic drive (deliberate): Clk_HC6 and HCrst are generated
-- directly here rather than from a real master_horiz_counter instance.
-- Reaching the 311->0 wrap through the real MHC would need ~20 ms of
-- gate-level sim (312 lines x 64 us); the synthetic drive reaches it in
-- ~32 us. The MHC's own clk_hc6/hc_rst generation (and its harmless
-- ripple glitch on hc_rst) is covered separately by
-- master_horiz_counter_tb and the CLAUDE.md glitch analysis.
--
-- Sampling: Clk_HC6 is a clean TB-generated clock. The DUT here is the
-- gate-level T_Structure, whose carry chain ripples for ~9·TG (~9 ns)
-- after each falling edge (the `after TG` delays in d_ff_nor). The
-- checker samples on the following RISING edge (mid-period, T/2 = 50 ns
-- later) — well clear of that settle — exactly mirroring the golden
-- model it advanced on the falling edge.
--
-- PASS = simulation runs to the "TB PASS" note with no assertion errors.
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vert_line_counter_tb is
end vert_line_counter_tb;

architecture Behavioral of vert_line_counter_tb is
    constant T     : time    := 100 ns;          -- Clk_HC6 period; T/2 = 50 ns >> gate-ripple settle (~9 ns)
    constant V_MAX : integer := 311;             -- last line; counter visits 0..311 = 312 states
    constant N_DISABLED : integer := 3;          -- leading cycles with enable low (hold test)

    signal clk_hc6 : std_logic := '0';
    signal hc_rst  : std_logic := '0';
    signal v0, v1, v2, v3, v4, v5, v6, v7, v8 : std_logic;
    signal vrst    : std_logic;
    signal sim_done : boolean := false;
begin

    -- Device under test -------------------------------------------------
    vlc: entity work.Vert_Line_counter(T_Structure)
        port map(
            HCrst        => hc_rst,
            Clk_HC6      => clk_hc6,
            V0 => v0, V1 => v1, V2 => v2, V3 => v3, V4 => v4,
            V5 => v5, V6 => v6, V7 => v7, V8 => v8,
            Vrst => vrst
        );

    -- Clk_HC6 generator -------------------------------------------------
    clkgen: process
    begin
        while not sim_done loop
            clk_hc6 <= '0';
            wait for T / 2;
            clk_hc6 <= '1';
            wait for T / 2;
        end loop;
        wait;
    end process;

    -- HCrst stimulus: low for the first N_DISABLED cycles (proves
    -- the counter holds), then high so it advances one line per cycle.
    -- Driven on the rising edge so it is stable at the falling edge the
    -- DUT (and the checker) sample on.
    hcrst_stim: process
        variable cyc : integer := 0;
    begin
        wait until rising_edge(clk_hc6);
        cyc := cyc + 1;
        if cyc <= N_DISABLED then
            hc_rst <= '0';
        else
            hc_rst <= '1';
        end if;
    end process;

    -- Golden checker: advance the expected count on the falling edge
    -- exactly as the DUT does, then compare on the following rising edge.
    check: process
        variable expected   : integer := 0;
        variable exp_vrst    : std_logic := '0';
        variable actual      : integer;
        variable vec         : std_logic_vector(8 downto 0);
        variable wraps_seen  : integer := 0;
    begin
        loop
            wait until falling_edge(clk_hc6);

            -- Mirror the DUT's synchronous count update (enable sampled here).
            if hc_rst = '1' then
                if expected = V_MAX then
                    expected   := 0;
                    wraps_seen := wraps_seen + 1;
                else
                    expected := expected + 1;
                end if;
            end if;

            -- T_Structure: Vrst is combinational, high while count = 311 with HCrst high
            if expected = V_MAX and hc_rst = '1' then
                exp_vrst := '1';
            else
                exp_vrst := '0';
            end if;

            -- Compare mid-period, after the count has settled.
            wait until rising_edge(clk_hc6);
            vec    := v8 & v7 & v6 & v5 & v4 & v3 & v2 & v1 & v0;
            actual := to_integer(unsigned(vec));

            assert actual = expected
                report "Vert count mismatch: expected " & integer'image(expected) &
                       ", got " & integer'image(actual)
                severity error;

            assert vrst = exp_vrst
                report "Vrst mismatch at line " & integer'image(expected) &
                       ": expected " & std_logic'image(exp_vrst) &
                       ", got " & std_logic'image(vrst)
                severity error;

            -- Stop a few lines past the first wrap: this exercises
            -- 310, 311 (Vrst high), wrap->0, then 1,2,3 (Vrst low again).
            if wraps_seen >= 1 and expected = 3 then
                report "Vert_Line_counter TB PASS: " &
                       integer'image(wraps_seen) &
                       " frame wrap(s) verified, increment/hold/Vrst all OK"
                    severity note;
                sim_done <= true;
                wait;
            end if;
        end loop;
    end process;

end Behavioral;
