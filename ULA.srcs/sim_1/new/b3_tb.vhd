----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 07.07.2020 13:33:46
-- Design Name:
-- Module Name: b3_tb - Behavioral
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
    use ieee.numeric_std.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
-- library UNISIM;
-- use UNISIM.VComponents.all;

entity b3_tb is
--  Port ( );
end entity b3_tb;

architecture behavioral of b3_tb is

    constant t        : time := 10 ns; -- clk period
    signal   clk      : std_logic;
    signal   reset    : std_logic;
    signal   output   : std_logic_vector(2 downto 0);
    signal   overflow : std_logic;

begin

    b3c : entity work.bit3_counter(Behavioral)
        port map (
            clk      => clk,
            reset    => reset,
            output   => output,
            overflow => overflow
        );

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
        wait for t * 100;

        wait;

    end process;

end architecture behavioral;
