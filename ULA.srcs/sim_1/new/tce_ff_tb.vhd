----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 01.07.2020 14:23:53
-- Design Name:
-- Module Name: tce_ff_tb - Behavioral
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
-- use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
-- library UNISIM;
-- use UNISIM.VComponents.all;

entity tce_ff_tb is
--  Port ( );
end entity tce_ff_tb;

architecture behavioral of tce_ff_tb is

    constant t      : time := 10 ns; -- clk period
    signal   clk    : std_logic;
    signal   enable : std_logic;
    signal   carry  : std_logic;
    signal   q      : std_logic;
    signal   qbar   : std_logic;

begin

    tce : entity work.tce_ff(Behavioral)
        port map (
            clk    => clk,
            enable => enable,
            q      => q,
            qbar   => qbar,
            carry  => carry
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

        enable <= '0';
        wait for 50 ns;
        enable <= '1';
        wait for 100 ns;
        enable <= '0';
        wait for 50 ns;
        enable <= '1';
        wait for 10 ns;
        enable <= '0';
        wait for 50 ns;
        enable <= '1';
        wait;

    end process;

end architecture behavioral;
