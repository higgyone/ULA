----------------------------------------------------------------------------------
-- Module Name: single_bit_shift_reg_tb - Behavioral
-- Description: Self-checking testbench for single_bit_shift_register.
--
--   Exercises both modes of the load/shift cell and asserts q after each
--   falling edge (the cell samples during clk high, updates on the fall):
--     * parallel LOAD  (set='1'): q <= data     = not data_n
--     * serial  SHIFT  (set='0'): q <= data-1   = not data_1_n
--   Both data inputs are active-low, matching the schematic.
--
--   Inputs are changed just after a falling edge so they are stable
--   through the following clk-high sampling window and captured on the
--   next falling edge. A short wait lets the modelled TG gate delays
--   settle before each check. Any mismatch reports a fatal error;
--   reaching the end prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity single_bit_shift_reg_tb is
--  Port ( );
end entity single_bit_shift_reg_tb;

architecture behavioral of single_bit_shift_reg_tb is

    constant t      : time := 10 ns; -- clk period
    constant settle : time := 4 ns;  -- > worst-case gate path after edge

    signal clk      : std_logic := '0';
    signal data_n   : std_logic := '1'; -- data   = 0
    signal data_1_n : std_logic := '1'; -- data-1 = 0
    signal set      : std_logic := '1'; -- start in LOAD mode
    signal q        : std_logic;
    signal q_bar    : std_logic;

    -- Check q (and its complement) after the falling edge just passed.

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

    dut : entity work.single_bit_shift_register(Structure)
        port map (
            clk      => clk,
            data_n   => data_n,
            data_1_n => data_1_n,
            set      => set,
            q        => q,
            q_bar    => q_bar
        );

    -- *****************************************************************
    -- clock: free-running, falling edge is the active (sample) edge
    -- *****************************************************************
    process is
    begin

        clk <= '0';
        wait for t / 2;
        clk <= '1';
        wait for t / 2;

    end process;

    -- *****************************************************************
    -- stimulus + self-check
    -- *****************************************************************
    process is
    begin

        -- Initial LOAD of 0 (set='1', data_n='1' => data=0) is already
        -- driven above; capture it on the first falling edge.
        wait until falling_edge(clk);
        wait for settle;
        check(q, q_bar, '0', "initial load 0");

        -- LOAD a 1  (set='1', data_n='0' => data=1)
        set    <= '1';
        data_n <= '0';
        wait until falling_edge(clk);
        wait for settle;
        check(q, q_bar, '1', "load 1");

        -- SHIFT in a 0 (set='0', data_1_n='1' => data-1=0)
        set      <= '0';
        data_1_n <= '1';
        wait until falling_edge(clk);
        wait for settle;
        check(q, q_bar, '0', "shift in 0");

        -- SHIFT in a 1 (set='0', data_1_n='0' => data-1=1)
        data_1_n <= '0';
        wait until falling_edge(clk);
        wait for settle;
        check(q, q_bar, '1', "shift in 1");

        -- HOLD the 1 by shifting in another 1
        wait until falling_edge(clk);
        wait for settle;
        check(q, q_bar, '1', "shift in 1 again (hold high)");

        -- SHIFT in a 0 again, back to low
        data_1_n <= '1';
        wait until falling_edge(clk);
        wait for settle;
        check(q, q_bar, '0', "shift in 0 (back low)");

        -- LOAD overrides shift: request shift-in 1 but assert set to load 0
        set      <= '1';
        data_n   <= '1';
        data_1_n <= '0';
        wait until falling_edge(clk);
        wait for settle;
        check(q, q_bar, '0', "load 0 overrides shift-in 1");

        report "ALL TESTS PASSED"
            severity note;
        wait;

    end process;

end architecture behavioral;
