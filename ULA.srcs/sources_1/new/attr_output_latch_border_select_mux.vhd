----------------------------------------------------------------------------------
-- attr_output_latch_border_select_mux — pixel/colour datapath integration
--
-- Top-level structural wrapper stitching the Phase-5 pixel and colour path
-- into one block:
--   display byte -> serial pixel stream -> flash select (data_select_n), and
--   attribute byte -> paper/border mux -> output latch -> colour mux -> RGB.
--
-- ── Sub-blocks (data flow) ───────────────────────────────────────────
--   pixel_serialiser                  pixel_data(7:0) -> serial_pixel_stream (MSB first)
--   pixel_flash                       serial + fl + flash_clk -> data_select_n
--   attr_data_latch_paper_border_mux  attr_data -> ink / paper-or-border / hl / fl (input latch)
--   attr_output_latch_colour_mux      output latch + ink/paper mux + blank -> blue/red/green
--
-- ── data_select_n (per-pixel ink/paper select, from pixel_flash) ─────
--   data_select_n = XNOR(serial_pixel, fl AND NOT flash_clk)
--     '0' -> INK leg        '1' -> PAPER/BORDER leg
--
-- ── Pixel colour table (not blanked: v_sync='0', h_blank_n='1') ──────
--   vid_en = 1  (display area):
--       serial | flash off | flash on (fl=1, flash_clk=0)
--       -------+-----------+----------------------------
--         1    |  INK      |  PAPER
--         0    |  PAPER    |  INK
--     INK = attr D0-2, PAPER = attr D3-5, BRIGHT = attr D6, FLASH = attr D7.
--
--   vid_en = 0  (border region): fl forced 0 (no flash), bright forced 0:
--       serial | output
--       -------+--------------------------------------
--         0    |  BORDER (border_colour_bgr)   <- expected off-screen state
--         1    |  INK (don't-care; pixel stream held 0 in the border)
--
--   Blanked (v_sync='1' OR h_blank_n='0'): blue=red=green='0' (black), always.
--
-- ── Display window where vid_en = 1 (central 256 x 192) ──────────────
--   horizontal  pixel columns 0..255   (H-counter c8=0; 256..447 = right border+blank)
--   vertical    lines         0..191   (192..255 and 256..311 = vertical border)
--   Outside this window vid_en='0' and the frame shows border_colour.
--
-- No border flash/bright input: the book's block diagram ties the border's
-- FLASH/BRIGHT to "00", but that is not a wire — it falls out of vid_en
-- gating al6_hl/al7_fl to '0' in the border region (see attr_data_latch_
-- paper_border_mux), so there is nothing to drive here.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity attr_output_latch_border_select_mux is
    port (
        clk_7              : in    std_logic;                    -- 7MHz clock
        flash_clk          : in    std_logic;
        s_load             : in    std_logic;                    -- serial pixel load
        pixel_data_latch_n : in    std_logic;                    -- latch pixel data
        pixel_data         : in    std_logic_vector(7 downto 0); -- pixel data
        attr_data_latch_n  : in    std_logic;                    -- when to latch the attribute data
        attr_data          : in    std_logic_vector(7 downto 0); -- D0-2 ink, D3-5 paper, D6 hl, D7 fl
        border_colour_bgr  : in    std_logic_vector(2 downto 0); -- blue, green ed bits
        video_en           : in    std_logic;                    -- enable video; dont display on blank
        attr_output_latch  : in    std_logic;                    -- latch attr output data to rgb mux
        v_sync             : in    std_logic;
        h_blank_n          : in    std_logic;
        blue               : out   std_logic;                    -- output blue bit
        green              : out   std_logic;                    -- output green bit
        red                : out   std_logic;                    -- output red bit
        hl                 : out   std_logic;
        fl                 : out   std_logic
    );
end entity attr_output_latch_border_select_mux;

architecture structural of attr_output_latch_border_select_mux is

    -- internal datapath wires between the four sub-blocks
    signal serial_pixel_stream : std_logic; -- serialiser -> flash: MSB-first pixel bit
    signal data_select_n       : std_logic; -- flash -> colour mux: '0' ink, '1' paper/border
    signal i0_b                : std_logic; -- INK   Blue  (attr D0): input mux -> output mux
    signal i1_r                : std_logic; -- INK   Red   (attr D1)
    signal i2_g                : std_logic; -- INK   Green (attr D2)
    signal pb0_b               : std_logic; -- PAPER/BORDER Blue
    signal pb1_r               : std_logic; -- PAPER/BORDER Red
    signal pb2_g               : std_logic; -- PAPER/BORDER Green
    signal al_6                : std_logic; -- BRIGHT before output latch (attr D6, gated by vid_en)
    signal al_7                : std_logic; -- FLASH  before output latch (attr D7, gated by vid_en)
    signal attr_output_latch_n : std_logic; -- active-low output-latch enable (= not attr_output_latch)
    signal fl_i                : std_logic; -- LATCHED flash: colour mux out -> pixel_flash in AND top fl

begin

    -- output latch takes an active-low enable; top strobe is active-high
    attr_output_latch_n <= not(attr_output_latch);
    -- expose the latched flash bit (also fed back into pixel_flash below)
    fl <= fl_i;

    -- 1) serialise the display byte into an MSB-first pixel stream
    pix_serial : entity work.pixel_serialiser
        port map (
            clk          => clk_7,
            sload        => s_load,
            data_latch_n => pixel_data_latch_n,
            data         => pixel_data,
            serial_data  => serial_pixel_stream
        );

    -- 2) flash select: XNOR the pixel bit with (fl AND NOT flash_clk) to
    --    produce the per-pixel ink/paper select
    pix_flash : entity work.pixel_flash
        port map (
            fl            => fl_i,
            flash_clk     => flash_clk,
            serial_data   => serial_pixel_stream,
            data_select_n => data_select_n
        );

    -- 3) attribute INPUT latch + paper/border mux: unpacks the attribute byte
    --    into ink / paper-or-border / bright / flash (border via vid_en)
    attr_paper_border_mux : entity work.attr_data_latch_paper_border_mux
        port map (
            attr_data       => attr_data,
            attr_latch_n    => attr_data_latch_n,
            border_colour   => border_colour_bgr,
            vid_en          => video_en,
            ink(2)          => i2_g,
            ink(1)          => i1_r,
            ink(0)          => i0_b,
            paper_border(2) => pb2_g,
            paper_border(1) => pb1_r,
            paper_border(0) => pb0_b,
            al6_hl          => al_6,
            al7_fl          => al_7
        );

    -- 4) attribute OUTPUT latch + colour mux + blank: double-buffers the
    --    colour signals, picks ink vs paper/border per data_select_n, and
    --    forces black on sync/blank -> blue/red/green
    attr_col_mux : entity work.attr_output_latch_colour_mux
        port map (
            v_sync        => v_sync,
            h_blank_n     => h_blank_n,
            data_select_n => data_select_n,
            i0_b          => i0_b,
            pb0_b         => pb0_b,
            i1_r          => i1_r,
            pb1_r         => pb1_r,
            i2_g          => i2_g,
            pb2_g         => pb2_g,
            al6_hl        => al_6,
            al7_fl        => al_7,
            a_o_latch_n   => attr_output_latch_n,
            blue          => blue,
            red           => red,
            green         => green,
            hl            => hl,
            fl            => fl_i
        );

end architecture structural;
