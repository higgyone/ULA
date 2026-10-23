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
--   provides an inverted output (q_n). So feeding a cell's q_n into the
--   next cell's data_1_n makes the two inversions cancel — the next cell
--   shifts in the TRUE bit of its right-hand neighbour, with no extra gates:
--
--     cell1.data_1_n <= cell0.q_n   -- and so on up to cell7.
--
--   Cell 0 (the LSB) has no right-hand neighbour, so its data_1_n comes from
--   the external serial input Sin. Cell 7 (the MSB) is the serial output.
--
--   Sin is ACTIVE HIGH (the book ties it to SLoad, which is active high), so
--   it is inverted into cell 0's active-low data_1_n (s_sin_n <= not sin).
--   This matters in the BORDER: nothing loads there, so the register keeps
--   shifting in from Sin, and those fill bits are what reach the screen.
--   SLoad idles at '0', so Sin shifts in pixel 0 = paper = the border
--   colour. (Inside the display a load every 8 pixels overwrites the fill
--   bits.) ula_tb caught the earlier active-low model: the border showed ink.
--
-- Clock:
--   All eight cells share clk. Each cell samples while clk is high and commits
--   on the falling edge (clk 1->0), so the whole row shifts together on one
--   edge — no bit races down the chain.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity shift8 is
    port (
        clk    : in    std_logic;                    -- pixel clock; cells commit on the falling edge
        sload  : in    std_logic;                    -- '1' = LOAD the data_n byte, '0' = SHIFT left one place
        sin    : in    std_logic;                    -- serial bit into the LSB end, ACTIVE HIGH (book: tied to SLoad)
        data_n : in    std_logic_vector(7 downto 0); -- byte to load, ACTIVE-LOW (each wire is the inverse of its bit)
        q      : out   std_logic;                    -- serial output = MSB cell's q (leftmost pixel first)
        q_n    : out   std_logic                     -- inverse of q
    );
end entity shift8;

architecture structural of shift8 is

    -- Per-cell output taps. s_q_<i> is bit i; s_q_<i>_n is its inverse and is what
    -- feeds the next cell up the chain (see header: the active-low trick).
    signal s_q_0   : std_logic;
    signal s_q_0_n : std_logic;
    signal s_q_1   : std_logic;
    signal s_q_1_n : std_logic;
    signal s_q_2   : std_logic;
    signal s_q_2_n : std_logic;
    signal s_q_3   : std_logic;
    signal s_q_3_n : std_logic;
    signal s_q_4   : std_logic;
    signal s_q_4_n : std_logic;
    signal s_q_5   : std_logic;
    signal s_q_5_n : std_logic;
    signal s_q_6   : std_logic;
    signal s_q_6_n : std_logic;
    signal s_q_7   : std_logic;
    signal s_q_7_n : std_logic;

    signal s_sin_n : std_logic;

begin

    s_sin_n <= not sin; -- Sin is active high (book); the first cell's shift input is active low

    -- Serial output taps off the top (MSB) cell.
    q   <= s_q_7;
    q_n <= s_q_7_n;

    -- Cell 0 (LSB): shift-in comes from the external serial input Sin, inverted
    -- into the cell's active-low shift input (see header).
    shift_0 : entity work.single_bit_shift_register
        port map (
            clk      => clk,
            data_n   => data_n(0),
            data_1_n => s_sin_n,
            set      => sload,
            q        => s_q_0,
            q_n      => s_q_0_n
        );

    -- Cells 1..7: shift-in comes from the neighbour below via its q_n,
    -- so the true bit climbs one place toward the MSB on each shift.
    shift_1 : entity work.single_bit_shift_register
        port map (
            clk      => clk,
            data_n   => data_n(1),
            data_1_n => s_q_0_n,
            set      => sload,
            q        => s_q_1,
            q_n      => s_q_1_n
        );

    shift_2 : entity work.single_bit_shift_register
        port map (
            clk      => clk,
            data_n   => data_n(2),
            data_1_n => s_q_1_n,
            set      => sload,
            q        => s_q_2,
            q_n      => s_q_2_n
        );

    shift_3 : entity work.single_bit_shift_register
        port map (
            clk      => clk,
            data_n   => data_n(3),
            data_1_n => s_q_2_n,
            set      => sload,
            q        => s_q_3,
            q_n      => s_q_3_n
        );

    shift_4 : entity work.single_bit_shift_register
        port map (
            clk      => clk,
            data_n   => data_n(4),
            data_1_n => s_q_3_n,
            set      => sload,
            q        => s_q_4,
            q_n      => s_q_4_n
        );

    shift_5 : entity work.single_bit_shift_register
        port map (
            clk      => clk,
            data_n   => data_n(5),
            data_1_n => s_q_4_n,
            set      => sload,
            q        => s_q_5,
            q_n      => s_q_5_n
        );

    shift_6 : entity work.single_bit_shift_register
        port map (
            clk      => clk,
            data_n   => data_n(6),
            data_1_n => s_q_5_n,
            set      => sload,
            q        => s_q_6,
            q_n      => s_q_6_n
        );

    -- Cell 7 (MSB): its q / q_n are the register's serial output.
    shift_7 : entity work.single_bit_shift_register
        port map (
            clk      => clk,
            data_n   => data_n(7),
            data_1_n => s_q_6_n,
            set      => sload,
            q        => s_q_7,
            q_n      => s_q_7_n
        );

end architecture structural;
