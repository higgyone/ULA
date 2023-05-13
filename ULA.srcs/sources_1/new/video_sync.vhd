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
use IEEE.NUMERIC_STD.ALL;

entity video_sync is
    Port (
        clk : in std_logic;
        tclk_a : in std_logic;
        reset : in std_logic;
        hsync_5c : out std_logic;
        hsync_6c : out std_logic;
        nHblank : out std_logic;
        vsync : out std_logic;
        nBorder : out std_logic;
        sync_5c : out std_logic;
        sync_6c : out std_logic
     );
end video_sync;

architecture Behavioral of video_sync is
signal c0 : std_logic;
signal c1 : std_logic;
signal c2 : std_logic;
signal c3 : std_logic;
signal c4 : std_logic;
signal c5 : std_logic;
signal c6 : std_logic;
signal c7 : std_logic;
signal c8 : std_logic;

signal v0     : std_logic;
signal v1     : std_logic;
signal v2     : std_logic;
signal v3     : std_logic;
signal v4     : std_logic;
signal v5     : std_logic;
signal v6     : std_logic;
signal v7     : std_logic;
signal v8     : std_logic;
signal clk_hc6     : std_logic;
signal HC_rst     : std_logic;

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

signal VBorderLower : std_logic;
signal VBorderUpper : std_logic;

signal sHsync_5c : std_logic;
signal sHsync_6c : std_logic;
signal sVsync : std_logic;

begin
mhc: entity work.master_horiz_counter(Behavioral)
    port map(
      clk7 => clk,
      tclk_a => tclk_a,
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
      clk_hc6 => clk_hc6, 
      hc_rst  => HC_rst  
    );
    
vlc: entity work.Vert_Line_counter(Behavioral)
    port map(
      HCrst_Enable => HC_rst,
      Clk_HC6 => clk_hc6,
      v0 => v0,
      v1 => v1,
      v2 => v2,
      v3 => v3,
      v4 => v4,
      v5 => v5,
      v6 => v6,
      v7 => v7,
      v8 => v8
   );

-----------------------------------------------------------
-- Horizontal sync
-----------------------------------------------------------
blank1 <= not((not c8) or c7 or (not c6)); -- 101 000 000
blank2 <= not((not c8) or (not c7) or c5); -- 110 100 00
nHblank <= not(blank1 or blank2); 

nHSyncA_5c <= not(c5 or c4); -- front porch
nHSyncB_5c <= not((not c5) or (not c4));
nHSyncPulses_5c <= nHSyncA_5c or nHSyncB_5c; 

X <= not((not c4) or (not c3)); -- delayed by half a c3 period
nHSyncA_6c <= not(c5 or X);
nHSyncB_6c <= not((not c5) or (not X));
nHSyncPulses_6c <= nHSyncA_6c or nHSyncB_6c;
    
nHSyncSelect <= (not c8) or c7 or (not c6);
sHsync_5c <= nHSyncSelect or nHSyncPulses_5c;
sHsync_6c <= nHSyncSelect or nHSyncPulses_6c;

hsync_5c <= sHsync_5c;
hsync_6c <= sHsync_6c;
-----------------------------------------------------------
-- Vertical sync
-----------------------------------------------------------
--VBorderLower <= not((not v7) or (not v6)); -- v6 and V7
--VBorderUpper <= v8;
--nVBorder <= not(VBorderLower or VBorderUpper); -- Border is not displayed when (v6 and v7) or v8
nBorder <= not((v6 and v7) or v8);

sVsync <= not((not v7) or (not v6) or not (v5) or (not v4) or (not v3) or v2);

sync_5c <= sHsync_5c nor sVsync;
sync_6c <= sHsync_6c nor sVsync;
vsync <= sVsync;

end Behavioral;
