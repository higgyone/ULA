----------------------------------------------------------------------
-- attr_data_latch_paper_border_mux — attribute latch + paper/border mux
--
-- Captures the display attribute byte and produces the colour signals the
-- final pixel mux needs. Two jobs in one block:
--   1. an 8-bit transparent latch (data_latch_8_bit) that holds the
--      attribute byte fetched from display RAM, and
--   2. a per-colour-bit 2:1 multiplexer that outputs either the PAPER
--      colour (inside the display area) or the BORDER colour (outside it),
--      selected by vid_en.
--
-- ── The three colours (ZX Spectrum colour model) ─────────────────────
--   INK    — the FOREGROUND colour: shown where a pixel bit = 1 (the lit
--            dots of a character). Straight out of the attribute byte.
--   PAPER  — the BACKGROUND colour: shown where a pixel bit = 0, inside
--            the drawable screen area. Also from the attribute byte.
--   BORDER — the colour of the frame AROUND the screen, outside the
--            drawable area. It has no attribute byte — it comes from the
--            border register (port 0xFE, bits 2:0) and never has
--            bright/flash.
--   The downstream final mux picks INK vs (PAPER-or-BORDER) using the
--   serialised pixel bit. This block supplies its INK and its
--   PAPER-or-BORDER inputs; substituting BORDER into the paper leg here is
--   what makes the frame the right colour when the beam is off-screen.
--
-- ── Attribute byte layout (attr_data / data_latch_out) ───────────────
--   bit 7      : FLASH   -> al7_fl  (swaps ink/paper downstream, 25 Hz)
--   bit 6      : BRIGHT  -> al6_hl  (brightness/highlight)
--   bits 5..3  : PAPER   colour  (b5=Green, b4=Red, b3=Blue)
--   bits 2..0  : INK     colour  (b2=Green, b1=Red, b0=Blue)
--   Each 3-bit colour is GRB; the same b0=Blue / b1=Red / b2=Green order
--   is used on border_colour, ink and paper_border.
--
-- ── vid_en (video enable) ────────────────────────────────────────────
--   vid_en = '1'  -> inside the display area: paper_border = PAPER, and
--                    bright/flash pass through.
--   vid_en = '0'  -> border region: paper_border = BORDER, and
--                    bright/flash are forced to 0 (the border is flat).
--   `vid_en_n` is the single shared inverter used by every mux/gate that
--   needs the complement (mirrors the one inverter on the schematic).
--
-- ── Per-bit 2:1 mux, gate-accurate NOR-NOR form (bit 0 shown) ─────────
--   a_o = NOR(border_colour(0), vid_en)    -- border leg (live when vid_en=0)
--   b_o = NOR(paper_bit(3),     vid_en_n)  -- paper  leg (live when vid_en=1)
--   paper_border(0) = NOR(a_o, b_o)        -- => paper when vid_en=1, else border
--
--   al6_hl = NOR(NOT bright, vid_en_n) = bright AND vid_en   (0 in border)
--   al7_fl = NOR(NOT flash,  vid_en_n) = flash  AND vid_en   (0 in border)
--
-- INK is NOT gated by vid_en here: during the border the final mux selects
-- the paper_border leg (the pixel bit is forced to paper upstream), so the
-- ungated ink line is a don't-care off-screen.
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity attr_data_latch_paper_border_mux is
    Port (
        attr_data       : in  STD_LOGIC_VECTOR (7 downto 0); -- attribute byte from display RAM
        attr_latch_n    : in  STD_LOGIC;                     -- active-low latch enable: '0' transparent, '1' hold
        border_colour   : in  STD_LOGIC_VECTOR (2 downto 0); -- border reg (port 0xFE); b0-Blue, b1-Red, b2-Green
        vid_en          : in  STD_LOGIC;                     -- '1' display area (paper), '0' border region
        ink             : out STD_LOGIC_VECTOR (2 downto 0); -- foreground colour; b0-Blue, b1-Red, b2-Green
        paper_border    : out STD_LOGIC_VECTOR (2 downto 0); -- background: paper (display) or border (off-screen)
        al6_hl          : out STD_LOGIC;                     -- BRIGHT (attr bit 6), gated by vid_en
        al7_fl          : out STD_LOGIC                      -- FLASH  (attr bit 7), gated by vid_en
           );
end attr_data_latch_paper_border_mux;

architecture Structural of attr_data_latch_paper_border_mux is
    signal data_latch_out : STD_LOGIC_VECTOR (7 downto 0);   -- latched attribute byte

    signal vid_en_n       : STD_LOGIC;                       -- shared inverter: not vid_en

    -- per-colour-bit mux intermediates (a/c/e = border legs, b/d/f = paper legs)
    signal a_o          : STD_LOGIC;
    signal b_o          : STD_LOGIC;
    signal c_o          : STD_LOGIC;
    signal d_o          : STD_LOGIC;
    signal e_o          : STD_LOGIC;
    signal f_o          : STD_LOGIC;

begin

        -- single shared inverter for the video-enable select line
        vid_en_n <= not vid_en;

        -- INK: foreground colour straight from the latched attribute byte
        ink <= data_latch_out(2 downto 0);

        -- PAPER/BORDER 2:1 mux per colour bit:
        --   border leg live when vid_en='0', paper leg live when vid_en='1'
        a_o <= not(border_colour(0) or vid_en);       -- Blue  border
        b_o <= not(data_latch_out(3) or vid_en_n);    -- Blue  paper
        c_o <= not(border_colour(1) or vid_en);       -- Red   border
        d_o <= not(data_latch_out(4) or vid_en_n);    -- Red   paper
        e_o <= not(border_colour(2) or vid_en);       -- Green border
        f_o <= not(data_latch_out(5) or vid_en_n);    -- Green paper

        paper_border(0) <= not(a_o or b_o);           -- Blue  out
        paper_border(1) <= not(c_o or d_o);           -- Red   out
        paper_border(2) <= not(e_o or f_o);           -- Green out

        -- BRIGHT / FLASH: pass the attribute bit only in the display area
        al6_hl  <= not(not(data_latch_out(6)) or vid_en_n);
        al7_fl  <= not(not(data_latch_out(7)) or vid_en_n);


data_latch_8: entity work.data_latch_8_bit
    port map (
                enable      => attr_latch_n,
                data        => attr_data,
                data_out    => data_latch_out,
                data_out_n  => open
                );

end Structural;
