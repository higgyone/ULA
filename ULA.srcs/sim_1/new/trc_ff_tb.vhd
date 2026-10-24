----------------------------------------------------------------------------------
-- trc_ff_tb — self-checking TB for the toggle flip-flop with synchronous
-- reset and carry (falling-edge, no enable: it always toggles).
--
-- A list gives reset for each falling edge. The TB predicts q from the cell's
-- characteristic table (reset clears, otherwise toggle) and after every edge
-- checks:
--   q      = the predicted value
--   q_n    = not q
--   carry  = q (no enable, so the carry-out is q itself)
-- It also checks q does not move while clk is high, when reset changes.
--
-- Stops itself (finish); a clean run prints "ALL TESTS PASSED". Works with
-- either ula_build_pkg (gate model or FPGA flip-flop).
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity trc_ff_tb is
end entity trc_ff_tb;

architecture behavioral of trc_ff_tb is

    constant t      : time := 40 ns; -- clk period: each phase (20 ns) fits two settles
    constant settle : time := 6 ns;  -- > the gate model's after-tg chain

    -- per falling edge: reset
    constant resets : std_logic_vector(0 to 11) := "110000010000";

    signal clk   : std_logic := '0';
    signal reset : std_logic := '1';
    signal q     : std_logic;
    signal q_n   : std_logic;
    signal carry : std_logic;

begin

    trc : entity work.trc_ff(behavioral)
        port map (
            clk   => clk,
            reset => reset,
            q     => q,
            q_n   => q_n,
            carry => carry
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

        variable checks : integer   := 0;
        variable model  : std_logic := 'U';

        procedure expect (
            cond : in boolean;
            what : in string
        ) is
        begin

            assert cond
                report "FAIL " & what & ": reset=" & std_logic'image(reset)
                       & " q=" & std_logic'image(q) & " q_n=" & std_logic'image(q_n)
                       & " carry=" & std_logic'image(carry)
                severity failure;

            checks := checks + 1;

        end procedure expect;

    begin

        for i in resets'range loop

            -- clk high: set reset; q must not move
            wait until rising_edge(clk);
            reset <= resets(i);
            wait for settle;

            if (model /= 'U') then
                expect(q = model, "q moved while clk high, step " & integer'image(i));
            end if;

            -- the characteristic table
            if (resets(i) = '1') then
                model := '0';
            else
                model := not model;
            end if;

            wait until falling_edge(clk);
            wait for settle;

            if (model /= 'U') then
                expect(q = model, "q after edge, step " & integer'image(i));
                expect(q_n = not q, "q_n complement, step " & integer'image(i));
                expect(carry = q, "carry = q, step " & integer'image(i));
            end if;

        end loop;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks: clear, "
               & "toggle, carry = q)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
