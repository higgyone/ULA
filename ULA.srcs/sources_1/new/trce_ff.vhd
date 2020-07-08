----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.06.2020 15:02:08
-- Design Name: 
-- Module Name: trce_ff - Behavioral
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


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity trce_ff is
    Port ( enable : in STD_LOGIC := '1';
           clk : in STD_LOGIC;
           reset : in STD_LOGIC;
           carry : out STD_LOGIC;
           q : out STD_LOGIC;
           qbar : out STD_LOGIC);
end trce_ff;

architecture Behavioral of trce_ff is

signal toggle : std_logic :='0';

begin

    process(clk, reset, enable, toggle)
    begin
        if (reset = '1') then
            toggle <= '0';
        elsif ((falling_edge(clk)) and (enable = '1')) then
            toggle <= not toggle;      
        end if;
    end process;
        
    q <= toggle;
    carry <= not toggle;
    qbar <= not toggle;
end Behavioral;
