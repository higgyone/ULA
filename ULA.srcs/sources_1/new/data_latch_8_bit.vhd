----------------------------------------------------------------------
-- data_latch_8_bit — the ULA video data latch (full byte)
--
-- Tiles eight `data_latch_1_bit` cells into the 8-bit transparent latch
-- that captures a byte returned from display RAM before it fans out to
-- the pixel shift register (`shift8`) and the attribute / colour path.
-- Pure structure: one shared enable, eight independent bit slices, no
-- glue logic. Each slice is the gate-accurate NOR latch documented in
-- data_latch_1_bit.vhd.
--
--   Enable polarity: `enable` is ACTIVE-LOW (driven straight into every
--   cell's `e`, so it inherits the 1-bit semantics):
--     enable='0' -> transparent (data_out follows data)
--     enable='1' -> hold / latched (byte frozen, data ignored)
--   i.e. the RISING edge of enable captures the byte. In the ULA this
--   port is driven by enable = NOT datalatch.
--
-- Outputs (both polarities of the whole byte are brought out):
--   data_out(7:0)   — latched byte, TRUE polarity  -> attribute/colour path
--   data_out_n(7:0) — latched byte, ACTIVE-LOW     -> shift8 `data_n(7:0)`
--
--   Why the inverted bus feeds shift8: shift8's parallel-load input
--   `data_n` is itself active-low, so wiring data_out_n -> data_n makes
--   the two active-low conventions cancel and the shift register loads
--   the TRUE pixel value. (See data_latch_1_bit.vhd, "Output use".)
--
-- Bit map: slice i wires data(i) -> cell.d, cell.q -> data_out(i),
--   cell.q_bar -> data_out_n(i). Enable is common across all eight.
--
-- Note: no gate delays / init values appear here — they live inside
-- data_latch_1_bit (the cross-coupled NORs that need them). This wrapper
-- is delay-free structural fan-out and is synthesis-clean.
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity data_latch_8_bit is
    Port ( enable       : in  STD_LOGIC;                     -- active-low latch enable (= not datalatch): '0' transparent, '1' hold
           data         : in  STD_LOGIC_VECTOR (7 downto 0); -- byte in (from display RAM)
           data_out     : out STD_LOGIC_VECTOR (7 downto 0); -- latched byte, TRUE polarity -> attribute/colour path
           data_out_n   : out STD_LOGIC_VECTOR (7 downto 0)  -- latched byte, ACTIVE-LOW -> shift8 data_n(7:0)
           );
end data_latch_8_bit;

architecture Structural of data_latch_8_bit is
    -- per-bit taps from each latch cell: q_i (true) and q_bar_i (active-low)
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
    -- fan the eight cell taps out onto the two output buses
    data_out(0)     <= q_0;
    data_out_n(0)   <= q_bar_0;
    data_out(1)     <= q_1;
    data_out_n(1)   <= q_bar_1;
    data_out(2)     <= q_2;
    data_out_n(2)   <= q_bar_2;
    data_out(3)     <= q_3;
    data_out_n(3)   <= q_bar_3;
    data_out(4)     <= q_4;
    data_out_n(4)   <= q_bar_4;
    data_out(5)     <= q_5;
    data_out_n(5)   <= q_bar_5;
    data_out(6)     <= q_6;
    data_out_n(6)   <= q_bar_6;
    data_out(7)     <= q_7;
    data_out_n(7)   <= q_bar_7;

    -- eight latch bit-slices, all sharing the common active-low enable
latch_0: entity work.data_latch_1_bit
    port map (
                e       => enable,
                d       => data(0),
                q       => q_0,
                q_bar   => q_bar_0
                );

latch_1: entity work.data_latch_1_bit
    port map (
                e       => enable,
                d       => data(1),
                q       => q_1,
                q_bar   => q_bar_1
                );

latch_2: entity work.data_latch_1_bit
    port map (
                e       => enable,
                d       => data(2),
                q       => q_2,
                q_bar   => q_bar_2
                );

latch_3: entity work.data_latch_1_bit
    port map (
                e       => enable,
                d       => data(3),
                q       => q_3,
                q_bar   => q_bar_3
                );

latch_4: entity work.data_latch_1_bit
    port map (
                e       => enable,
                d       => data(4),
                q       => q_4,
                q_bar   => q_bar_4
                );

latch_5: entity work.data_latch_1_bit
    port map (
                e       => enable,
                d       => data(5),
                q       => q_5,
                q_bar   => q_bar_5
                );

latch_6: entity work.data_latch_1_bit
    port map (
                e       => enable,
                d       => data(6),
                q       => q_6,
                q_bar   => q_bar_6
                );

latch_7: entity work.data_latch_1_bit
    port map (
                e       => enable,
                d       => data(7),
                q       => q_7,
                q_bar   => q_bar_7
                );

end Structural;
