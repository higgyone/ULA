----------------------------------------------------------------------
-- video_sync — top-level timing for the ULA recreation
--
-- Instantiates horiz_timing (which owns the master horizontal counter)
-- and Vert_Line_counter, then derives:
--   * border (H + V)        (nBorder)        — Chris Smith pg 92
--   * vertical sync pulse   (vsync)          — Chris Smith pg 92
--   * composite sync        (n_sync_5c/n_sync_6c)
--
-- The horizontal sync and blanking signals (hsync_5c/hsync_6c/nHblank)
-- come directly from horiz_timing and are passed through.
--
-- All combinational logic uses NORs with inverted inputs (the Ferranti
-- gate style), with named intermediate signals matching the schematic.
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity video_sync is
    Port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        tclk_a   : in  std_logic;    -- retained for backwards compatibility; unused (horiz_timing ties internally to '0')
        hsync_5c : out std_logic;
        hsync_6c : out std_logic;
        nHblank  : out std_logic;
        vsync    : out std_logic;
        nBorder  : out std_logic;
        n_sync_5c : out std_logic;   -- composite active-low sync = NOR(vsync, hsync), issue-5 hsync timing
        n_sync_6c : out std_logic    -- composite active-low sync = NOR(vsync, hsync), issue-6 hsync timing
    );
end video_sync;

architecture Behavioral of video_sync is
    -- horizontal-timing outputs we consume locally
    signal h_5c    : std_logic;
    signal h_6c    : std_logic;
    signal h_blank : std_logic;
    signal hc6     : std_logic;
    signal hcrst   : std_logic;

    -- horizontal counter MSB from horiz_timing: HIGH for pixels 256..447,
    -- i.e. the horizontal border/blanking region. Gates the border decode
    -- so the display window is the central 256 columns, not the whole line.
    signal c8      : std_logic;

    -- vertical counter taps consumed by the decode (true form)
    signal v2, v8 : std_logic;

    -- vertical border intermediates
    signal v_border_lower, v_border_upper : std_logic;

    -- complemented V taps (qbar) from the counter, used by the
    -- nBorder and vsync NORs
    signal v3_n, v4_n, v5_n, v6_n, v7_n : std_logic;

    -- composite-sync intermediates
    signal s_vsync : std_logic;
begin
    ----------------------------------------------------------------
    -- Horizontal timing block (owns master_horiz_counter)
    ----------------------------------------------------------------
    ht: entity work.horiz_timing(Behavioral)
        port map(
            clk      => clk,
            reset    => reset,
            hsync_5c => h_5c,
            hsync_6c => h_6c,
            nHblank  => h_blank,
            c8       => c8,          -- H-counter MSB, for the border decode below
            clk_hc6  => hc6,
            hc_rst   => hcrst
        );

    hsync_5c <= h_5c;
    hsync_6c <= h_6c;
    nHblank  <= h_blank;

    ----------------------------------------------------------------
    -- Vertical line counter (clocked by clk_hc6, advanced by hc_rst)
    ----------------------------------------------------------------
    vlc: entity work.Vert_Line_counter(T_Structure)
        port map(
            hcrst        => hcrst,
            clk_hc6      => hc6,
            -- only the taps the decode actually consumes are wired;
            -- the rest default to open (the counter still counts them).
            v2 => v2, v8 => v8,
            -- complemented taps straight from the counter's qbar outputs
            -- (no extra inverters in video_sync)
            v3_n => v3_n, v4_n => v4_n, v5_n => v5_n,
            v6_n => v6_n, v7_n => v7_n,
            vrst         => open
        );

    ----------------------------------------------------------------
    -- Border decode (Chris Smith pg 92)
    --
    --   nBorder = NOR(c8, v8, v6·v7)        (book equation)
    --
    -- The border is the frame AROUND the central 256x192 display, so it
    -- must be gated BOTH horizontally and vertically. nBorder is HIGH
    -- (display, border off) only when all three terms are 0:
    --
    --   c8        H-counter MSB. 0 for pixels 0..255 (display columns),
    --             1 for pixels 256..447 (right border + H-blank + left
    --             border). This is the HORIZONTAL gate.
    --   v8        bit8(256): V lines 256..311 -> vertical border.
    --   v6·v7     bits 7(128)+6(64): V lines 192..255 -> vertical border.
    --
    -- The two vertical pieces are OR'd because no single AND of V bits
    -- selects the whole 192..311 range. Written as NORs of qbar taps to
    -- match the ULA's NOR-gate silicon: v6 AND v7 = NOR(v6_n, v7_n).
    --
    -- Net effect: nBorder is HIGH only inside the central display window
    -- (c8=0 AND V line 0..191); it goes LOW across the whole horizontal
    -- border on every line, and across all of V lines 192..311.
    ----------------------------------------------------------------
    v_border_lower <= not(v6_n or v7_n);           -- v6 AND v7 -> V lines 192..255
    v_border_upper <= v8;                          --           -> V lines 256..311
    nBorder      <= not(c8 or v_border_lower or v_border_upper);  -- + c8 = horizontal border gate

    ----------------------------------------------------------------
    -- Vertical sync pulse — 4 lines wide, lines 248..251
    --
    -- s_vsync = NOR(v7_n, v6_n, v5_n, v4_n, v3_n, v2)
    -- A NOR is high only when EVERY input is 0, which here means:
    --   v7=v6=v5=v4=v3 = 1  -> 128+64+32+16+8 = 248
    --   v2            = 0  -> bit2 (value 4) must be clear
    --   v1, v0          free
    -- so the pulse is high for 248 + {0,1,2,3} = lines 248..251:
    --
    --   line  v7 v6 v5 v4 v3 v2 v1 v0
    --   248    1  1  1  1  1  0  0  0
    --   249    1  1  1  1  1  0  0  1
    --   250    1  1  1  1  1  0  1  0
    --   251    1  1  1  1  1  0  1  1
    --
    -- The v2 = 0 term is what limits it to 4 lines: drop it and the
    -- condition becomes "bits 7..3 set, bits 2/1/0 anything" = lines
    -- 248..255 (8 lines). v3_n..v7_n are the counter's qbar taps (wired
    -- in the port map), so no local inverters are needed here.
    ----------------------------------------------------------------
    s_vsync <= not(v7_n or v6_n or v5_n or v4_n or v3_n or v2);

    ----------------------------------------------------------------
    -- Composite sync — n_sync = NOR(vsync, hsync), active LOW
    --
    -- A TV expects a single sync signal, so the horizontal sync (h_5c or
    -- h_6c, from horiz_timing) and the vertical sync (s_vsync) are merged
    -- with a NOR into one composite waveform. The `n_` prefix marks it
    -- active LOW. vsync is also broken out on its own for consumers that
    -- want it separately. The 5c/6c pair carry the two hsync timings
    -- (issue-5 vs issue-6 ULA); they differ ONLY in which hsync is folded
    -- in here.
    ----------------------------------------------------------------
    n_sync_5c <= h_5c nor s_vsync;   -- NOR(vsync, hsync_5c)
    n_sync_6c <= h_6c nor s_vsync;   -- NOR(vsync, hsync_6c)
    vsync     <= s_vsync;
end Behavioral;
