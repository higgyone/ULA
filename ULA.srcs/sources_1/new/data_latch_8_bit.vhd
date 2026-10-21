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
--   cell.q_n -> data_out_n(i). Enable is common across all eight.
--
-- Note: no gate delays / init values appear here — they live inside
-- data_latch_1_bit (the cross-coupled NORs that need them). This wrapper
-- is delay-free structural fan-out and is synthesis-clean.
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity data_latch_8_bit is
    port (
        enable     : in    std_logic;                    -- active-low latch enable (= not datalatch): '0' transparent, '1' hold
        data       : in    std_logic_vector(7 downto 0); -- byte in (from display RAM)
        data_out   : out   std_logic_vector(7 downto 0); -- latched byte, TRUE polarity -> attribute/colour path
        data_out_n : out   std_logic_vector(7 downto 0)  -- latched byte, ACTIVE-LOW -> shift8 data_n(7:0)
    );
end entity data_latch_8_bit;

architecture structural of data_latch_8_bit is

    -- per-bit taps from each latch cell: s_q_i (true) and s_q_i_n (active-low)
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

begin

    -- fan the eight cell taps out onto the two output buses
    data_out(0)   <= s_q_0;
    data_out_n(0) <= s_q_0_n;
    data_out(1)   <= s_q_1;
    data_out_n(1) <= s_q_1_n;
    data_out(2)   <= s_q_2;
    data_out_n(2) <= s_q_2_n;
    data_out(3)   <= s_q_3;
    data_out_n(3) <= s_q_3_n;
    data_out(4)   <= s_q_4;
    data_out_n(4) <= s_q_4_n;
    data_out(5)   <= s_q_5;
    data_out_n(5) <= s_q_5_n;
    data_out(6)   <= s_q_6;
    data_out_n(6) <= s_q_6_n;
    data_out(7)   <= s_q_7;
    data_out_n(7) <= s_q_7_n;

    -- eight latch bit-slices, all sharing the common active-low enable
    latch_0 : entity work.data_latch_1_bit
        port map (
            e   => enable,
            d   => data(0),
            q   => s_q_0,
            q_n => s_q_0_n
        );

    latch_1 : entity work.data_latch_1_bit
        port map (
            e   => enable,
            d   => data(1),
            q   => s_q_1,
            q_n => s_q_1_n
        );

    latch_2 : entity work.data_latch_1_bit
        port map (
            e   => enable,
            d   => data(2),
            q   => s_q_2,
            q_n => s_q_2_n
        );

    latch_3 : entity work.data_latch_1_bit
        port map (
            e   => enable,
            d   => data(3),
            q   => s_q_3,
            q_n => s_q_3_n
        );

    latch_4 : entity work.data_latch_1_bit
        port map (
            e   => enable,
            d   => data(4),
            q   => s_q_4,
            q_n => s_q_4_n
        );

    latch_5 : entity work.data_latch_1_bit
        port map (
            e   => enable,
            d   => data(5),
            q   => s_q_5,
            q_n => s_q_5_n
        );

    latch_6 : entity work.data_latch_1_bit
        port map (
            e   => enable,
            d   => data(6),
            q   => s_q_6,
            q_n => s_q_6_n
        );

    latch_7 : entity work.data_latch_1_bit
        port map (
            e   => enable,
            d   => data(7),
            q   => s_q_7,
            q_n => s_q_7_n
        );

end architecture structural;
