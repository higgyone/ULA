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
use IEEE.NUMERIC_STD.ALL;


entity master_horiz_counter_tb is
--  Port ( );
end master_horiz_counter_tb;

architecture Behavioral of master_horiz_counter_tb is
    -- Speed-knob: real ULA pixel clock is 7 MHz (period 143 ns). Set
    -- T to 143 ns for timing-accurate simulation; 10 ns runs ~14x
    -- faster and is fine for functional verification of counter
    -- bits and overflow.
    constant T    : time    := 10 ns; -- clk period (10 ns fast / 143 ns real)
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

    -- Golden full-line count (0..447) for the self-check below.
    signal golden_count : integer range 0 to 447 := 0;

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
       wait for 50 ns;
      reset <= '0';
      wait for T * 100;

      wait;
   end process;

   --*****************************************************************
   -- Self-check: golden 0..447 line counter
   --*****************************************************************
   -- The MHC advances on the RISING edge of clk7 (C0 = clk_div_2 on
   -- clk_c0 = NOT clk7, i.e. it toggles on clk7's rising edge). The
   -- full count is the 9-bit tap concatenation c8..c0 = c_upper*64 +
   -- c_lower, which runs 0..447 (64 x 7). The golden mirrors that:
   -- increment once per rising clk7, clear with reset.
   golden_proc : process(clk_7)
   begin
      if rising_edge(clk_7) then
         if reset = '1' then
            golden_count <= 0;
         elsif golden_count = 447 then
            golden_count <= 0;
         else
            golden_count <= golden_count + 1;
         end if;
      end if;
   end process;

   -- Checker samples on the FALLING edge of clk7 (mid-period), by which
   -- point the ripple chain and the T_Structure C6-C8 stage (with its
   -- after-TG gate delays) have settled. Skips reset and any 'U'/'X' on
   -- the taps. A wrap heartbeat confirms full lines are being verified.
   check_proc : process(clk_7)
      variable taps : std_logic_vector(8 downto 0);
      variable act  : integer range 0 to 511;
   begin
      if falling_edge(clk_7) then
         taps := c8 & c7 & c6 & c5 & c4 & c3 & c2 & c1 & c0;
         if (reset = '0') and (not is_x(taps)) then
            act := to_integer(unsigned(taps));
            assert act = golden_count
               report "MHC count mismatch: taps=" & integer'image(act) &
                      " expected=" & integer'image(golden_count)
               severity error;
            if golden_count = 447 then
               report "MHC: line complete -- 448 counts verified (0..447)."
                  severity note;
            end if;
         end if;
      end if;
   end process;

end Behavioral;
