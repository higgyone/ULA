----------------------------------------------------------------------
-- bit3_counter_tb — testbench for bit3_counter
--
-- Drives the UUT with a free-running 10 ns clock and a reset pattern,
-- then continuously checks the modulo-7 invariant via assert.
--
-- Self-checking invariant (process at the bottom of this file):
--
--   overflow = '1'  iff  output = "110"
--
-- The assert fires on every falling edge of clk; any divergence
-- between `overflow` and the wrap-state detector in bit3_counter is
-- reported as a simulation error.
--
-- TODO: cross-check the Structural architecture of bit3_counter
-- against the Behavioral reference (preserved commented-out in
-- bit3_counter.vhd):
--
--   1. Run with `(Structural)` active (the current configuration) and
--      capture the `output` and `overflow` waveforms.
--   2. Swap to the Behavioral reference architecture (uncomment it in
--      bit3_counter.vhd; comment out Structural) and re-run.
--   3. The two waveforms must overlay exactly across every state and
--      every reset event. Any divergence is a bug in the structural
--      next-state logic or wrap detection.
--
-- Coverage still to add:
--   * All 7 legal states (000..110) visited at least once — the
--     existing 100×T run after the second deassert should achieve this
--     but should be confirmed by inspection.
--   * Reset asserted from each legal state — verify count clears on
--     the next falling edge, not before (sync reset semantics).
--   * Force the FF state to "111" (illegal) and verify the counter
--     self-corrects to "000" on the next clock — the glitch-recovery
--     property documented in the source.
----------------------------------------------------------------------


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
    signal overflow : std_logic;
begin

b3c: entity work.bit3_counter(Structural)
port map(
      clk => clk,        
      reset => reset,
      output => output,
      overflow => overflow,
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
         wait for 50 ns;
         reset <= '0';
         wait for 50 ns;
         reset <= '1';
         wait for 50 ns;
         reset <= '0';
         wait for T * 100;
         
         wait;
   end process;

   process(clk)
      begin
         if falling_edge(clk) then
            assert (overflow = '1') = (output = "110")
                  report "overflow does not match (output = ""110"")"
                  severity error;
         end if;
end process;

end Behavioral;
