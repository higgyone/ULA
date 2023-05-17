----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09.07.2020 14:45:07
-- Design Name: 
-- Module Name: horiz_timing - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- hsync is 4.6us or 32 pixels
-- front porch video blank before hsync is asserted is 2.29us or 16 pixels
-- total blanking period is 13.7us or 96 pixels
-- periods are derived from 16 clock cycles or 2.29us (143ns * 16)
--
-- pixel output 0-255 pixels 000 000 000
-- right border 256-319 pixels 100 000 000
-- video blanking period 320-415 pixels 101 000 000
-- hsync pulse 344-375 pixels 101 011 000 (for 6c)
-- left border 416-447 pixels 110 100 000
-- sync counter reset 447-448 pixels 110 111 111 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity horiz_timing is
    Port (
        clk : in std_logic;
        reset : in std_logic;
        hsync_5c : out std_logic;
        hsync_6c : out std_logic;
        nHblank : out std_logic
     );
end horiz_timing;

architecture Behavioral of horiz_timing is
signal c0 : std_logic;
signal c1 : std_logic;
signal c2 : std_logic;
signal c3 : std_logic;
signal c4 : std_logic;
signal c5 : std_logic;
signal c6 : std_logic;
signal c7 : std_logic;
signal c8 : std_logic;

signal blank1 : std_logic;
signal blank2 : std_logic;
signal nHSyncA_5c : std_logic;
signal nHSyncB_5c : std_logic;
signal nHSyncA_6c : std_logic;
signal nHSyncB_6c : std_logic;
signal nHSyncPulses_5c : std_logic;
signal nHSyncPulses_6c : std_logic;
signal X : std_logic;
signal nHSyncSelect : std_logic;

begin
mhc: entity work.master_horiz_counter(Behavioral)
    port map(
      clk7 => clk,
      tclk_a => '0',
      reset => reset,
      c0 => c0,       
      c1 => c1,       
      c2 => c2,      
      c3 => c3,       
      c4 => c4,
      c5 => c5,       
      c6 => c6,       
      c7 => c7,       
      c8 => c8,       
      clk_hc6 => open, 
      hc_rst  => open  
    );

blank1 <= not((not c8) or c7 or (not c6)); -- 101 000 000 video blanking period start
blank2 <= not((not c8) or (not c7) or c5); -- 110 100 000 video blanking period ends
nHblank <= not(blank1 or blank2); 

nHSyncA_5c <= not(c5 or c4); -- front porch
nHSyncB_5c <= not((not c5) or (not c4));
nHSyncPulses_5c <=  nHSyncA_5c or nHSyncB_5c; 

X <= not((not c4) or (not c3)); -- delayed by half a c3 period
nHSyncA_6c <= not(c5 or X);
nHSyncB_6c <= not((not c5) or (not X));
nHSyncPulses_6c <= nHSyncA_6c or nHSyncB_6c;
    
nHSyncSelect <= (not c8) or c7 or (not c6);
hsync_5c <= nHSyncSelect or nHSyncPulses_5c;
hsync_6c <= nHSyncSelect or nHSyncPulses_6c;

end Behavioral;
