----------------------------------------------------------------------
-- vert_line_counter_tb — self-checking TB for Vert_Line_counter
--
-- Verifies the vertical counter's full contract against a golden model
-- computed in the TB (no second entity needed):
--   * increments by exactly 1 per ENABLED falling edge of clk_hc6
--   * HOLDS when hcrst = '0' (no count change)
--   * wraps 311 -> 0 (v_max = 311, 312 states = 312 PAL lines)
--   * vrst pulses high for exactly the one line where the count is 311
--
-- Synthetic drive (deliberate): clk_hc6 and hcrst are generated
-- directly here rather than from a real master_horiz_counter instance.
-- Reaching the 311->0 wrap through the real MHC would need ~20 ms of
-- gate-level sim (312 lines x 64 us); the synthetic drive reaches it in
-- ~32 us. The MHC's own clk_hc6/hc_rst generation (and its harmless
-- ripple glitch on hc_rst) is covered separately by
-- master_horiz_counter_tb and the CLAUDE.md glitch analysis.
--
-- Sampling: clk_hc6 is a clean TB-generated clock. The DUT here is the
-- gate-level T_Structure, whose carry chain ripples for ~9·TG (~9 ns)
-- after each falling edge (the `after TG` delays in d_ff_nor). The
-- checker samples on the following RISING edge (mid-period, T/2 = 50 ns
-- later) — well clear of that settle — exactly mirroring the golden
-- model it advanced on the falling edge.
--
-- PASS = simulation runs to the "TB PASS" note with no assertion errors.
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity vert_line_counter_tb is
end entity vert_line_counter_tb;

architecture behavioral of vert_line_counter_tb is

    constant t          : time    := 100 ns; -- clk_hc6 period; T/2 = 50 ns >> gate-ripple settle (~9 ns)
    constant v_max      : integer := 311;    -- last line; counter visits 0..311 = 312 states
    constant n_disabled : integer := 3;      -- leading cycles with enable low (hold test)

    signal clk_hc6  : std_logic := '0';
    signal hc_rst   : std_logic := '0';
    signal v0       : std_logic;
    signal v1       : std_logic;
    signal v2       : std_logic;
    signal v3       : std_logic;
    signal v4       : std_logic;
    signal v5       : std_logic;
    signal v6       : std_logic;
    signal v7       : std_logic;
    signal v8       : std_logic;
    signal vrst     : std_logic;
    signal sim_done : boolean   := false;

begin

    -- Device under test -------------------------------------------------
    vlc : entity work.vert_line_counter(T_Structure)
        port map (
            hcrst   => hc_rst,
            clk_hc6 => clk_hc6,
            v0      => v0,
            v1      => v1,
            v2      => v2,
            v3      => v3,
            v4      => v4,
            v5      => v5,
            v6      => v6,
            v7      => v7,
            v8      => v8,
            vrst    => vrst
        );

    -- clk_hc6 generator -------------------------------------------------
    clkgen : process is
    begin

        while not sim_done loop

            clk_hc6 <= '0';
            wait for t / 2;
            clk_hc6 <= '1';
            wait for t / 2;

        end loop;

        wait;

    end process clkgen;

    -- hcrst stimulus: low for the first N_DISABLED cycles (proves
    -- the counter holds), then high so it advances one line per cycle.
    -- Driven on the rising edge so it is stable at the falling edge the
    -- DUT (and the checker) sample on.
    hcrst_stim : process is

        variable cyc : integer := 0;

    begin

        wait until rising_edge(clk_hc6);
        cyc := cyc + 1;

        if (cyc <= n_disabled) then
            hc_rst <= '0';
        else
            hc_rst <= '1';
        end if;

    end process hcrst_stim;

    -- Golden checker: advance the expected count on the falling edge
    -- exactly as the DUT does, then compare on the following rising edge.
    check : process is

        variable expected   : integer   := 0;
        variable exp_vrst   : std_logic := '0';
        variable actual     : integer;
        variable vec        : std_logic_vector(8 downto 0);
        variable wraps_seen : integer   := 0;

    begin

        loop

            wait until falling_edge(clk_hc6);

            -- Mirror the DUT's synchronous count update (enable sampled here).
            if (hc_rst = '1') then
                if (expected = v_max) then
                    expected   := 0;
                    wraps_seen := wraps_seen + 1;
                else
                    expected := expected + 1;
                end if;
            end if;

            -- T_Structure: vrst is combinational, high while count = 311 with hcrst high
            if (expected = v_max and hc_rst = '1') then
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
                report "vrst mismatch at line " & integer'image(expected) &
                       ": expected " & std_logic'image(exp_vrst) &
                       ", got " & std_logic'image(vrst)
                severity error;

            -- Stop a few lines past the first wrap: this exercises
            -- 310, 311 (vrst high), wrap->0, then 1,2,3 (vrst low again).
            if (wraps_seen >= 1 and expected = 3) then
                report "Vert_Line_counter TB PASS: " &
                       integer'image(wraps_seen) &
                       " frame wrap(s) verified, increment/hold/vrst all OK"
                    severity note;
                sim_done <= true;
                wait;
            end if;

        end loop;

    end process check;

end architecture behavioral;
