----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 06.07.2020 15:41:19
-- Design Name: 
-- Module Name: bit3_counter_tb - Behavioral
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
use ieee.numeric_std.all;  

entity bit3_counter_tb is
--  Port ( );
end bit3_counter_tb;

architecture Behavioral of bit3_counter_tb is
    constant T    : time    := 10 ns; -- clk period
    signal clk   : std_logic;
    signal reset  : std_logic;
    signal output : std_logic_vector (2 downto 0);
begin

b3c: entity work.bit3_counter(Behavioral)
port map(
      clk => clk,        
      reset => reset,
      output => output
   );
   
    process
   begin
      clk <= '0';
      wait for T / 2;
      clk <= '1';
      wait for T / 2;
   end process;
   
   process   
   begin 
       reset <= '1';
       wait for 50ns;
      reset <= '0';
      wait for 50ns;
      reset <= '1';
       wait for 50ns;
      reset <= '0';
      wait for T * 100;
      
      wait;
   end process;

end Behavioral;
