----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 01.07.2020 14:20:56
-- Design Name: 
-- Module Name: tce_ff - Behavioral
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

entity tce_ff is
    Port ( clk : in STD_LOGIC;
           enable : in STD_LOGIC;
           q : out STD_LOGIC;
           qbar : out STD_LOGIC;
           carry : out STD_LOGIC);
end tce_ff;

architecture Behavioral of tce_ff is

signal toggle : std_logic :='0';

begin
    process(clk, enable, toggle)
    begin
        if (enable = '1') and (falling_edge(clk)) then
            toggle <= not toggle;         
        end if;        
    end process;
    
    q <= toggle;
    carry <= not toggle;
    qbar <= not toggle;

end Behavioral;
