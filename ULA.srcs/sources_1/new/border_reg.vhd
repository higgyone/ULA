----------------------------------------------------------------------------------
-- border_reg — border colour register (ULA port write, bits 0..2)
--
-- When the Z80 writes to the ULA's I/O port (OUT to any even address, e.g.
-- OUT (0xFE), A), data bits 0..2 set the border colour. Three transparent
-- latches capture them and hold them until the next write.
--
-- ── The colour bits ──────────────────────────────────────────────────
--   bit  colour   output
--   ---  ------   ------
--    0   blue     b0
--    1   red      b1
--    2   green    b2
--   giving the Spectrum's 8 colours: 0 black, 1 blue, 2 red, 3 magenta,
--   4 green, 5 cyan, 6 yellow, 7 white. There is no BRIGHT for the border.
--
--   b2..b0 feed attr_output_latch_border_select_mux's border_colour_bgr(2:0)
--   directly: bit 0 blue, bit 1 red, bit 2 green, the same order.
--
--   Bits 3 (MIC) and 4 (speaker) of the same write are not handled here.
--
-- ── The latches ──────────────────────────────────────────────────────
--   Three data_latch_1_bit cells, all enabled by port_wr_n (ACTIVE LOW):
--     port_wr_n = '0'  during the port write: transparent, b follows di
--     port_wr_n = '1'  otherwise: holds the last value written
--   A transparent latch, not an edge flip-flop, as in the book. The value
--   that sticks is whatever is on di when port_wr_n rises at the end of the
--   write. The Z80 keeps the data valid until after WR rises, so that is
--   the byte it wrote.
--
--   At power-on the latches start at '0' (data_latch_1_bit's seed), so the
--   border is black until the first write.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   di_0..di_2  data bus bits 0..2, from the D-pin input buffers
--   port_wr_n   ULA port write, active low (an even-address I/O write, from
--               io_port_decode_0xfe)
--   b0, b1, b2  border colour: blue, red, green
--
-- Verified by border_reg_tb.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity border_reg is
    port (
        di_0      : in    std_logic; -- data bit 0 (blue)
        di_1      : in    std_logic; -- data bit 1 (red)
        di_2      : in    std_logic; -- data bit 2 (green)
        port_wr_n : in    std_logic; -- ULA port write, active low
        b0        : out   std_logic; -- border blue
        b1        : out   std_logic; -- border red
        b2        : out   std_logic  -- border green
    );
end entity border_reg;

architecture structural of border_reg is

begin

    -- blue
    latch_0 : entity work.data_latch_1_bit
        port map (
            e     => port_wr_n,
            d     => di_0,
            q     => b0,
            q_bar => open
        );

    -- red
    latch_1 : entity work.data_latch_1_bit
        port map (
            e     => port_wr_n,
            d     => di_1,
            q     => b1,
            q_bar => open
        );

    -- green
    latch_2 : entity work.data_latch_1_bit
        port map (
            e     => port_wr_n,
            d     => di_2,
            q     => b2,
            q_bar => open
        );

end architecture structural;
