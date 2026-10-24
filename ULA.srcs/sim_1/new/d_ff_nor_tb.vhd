----------------------------------------------------------------------------------
-- d_ff_nor_tb — self-checking TB for the negative-edge D flip-flop.
--
-- What it proves, over a pattern of 0s and 1s:
--   1. CAPTURE: q takes the value d had at the FALLING edge of clk.
--   2. NO CHANGE WHILE CLK IS HIGH: changing d in the high phase does not
--      reach q (the master follows d, the slave holds).
--   3. NO CHANGE WHILE CLK IS LOW: after the edge, d can change and q holds
--      until the next falling edge.
--   4. q_n is always the complement of q.
--
-- Stops itself (finish); a clean run prints "ALL TESTS PASSED". Works with
-- either ula_build_pkg (gate model or FPGA flip-flop).
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity d_ff_nor_tb is
end entity d_ff_nor_tb;

architecture behavioral of d_ff_nor_tb is

    constant t      : time := 40 ns; -- clk period: each phase (20 ns) fits two settles
    constant settle : time := 6 ns;  -- > the gate model's after-tg chain

    -- the d values captured at successive falling edges
    constant pattern : std_logic_vector(0 to 11) := "011010011100";

    signal clk : std_logic := '0';
    signal d   : std_logic := '0';
    signal q   : std_logic;
    signal q_n : std_logic;

begin

    d_ffnor : entity work.d_ff_nor(behavioral)
        port map (
            clk => clk,
            d   => d,
            q   => q,
            q_n => q_n
        );

    -- free-running clock; the stimulus process ends the run with finish
    clk_gen : process is
    begin

        clk <= '0';
        wait for t / 2;
        clk <= '1';
        wait for t / 2;

    end process clk_gen;

    stim : process is

        variable checks : integer := 0;
        variable val    : std_logic;
        variable prev   : std_logic;

        procedure expect (
            cond : in boolean;
            what : in string
        ) is
        begin

            assert cond
                report "FAIL " & what & ": d=" & std_logic'image(d) & " q="
                       & std_logic'image(q) & " q_n=" & std_logic'image(q_n)
                severity failure;

            checks := checks + 1;

        end procedure expect;

    begin

        for i in pattern'range loop

            val := pattern(i);

            -- clk high: set d; q must not move (except before the first edge,
            -- when q has no defined value yet)
            wait until rising_edge(clk);
            d <= val;
            wait for settle;

            if (i > 0) then
                expect(q = prev, "q changed while clk high, step " & integer'image(i));
            end if;

            -- falling edge: q captures d
            wait until falling_edge(clk);
            wait for settle;
            expect(q = val, "capture at falling edge, step " & integer'image(i));
            expect(q_n = not q, "q_n complement, step " & integer'image(i));

            -- clk low: d changes, q must hold
            d <= not val;
            wait for settle;
            expect(q = val, "q changed while clk low, step " & integer'image(i));

            prev := val;

        end loop;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks: capture on "
               & "the falling edge only, q_n = not q)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
