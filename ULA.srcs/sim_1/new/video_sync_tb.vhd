----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09.07.2020 15:00:16
-- Design Name: 
-- Module Name: horiz_timing_tb - Behavioral
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

entity video_sync_tb is
--  Port ( );
end video_sync_tb;

architecture Behavioral of video_sync_tb is
    constant T    : time    := 143 ns; -- clk period
    signal clk_7   : std_logic;
    signal tclk_a : std_logic   := '0';
    signal reset  : std_logic;
  
    signal hsync_5c : std_logic;
    signal hsync_6c : std_logic;
    signal nHblank  : std_logic;
    
    signal vsync  : std_logic;
    signal nBorder  : std_logic;
    signal sync_5c  : std_logic;
    signal sync_6c  : std_logic;
    
begin
   
ht: entity work.video_sync(Behavioral)
    port map(
        clk => clk_7,
        tclk_a => '0',
        reset => reset,
        hsync_5c => hsync_5c,
        hsync_6c => hsync_6c,
        nHblank => nHblank,
        vsync => vsync,
        nBorder => nBorder,
        sync_5c => sync_5c,
        sync_6c => sync_6c
    );

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
