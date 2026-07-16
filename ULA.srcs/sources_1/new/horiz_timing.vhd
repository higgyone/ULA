----------------------------------------------------------------------
-- horiz_timing — horizontal counter + sync/blank decoders
--
-- Owns the master horizontal counter (modulo-448) and derives:
--   hsync_5c — active-HIGH hsync for issue 5 ULAs (pixels 336..367)
--   hsync_6c — active-HIGH hsync for issue 6 ULAs (pixels 344..375)
--   nHblank  — active-low horizontal blanking      (pixels 320..415)
--
-- Also exposes MHC outputs needed by the vertical counter:
--   clk_hc6 — clock for the bit3_counter chain (= C5)
--   hc_rst  — horizontal counter overflow pulse (line end)
--
-- All combinational logic is built from NORs with inverted inputs,
-- matching the Ferranti gate library (Chris Smith pg 90).
--
-- Why two hsync outputs (5c vs 6c)?
-- The original ZX Spectrum shipped with two distinct ULA revisions
-- that handled hsync differently:
--   * Issue 5 (5c) — the earlier chip. Hsync pulse aligned to the
--     start of the blanking window (pixels 336..367).
--   * Issue 6 (6c) — later revision. Hsync shifted by half a C3
--     period (~1.14 us / ~8 pixels) to fix compatibility issues
--     with certain TVs and the original PAL standard
--     (pixels 344..375).
-- Both outputs are generated together; whichever the board uses
-- depends on which chip variant is being emulated.
--
-- Horizontal line structure (PAL composite, sync in blanking):
--   active video → front porch → sync pulse → back porch → next line
--
--   * Blanking (nHblank LOW) — the off-time window during which
--     the beam flies back to the start of the next line. Holds
--     the signal at black level so retrace leaves no streak.
--   * Front porch — flat black-level region BEFORE the sync pulse.
--     Lets the signal settle from active video to black before the
--     sync edge, so the receiver's sync detector triggers cleanly.
--   * Sync pulse — the active-LOW pulse the TV locks onto; the
--     falling edge is the time reference for the next line.
--   * Back porch — flat black-level region AFTER the sync pulse.
--     The receiver uses it for clamping (re-establishing black
--     level) and AGC settling.
--
-- No colour burst is generated here. The Spectrum outputs digital
-- RGB + sync; the burst (used by a colour TV to phase-lock its
-- chrominance decoder) is added downstream by the RF modulator,
-- not by the ULA.
--
-- Pixel reference (448 pixels per line, 7 MHz, 64 us PAL):
--   pixel output           0..255   C[8:6] = 000
--   right border         256..319   C[8:6] = 100
--   video blanking       320..415   C8=1, C7=0..1 sub-windows
--   hsync 5c pulse       336..367
--   hsync 6c pulse       344..375
--   left border          416..447
--   sync counter reset      447..  C[8:0] = 110 111 111
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity horiz_timing is
    port (
        clk      : in    std_logic;
        reset    : in    std_logic;
        hsync_5c : out   std_logic;
        hsync_6c : out   std_logic;
        nhblank  : out   std_logic;
        c8       : out   std_logic;   -- H-counter MSB (HIGH for pixels 256..447); exposed so video_sync can gate the horizontal border
        clk_hc6  : out   std_logic;
        hc_rst   : out   std_logic
    );
end entity horiz_timing;

architecture behavioral of horiz_timing is

    signal c0        : std_logic;
    signal c1        : std_logic;
    signal c2        : std_logic;
    signal c3        : std_logic;
    signal c4        : std_logic;
    signal c5        : std_logic;
    signal c6        : std_logic;
    signal c7        : std_logic;
    signal s_c8      : std_logic;   -- H-counter MSB; backs the c8 output port (cf. s_clk_hc6 / s_hc_rst)
    signal s_clk_hc6 : std_logic;
    signal s_hc_rst  : std_logic;

    signal blank1, blank2  : std_logic;
    signal nhsynca_5c      : std_logic;
    signal nhsyncb_5c      : std_logic;
    signal nhsyncpulses_5c : std_logic;
    signal x               : std_logic;
    signal nhsynca_6c      : std_logic;
    signal nhsyncb_6c      : std_logic;
    signal nhsyncpulses_6c : std_logic;
    signal nhsyncselect    : std_logic;

begin

    mhc : entity work.master_horiz_counter(Behavioral)
        port map (
            clk7    => clk,
            reset   => reset,
            tclk_a  => '0',
            c0      => c0,
            c1      => c1,
            c2      => c2,
            c3      => c3,
            c4      => c4,
            c5      => c5,
            c6      => c6,
            c7      => c7,
            c8      => s_c8,
            clk_hc6 => s_clk_hc6,
            hc_rst  => s_hc_rst
        );

    clk_hc6 <= s_clk_hc6;
    hc_rst  <= s_hc_rst;
    c8      <= s_c8; -- expose the H-counter MSB for the border decode in video_sync

    --------------------------------------------------------------
    -- Horizontal blanking — LOW during pixels 320..415
    --------------------------------------------------------------
    -- Start of blanking: C8=1, C7=0, C6=1 -> pixel 320
    blank1 <= not((not s_c8) or c7 or (not c6));
    -- End of blanking:   C8=1, C7=1, C5=0 -> through pixel 415
    blank2  <= not((not s_c8) or (not c7) or c5);
    nhblank <= not(blank1 or blank2);

    --------------------------------------------------------------
    -- hsync 5c — pulse pixels 336..367
    --------------------------------------------------------------
    nhsynca_5c      <= not(c5 or c4);             -- front porch
    nhsyncb_5c      <= not((not c5) or (not c4)); -- back porch
    nhsyncpulses_5c <= nhsynca_5c or nhsyncb_5c;

    --------------------------------------------------------------
    -- hsync 6c — pulse pixels 344..375 (delayed by 1/2 c3)
    -- X = NOR((not c4),(not c3)) = c4 AND c3
    --------------------------------------------------------------
    x               <= not((not c4) or (not c3));
    nhsynca_6c      <= not(c5 or x);
    nhsyncb_6c      <= not((not c5) or (not x));
    nhsyncpulses_6c <= nhsynca_6c or nhsyncb_6c;

    --------------------------------------------------------------
    -- Sync select — HIGH (= no pulse) outside the blanking window
    --------------------------------------------------------------
    nhsyncselect <= (not s_c8) or c7 or (not c6);

    -- Book pg 90: hsync = NOR(nc6, c7, nc8, nhsyncpulses) = not(nHSyncSelect or
    -- nHSyncPulses). hsync is therefore active-HIGH (1 during the sync pulse),
    -- the SAME polarity as vsync -- so the composite n_sync = NOR(vsync, hsync)
    -- in video_sync comes out as a correct active-LOW csync (LOW during any
    -- sync). Previously this was a bare OR (active-LOW hsync), which fed the
    -- wrong polarity into the composite NOR and inverted/suppressed it.
    hsync_5c <= not(nhsyncselect or nhsyncpulses_5c);
    hsync_6c <= not(nhsyncselect or nhsyncpulses_6c);

end architecture behavioral;
