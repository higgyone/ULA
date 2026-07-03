----------------------------------------------------------------------------------
-- Module Name: shift8 - Structural
--
-- 8-bit parallel-load, serial-out, shift-LEFT register — the ULA pixel
-- shift register.
--
-- In plain words:
--   It is a row of eight one-bit boxes (single_bit_shift_register cells)
--   standing side by side. It can do one of two things on every clock tick,
--   chosen by SLoad:
--
--     SLoad = '1'  LOAD  : all eight boxes grab a fresh byte at once, straight
--                          from the data_n bus (one bit per box).
--     SLoad = '0'  SHIFT : every box passes its bit one place to the LEFT
--                          (toward the most-significant end) and takes a new
--                          bit from the box on its right. The top (MSB) bit
--                          falls out of q; a new bit enters the bottom from Sin.
--
--   Typical use: load a pixel byte with SLoad='1', then hold SLoad='0' and
--   clock eight times — the eight pixels come out of q one per tick, the
--   most-significant (leftmost) pixel first. That MSB-first order is exactly
--   how the ULA paints pixels across the screen, left to right.
--
-- How the cells are chained (the active-low trick):
--   Each cell's shift-in port (data_1_n) is ACTIVE-LOW, and each cell already
--   provides an inverted output (q_bar). So feeding a cell's q_bar into the
--   next cell's data_1_n makes the two inversions cancel — the next cell
--   shifts in the TRUE bit of its right-hand neighbour, with no extra gates:
--
--     cell1.data_1_n <= cell0.q_bar   -- and so on up to cell7.
--
--   Cell 0 (the LSB) has no right-hand neighbour, so its data_1_n comes from
--   the external serial input Sin. Cell 7 (the MSB) is the serial output.
--
-- Clock:
--   All eight cells share clk. Each cell samples while clk is high and commits
--   on the falling edge (clk 1->0), so the whole row shifts together on one
--   edge — no bit races down the chain.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity shift8 is
    Port ( clk      : in  STD_LOGIC;                     -- pixel clock; cells commit on the falling edge
           SLoad    : in  STD_LOGIC;                     -- '1' = LOAD the data_n byte, '0' = SHIFT left one place
           Sin      : in  STD_LOGIC;                     -- serial bit shifted into the LSB end (ACTIVE-LOW; don't-care in normal pixel use)
           data_n   : in  STD_LOGIC_VECTOR (7 downto 0); -- byte to load, ACTIVE-LOW (each wire is the inverse of its bit)
           q        : out STD_LOGIC;                     -- serial output = MSB cell's q (leftmost pixel first)
           q_bar    : out STD_LOGIC);                    -- inverse of q
end shift8;

architecture Structural of shift8 is
    -- Per-cell output taps. q_n is bit n; q_bar_n is its inverse and is what
    -- feeds the next cell up the chain (see header: the active-low trick).
    signal q_0  : std_logic;
    signal q_bar_0 : std_logic;
    signal q_1  : std_logic;
    signal q_bar_1 : std_logic;
    signal q_2  : std_logic;
    signal q_bar_2 : std_logic;
    signal q_3  : std_logic;
    signal q_bar_3 : std_logic;
    signal q_4  : std_logic;
    signal q_bar_4 : std_logic;
    signal q_5  : std_logic;
    signal q_bar_5 : std_logic;
    signal q_6  : std_logic;
    signal q_bar_6 : std_logic;
    signal q_7  : std_logic;
    signal q_bar_7 : std_logic;

begin
    -- Serial output taps off the top (MSB) cell.
    q       <= q_7;
    q_bar   <= q_bar_7;

    -- Cell 0 (LSB): shift-in comes from the external serial input Sin.
shift_0: entity work.single_bit_shift_register
    port map (
               clk        => clk,
               data_n     => data_n(0),
               data_1_n   => Sin,
               set        => SLoad,
               q          => q_0,
               q_bar      => q_bar_0
               );

    -- Cells 1..7: shift-in comes from the neighbour below via its q_bar,
    -- so the true bit climbs one place toward the MSB on each shift.
shift_1: entity work.single_bit_shift_register
    port map (
               clk        => clk,
               data_n     => data_n(1),
               data_1_n   => q_bar_0,
               set        => SLoad,
               q          => q_1,
               q_bar      => q_bar_1
               );

shift_2: entity work.single_bit_shift_register
    port map (
               clk        => clk,
               data_n     => data_n(2),
               data_1_n   => q_bar_1,
               set        => SLoad,
               q          => q_2,
               q_bar      => q_bar_2
               );

shift_3: entity work.single_bit_shift_register
    port map (
               clk        => clk,
               data_n     => data_n(3),
               data_1_n   => q_bar_2,
               set        => SLoad,
               q          => q_3,
               q_bar      => q_bar_3
               );

shift_4: entity work.single_bit_shift_register
    port map (
               clk        => clk,
               data_n     => data_n(4),
               data_1_n   => q_bar_3,
               set        => SLoad,
               q          => q_4,
               q_bar      => q_bar_4
               );

shift_5: entity work.single_bit_shift_register
    port map (
               clk        => clk,
               data_n     => data_n(5),
               data_1_n   => q_bar_4,
               set        => SLoad,
               q          => q_5,
               q_bar      => q_bar_5
               );

shift_6: entity work.single_bit_shift_register
    port map (
               clk        => clk,
               data_n     => data_n(6),
               data_1_n   => q_bar_5,
               set        => SLoad,
               q          => q_6,
               q_bar      => q_bar_6
               );

    -- Cell 7 (MSB): its q / q_bar are the register's serial output.
shift_7: entity work.single_bit_shift_register
    port map (
               clk        => clk,
               data_n     => data_n(7),
               data_1_n   => q_bar_6,
               set        => SLoad,
               q          => q_7,
               q_bar      => q_bar_7
               );
end Structural;
