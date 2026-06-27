----------------------------------------------------------------------
-- video_sync — top-level timing for the ULA recreation
--
-- Instantiates horiz_timing (which owns the master horizontal counter)
-- and Vert_Line_counter, then derives:
--   * vertical border       (nBorder)        — Chris Smith pg 92
--   * vertical sync pulse   (vsync)          — Chris Smith pg 92
--   * composite sync        (sync_5c/sync_6c)
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
        tclk_a   : in  std_logic;    -- retained for backwards compatibility; unused (horiz_timing ties internally to '0')
        reset    : in  std_logic;
        hsync_5c : out std_logic;
        hsync_6c : out std_logic;
        nHblank  : out std_logic;
        vsync    : out std_logic;
        nBorder  : out std_logic;
        sync_5c  : out std_logic;
        sync_6c  : out std_logic
    );
end video_sync;

architecture Behavioral of video_sync is
    -- horizontal-timing outputs we consume locally
    signal h_5c    : std_logic;
    signal h_6c    : std_logic;
    signal h_blank : std_logic;
    signal hc6     : std_logic;
    signal hcrst   : std_logic;

    -- vertical counter taps consumed by the decode (true form)
    signal v2, v8 : std_logic;

    -- vertical border intermediates
    signal VBorderLower, VBorderUpper : std_logic;

    -- complemented V taps (qbar) from the counter, used by the
    -- nBorder and vsync NORs
    signal v3_n, v4_n, v5_n, v6_n, v7_n : std_logic;

    -- composite-sync intermediates
    signal sVsync : std_logic;
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
            HCrst        => hcrst,
            Clk_HC6      => hc6,
            -- only the taps the decode actually consumes are wired;
            -- the rest default to open (the counter still counts them).
            v2 => v2, v8 => v8,
            -- complemented taps straight from the counter's qbar outputs
            -- (no extra inverters in video_sync)
            V3_n => v3_n, V4_n => v4_n, V5_n => v5_n,
            V6_n => v6_n, V7_n => v7_n,
            Vrst         => open
        );

    ----------------------------------------------------------------
    -- Vertical border (Chris Smith pg 92)
    -- nBorder LOW during border lines (192..311), HIGH during 0..191.
    ----------------------------------------------------------------
    VBorderLower <= not(v6_n or v7_n);           -- v6 AND v7 -> lines 192..255
    VBorderUpper <= v8;                          --           -> lines 256..311
    nBorder      <= not(VBorderLower or VBorderUpper);

    ----------------------------------------------------------------
    -- Vertical sync pulse — 4 lines wide, lines 248..251
    -- sVsync = NOR((not v7..v3), v2)
    -- The v2 = 0 term limits the pulse to 4 lines; without it the
    -- pulse would extend to lines 252..255 as well.
    -- v3_n..v7_n are the counter's qbar taps (wired in the port map),
    -- so no local inverters are needed here.
    ----------------------------------------------------------------
    sVsync <= not(v7_n or v6_n or v5_n or v4_n or v3_n or v2);

    ----------------------------------------------------------------
    -- Composite sync (active LOW combines hsync + vsync)
    ----------------------------------------------------------------
    sync_5c <= h_5c nor sVsync;
    sync_6c <= h_6c nor sVsync;
    vsync   <= sVsync;
end Behavioral;
