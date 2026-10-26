----------------------------------------------------------------------------------
-- tce_ff_tb — self-checking TB for the toggle flip-flop with enable and carry
-- (falling-edge, no reset).
--
-- There is no reset, so the TB first holds enable low for an edge and reads
-- the power-up value (it must be a defined '0' or '1'). Then a list gives
-- enable for each falling edge; the TB predicts q from the characteristic
-- table (toggle when enabled, hold otherwise) and after every edge checks:
--   q      = the predicted value
--   q_n    = not q
--   carry  = enable AND q (combinational)
-- It also checks q does not move while clk is high, when enable changes.
--
-- Stops itself (finish); a clean run prints "ALL TESTS PASSED". Works with
-- either ula_build_pkg (gate model or FPGA flip-flop).
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity tce_ff_tb is
end entity tce_ff_tb;

architecture behavioral of tce_ff_tb is

    constant t      : time := 40 ns; -- clk period: each phase (20 ns) fits two settles
    constant settle : time := 6 ns;  -- > the gate model's after-tg chain

    -- per falling edge: enable
    constant enables : std_logic_vector(0 to 11) := "110100111010";

    signal clk    : std_logic := '0';
    signal enable : std_logic := '0';
    signal q      : std_logic;
    signal q_n    : std_logic;
    signal carry  : std_logic;

begin

    tce : entity work.tce_ff(behavioral)
        port map (
            clk    => clk,
            enable => enable,
            q      => q,
            q_n    => q_n,
            carry  => carry
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
        variable model  : std_logic;

        procedure expect (
            cond : in boolean;
            what : in string
        ) is
        begin

            assert cond
                report "FAIL " & what & ": enable=" & std_logic'image(enable)
                       & " q=" & std_logic'image(q) & " q_n=" & std_logic'image(q_n)
                       & " carry=" & std_logic'image(carry)
                severity failure;

            checks := checks + 1;

        end procedure expect;

    begin

        -- power-up: hold for one edge, then q must be defined
        enable <= '0';
        wait until falling_edge(clk);
        wait for settle;
        expect(q = '0' or q = '1', "power-up value not defined");
        model  := q;

        for i in enables'range loop

            -- clk high: set enable; q must not move
            wait until rising_edge(clk);
            enable <= enables(i);
            wait for settle;
            expect(q = model, "q moved while clk high, step " & integer'image(i));
            expect(carry = (enable and q), "carry before edge, step " & integer'image(i));

            -- the characteristic table
            if (enables(i) = '1') then
                model := not model;
            end if;

            wait until falling_edge(clk);
            wait for settle;
            expect(q = model, "q after edge, step " & integer'image(i));
            expect(q_n = not q, "q_n complement, step " & integer'image(i));
            expect(carry = (enable and q), "carry after edge, step " & integer'image(i));

        end loop;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks: toggle, "
               & "hold, carry = enable and q)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
