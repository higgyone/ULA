----------------------------------------------------------------------
-- video_sync_tb — self-checking TB for the full video_sync stack
--
-- Drives the real gate-level hierarchy (video_sync -> horiz_timing +
-- master_horiz_counter + Vert_Line_counter(T_Structure) + the FF
-- library) at the real 7 MHz pixel clock and checks the border + vsync
-- decode end to end:
--   * border_n (vertical)   : sampled at c8=0 (~pixel 4) -- HIGH on display
--                            lines 0..191, LOW on border lines 192..311
--   * border_n (horizontal) : sampled at c8=1 (~pixel 304) -- LOW on EVERY
--                            line, incl. display lines, which exercises the
--                            c8 term (the old vertical-only decode wrongly
--                            held border_n HIGH here)
--   * vsync   : HIGH only on lines 248..251 (4-line PAL vsync)
--   * frame wrap at 312 (V 311 -> 0): decode returns to the line-0 state
--
-- The hsync/blank decode is already verified by master_horiz_counter_tb
-- and the CLAUDE.md "Verified Correct" list, so this TB covers the border
-- (both axes) and vsync paths.
--
-- Line tracking: one-time phase-lock at line 0's start. hsync_5c is
-- active-HIGH, so it sits inactive-LOW at pixel 0 right after reset --
-- that low level is the lock reference. Then count exactly 448 pixel
-- clocks per line. vsync and the vertical border_n term are functions of
-- V0..V8, sampled mid-line clear of the line-boundary carry ripple; the
-- horizontal border_n term is then checked by stepping into the c8=1
-- region of the same line.
--
-- Counter taps (exported for the rest of the ULA): a separate taps
-- process checks, on every falling clk_7_n edge after reset:
--   * c0_n..c8_n = NOT c0..c8 and v0_n..v8_n = NOT v0..v8
--   * c8..c0 steps by exactly 1 per pixel and wraps 447 -> 0
--   * v8..v0 (read mid-line) steps by exactly 1 per line and wraps 311 -> 0
-- so a crossed or missing tap shows up, not just a bad complement.
--
-- Runtime: ~315 lines x 64 us ~= 20 ms of gate-level sim (~30 s wall).
-- PASS = runs to the "video_sync_tb PASS" note with no assertion errors.
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity video_sync_tb is
end entity video_sync_tb;

architecture behavioral of video_sync_tb is

    constant t         : time    := 143 ns; -- 7 MHz pixel clock period
    constant pix_line  : integer := 448;    -- pixel clocks per scan line
    constant v_lines   : integer := 312;    -- lines per PAL field (0..311)
    constant last_line : integer := 315;    -- run a little past the 312 wrap
    constant c8_hi_off : integer := 300;    -- step from the ~pixel-4 sample into the c8=1 region (~pixel 304)

    signal clk_7_n   : std_logic := '0';
    signal reset     : std_logic := '1';
    signal hsync_5c  : std_logic;
    signal hsync_6c  : std_logic;
    signal hblank_n  : std_logic;
    signal vsync     : std_logic;
    signal border_n  : std_logic;
    signal border    : std_logic;
    signal sync_5c_n : std_logic;
    signal sync_6c_n : std_logic;
    signal sim_done  : boolean   := false;

    -- counter taps out of video_sync, bit n = cn / vn
    signal cv   : std_logic_vector(8 downto 0);
    signal cv_n : std_logic_vector(8 downto 0);
    signal vv   : std_logic_vector(8 downto 0);
    signal vv_n : std_logic_vector(8 downto 0);

    -- Waveform instrumentation (driven by the track process below).
    -- Add these to the wave window to read position and expected pulses:
    --   dbg_pixel : where we are within the line   (0..447)
    --   dbg_vline : which scan line   (0..311) -> tells you when vsync/
    --               border are due
    --   dbg_line  : absolute line since lock (lets you see frame number)
    --   dbg_exp_* : expected border_n/vsync for the current line, so you
    --               can line them up against the real outputs
    signal dbg_pixel       : integer range 0 to pix_line - 1 := 0;
    signal dbg_line        : integer                         := 0;
    signal dbg_vline       : integer range 0 to v_lines - 1  := 0;
    signal dbg_exp_nborder : std_logic                       := '0';
    signal dbg_exp_vsync   : std_logic                       := '0';

begin

    dut : entity work.video_sync(Behavioral)
        port map (
            clk_7_n   => clk_7_n,
            reset     => reset,
            tclk_a    => '0',
            hsync_5c  => hsync_5c,
            hsync_6c  => hsync_6c,
            hblank_n  => hblank_n,
            vsync     => vsync,
            border_n  => border_n,
            border    => border,
            sync_5c_n => sync_5c_n,
            sync_6c_n => sync_6c_n,
            c0        => cv(0),
            c0_n      => cv_n(0),
            c1        => cv(1),
            c1_n      => cv_n(1),
            c2        => cv(2),
            c2_n      => cv_n(2),
            c3        => cv(3),
            c3_n      => cv_n(3),
            c4        => cv(4),
            c4_n      => cv_n(4),
            c5        => cv(5),
            c5_n      => cv_n(5),
            c6        => cv(6),
            c6_n      => cv_n(6),
            c7        => cv(7),
            c7_n      => cv_n(7),
            c8        => cv(8),
            c8_n      => cv_n(8),
            v0        => vv(0),
            v0_n      => vv_n(0),
            v1        => vv(1),
            v1_n      => vv_n(1),
            v2        => vv(2),
            v2_n      => vv_n(2),
            v3        => vv(3),
            v3_n      => vv_n(3),
            v4        => vv(4),
            v4_n      => vv_n(4),
            v5        => vv(5),
            v5_n      => vv_n(5),
            v6        => vv(6),
            v6_n      => vv_n(6),
            v7        => vv(7),
            v7_n      => vv_n(7),
            v8        => vv(8),
            v8_n      => vv_n(8)
        );

    -- 7 MHz pixel clock (stops when the checker is done)
    clkgen : process is
    begin

        while not sim_done loop

            clk_7_n <= '0';
            wait for t / 2;
            clk_7_n <= '1';
            wait for t / 2;

        end loop;

        wait;

    end process clkgen;

    -- reset: assert for 50 ns at start, then release
    rstgen : process is
    begin

        reset <= '1';
        wait for 50 ns;
        reset <= '0';
        wait;

    end process rstgen;

    -- Counter taps: complements, C steps per pixel, V steps per line -------
    taps : process (clk_7_n, sim_done) is

        variable c_now    : integer;
        variable c_prev   : integer := -1;
        variable v_now    : integer;
        variable v_prev   : integer := -1;
        variable n_checks : integer := 0;
        variable valid    : boolean := false; -- taps seen fully defined once

    begin

        if (falling_edge(clk_7_n) and reset = '0') then
            if (is_x(cv) or is_x(cv_n) or is_x(vv) or is_x(vv_n)) then
                -- allowed only while the counters come out of reset; once
                -- they have been valid, an 'X' / 'U' tap is a wiring fault
                assert not valid
                    report "FAIL taps: undefined tap after start-up (c = " & to_string(cv)
                           & ", c_n = " & to_string(cv_n) & ", v = " & to_string(vv)
                           & ", v_n = " & to_string(vv_n) & ")"
                    severity failure;
            else
                valid := true;

                assert cv_n = not cv
                    report "FAIL taps: c8_n..c0_n /= NOT c8..c0 (c = " & to_string(cv)
                           & ", c_n = " & to_string(cv_n) & ")"
                    severity failure;
                assert vv_n = not vv
                    report "FAIL taps: v8_n..v0_n /= NOT v8..v0 (v = " & to_string(vv)
                           & ", v_n = " & to_string(vv_n) & ")"
                    severity failure;

                c_now := to_integer(unsigned(cv));

                if (c_prev >= 0) then
                    assert c_now = (c_prev + 1) mod pix_line
                        report "FAIL taps: c8..c0 went " & integer'image(c_prev) & " -> "
                               & integer'image(c_now)
                        severity failure;
                end if;

                c_prev := c_now;

                -- V is stable mid-line, well clear of the line-boundary ripple
                if (c_now = 200) then
                    v_now := to_integer(unsigned(vv));

                    if (v_prev >= 0) then
                        assert v_now = (v_prev + 1) mod v_lines
                            report "FAIL taps: v8..v0 went " & integer'image(v_prev)
                                   & " -> " & integer'image(v_now)
                            severity failure;
                    end if;

                    v_prev := v_now;
                end if;

                n_checks := n_checks + 1;
            end if;
        end if;

        if (sim_done'event and sim_done) then
            -- the run is ~316 lines x 448 pixels: the taps must have been
            -- checked on (nearly) all of them, or the checks were skipped
            assert n_checks > (last_line - 2) * pix_line
                report "FAIL taps: only " & integer'image(n_checks)
                       & " samples had defined taps"
                severity failure;
            report "video_sync_tb taps PASS: complements, C per pixel and V per line ("
                   & integer'image(n_checks) & " samples)"
                severity note;
        end if;

    end process taps;

    -- Border (H+V) + vsync checker --------------------------------------
    check : process is

        variable line  : integer := 0; -- absolute line count since lock
        variable vline : integer := 0; -- line mod 312 = expected V count
        variable expb  : std_logic;    -- expected border_n
        variable expv  : std_logic;    -- expected vsync

        procedure wait_cycles (
            n : integer
        ) is
        begin

            for i in 1 to n loop

                wait until rising_edge(clk_7_n);

            end loop;

        end procedure wait_cycles;

    begin

        wait until reset = '0';
        -- one-time phase lock to line 0's start: hsync_5c is active-HIGH,
        -- so '0' is its inactive level, already true at pixel 0 right
        -- after reset. Step a few pixels in so the per-line sample sits
        -- clear of the line-boundary carry ripple.
        wait until rising_edge(clk_7_n) and hsync_5c = '0';
        wait_cycles(4);
        line := 0;

        loop

            vline := line mod v_lines;

            if (vline <= 191) then
                expb := '1';
            else
                expb := '0';
            end if;

            if (vline >= 248 and vline <= 251) then
                expv := '1';
            else
                expv := '0';
            end if;

            -- (1) vertical check at c8=0 (~pixel 4): border_n follows the V decode
            assert border_n = expb
                report "border_n (c8=0) mismatch at V=" & integer'image(vline) &
                       " (abs line " & integer'image(line) & "): expected " &
                       std_logic'image(expb) & ", got " & std_logic'image(border_n)
                severity error;

            assert border = not border_n
                report "border is not the complement of border_n at V=" & integer'image(vline)
                severity error;

            assert vsync = expv
                report "vsync mismatch at V=" & integer'image(vline) &
                       ": expected " & std_logic'image(expv) &
                       ", got " & std_logic'image(vsync)
                severity error;

            -- heartbeat at the interesting boundaries (and start of frame)
            if (vline = 0   or vline = 191 or vline = 192 or
                vline = 247 or vline = 248 or vline = 251 or vline = 252) then
                report "V=" & integer'image(vline) &
                       "  border_n=" & std_logic'image(border_n) &
                       "  vsync=" & std_logic'image(vsync)
                    severity note;
            end if;

            -- (2) horizontal check: step into the c8=1 region (~pixel 304,
            -- right border) and re-read border_n. With c8=1 the border NOR is
            -- forced, so border_n MUST be '0' on EVERY line -- including display
            -- lines 0..191, where the old vertical-only decode wrongly held it
            -- '1'. This is the regression check for the horizontal c8 term.
            wait_cycles(C8_HI_OFF);                                                                 -- ~pixel 4 -> ~pixel 304 (c8=1)

            assert border_n = '0'
                report "border_n (c8=1 horizontal border) should be '0' at V=" &
                       integer'image(vline) & " (abs line " &
                       integer'image(line) & "), got " & std_logic'image(border_n)
                severity error;

            assert border = '1'
                report "border (c8=1 horizontal border) should be '1' at V=" & integer'image(vline)
                severity error;

            wait_cycles(PIX_LINE - C8_HI_OFF);                                                      -- finish the line, restore phase
            line := line + 1;

            if (line > last_line) then
                report "video_sync_tb PASS: H+V border + vsync correct through " &
                       integer'image(line) & " lines (border_n: V-edge @192, " &
                       "H-border via c8 @>=256; vsync 248..251; frame wrap @312)"
                    severity note;
                sim_done <= true;
                wait;
            end if;

        end loop;

    end process check;

    -- Waveform instrumentation: a free-running pixel/line tracker so the
    -- current position can be read straight off the wave window. Locks to
    -- line 0's start the same way the checker does (hsync_5c inactive-LOW
    -- at pixel 0), then counts 448 pixels per line, incrementing the line
    -- at each wrap. Purely for visibility — it drives no asserts and never
    -- affects PASS/FAIL. dbg_pixel ~= the real pixel (+/- a clock of lock
    -- slop), so hsync (pixels 336..367) and blank (320..415) line up with
    -- it; dbg_vline says which line, so vsync (248..251) / border edge
    -- (192) are easy to anticipate.
    track : process is

        variable px : integer := 0;
        variable ln : integer := 0;

    begin

        wait until reset = '0';
        wait until rising_edge(clk_7_n) and hsync_5c = '0';  -- ~pixel 0 of line 0 (inactive-LOW)

        loop

            dbg_pixel <= px;
            dbg_line  <= ln;
            dbg_vline <= ln mod v_lines;
            wait until rising_edge(clk_7_n);

            if (px = pix_line - 1) then
                px := 0;
                ln := ln + 1;
            else
                px := px + 1;
            end if;

        end loop;

    end process track;

    -- expected vertical-decode regions, derived from the tracked line, so
    -- they can sit next to border_n/vsync in the wave window. NOTE
    -- dbg_exp_nborder is the VERTICAL (c8=0) expectation only; at c8=1
    -- pixels the real border_n is '0' regardless (horizontal border).
    dbg_exp_nborder <= '1' when dbg_vline <= 191 else
                       '0';
    dbg_exp_vsync   <= '1' when (dbg_vline >= 248 and dbg_vline <= 251) else
                       '0';

end architecture behavioral;
