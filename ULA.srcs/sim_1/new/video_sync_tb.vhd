----------------------------------------------------------------------
-- video_sync_tb — self-checking TB for the full video_sync stack
--
-- Drives the real gate-level hierarchy (video_sync -> horiz_timing +
-- master_horiz_counter + Vert_Line_counter(T_Structure) + the FF
-- library) at the real 7 MHz pixel clock and checks the VERTICAL decode
-- end to end:
--   * nBorder : HIGH on lines 0..191, LOW on border lines 192..311
--   * vsync   : HIGH only on lines 248..251 (4-line PAL vsync)
--   * frame wrap at 312 (V 311 -> 0): decode returns to the line-0 state
--
-- The horizontal decode (hsync/blank) is already verified by
-- master_horiz_counter_tb and is on the CLAUDE.md "Verified Correct"
-- list, so this TB focuses on the vertical path that the T_Structure
-- switch exercises.
--
-- Line tracking: one-time phase-lock at line 0's start. hsync_5c is
-- active-LOW, so it sits inactive-HIGH at pixel 0 right after reset --
-- that high level is the lock reference. Then count exactly 448 pixel
-- clocks per line. nBorder/vsync are purely vertical (functions of
-- V0..V8), so they are sampled mid-line, clear of the line-boundary
-- carry ripple.
--
-- Runtime: ~315 lines x 64 us ~= 20 ms of gate-level sim (~30 s wall).
-- PASS = runs to the "video_sync_tb PASS" note with no assertion errors.
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity video_sync_tb is
end video_sync_tb;

architecture Behavioral of video_sync_tb is
    constant T         : time    := 143 ns;   -- 7 MHz pixel clock period
    constant PIX_LINE  : integer := 448;      -- pixel clocks per scan line
    constant V_LINES   : integer := 312;      -- lines per PAL field (0..311)
    constant LAST_LINE : integer := 315;      -- run a little past the 312 wrap

    signal clk_7    : std_logic := '0';
    signal reset    : std_logic := '1';
    signal hsync_5c : std_logic;
    signal hsync_6c : std_logic;
    signal nHblank  : std_logic;
    signal vsync    : std_logic;
    signal nBorder  : std_logic;
    signal sync_5c  : std_logic;
    signal sync_6c  : std_logic;
    signal sim_done : boolean := false;

    -- Waveform instrumentation (driven by the track process below).
    -- Add these to the wave window to read position and expected pulses:
    --   dbg_pixel : where we are within the line   (0..447)
    --   dbg_vline : which scan line   (0..311) -> tells you when vsync/
    --               border are due
    --   dbg_line  : absolute line since lock (lets you see frame number)
    --   dbg_exp_* : expected nBorder/vsync for the current line, so you
    --               can line them up against the real outputs
    signal dbg_pixel       : integer range 0 to PIX_LINE - 1 := 0;
    signal dbg_line        : integer := 0;
    signal dbg_vline       : integer range 0 to V_LINES - 1  := 0;
    signal dbg_exp_nborder : std_logic := '0';
    signal dbg_exp_vsync   : std_logic := '0';
begin

    dut: entity work.video_sync(Behavioral)
        port map(
            clk      => clk_7,
            tclk_a   => '0',
            reset    => reset,
            hsync_5c => hsync_5c,
            hsync_6c => hsync_6c,
            nHblank  => nHblank,
            vsync    => vsync,
            nBorder  => nBorder,
            sync_5c  => sync_5c,
            sync_6c  => sync_6c
        );

    -- 7 MHz pixel clock (stops when the checker is done)
    clkgen: process
    begin
        while not sim_done loop
            clk_7 <= '0';
            wait for T / 2;
            clk_7 <= '1';
            wait for T / 2;
        end loop;
        wait;
    end process;

    -- reset: assert for 50 ns at start, then release
    rstgen: process
    begin
        reset <= '1';
        wait for 50 ns;
        reset <= '0';
        wait;
    end process;

    -- Vertical-decode checker -------------------------------------------
    check: process
        variable line  : integer := 0;   -- absolute line count since lock
        variable vline : integer := 0;   -- line mod 312 = expected V count
        variable expB  : std_logic;      -- expected nBorder
        variable expV  : std_logic;      -- expected vsync

        procedure wait_cycles(n : integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk_7);
            end loop;
        end procedure;
    begin
        wait until reset = '0';
        -- one-time phase lock to line 0's start: hsync_5c is active-LOW,
        -- so '1' is its inactive level, already true at pixel 0 right
        -- after reset. Step a few pixels in so the per-line sample sits
        -- clear of the line-boundary carry ripple.
        wait until rising_edge(clk_7) and hsync_5c = '1';
        wait_cycles(4);
        line := 0;

        loop
            vline := line mod V_LINES;

            if vline <= 191 then expB := '1'; else expB := '0'; end if;
            if vline >= 248 and vline <= 251 then expV := '1'; else expV := '0'; end if;

            assert nBorder = expB
                report "nBorder mismatch at V=" & integer'image(vline) &
                       " (abs line " & integer'image(line) & "): expected " &
                       std_logic'image(expB) & ", got " & std_logic'image(nBorder)
                severity error;

            assert vsync = expV
                report "vsync mismatch at V=" & integer'image(vline) &
                       ": expected " & std_logic'image(expV) &
                       ", got " & std_logic'image(vsync)
                severity error;

            -- heartbeat at the interesting boundaries (and start of frame)
            if vline = 0   or vline = 191 or vline = 192 or
               vline = 247 or vline = 248 or vline = 251 or vline = 252 then
                report "V=" & integer'image(vline) &
                       "  nBorder=" & std_logic'image(nBorder) &
                       "  vsync="   & std_logic'image(vsync)
                    severity note;
            end if;

            wait_cycles(PIX_LINE);   -- advance exactly one line, same phase
            line := line + 1;

            if line > LAST_LINE then
                report "video_sync_tb PASS: vertical decode correct through " &
                       integer'image(line) & " lines (nBorder edge @192, " &
                       "vsync 248..251, frame wrap @312 verified)"
                    severity note;
                sim_done <= true;
                wait;
            end if;
        end loop;
    end process;

    -- Waveform instrumentation: a free-running pixel/line tracker so the
    -- current position can be read straight off the wave window. Locks to
    -- line 0's start the same way the checker does (hsync_5c inactive-HIGH
    -- at pixel 0), then counts 448 pixels per line, incrementing the line
    -- at each wrap. Purely for visibility — it drives no asserts and never
    -- affects PASS/FAIL. dbg_pixel ~= the real pixel (+/- a clock of lock
    -- slop), so hsync (pixels 336..367) and blank (320..415) line up with
    -- it; dbg_vline says which line, so vsync (248..251) / border edge
    -- (192) are easy to anticipate.
    track: process
        variable px : integer := 0;
        variable ln : integer := 0;
    begin
        wait until reset = '0';
        wait until rising_edge(clk_7) and hsync_5c = '1';  -- ~pixel 0 of line 0
        loop
            dbg_pixel <= px;
            dbg_line  <= ln;
            dbg_vline <= ln mod V_LINES;
            wait until rising_edge(clk_7);
            if px = PIX_LINE - 1 then
                px := 0;
                ln := ln + 1;
            else
                px := px + 1;
            end if;
        end loop;
    end process;

    -- expected vertical-decode regions, derived from the tracked line
    -- (same rule the checker uses) so they can sit next to nBorder/vsync
    -- in the wave window
    dbg_exp_nborder <= '1' when dbg_vline <= 191 else '0';
    dbg_exp_vsync   <= '1' when (dbg_vline >= 248 and dbg_vline <= 251) else '0';

end Behavioral;
