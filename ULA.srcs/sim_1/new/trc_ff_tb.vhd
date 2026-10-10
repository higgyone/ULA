----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 29.06.2020 15:48:36
-- Design Name:
-- Module Name: trce_ff_tb - Behavioral
-- Project Name:
-- Target Devices:
-- Tool Versions:
-- Description:
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity trc_ff_tb is
--  Port ( );
end entity trc_ff_tb;

architecture behavioral of trc_ff_tb is

    constant t     : time := 10 ns; -- clk period
    signal   clk   : std_logic;
    signal   reset : std_logic;
    signal   carry : std_logic;
    signal   q     : std_logic;
    signal   qbar  : std_logic;

begin

    trc : entity work.trc_ff(Behavioral)
        port map (
            clk   => clk,
            reset => reset,
            q     => q,
            qbar  => qbar,
            carry => carry
        );

    -- *****************************************************************
    -- clock
    -- *****************************************************************
    -- 20 ns clock running forever
    process is
    begin

        clk <= '0';
        wait for t / 2;
        clk <= '1';
        wait for t / 2;

    end process;

    process is
    begin

        reset <= '1';
        wait for 50 ns;
        reset <= '0';
        wait for 50 ns;
        reset <= '1';
        wait for 50 ns;
        reset <= '0';
        wait for 40 ns;
        reset <= '1';
        wait for 50 ns;
        reset <= '0';
        wait for t * 100;

        wait;

    end process;

end architecture behavioral;
