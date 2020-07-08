----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.06.2020 14:01:39
-- Design Name: 
-- Module Name: master_horiz_counter_tb - Behavioral
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


entity master_horiz_counter_tb is
--  Port ( );
end master_horiz_counter_tb;

architecture Behavioral of master_horiz_counter_tb is
    constant T    : time    := 10 ns; -- clk period
    signal clk_7   : std_logic;
    signal tclk_a : std_logic   := '0';
    signal reset  : std_logic;
    signal c0     : std_logic;
    signal c1     : std_logic;
    signal c2     : std_logic;
    signal c3     : std_logic;
    signal c4     : std_logic;
    signal c5     : std_logic;
    signal c6     : std_logic;
    signal c7     : std_logic;
    signal c8     : std_logic;
    signal clk_hc6     : std_logic;
    signal HC_rst     : std_logic;
    
begin
mhc: entity work.master_horiz_counter(Behavioral)
    port map(
      clk7 => clk_7,        
      reset => reset,
      tclk_a => tclk_a,
      c0 => c0,
      c1 => c1,   
      c2 => c2,   
      c3 => c3,   
      c4 => c4,   
      c5 => c5,   
      c6 => c6,   
      c7 => c7,   
      c8 => c8,   
      clk_hc6 => clk_hc6,   
      hc_rst => HC_rst
   );
   



   --*****************************************************************
   -- clock
   --*****************************************************************
   -- 20 ns clock running forever
   process
   begin
      clk_7 <= '0';
      wait for T / 2;
      clk_7 <= '1';
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
