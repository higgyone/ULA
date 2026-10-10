----------------------------------------------------------------------------------
-- yuv_video_tb — self-checking TB for the complete analogue video strand
-- (pal_v_burst -> yuv_control_signals -> yuv, wired by yuv_video).
--
-- The three cells each have their own TB. This one proves the WIRING: that
-- every join carries the right signal, so the top-level inputs (pixel colour,
-- BRIGHT, sync, counter taps) produce the right y_n / u / v end to end.
--
-- ── The reference model works at COLOUR level, not gate level ────────
-- It does not reuse any cell's logic. It goes straight from the pixel colour
-- to the conducting sinks, using the meaning of each family:
--
--   Y  sync sink on unless sync asserted; each gun draws its normal or
--      BRIGHT current; clamp at 259 mV (only bright white reaches it).
--   U  fixed black sink always on; red / green sinks on when that colour is
--      ABSENT, blue sink on when blue is PRESENT (the U coefficient signs);
--      burst sink on except in the burst window. Black is encoded as white.
--   V  on an inverted line (v0='1') every colour bit is inverted first (the
--      V-switch); black in that switched domain is encoded as white. Then red
--      sink on when red PRESENT, green / blue sinks on when ABSENT (the V
--      coefficient signs). burst_star sink on in the burst window on normal
--      lines only; burst_star_n sink on except in the window on inverted lines.
--
--   mV = 4300 - sum of (I_uA x R + 500) / 1000 per conducting sink, the same
--   half-up rounding used to derive yuv's constants. The currents are the
--   specification (see yuv.vhd).
--
-- A crossed or tied-off wire breaks the match somewhere in the sweep. Checked
-- by deliberately breaking yuv_video (mutation testing): CAUGHT are
-- red_i <-> green_i, red_ii_n <-> green_ii_n, blue_star_n fed red_star, hl_n
-- fed the raw hl, timing tied high, v0 tied low, c4 tied low, and the latch's
-- sync_n tied low.
--
-- Joins NO test at the outputs can see, because swapping them gives the same
-- function:
--   - sync_i_n vs raw sync_n into yuv: the same value by design.
--   - burst_star <-> burst_star_n: the two V burst sinks draw IDENTICAL
--     currents (309 uA), and every reachable state has both on, both off,
--     or exactly one on.
--   - any rearrangement of c4, c5, c6, c7_n, c8_n: all five feed ONE NOR,
--     which is symmetric. Their polarity is fixed at the SOURCE (the counter
--     taps at the top level), not in this block.
--
-- ── What it proves ───────────────────────────────────────────────────
--   1. SWEEP: both line parities x all 32 codes of c8..c4 x sync x BRIGHT x
--      all 8 colours, y_n / u / v each checked against the model.
--      Inside the burst window (code 24) only the one real state is driven:
--      black pixel, sync NOT asserted. The rest are impossible and skipped:
--        - a coloured pixel: blanking makes it black (on even lines some
--          colours would drive v below 0 mV, outside millivolts_t; see yuv_tb)
--        - sync asserted: sync ends at pixel 367, the burst starts at 384
--      That is 2 parities x (16 sync + 14 coloured) = 60, asserted exactly.
--   2. LANDMARKS: the book's voltages, reached from the real top-level inputs:
--      Y black 2449, bright white 259, sync 4300; U zero 2015 (black AND
--      white), yellow 3026, blue 1012, burst 2925; V zero 1925, red 496 /
--      cyan 3342 on a normal line and swapped on an inverted line (book
--      0.495 V for red and inverted cyan), burst 967 even / 2883 odd.
--   3. PAL ALTERNATION: for every colour, Y and U are identical on both line
--      parities and V's two values sum to 2 x zero (3850) within +/-15 mV.
--   4. PARITY LATCH: v0 moving mid-line (sync_n high) does not change V; it
--      is picked up once sync_n goes low.
--
-- ── Stimulus ORDER matters (found writing this TB) ───────────────────
--   The stimulus follows the real ULA's order of events: the pixel is BLANKED
--   before the burst window opens, and the parity only changes during sync,
--   OUTSIDE the window. Changing the colour and the counter in the same
--   instant is not just unrealistic, it is FATAL: the burst path is a couple
--   of gates, the colour path is the 4-NOR V-switch plus black_star, so for a
--   few delta cycles yuv sees "burst on + previous colour", the V sum dips
--   below 0 mV and the run dies with a bound-check failure in yuv.vhd. The
--   same applies at the top level: the real counters give the right order,
--   but a hand-driven stimulus must too.
--
--   Sync during the burst is fatal for a related reason: a HAZARD in the
--   gate-level parity latch (data_latch_1_bit). When its enable (sync_n)
--   falls while holding q = '0', the two input NORs both act on the old b_o,
--   and for one tg (1 ns) q and q_bar are BOTH '0', with d unchanged. timing
--   (= q_bar) blips, the V-switch passes through wrong colour patterns, and
--   with the burst sinks on the V sum dips below zero. Harmless in the real
--   ULA, since sync and burst never overlap, and outside the burst window the
--   worst V sum is 496 mV, so a blip during sync cannot go negative.
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

library work;
    use work.yuv_levels_pkg.all;

entity yuv_video_tb is
end entity yuv_video_tb;

architecture behavioral of yuv_video_tb is

    constant settle : time := 20 ns; -- > worst-case settle incl. the parity latch's after-tg

    -- the one c8..c4 code that opens the burst window: c8 c7 c6 c5 c4 = 1 1 0 0 0
    constant burst_code : integer := 24;

    -- ── Reference data: the CURRENTS (microamps) and resistors ─────────
    constant v_min_y : integer := 259; -- Y saturation floor

    constant r_y_ohms      : integer := 3100;
    constant i_sync_ua     : integer := 597;
    constant i_red_ua      : integer := 178;
    constant i_red_br_ua   : integer := 234;
    constant i_green_ua    : integer := 348;
    constant i_green_br_ua : integer := 457;
    constant i_blue_ua     : integer := 92;
    constant i_blue_br_ua  : integer := 118;

    constant r_u_ohms     : integer := 1550;
    constant i_black_u_ua : integer := 235;
    constant i_red_u_ua   : integer := 216;
    constant i_green_u_ua : integer := 431;
    constant i_blue_u_ua  : integer := 652;
    constant i_burst_u_ua : integer := 587;

    constant r_v_ohms       : integer := 3100;
    constant i_red_v_ua     : integer := 457;
    constant i_green_v_ua   : integer := 383;
    constant i_blue_v_ua    : integer := 78;
    constant i_burst_v_ua   : integer := 309;
    constant i_burst_n_v_ua : integer := 309;

    constant v_zero_v   : integer := 1925; -- V zero point
    constant v_pair_tol : integer := 15;   -- mV; colour pairs come in ~12 mV low

    -- Spectrum colour numbering: bit 0 = blue, bit 1 = red, bit 2 = green

    type colour_names_t is array (0 to 7) of string(1 to 7);

    constant colour_name : colour_names_t :=
    (
        "black  ",
        "blue   ",
        "red    ",
        "magenta",
        "green  ",
        "cyan   ",
        "yellow ",
        "white  "
    );

    -- DUT inputs
    signal red    : std_logic := '0';
    signal green  : std_logic := '0';
    signal blue   : std_logic := '0';
    signal hl     : std_logic := '0';
    signal sync_n : std_logic := '1';
    signal c4     : std_logic := '0';
    signal c5     : std_logic := '0';
    signal c6     : std_logic := '0';
    signal c7_n   : std_logic := '1';
    signal c8_n   : std_logic := '1';
    signal v0     : std_logic := '0';

    -- DUT outputs. MUST be millivolts_t to match the ports (GHDL rejects a
    -- plain INTEGER actual on a constrained scalar out port; xsim does not).
    signal y_n : millivolts_t;
    signal u   : millivolts_t;
    signal v   : millivolts_t;

    signal checks : integer := 0;

    -- bit k of n as std_logic

    function bit_of (
        n : integer;
        k : integer
    ) return std_logic is
    begin

        if ((n / (2 ** k)) mod 2 = 1) then
            return '1';
        end if;

        return '0';

    end function bit_of;

    -- one sink's millivolt contribution, rounded half up

    function contrib (
        i_ua   : integer;
        r_ohms : integer
    ) return integer is
    begin

        return (i_ua * r_ohms + 500) / 1000;

    end function contrib;

    -- Y reference. hl is BRIGHT, ACTIVE HIGH at this level.

    function ref_y (
        sync_v : std_logic;
        hl_v   : std_logic;
        col    : integer
    ) return integer is

        variable total : integer := 0;
        variable raw   : integer;

    begin

        if (sync_v = '1') then -- sync NOT asserted: sink on
            total := total + contrib(i_sync_ua, r_y_ohms);
        end if;

        if (bit_of(col, 1) = '1') then
            if (hl_v = '1') then
                total := total + contrib(i_red_br_ua, r_y_ohms);
            else
                total := total + contrib(i_red_ua, r_y_ohms);
            end if;
        end if;

        if (bit_of(col, 2) = '1') then
            if (hl_v = '1') then
                total := total + contrib(i_green_br_ua, r_y_ohms);
            else
                total := total + contrib(i_green_ua, r_y_ohms);
            end if;
        end if;

        if (bit_of(col, 0) = '1') then
            if (hl_v = '1') then
                total := total + contrib(i_blue_br_ua, r_y_ohms);
            else
                total := total + contrib(i_blue_ua, r_y_ohms);
            end if;
        end if;

        raw := 4300 - total;

        if (raw < v_min_y) then
            return v_min_y;
        end if;

        return raw;

    end function ref_y;

    -- U reference. Does not depend on line parity.

    function ref_u (
        col   : integer;
        burst : boolean
    ) return integer is

        variable c     : integer;
        variable total : integer;

    begin

        c := col;

        if (c = 0) then
            c := 7; -- black encoded as white
        end if;

        total := contrib(i_black_u_ua, r_u_ohms); -- always on

        if (bit_of(c, 1) = '0') then -- red ABSENT (U coeff negative)
            total := total + contrib(i_red_u_ua, r_u_ohms);
        end if;

        if (bit_of(c, 2) = '0') then -- green ABSENT (U coeff negative)
            total := total + contrib(i_green_u_ua, r_u_ohms);
        end if;

        if (bit_of(c, 0) = '1') then -- blue PRESENT (U coeff positive)
            total := total + contrib(i_blue_u_ua, r_u_ohms);
        end if;

        if (not burst) then -- burst sink switches OFF in the window
            total := total + contrib(i_burst_u_ua, r_u_ohms);
        end if;

        return 4300 - total;

    end function ref_u;

    -- V reference. odd = inverted line (v0 = '1').

    function ref_v (
        col   : integer;
        odd   : boolean;
        burst : boolean
    ) return integer is

        variable c     : integer;
        variable total : integer := 0;

    begin

        c := col;

        if (odd) then
            c := 7 - c; -- V-switch: every colour bit inverted
        end if;

        if (c = 0) then
            c := 7; -- black (in the switched domain) encoded as white
        end if;

        if (bit_of(c, 1) = '1') then -- red PRESENT (V coeff positive)
            total := total + contrib(i_red_v_ua, r_v_ohms);
        end if;

        if (bit_of(c, 2) = '0') then -- green ABSENT (V coeff negative)
            total := total + contrib(i_green_v_ua, r_v_ohms);
        end if;

        if (bit_of(c, 0) = '0') then -- blue ABSENT (V coeff negative)
            total := total + contrib(i_blue_v_ua, r_v_ohms);
        end if;

        if (burst and not odd) then -- burst_star: on in the window, normal lines
            total := total + contrib(i_burst_v_ua, r_v_ohms);
        end if;

        if (not (burst and odd)) then -- burst_star_n: off in the window, inverted lines
            total := total + contrib(i_burst_n_v_ua, r_v_ohms);
        end if;

        return 4300 - total;

    end function ref_v;

begin

    dut : entity work.yuv_video(structural)
        port map (
            red    => red,
            green  => green,
            blue   => blue,
            hl     => hl,
            sync_n => sync_n,
            c4     => c4,
            c5     => c5,
            c6     => c6,
            c7_n   => c7_n,
            c8_n   => c8_n,
            v0     => v0,
            y_n    => y_n,
            u      => u,
            v      => v
        );

    stim : process is

        variable checks_v : integer := 0;
        variable skipped  : integer := 0;
        variable odd      : boolean;
        variable in_burst : boolean;

        -- captured levels for the alternation check
        variable y_even : integer;
        variable u_even : integer;
        variable v_even : integer;

        -- drive c8..c4 from a 5-bit code (bit 4 = c8 ... bit 0 = c4)

        procedure set_code (
            code : in integer
        ) is
        begin

            c4   <= bit_of(code, 0);
            c5   <= bit_of(code, 1);
            c6   <= bit_of(code, 2);
            c7_n <= not bit_of(code, 3);
            c8_n <= not bit_of(code, 4);

        end procedure set_code;

        -- capture a line parity: sync_n low (latch transparent), then high (held)

        procedure latch_parity (
            p : in std_logic
        ) is
        begin

            v0     <= p;
            sync_n <= '0';
            wait for settle;
            sync_n <= '1';
            wait for settle;

        end procedure latch_parity;

        -- drive the pixel, BRIGHT and sync, then settle

        procedure drive (
            col    : in integer;
            hl_v   : in std_logic;
            sync_v : in std_logic
        ) is
        begin

            red    <= bit_of(col, 1);
            green  <= bit_of(col, 2);
            blue   <= bit_of(col, 0);
            hl     <= hl_v;
            sync_n <= sync_v;
            wait for settle;

        end procedure drive;

        -- check all three outputs against the model for the driven state

        procedure check_all (
            col    : in integer;
            hl_v   : in std_logic;
            sync_v : in std_logic;
            odd_l  : in boolean;
            burst  : in boolean;
            msg    : in string
        ) is

            variable ey : integer;
            variable eu : integer;
            variable ev : integer;

        begin

            ey := ref_y(sync_v, hl_v, col);
            eu := ref_u(col, burst);
            ev := ref_v(col, odd_l, burst);

            assert y_n = ey
                report "FAIL " & msg & ": y_n expected " & integer'image(ey)
                       & " got " & integer'image(y_n)
                severity failure;

            assert u = eu
                report "FAIL " & msg & ": u expected " & integer'image(eu)
                       & " got " & integer'image(u)
                severity failure;

            assert v = ev
                report "FAIL " & msg & ": v expected " & integer'image(ev)
                       & " got " & integer'image(v)
                severity failure;

            checks_v := checks_v + 3;

        end procedure check_all;

        -- assert one output equals a landmark value

        procedure expect (
            actual   : in integer;
            expected : in integer;
            msg      : in string
        ) is
        begin

            assert actual = expected
                report "FAIL " & msg & ": expected " & integer'image(expected)
                       & " mV, got " & integer'image(actual)
                severity failure;

            checks_v := checks_v + 1;

        end procedure expect;

    begin

        --------------------------------------------------------------
        -- 1) SWEEP: parity x counter code x sync x BRIGHT x colour
        --------------------------------------------------------------
        for p in 0 to 1 loop

            latch_parity(bit_of(p, 0));
            odd := (p = 1);

            for code in 0 to 31 loop

                -- Blank the pixel BEFORE moving the counter, as the real
                -- ULA does (blanked from pixel 320, burst opens at 384).
                -- Changing both at once lets the short burst path settle a
                -- few deltas ahead of the long colour path, so yuv briefly
                -- sees "burst on + old colour" and v dips below 0 mV.
                drive(0, '0', '1');
                set_code(code);
                in_burst := (code = burst_code);

                for s in 0 to 1 loop

                    for h in 0 to 1 loop

                        for col in 0 to 7 loop

                            if (in_burst and (col /= 0 or s = 0)) then
                                -- impossible in the burst window: a coloured
                                -- pixel (blanked) or sync (it ends at 367,
                                -- the burst starts at 384). See header.
                                skipped := skipped + 1;
                            else
                                drive(col, bit_of(h, 0), bit_of(s, 0));
                                check_all(col, bit_of(h, 0), bit_of(s, 0), odd, in_burst,
                                          "parity " & integer'image(p)
                                          & " code " & integer'image(code)
                                          & " sync_n " & integer'image(s)
                                          & " hl " & integer'image(h)
                                          & " " & colour_name(col));
                            end if;

                        end loop;

                    end loop;

                end loop;

            end loop;

        end loop;

        assert skipped = 60
            report "FAIL: expected 60 impossible burst states skipped, got "
                   & integer'image(skipped)
            severity failure;
        checks_v := checks_v + 1;

        sync_n <= '1';

        report "PASS: sweep of both parities x 32 codes x sync x BRIGHT x 8 colours ("
               & integer'image(skipped) & " impossible burst states skipped)"
            severity note;

        --------------------------------------------------------------
        -- 2) LANDMARKS: the book's voltages from the real inputs
        --------------------------------------------------------------
        -- outside the burst window
        set_code(0);
        latch_parity('0');

        drive(0, '0', '1');
        expect(y_n, 2449, "Y black");
        expect(u, 2015, "U zero (black)");
        expect(v, v_zero_v, "V zero (black)");

        drive(7, '0', '1');
        expect(u, 2015, "U zero (white)");
        expect(v, v_zero_v, "V zero (white)");

        drive(7, '1', '1');
        expect(y_n, 259, "Y bright white (saturation clamp)");

        drive(0, '0', '0');
        expect(y_n, 4300, "Y sync");

        drive(6, '0', '1');
        expect(u, 3026, "U yellow (book 3.027 V)");

        drive(1, '0', '1');
        expect(u, 1012, "U blue (book 1.013 V)");

        drive(2, '0', '1');
        expect(v, 496, "V red, normal line (book 0.495 V)");

        drive(5, '0', '1');
        expect(v, 3342, "V cyan, normal line");

        latch_parity('1');

        drive(5, '0', '1');
        expect(v, 496, "V cyan, inverted line (book 0.495 V)");

        drive(2, '0', '1');
        expect(v, 3342, "V red, inverted line");

        -- Burst: blank first, latch the parity OUTSIDE the window (it only
        -- changes in sync, which is before the burst), then open the window.
        drive(0, '0', '1');
        latch_parity('0');
        set_code(burst_code);
        wait for settle;
        expect(u, 2925, "U burst, even line");
        expect(v, 967, "V burst, even line (+V)");

        set_code(0);
        wait for settle;
        latch_parity('1');
        set_code(burst_code);
        wait for settle;
        expect(u, 2925, "U burst, odd line");
        expect(v, 2883, "V burst, odd line (-V)");

        report "PASS: book landmarks for Y, U and V, incl. red / inverted cyan at 496 mV"
            severity note;

        --------------------------------------------------------------
        -- 3) PAL ALTERNATION: Y and U fixed, V reflected about zero
        --------------------------------------------------------------
        set_code(0);

        for col in 0 to 7 loop

            latch_parity('0');
            drive(col, '0', '1');
            y_even := y_n;
            u_even := u;
            v_even := v;

            latch_parity('1');
            drive(col, '0', '1');

            expect(y_n, y_even, "Y same on both lines, " & colour_name(col));
            expect(u, u_even, "U same on both lines, " & colour_name(col));

            assert abs (v_even + v - 2 * v_zero_v) <= v_pair_tol
                report "FAIL V pair sum, " & colour_name(col) & ": "
                       & integer'image(v_even) & " + " & integer'image(v) & " = "
                       & integer'image(v_even + v) & ", expected "
                       & integer'image(2 * v_zero_v) & " +/- " & integer'image(v_pair_tol)
                severity failure;
            checks_v := checks_v + 1;

        end loop;

        report "PASS: Y and U do not alternate; V pairs sum to 2 x zero within +/-"
               & integer'image(v_pair_tol) & " mV for all 8 colours"
            severity note;

        --------------------------------------------------------------
        -- 4) PARITY LATCH: held for the line, re-sampled in sync
        --------------------------------------------------------------
        set_code(0);
        latch_parity('0');
        drive(2, '0', '1');
        expect(v, 496, "V red, even line latched");

        -- v0 moves mid-line, sync_n high: the latch must hold
        v0 <= '1';
        wait for settle;
        expect(v, 496, "V red, parity HELD after v0 moved mid-line");

        -- sync: latch transparent, picks up v0
        sync_n <= '0';
        wait for settle;
        sync_n <= '1';
        wait for settle;
        expect(v, 3342, "V red, parity re-sampled during sync");

        report "PASS: parity latch holds mid-line and re-samples in sync"
            severity note;

        checks <= checks_v;
        wait for 1 ns;

        report "ALL TESTS PASSED (" & integer'image(checks_v) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
