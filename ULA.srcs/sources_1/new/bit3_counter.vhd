----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 06.07.2020 15:33:43
-- Design Name: 
-- Module Name: 3_bit counter - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- This is a 3 bit counter that counts to '110'
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;  

entity bit3_counter is
    Port ( reset : in STD_LOGIC;
           clk : in STD_LOGIC;
           output : out std_logic_vector (2 downto 0);
           overflow : out std_logic);
end bit3_counter;

architecture Behavioral of bit3_counter is
signal outputint:  unsigned( 2 downto 0 ) := "000";
begin 
              
  process (clk, reset)
  begin
    if falling_edge(clk) then  
      if reset = '1' then                  
        outputint <= "000" ;                
      else
        outputint <= outputint + 1;
        if outputint = "110" then
            outputint <= "000";
         end if;       
      end if;
    end if;
  end process;
  
   output <= std_logic_vector(outputint);
   overflow <= '1' when outputint = "110" else '0';
end Behavioral;
