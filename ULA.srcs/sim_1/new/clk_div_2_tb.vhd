----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.06.2020 11:11:42
-- Design Name: 
-- Module Name: clk_div_2_tb - Behavioral
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

entity clk_div_2_tb is
--  Port ( );
end clk_div_2_tb;

architecture Behavioral of clk_div_2_tb is
    constant T       : time    := 10 ns; -- clk period
    signal clk_in    : std_logic;
    signal clk_out   : std_logic;
    signal clk_out_n : std_logic;
    signal reset     : std_logic;

begin
    clk_div2: entity work.clk_div_2(Behavioral)
    port map(
            reset => reset,
            clk_in => clk_in,
            clk_out => clk_out,
            clk_out_n => clk_out_n
          );
          
   --*****************************************************************
   -- clock
   --*****************************************************************
   -- 20 ns clock running forever
   process
   begin
      clk_in <= '0';
      wait for T / 2;
      clk_in <= '1';
      wait for T / 2;
   end process;
   
   process   
   begin 
       reset <= '1';
       wait for 50ns;
       
      reset <= '0';
      
      wait for T * 100;
      
      wait;
   end process;
   

end Behavioral;
