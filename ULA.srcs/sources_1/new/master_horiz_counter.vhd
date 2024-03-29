----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.06.2020 12:50:53
-- Design Name: 
-- Module Name: master_horiz_counter - Behavioral
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


entity master_horiz_counter is
port(
      clk7         : in     std_logic;
      tclk_a       : in     std_logic := '0';
      reset        : in     std_logic;
      c0           : out    std_logic;
      c1           : out    std_logic;
      c2           : out    std_logic;
      c3           : out    std_logic;
      c4           : out    std_logic;
      c5           : out    std_logic;
      c6           : out    std_logic;
      c7           : out    std_logic;
      c8           : out    std_logic;
      clk_hc6      : out  std_logic;
      hc_rst       : out  std_logic
   );
end master_horiz_counter;

architecture Behavioral of master_horiz_counter is

    signal c0_n : std_logic;
    signal c1_n : std_logic;
    signal c2_n : std_logic;
    signal c3_n : std_logic;
    signal c4_n : std_logic;
    signal c5_n : std_logic;
    signal c6_n : std_logic;
    signal c7_n : std_logic;
    signal c8_n : std_logic;
    
    signal clk_c0 : std_logic;
    signal clk_c1 : std_logic;
    signal clk_c2 : std_logic;
    signal clk_c3 : std_logic;
    signal clk_c4 : std_logic;
    signal clk_c5 : std_logic;
    
    signal clk8_6 : std_logic_vector (2 downto 0);
    signal s_clkhc6 : std_logic;


begin
    clk_c0 <= not clk7;
    clk_c1 <= c0_n nor clk7;
    clk_c2 <= not(c0_n or c1_n or clk7);
    clk_c3 <= not(c2_n or c1_n or c0_n or clk7);
    clk_c4 <= not c3_n;
    clk_c5 <= c4_n nor c3_n;
    
    s_clkhc6 <= not(tclk_a or c5_n);
    clk_hc6 <= s_clkhc6;
    
    c6 <= clk8_6(0);
    c7 <= clk8_6(1);
    c8 <= clk8_6(2);


--******************************************************************
--  Counter initialisation  
--******************************************************************
count_0: entity work.clk_div_2
  port map(
     reset => reset,
     clk_in  => clk_c0,
     clk_out => c0,
     clk_out_n => c0_n
     );
     
count_1: entity work.clk_div_2
  port map(
     reset => reset,
     clk_in => clk_c1,
     clk_out => c1,
     clk_out_n => c1_n
     );

count_2: entity work.clk_div_2
  port map(
     reset => reset,
     clk_in => clk_c2,
     clk_out => c2,
     clk_out_n => c2_n
     );

count_3: entity work.clk_div_2
  port map(
     reset => reset,
     clk_in => clk_c3,
     clk_out => c3,
     clk_out_n => c3_n
     );
     
count_4: entity work.clk_div_2
  port map(
     reset => reset,
     clk_in => clk_c4,
     clk_out => c4,
     clk_out_n => c4_n
     );

count_5: entity work.clk_div_2
  port map(
     reset => reset,
     clk_in => clk_c5,
     clk_out => c5,
     clk_out_n => c5_n
     );     
     
b3c: entity work.bit3_counter(Behavioral)
port map(
      clk => s_clkhc6,        
      reset => '0',
      output => clk8_6,
      overflow => hc_rst
   );     
     
--count_6: entity work.trc_ff
--    port map(
--    clk => clk_c6_8,
--    reset => hc_rst,
--    carry => carry6,
--    q => c6,
--    qbar => open
--    );   
    
--count_7: entity work.trce_ff
--    port map(
--    enable => enable7,
--    clk => clk_c6_8,
--    reset => hc_rst,
--    carry => carry7,
--    q => c7,
--    qbar => c7_n
--    );   
    
--count_8: entity work.trce_ff
--    port map(
--    enable => enable8,
--    clk => clk_c6_8,
--    reset => hc_rst,
--    carry => open,
--    q => c8,
--    qbar => c8_n
--    );   

end Behavioral;
