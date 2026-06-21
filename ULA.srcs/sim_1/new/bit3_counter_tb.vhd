----------------------------------------------------------------------
-- bit3_counter_tb — testbench for bit3_counter (oracle pattern)
--
-- Drives two instantiations of bit3_counter side-by-side off the same
-- clk + reset:
--
--   uut_struct = entity work.bit3_counter(Structural)
--                  -- three d_ff_nor cells + next-state logic
--   uut_ref    = entity work.bit3_counter(Reference)
--                  -- behavioural unsigned + 1 arithmetic oracle
--
-- On every falling edge of clk (after the d_ff_nor network has
-- resolved out of 'U'), the testbench asserts:
--
--   1. Oracle equivalence : out_s = out_r  AND  ov_s = ov_r
--   2. Invariant on UUT   : ov_s = '1'     iff  out_s = "110"
--   3. Invariant on REF   : ov_r = '1'     iff  out_r = "110"
--
-- A divergence on (1) means the structural next-state logic does not
-- match the +1-with-wrap arithmetic spec.
--
-- Stimulus coverage:
--   * Phase 1 — power-on reset held for 45 ns (4 falling edges),
--     long enough for the d_ff_nor network to resolve to "000"
--     before any assert is checked.
--   * Phase 2 — long free run; counter cycles through all 7 legal
--     states many times. Coverage tracker (states_visited) records
--     each state the UUT lands in.
--   * Phase 3 — assert reset from each non-zero state K = 1..6 in
--     turn, verifying sync-clear semantics from arbitrary state.
--     (Reset from state 0 is implicit in Phase 1.)
--   * Phase 4 — final free run, then end-of-sim coverage report.
--
-- All `wait for X ns;` durations are chosen so reset transitions
-- land at clk-rising edges (t = 5+10n), half a period before the
-- next falling-edge sample. This avoids the simulation-only race
-- where a reset transition coincident with a falling clock edge is
-- seen by the behavioural Reference arch (process(clk) reads the
-- NEW reset value at the trigger delta) but missed by the Structural
-- arch (the d_ff_nor master has already captured the OLD d value
-- by the time `reset → d` propagates through the combinational
-- d-input mux). Real silicon has gate-propagation delays so the new
-- reset always reaches `d` first; zero-delay simulation does not.
--
-- xsim ISSUES — both now worked around (see CLAUDE.md notes):
--
--   1. Dual-instantiation transposition [WORKED AROUND]. With BOTH
--      uut_struct and uut_ref bound to the SAME sysclk/sysrst nets,
--      xsim mis-binds the instance clk/reset ports (each instance sees
--      clk<->reset swapped); a single instance binds correctly. Looks
--      like xsim input-port net collapsing across two instances of the
--      same entity. FIX APPLIED HERE: each instance is driven from its
--      own buffered clk/reset copy (sclk/srst, rclk/rrst) so there is
--      no shared net to collapse. See the buffer assignments below.
--
--   2. Structural (d_ff_nor) zero-delay oscillation [FIXED in source].
--      Run alone, the Structural arch hit the 10000-delta iteration
--      limit at t=0 because the cross-coupled NOR feedback loops in
--      d_ff_nor were zero-delay. d_ff_nor.vhd now carries `after TG`
--      (1 ns) on all six NOR gates so the loop advances and settles.
--      Synthesis ignores `after`; simulation only.
--
--   The Reference arch (pure behavioural) verifies CLEAN on its own:
--   counts 0..6, wraps, overflow only at "110".
--
-- The `wait for X ns` stimulus below is timed so every reset
-- transition lands on a rising clk edge (t = 5+10n), half a period
-- before the next falling-edge sample.
--
-- Not testable through entity ports alone:
--   * The illegal state "111" self-correction property. Forcing the
--     FF state to "111" would require a backdoor write into the
--     individual d_ff_nor instances inside the Structural arch.
--     Left as a future exercise; for now we rely on the +1-rule
--     analysis in the source-file header to argue glitch recovery.
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

    -- Per-instance clk/reset copies (oracle workaround for xsim issue #1).
    -- Each UUT is driven from its OWN net rather than the shared sysclk/
    -- sysrst, so xsim cannot collapse the two instances' input ports onto
    -- a common net and transpose clk<->reset. The copies are plain delta-
    -- delayed buffers of the masters; both instances stay phase-aligned, so
    -- the oracle comparison (out_s = out_r) remains valid.
    signal sclk, srst : std_logic;   -- -> uut_struct
    signal rclk, rrst : std_logic;   -- -> uut_ref

    -- UUT under test (structural d_ff_nor chain)
    signal out_s  : std_logic_vector(2 downto 0);
    signal ov_s   : std_logic;

    -- Reference oracle (behavioural arithmetic)
    signal out_r  : std_logic_vector(2 downto 0);
    signal ov_r   : std_logic;

    -- Coverage: bit k is set once the instance has been observed in state k.
    signal states_visited   : std_logic_vector(6 downto 0) := (others => '0');  -- structural UUT
    signal states_visited_r : std_logic_vector(6 downto 0) := (others => '0');  -- reference oracle

    -- End-of-sim flag — gates the final coverage report.
    signal sim_done : boolean := false;
begin

    -- Per-instance clk/reset buffers (workaround for the xsim dual-
    -- instantiation port transposition — see header / CLAUDE.md issue #1).
    sclk <= sysclk;
    srst <= sysrst;
    rclk <= sysclk;
    rrst <= sysrst;

    uut_struct : entity work.bit3_counter(Structural)
        port map ( clk      => sclk,
                   reset    => srst,
                   output   => out_s,
                   overflow => ov_s );

    uut_ref : entity work.bit3_counter(Reference)
        port map ( clk      => rclk,
                   reset    => rrst,
                   output   => out_r,
                   overflow => ov_r );

    -- Free-running 10 ns clock. Falling edges at t = 10, 20, 30, ...
    process
    begin
        sysclk <= '0';
        wait for T / 2;
        sysclk <= '1';
        wait for T / 2;
    end process;

    -- Reset stimulus — clock-synchronous.
    --
    -- All `reset <= ...` assignments are scheduled at a rising edge of
    -- clk. The new reset value becomes visible one delta later, then
    -- propagates through the structural d-input mux long before the
    -- next falling edge (which is T/2 away). This eliminates the
    -- delta-cycle race between reset-rise and falling-edge sampling.
    process
    begin
        -- Phase 1: hold reset for 45 ns (covers 4 falling edges).
        -- Ends at t=45 ns, which is a rising edge of clk (clk='1' phase).
        sysrst <= '1';
        wait for 45 ns;

        -- Phase 2: 200 ns free run.
        -- Ends at t=245 ns, also a rising edge.
        sysrst <= '0';
        wait for 200 ns;

        -- Phase 3: targeted reset-from-state-K for K = 1..6.
        -- Each iteration uses 30 ns reset hold (3 clock periods) and
        -- k*T release. Total iter time = 30 + k*10 ns. All transitions
        -- land at rising edges of clk.
        for k in 1 to 6 loop
            sysrst <= '1';
            wait for 30 ns;
            sysrst <= '0';
            wait for k * T;
        end loop;

        -- Phase 4: one more reset/clear, then final free run for
        -- coverage padding, then end-of-sim.
        sysrst <= '1';
        wait for 30 ns;
        sysrst <= '0';
        wait for 200 ns;

        sim_done <= true;
        wait;
    end process;

    -- Per-edge self-checks. Skipped while the UUT output is still 'U'
    -- (the d_ff_nor network needs the first falling edge under reset
    -- to escape its 'U' initial state). The Reference arch has an
    -- initialised signal and is "000" from t=0, so once UUT resolves
    -- both should be "000" together and the asserts engage.
    process(sysclk)
    begin
        if falling_edge(sysclk) then
            -- Wait for UUT to escape 'U' before checking anything.
            if out_s /= "UUU" then
                assert (out_s = out_r) and (ov_s = ov_r)
                    report "Oracle mismatch: Structural diverges from Reference."
                    severity error;

                assert (ov_s = '1') = (out_s = "110")
                    report "Structural invariant broken: overflow vs output."
                    severity error;

                assert (ov_r = '1') = (out_r = "110")
                    report "Reference invariant broken: overflow vs output."
                    severity error;
            end if;
        end if;
    end process;

    -- *** TEMPORARY monitor — prints settled counts mid-period (rising
    -- edge), where both DUTs are fully settled. Read these MON lines from
    -- the auto-run launch transcript (no restart / get_value needed). ***
    mon : process(sysclk)
    begin
        if rising_edge(sysclk) then
            if is_x(out_s) or is_x(out_r) then
                report "MON " & time'image(now) & "  s/r = X/U" severity note;
            else
                report "MON " & time'image(now) &
                       "  s=" & integer'image(to_integer(unsigned(out_s))) &
                       "  r=" & integer'image(to_integer(unsigned(out_r))) severity note;
            end if;
        end if;
    end process;

    -- Coverage tracker: latch every legal state the UUT visits.
process(sysclk)
begin
    if falling_edge(sysclk) then
        -- structural UUT
        if    out_s = "000" then states_visited(0) <= '1';
        elsif out_s = "001" then states_visited(1) <= '1';
        elsif out_s = "010" then states_visited(2) <= '1';
        elsif out_s = "011" then states_visited(3) <= '1';
        elsif out_s = "100" then states_visited(4) <= '1';
        elsif out_s = "101" then states_visited(5) <= '1';
        elsif out_s = "110" then states_visited(6) <= '1';
        end if;

        -- reference oracle (independent witness)
        if    out_r = "000" then states_visited_r(0) <= '1';
        elsif out_r = "001" then states_visited_r(1) <= '1';
        elsif out_r = "010" then states_visited_r(2) <= '1';
        elsif out_r = "011" then states_visited_r(3) <= '1';
        elsif out_r = "100" then states_visited_r(4) <= '1';
        elsif out_r = "101" then states_visited_r(5) <= '1';
        elsif out_r = "110" then states_visited_r(6) <= '1';
        end if;
    end if;
end process;

    -- End-of-sim coverage report. Warns (not errors) if any legal
    -- state was missed by the stimulus.
process(sim_done)
begin
    if sim_done then
        for k in 0 to 6 loop
            assert states_visited(k) = '1'
                report "Coverage gap [STRUCTURAL]: state " & integer'image(k) &
                       " was never visited."
                severity warning;

            assert states_visited_r(k) = '1'
                report "Coverage gap [REFERENCE]: state " & integer'image(k) &
                       " was never visited."
                severity warning;
        end loop;
        report "bit3_counter_tb: simulation complete." severity note;
    end if;
end process;

end Behavioral;
