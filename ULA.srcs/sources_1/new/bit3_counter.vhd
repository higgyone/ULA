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
-- Implementation is still behavioural (arithmetic on an unsigned
-- signal), NOT a structural chain of d_ff_nor cells. A future refactor
-- could decompose this into three d_ff_nor instances plus the
-- appropriate NOR-gated combinational logic for full gate-accurate
-- parity with the original ULA schematic.
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

architecture Behavioral of bit3_counter is
    signal outputint : unsigned(2 downto 0) := "000";
begin
    process (clk, reset)
    begin
        if falling_edge(clk) then
            if reset = '1' then
                outputint <= "000";
            else
                outputint <= outputint + 1;
                if outputint = "110" then
                    outputint <= "000";
                end if;
            end if;
        end if;
    end process;

    output   <= std_logic_vector(outputint);
    overflow <= '1' when outputint = "110" else '0';
end Behavioral;
