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
   -- Self-check: full count increments by 1 each clk7, wraps at 448
   --*****************************************************************
   -- The full line count is the 9-bit tap concatenation c8..c0
   -- (= c_upper*64 + c_lower), which runs 0..447 (64 x 7). Rather than
   -- predict the absolute start phase (tricky with the gated clocks,
   -- synchronous reset and after-TG gate delays), we LOCK onto the
   -- actual count after reset and then assert it advances by exactly 1
   -- (mod 448) every clk7. This catches any skip, stuck bit, or wrong
   -- wrap without depending on the start phase.
   --
   -- Sampled on the FALLING edge of clk7 (mid-period), by which point
   -- the ripple chain and the T_Structure C6-C8 stage have settled.
   check_proc : process(clk_7)
      variable taps    : std_logic_vector(8 downto 0);
      variable act     : integer range 0 to 511;
      variable expnext : integer range 0 to 447;
      variable locked  : boolean := false;
   begin
      if falling_edge(clk_7) then
         if reset = '1' then
            locked := false;                 -- re-lock after every reset
         else
            taps := c8 & c7 & c6 & c5 & c4 & c3 & c2 & c1 & c0;
            if not is_x(taps) then
               act := to_integer(unsigned(taps));
               if locked then
                  assert act = expnext
                     report "MHC count mismatch: taps=" & integer'image(act) &
                            " expected=" & integer'image(expnext)
                     severity error;
                  if expnext = 447 then
                     report "MHC: line complete -- 448 counts verified (0..447)."
                        severity note;
                  end if;
               end if;
               -- predict next count and lock on
               if act = 447 then expnext := 0; else expnext := act + 1; end if;
               locked := true;
            end if;
         end if;
      end if;
   end process;

end Behavioral;
