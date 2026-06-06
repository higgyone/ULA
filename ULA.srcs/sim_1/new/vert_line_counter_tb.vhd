----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 08.07.2020 15:21:13
-- Design Name: 
-- Module Name: vert_line_counter_tb - Behavioral
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

entity vert_line_counter_tb is
--  Port ( );
end vert_line_counter_tb;

architecture Behavioral of vert_line_counter_tb is
    constant T    : time    := 143 ns; -- clk period
    signal clk    : std_logic;
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
    signal Vrst : std_logic;
    signal reset : std_logic;
    
begin

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
      v8 => v8,
      Vrst => Vrst
   );

mhc: entity work.master_horiz_counter(Behavioral)
    port map(
      clk7 => clk,
      tclk_a => '0',
      reset => reset,
      c0 => open,       
      c1 => open,       
      c2 => open,      
      c3 => open,       
      c4 => open,
      c5 => open,       
      c6 => open,       
      c7 => open,       
      c8 => open,       
      clk_hc6 => clk_hc6, 
      hc_rst  => HC_rst  
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
      wait for T * 100;
      
      wait;
   end process;

end Behavioral;
