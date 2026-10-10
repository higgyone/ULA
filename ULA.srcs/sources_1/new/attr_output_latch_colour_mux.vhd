----------------------------------------------------------------------------------
-- attr_output_latch_colour_mux — attribute output latch + colour mux + blank
--
-- The LAST block of the ULA colour back-end (Chris Smith, "The ZX Spectrum
-- ULA"). It does three jobs:
--   1. Attribute OUTPUT latch (the second half of the attribute double
--      buffer). While the attr INPUT latch upstream
--      (attr_data_latch_paper_border_mux) prefetches the NEXT character
--      cell, this latch holds the CURRENT cell's colour signals steady for
--      all 8 pixels of the cell. Reuses data_latch_8_bit (active-low
--      enable a_o_latch_n: '0' transparent, '1' hold).
--   2. Colour multiplexer — per colour bit, selects INK or PAPER using the
--      per-pixel select bit data_select_n.
--   3. Final blanking mux — forces the colour output to black during sync /
--      horizontal blank, folded straight into the colour NOR.
--
-- ── Latch bit packing (latch_data_in / q) ────────────────────────────
--   Ink and paper are INTERLEAVED per colour, bright and flash on top:
--     bit 0  i0_b   INK  Blue      bit 1  pb0_b  PAPER Blue
--     bit 2  i1_r   INK  Red       bit 3  pb1_r  PAPER Red
--     bit 4  i2_g   INK  Green     bit 5  pb2_g  PAPER Green
--     bit 6  al6_hl BRIGHT         bit 7  al7_fl FLASH
--   So each colour output is a 2:1 mux of its (ink, paper) pair:
--   blue=mux(q0,q1), red=mux(q2,q3), green=mux(q4,q5).
--
-- ── data_select_n (per-pixel ink/paper select) ──────────────────────
--   The serialised pixel/flash select bit. It is NOT latched here — it
--   changes every pixel, so it bypasses the output latch and drives the
--   mux directly.
--     data_select_n = '0'  -> select INK
--     data_select_n = '1'  -> select PAPER
--   `data_select` is the single shared inverter (not data_select_n) used
--   by the three paper legs.
--
-- ── Per-bit 2:1 mux, gate-accurate NOR-NOR form (blue shown) ─────────
--   a_o  = NOR(q0 INK-blue,   data_select_n)   -- ink leg   (live when sel='0')
--   b_o  = NOR(q1 PAPER-blue, data_select)     -- paper leg (live when sel='1')
--   blue = NOR(v_sync, a_o, h_blank, b_o)      -- mux result, unless blanked
--   => data_select_n='0' -> blue=INK-blue; ='1' -> blue=PAPER-blue.
--
-- ── Blanking (v_sync, h_blank) ───────────────────────────────────────
--   The two blank terms are OR'd into every colour NOR, so either one high
--   forces the colour to '0' (black):
--     v_sync    active-HIGH : '1' during vertical sync.
--     h_blank_n active-LOW  : inverted to h_blank ('1' = blank) so the
--                             active-low nHblank line blanks the output.
--   Border colour is NOT blanked here — the border shows its own colour via
--   paper_border upstream; only true sync/retrace goes black.
--
-- ── Bright / flash pass-through ──────────────────────────────────────
--   hl = latched al6_hl (bright), fl = latched al7_fl (flash). fl is the
--   double-buffered flash bit; it feeds pixel_flash, which therefore sits
--   AFTER this latch and produces the data_select_n fed back in above.
--
-- Gate delay TG (sim only). The mux/blank NORs are feedback-free so they do
-- not need it to simulate, but each gate carries `after TG` for consistency
-- with the rest of the FF/gate library and to model real NOR propagation
-- (and the mux's transient static hazard). TG is ignored by synthesis.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity attr_output_latch_colour_mux is
    port (
        v_sync        : in    std_logic;
        h_blank_n     : in    std_logic;
        data_select_n : in    std_logic;
        i0_b          : in    std_logic;
        pb0_b         : in    std_logic;
        i1_r          : in    std_logic;
        pb1_r         : in    std_logic;
        i2_g          : in    std_logic;
        pb2_g         : in    std_logic;
        al6_hl        : in    std_logic;
        al7_fl        : in    std_logic;
        a_o_latch_n   : in    std_logic;
        blue          : out   std_logic;
        red           : out   std_logic;
        green         : out   std_logic;
        hl            : out   std_logic;
        fl            : out   std_logic
    );
end entity attr_output_latch_colour_mux;

architecture structural of attr_output_latch_colour_mux is

    signal q             : std_logic_vector(7 downto 0);
    signal latch_data_in : std_logic_vector(7 downto 0);

    signal h_blank     : std_logic;
    signal data_select : std_logic;

    signal a_o : std_logic;
    signal b_o : std_logic;
    signal c_o : std_logic;
    signal d_o : std_logic;
    signal e_o : std_logic;
    signal f_o : std_logic;

    constant tg : time := 1 ns;   -- modelled gate propagation delay (sim only)

begin

    -- pack the attribute-cell colour signals into the 8-bit latch input
    -- (ink/paper interleaved per colour; bright, flash on the top two bits)
    latch_data_in(0) <= i0_b;
    latch_data_in(1) <= pb0_b;
    latch_data_in(2) <= i1_r;
    latch_data_in(3) <= pb1_r;
    latch_data_in(4) <= i2_g;
    latch_data_in(5) <= pb2_g;
    latch_data_in(6) <= al6_hl;
    latch_data_in(7) <= al7_fl;

    -- shared inverters: active-high blank, and the paper-leg select
    h_blank     <= not(h_blank_n) after tg;
    data_select <= not(data_select_n) after tg;

    -- attribute OUTPUT latch (double-buffer): holds the current cell while
    -- the upstream input latch prefetches the next. q is the latched byte.
    data_latch_8 : entity work.data_latch_8_bit
        port map (
            enable     => a_o_latch_n,
            data       => latch_data_in,
            data_out   => q,
            data_out_n => open
        );

    -- 2:1 colour mux legs: ink leg live when data_select_n='0',
    -- paper leg live when data_select_n='1' (data_select='0')
    a_o <= not(q(0) or data_select_n) after tg; -- Blue  ink
    b_o <= not(q(1) or data_select) after tg;   -- Blue  paper
    c_o <= not(q(2) or data_select_n) after tg; -- Red   ink
    d_o <= not(q(3) or data_select) after tg;   -- Red   paper
    e_o <= not(q(4) or data_select_n) after tg; -- Green ink
    f_o <= not(q(5) or data_select) after tg;   -- Green paper

    -- mux result OR'd with the blank terms: v_sync or h_blank forces black
    blue  <= not(v_sync or a_o or h_blank or b_o) after tg;
    red   <= not(v_sync or c_o or h_blank or d_o) after tg;
    green <= not(v_sync or e_o or h_blank or f_o) after tg;

    -- bright / flash pass straight through from the latch (fl -> pixel_flash)
    hl <= q(6);
    fl <= q(7);

end architecture structural;
