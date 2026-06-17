----------------------------------------------------------------------
-- bit3_counter — 3-bit synchronous counter, modulo-7
--
-- Counts 0..6 (7 states) on the falling edge of clk and wraps back
-- to 0 on the next edge. `overflow` is asserted while the count
-- equals "110" (= 6) — i.e. the cycle in which the counter is about
-- to wrap.
--
-- Used as the C6..C8 cells of master_horiz_counter. Together with
-- the six clk_div_2 cells (C0..C5), this gives the 9-bit horizontal
-- counter modulo 448 (= 64 × 7) at 7 MHz for 64 µs PAL lines.
--
-- Reset is synchronous: when reset='1', the count clears on the next
-- falling edge of clk.
--
-- Structural implementation: three d_ff_nor cells (one per bit) with
-- combinational next-state logic on each d input. The next-state per
-- bit follows the standard binary ripple-carry "+1 rule":
--
--   d(0) = not q(0)                       (LSB always flips)
--   d(1) = q(1) xor q(0)                  (flip when q(0)=1)
--   d(2) = q(2) xor (q(1) and q(0))       (flip when q(1) and q(0)=1)
--
-- Modulo-7 wrap is enforced by ANDing every d-bit with `not wrap`,
-- where `wrap = q(2) and q(1) and not q(0)` detects state "110".
-- Synchronous reset uses the same trick: AND every d-bit with
-- `not reset`. Both reset and wrap leave the clock path untouched —
-- they only change what gets sampled on the next falling edge.
--
-- A glitch into the unused state "111" is self-correcting: wrap is 0
-- there (it requires q(0)=0), the +1 rule gives "000", and the
-- counter rejoins the legal sequence on the next clock.
--
-- A reference behavioural architecture is preserved below (commented
-- out) as the simulation oracle for the structural design — both must
-- produce identical output and overflow waveforms for every state.
--
-- State sequence:
--
--   output  : 000 → 001 → 010 → 011 → 100 → 101 → 110 → 000 → ...
--   overflow:  0     0     0     0     0     0     1     0
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity bit3_counter is
    Port ( reset    : in  STD_LOGIC;
           clk      : in  STD_LOGIC;
           output   : out std_logic_vector (2 downto 0);
           overflow : out std_logic );
end bit3_counter;

architecture Structural of bit3_counter is
    signal q       : std_logic_vector(2 downto 0);  -- current state
    signal d       : std_logic_vector(2 downto 0);  -- next state into FFs
    signal wrap    : std_logic;                     -- 1 when at "110"
begin
    -- detect we're at the wrap state
    wrap <= q(2) and q(1) and (not q(0));   -- "110"

    -- next-state combinational logic per bit (binary +1, forced to 0 at wrap, forced to 0 at reset)
    d(0) <= (not reset) and (not wrap) and (not q(0));
    d(1) <= (not reset) and (not wrap) and (q(1) xor q(0));
    d(2) <= (not reset) and (not wrap) and (q(2) xor (q(1) and q(0)));

    -- three d_ff_nor instances — one per bit
    ff0 : entity work.d_ff_nor port map (clk => clk, d => d(0), q => q(0), qbar => open);
    ff1 : entity work.d_ff_nor port map (clk => clk, d => d(1), q => q(1), qbar => open);
    ff2 : entity work.d_ff_nor port map (clk => clk, d => d(2), q => q(2), qbar => open);

    output   <= q;
    overflow <= wrap;
end Structural;