----------------------------------------------------------------------------------
-- Module Name: data_latch_1_bit_tb - Behavioral
-- Description: Self-checking testbench for data_latch_1_bit.
--
--   data_latch_1_bit is a transparent D latch with an ACTIVE-LOW enable:
--     * e='0' : transparent -> q follows d
--     * e='1' : hold        -> q frozen, d ignored
--
--   There is no clock (the cell is level-sensitive), so the TB drives e/d
--   directly, waits SETTLE for the modelled TG gate delays to settle, then
--   checks q and its complement q_bar. Coverage:
--     - transparent follow, both 0 and 1
--     - latch a 1, then change d underneath -> must hold 1
--     - re-open transparent -> follows d again
--     - latch a 0, then change d underneath -> must hold 0
--   q_bar is asserted complementary to q at every check (a real consumer,
--   the shift register's data_n input, depends on it). Any mismatch is a
--   fatal error; reaching the end prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity data_latch_1_bit_tb is
--  Port ( );
end entity data_latch_1_bit_tb;

architecture behavioral of data_latch_1_bit_tb is

    constant settle : time := 5 ns; -- > worst-case gate path (~4*TG)

    signal e     : std_logic := '0'; -- active-low enable: start transparent
    signal d     : std_logic := '0';
    signal q     : std_logic;
    signal q_bar : std_logic;

    -- Check q (and its complement) after the last stimulus has settled.

    procedure check (
        signal qv  : in std_logic;
        signal qbv : in std_logic;
        expected   : in std_logic;
        msg        : in string
    ) is
    begin

        assert qv = expected
            report "FAIL: " & msg & " - expected q=" & std_logic'image(expected)
                   & " got q=" & std_logic'image(qv)
            severity failure;
        assert qbv = not qv
            report "FAIL: " & msg & " - q_bar not complementary"
            severity failure;
        report "PASS: " & msg
            severity note;

    end procedure check;

begin

    dut : entity work.data_latch_1_bit(Structural)
        port map (
            e     => e,
            d     => d,
            q     => q,
            q_bar => q_bar
        );

    -- *****************************************************************
    -- stimulus + self-check (level-sensitive, no clock)
    -- *****************************************************************
    process is
    begin

        -- transparent (e='0'), d='0' from init
        wait for settle;
        check(q, q_bar, '0', "transparent: follow 0");

        -- transparent follow to 1
        d <= '1';
        wait for settle;
        check(q, q_bar, '1', "transparent: follow 1");

        -- latch the 1: e='1' freezes it
        e <= '1';
        wait for settle;
        check(q, q_bar, '1', "latch a 1");

        -- while latched, drop d -> q must hold 1
        d <= '0';
        wait for settle;
        check(q, q_bar, '1', "hold 1 while d=0");

        -- re-open transparent -> q now follows d (=0)
        e <= '0';
        wait for settle;
        check(q, q_bar, '0', "re-open transparent: follow 0");

        -- latch the 0: e='1'
        e <= '1';
        wait for settle;
        check(q, q_bar, '0', "latch a 0");

        -- while latched, raise d -> q must hold 0
        d <= '1';
        wait for settle;
        check(q, q_bar, '0', "hold 0 while d=1");

        -- re-open transparent -> follows d (=1)
        e <= '0';
        wait for settle;
        check(q, q_bar, '1', "re-open transparent: follow 1");

        report "ALL TESTS PASSED"
            severity note;
        wait;

    end process;

end architecture behavioral;
