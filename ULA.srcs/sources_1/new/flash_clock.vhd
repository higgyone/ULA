----------------------------------------------------------------------
-- flash_clock — FLASH attribute clock (~1.56 Hz)
--
-- Generates the slow toggle that drives the ZX Spectrum's FLASH
-- attribute. When an attribute byte has D7 (FLASH) set, INK and PAPER
-- swap on alternate halves of this clock; pixel_flash consumes it as
--   data_select_n = XNOR(serial_pixel, fl AND NOT flash_clk)
-- so the swap happens while flash_clk is LOW.
--
-- ── Clock source ─────────────────────────────────────────────────────
--   clock_in = NOR(v8_n, tclkb_n)
--   tclkb_n is a test-clock input that is tied LOW in normal operation
--   (same convention as tclk_a on master_horiz_counter, which horiz_timing
--   ties off with tclk_a => '0'). With tclkb_n='0' the NOR reduces to
--   clock_in = not(v8_n) = v8, the vertical counter's MSB.
--
--   The 9-bit vertical counter runs 0..311, so v8 is HIGH for lines
--   256..311 and LOW for lines 0..255 — exactly ONE falling edge per
--   frame, at the 311->0 wrap. d_ff_nor triggers on the FALLING edge, so
--   the chain advances once per frame, on the frame boundary.
--
--   (Driving the chain from v8_n directly would also give one edge per
--   frame, but at lines 255->256 — mid-frame instead of at the wrap.)
--
-- ── Divider ──────────────────────────────────────────────────────────
--   Five D flip-flops in a RIPPLE chain: each stage's q clocks the next,
--   and each is wired as a T (toggle) flip-flop by feeding its own qbar
--   back to its d input. Every stage therefore divides by 2, and five
--   stages divide by 32:
--
--     stage      0     1     2     3     4
--     divide    /2    /4    /8   /16   /32
--
--   flash_clk is the fifth stage, so it TOGGLES every 16 frames and has a
--   full period of 32 frames. At 50 Hz PAL that is 0.64 s = 1.5625 Hz,
--   matching the Spectrum's FLASH rate of one swap every 16 frames.
--
-- ── T flip-flop wiring ───────────────────────────────────────────────
--   Each instance maps the SAME signal to both its qbar output and its d
--   input (d => rippleN_q_bar, qbar => rippleN_q_bar). That is the
--   standard toggle connection: d always presents the complement of q, so
--   q inverts on every active clock edge. It simulates cleanly because
--   d_ff_nor carries `after TG` gate delays and init values, so the
--   feedback advances through time instead of spinning delta cycles.
--
--   clk_div_2 is this same d_ff_nor + qbar feedback with a reset added;
--   the flip-flops are kept discrete here to stay close to the book's
--   schematic drawing.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   v8_n      vertical counter bit 8, complement (from Vert_Line_counter)
--   tclkb_n   test clock, active-low — tie to '0' in normal operation
--   flash_clk ~1.56 Hz FLASH clock -> pixel_flash / the colour datapath
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity flash_clock is
    port (
        v8_n      : in    std_logic; -- vertical counter bit 8, complement
        tclkb_n   : in    std_logic; -- test clock; tied '0' in normal operation
        flash_clk : out   std_logic  -- ~1.56 Hz FLASH clock (32-frame period)
    );
end entity flash_clock;

architecture structural of flash_clock is

    signal clock_in : std_logic; -- = NOR(v8_n, tclkb_n) = v8 when tclkb_n='0'

    -- ripple chain: q drives the next stage's clock, qbar feeds back to d
    signal ripple0_q     : std_logic;
    signal ripple0_q_bar : std_logic;
    signal ripple1_q     : std_logic;
    signal ripple1_q_bar : std_logic;
    signal ripple2_q     : std_logic;
    signal ripple2_q_bar : std_logic;
    signal ripple3_q     : std_logic;
    signal ripple3_q_bar : std_logic;
    signal ripple4_q     : std_logic;
    signal ripple4_q_bar : std_logic;

begin

    -- tclkb_n is low in normal use, so this is simply v8; the chain then
    -- advances on v8's falling edge = the 311->0 frame wrap
    clock_in <= not(v8_n or tclkb_n);

    -- stage 0 (/2) — clocked once per frame
    ripple0 : entity work.d_ff_nor
        port map (
            clk  => clock_in,
            d    => ripple0_q_bar,
            q    => ripple0_q,
            qbar => ripple0_q_bar
        );

    -- stage 1 (/4)
    ripple1 : entity work.d_ff_nor
        port map (
            clk  => ripple0_q,
            d    => ripple1_q_bar,
            q    => ripple1_q,
            qbar => ripple1_q_bar
        );

    -- stage 2 (/8)
    ripple2 : entity work.d_ff_nor
        port map (
            clk  => ripple1_q,
            d    => ripple2_q_bar,
            q    => ripple2_q,
            qbar => ripple2_q_bar
        );

    -- stage 3 (/16)
    ripple3 : entity work.d_ff_nor
        port map (
            clk  => ripple2_q,
            d    => ripple3_q_bar,
            q    => ripple3_q,
            qbar => ripple3_q_bar
        );

    -- stage 4 (/32) — toggles every 16 frames -> 32-frame period, 1.56 Hz
    ripple4 : entity work.d_ff_nor
        port map (
            clk  => ripple3_q,
            d    => ripple4_q_bar,
            q    => ripple4_q,
            qbar => ripple4_q_bar
        );

    flash_clk <= ripple4_q;

end architecture structural;
