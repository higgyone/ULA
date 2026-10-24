----------------------------------------------------------------------------------
-- clk_div_2_tb — self-checking TB for the divide-by-2 cell (a T flip-flop:
-- d_ff_nor with d = q_n, negative-edge, synchronous reset).
--
-- What it proves:
--   1. RESET: while reset = '1', clk_out is '0' after every falling edge.
--   2. DIVIDE BY 2: once reset is released, clk_out toggles on EVERY falling
--      edge of clk_in and never on a rising edge, so it runs at half the
--      input frequency. clk_out_n is always the complement of clk_out.
--   3. RESET AGAIN: asserting reset mid-run clears clk_out at the next
--      falling edge and holds it there.
--
-- Stops itself (finish); a clean run prints "ALL TESTS PASSED". Works with
-- either ula_build_pkg (gate model or FPGA flip-flop).
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity clk_div_2_tb is
end entity clk_div_2_tb;

architecture behavioral of clk_div_2_tb is

    constant t      : time := 20 ns; -- clk_in period
    constant settle : time := 6 ns;  -- > the gate model's after-tg chain

    signal clk_in    : std_logic := '0';
    signal clk_out   : std_logic;
    signal clk_out_n : std_logic;
    signal reset     : std_logic := '1';

begin

    clk_div2 : entity work.clk_div_2(behavioral)
        port map (
            clk_in    => clk_in,
            reset     => reset,
            clk_out   => clk_out,
            clk_out_n => clk_out_n
        );

    -- free-running clock; the stimulus process ends the run with finish
    clk_gen : process is
    begin

        clk_in <= '0';
        wait for t / 2;
        clk_in <= '1';
        wait for t / 2;

    end process clk_gen;

    stim : process is

        variable checks : integer := 0;
        variable prev   : std_logic;

        procedure expect (
            cond : in boolean;
            what : in string
        ) is
        begin

            assert cond
                report "FAIL " & what & ": clk_out=" & std_logic'image(clk_out)
                       & " clk_out_n=" & std_logic'image(clk_out_n)
                severity failure;

            checks := checks + 1;

        end procedure expect;

    begin

        --------------------------------------------------------------
        -- 1) RESET holds clk_out at '0'
        --------------------------------------------------------------
        reset <= '1';

        for i in 1 to 4 loop

            wait until falling_edge(clk_in);
            wait for settle;
            expect(clk_out = '0' and clk_out_n = '1', "reset, edge " & integer'image(i));

        end loop;

        report "PASS: clk_out held at 0 during reset"
            severity note;

        --------------------------------------------------------------
        -- 2) DIVIDE BY 2: toggle on every falling edge, never on a rising
        --------------------------------------------------------------
        reset <= '0';
        prev  := clk_out;

        for i in 1 to 32 loop

            wait until rising_edge(clk_in);
            wait for settle;
            expect(clk_out = prev, "no change on rising edge " & integer'image(i));

            wait until falling_edge(clk_in);
            wait for settle;
            expect(clk_out = not prev, "toggle on falling edge " & integer'image(i));
            expect(clk_out_n = not clk_out, "clk_out_n complement, edge "
                   & integer'image(i));
            prev := clk_out;

        end loop;

        report "PASS: clk_out toggles on every falling edge (divide by 2), "
               & "clk_out_n is its complement"
            severity note;

        --------------------------------------------------------------
        -- 3) RESET AGAIN mid-run
        --------------------------------------------------------------
        wait until rising_edge(clk_in);
        reset <= '1';

        for i in 1 to 3 loop

            wait until falling_edge(clk_in);
            wait for settle;
            expect(clk_out = '0' and clk_out_n = '1', "reset again, edge "
                   & integer'image(i));

        end loop;

        report "PASS: reset mid-run clears clk_out at the next falling edge"
            severity note;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
