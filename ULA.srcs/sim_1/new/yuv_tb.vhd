----------------------------------------------------------------------------------
-- yuv_tb — self-checking TB for the yuv block: luminance (Y) and the U and V
-- colour-difference channels.
--
-- SCOPE: all three channels -- Y, U and V.
--
-- ── What the DUT models (Y) ──────────────────────────────────────────
-- A current-summing DAC. Each asserted signal switches a current sink into a
-- summing node; the total develops a drop across R2 = 3.1k, and an emitter
-- follower passes that through less one Vbe:
--
--     y_n = 4300 - ( I_sync + I_red + I_green + I_blue ) x R2      [mV]
--
-- 4300 mV is the no-sinks-conducting state (5.0 V rail - 0.7 V Vbe), which is
-- also what sync produces, since sync_n asserted turns its sink OFF.
--
-- The output transistor saturates at a 4041 mV drop, so y_n cannot fall below
-- 4300 - 4041 = 259 mV. Of the 16 colour combinations only BRIGHT WHITE hits
-- this (it would otherwise reach -59 mV); every other combination is inside
-- the linear region. The model is therefore piecewise linear.
--
-- ── What the DUT models (U) ──────────────────────────────────────────
-- The same current-summing structure with its own summing resistor
-- (R = 1550 ohm), the same 4300 mV top of range, and a fixed black-level
-- sink that is ALWAYS on:
--
--     u = 4300 - ( I_black + I_red + I_green + I_blue + I_burst ) x R   [mV]
--
-- EVERY sink conducts when its input is '1', whatever the input's name. The
-- _n suffixes encode the SIGN of the U coefficient, not the sink sense:
-- red_ii_n = NOR(red, black_ii) is HIGH when red is ABSENT, so the red sink
-- conducts on the absence of red -- that is how a negative coefficient is
-- built. burst_ii_n is '1' for the whole line except the burst window, so the
-- burst sink is ON in active video and switches OFF during the burst.
--
-- There is no BRIGHT term (BRIGHT is luminance-only) and no clamp: every state
-- lies between 1012 mV (blue) and 3026 mV (yellow), well inside the range.
--
-- ── The U/V zero point (the book's "black/white") ───────────────────
-- U = 0.493(B-Y) and V = 0.877(R-Y) are colour DIFFERENCES: any grey (R=G=B)
-- gives U = V = 0, so black and white share one point and only Y tells them
-- apart. The circuit cannot output negative volts, so zero is offset to
-- mid-range: U zero = 2015 mV (V zero = 1925 mV).
--
-- Black is ENCODED AS WHITE: black_ii catches R=G=B=0 and substitutes white's
-- sink pattern (blue_ii on, red_ii_n and green_ii_n off -- i.e. all three
-- colours "present"). Black's literal pattern (red_ii_n and green_ii_n on,
-- blue_ii off) would draw 647 uA against white's 652 uA, so it would land
-- within ~8 mV of zero anyway; the substitution makes black EXACTLY equal to
-- white and independent of resistor matching, rather than stopping it
-- reading as a colour.
--
-- Each complementary pair lies either side of the zero point. The pairs are
-- symmetric to within 8 mV, not exactly: the U equation
-- needs I_blue = I_red + I_green (0.436 = 0.147 + 0.289), and the book's
-- currents give 652 vs 647 uA -- 5 uA x 1.55k ~= 8 mV of rounding.
--
-- ── What the DUT models (V) ──────────────────────────────────────────
-- Same structure again: R = 3.1k, top 4300 mV, NO fixed sink:
--
--     v = 4300 - ( I_red + I_green + I_blue + I_burst + I_burst_n ) x R  [mV]
--
-- Every sink conducts on '1'. V's single positive coefficient is red, so
-- red_star has no _n and the zero point (black/white) has ONLY the red sink
-- on -- the mirror of U, where it is blue. The PAL V-switch is applied
-- upstream in yuv_control_signals, so the same pixel reaches this block as a
-- different sink pattern on normal (even, timing='1') and inverted (odd,
-- timing='0') lines; the TB drives those patterns directly.
--
-- The two burst sinks come from pal_v_burst. In active video burst_star_n is
-- '1' (on) and burst_star '0' (off). During the burst on EVEN lines both are
-- on (+V, burst at 135 deg); on ODD lines both are off (-V, 225 deg). The
-- pixel is blanked to black, so the red sink stays on throughout.
--
-- Every normal-line value and its inverted-line counterpart sum to 2 x the V
-- zero point (2 x 1925 = 3850 mV): the V-switch reflects V about zero. Colours
-- come in ~12 mV low (I_red 457 vs I_green + I_blue 461 uA); the burst pair is
-- exact (the two burst sinks draw identical currents).
--
-- BOOK ERROR: the book gives the inverted burst as 3.112 V (R2 1.188 V). That
-- is the green-sink term alone with the blue term dropped -- its own listed
-- currents (/green + /blue = 0.461 mA) give 2.871 V, and its pair sum would be
-- 4080 mV, not ~3850. The design value, 2883 mV (red sink only), is used.
--
-- ── Why the reference model starts from CURRENTS ─────────────────────
-- The DUT stores voltage contributions (I x R2 folded at design time). This TB
-- deliberately does NOT reuse those constants: it holds the CURRENTS in
-- microamps and derives the millivolt contributions itself. The currents are
-- the specification -- the book also prints a voltage truth table, but it is
-- inconsistently rounded and disagrees with its own currents by a few mV.
-- Deriving independently means a fat-fingered constant in the DUT fails here
-- rather than being silently mirrored.
--
-- Rounding is half-up, matching how the DUT's constants were computed:
--     mV = (I_uA * R2_ohm + 500) / 1000
--
-- ── What it proves ───────────────────────────────────────────────────
--   1. EXHAUSTIVE: all 2**5 = 32 combinations of sync_n, hl_n and the three
--      colour bits, each checked against the reference model.
--   2. SYNC: sync_n asserted gives exactly 4300 regardless of colour. This is
--      the check that catches the sync contribution being applied
--      unconditionally -- a real bug this module had, where the summing line
--      referenced the CONSTANT V_SYNC_Y instead of the signal v_sync_c_y
--      (VHDL is case-insensitive, so it compiled and elaborated cleanly).
--   3. CLAMP: bright white gives exactly 259, the saturation floor. It is the
--      only combination exercising the clamp, so without this case a broken
--      clamp would pass every other row.
--   4. BLACK INVARIANCE: black is 2449 with BRIGHT both set and clear. This is
--      structural in the DUT -- with no guns conducting there is nothing for
--      hl to scale -- and this check keeps it that way.
--   5. BRIGHT POLARITY: hl_n is ACTIVE LOW, so '0' selects the bright current.
--      Landmark cases assert bright is brighter (lower y_n, since y_n is
--      inverted luminance), which a swapped polarity would fail.
--   6. U EXHAUSTIVE: all 2**4 = 16 combinations of red_ii_n, green_ii_n,
--      blue_ii and burst_ii_n against the U reference model.
--   7. U LANDMARKS: yellow 3026 and blue 1012 (the book's top and bottom,
--      3.027 V / 1.013 V), zero 2015, and the burst step to 2925.
--   8. U ORDERING: yellow > zero > blue. This is the check that catches the U
--      sum being inverted (computing the drop instead of top-minus-drop). The
--      symmetry check below CANNOT catch that -- a mirror image is still
--      symmetric -- so ordering is checked separately.
--   9. U SYMMETRY: each complementary pair sums to 2 x zero within +/-10 mV
--      (see the 8 mV note above). This catches a wrong or swapped current.
--  10. V EXHAUSTIVE: all 2**5 = 32 combinations of the five V inputs against
--      the V reference model.
--  11. V LANDMARKS: zero point 1925, red 496 and cyan 3342 (normal-line
--      extremes), burst 967 on even lines and 2883 on odd lines.
--  12. V ORDERING: cyan > zero > red on a normal line -- catches an inverted
--      V sum, which the pair-sum check cannot.
--  13. V PAIR SUM: for every colour, normal-line V + inverted-line V is within
--      +/-15 mV of 2 x zero, and the burst pair likewise. This is the V-switch
--      reflecting V about its zero point.
--
-- Pure combinational with no modelled gate delays, so SETTLE only has to cover
-- the delta chain (contributions -> raw sum -> clamp). The sweeps are silent
-- and only landmark cases report. Any mismatch is fatal; a clean run prints
-- "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

library work;
    use work.yuv_levels_pkg.all;

entity yuv_tb is
end entity yuv_tb;

architecture behavioral of yuv_tb is

    constant settle : time := 10 ns; -- >> the delta chain in the DUT

    -- ── Reference data: the CURRENTS (microamps) and the circuit values ──
    -- These are the specification. Everything else is derived.
    constant r2_ohms       : integer := 3100;
    constant i_sync_ua     : integer := 597;
    constant i_blue_ua     : integer := 92;
    constant i_blue_br_ua  : integer := 118;
    constant i_red_ua      : integer := 178;
    constant i_red_br_ua   : integer := 234;
    constant i_green_ua    : integer := 348;
    constant i_green_br_ua : integer := 457;

    constant v_top : integer := 4300; -- 5.0 V rail - 0.7 V Vbe, no sinks conducting
    constant v_min : integer := 259;  -- 4300 - 4041 max drop, transistor saturated

    -- U channel: its own summing resistor, same top of range, no clamp
    constant r_u_ohms     : integer := 1550;
    constant i_black_u_ua : integer := 235; -- fixed black-level sink, always on
    constant i_red_u_ua   : integer := 216;
    constant i_green_u_ua : integer := 431;
    constant i_blue_u_ua  : integer := 652;
    constant i_burst_u_ua : integer := 587;
    constant u_sym_tol    : integer := 10;  -- mV; book currents asymmetric by ~8 mV

    -- V channel: R = 3.1k (as Y), same top of range, no fixed sink, no clamp
    constant r_v_ohms       : integer := 3100;
    constant i_red_v_ua     : integer := 457;
    constant i_green_v_ua   : integer := 383;
    constant i_blue_v_ua    : integer := 78;
    constant i_burst_v_ua   : integer := 309; -- burst_star sink
    constant i_burst_n_v_ua : integer := 309; -- burst_star_n sink
    constant v_pair_tol     : integer := 15;  -- mV; colour pairs come in ~12 mV low

    -- DUT inputs, Y group
    signal hl_n    : std_logic := '1'; -- ACTIVE LOW: '0' = bright
    signal red_i   : std_logic := '0';
    signal green_i : std_logic := '0';
    signal blue_i  : std_logic := '0';
    signal sync_n  : std_logic := '1'; -- ACTIVE LOW: '0' = sync applied

    -- DUT inputs, U group
    signal red_ii_n   : std_logic := '0';
    signal green_ii_n : std_logic := '0';
    signal blue_ii    : std_logic := '0';
    signal burst_ii_n : std_logic := '0';

    -- DUT inputs, V group
    signal red_star     : std_logic := '0';
    signal green_star_n : std_logic := '0';
    signal blue_star_n  : std_logic := '0';
    signal burst_star   : std_logic := '0';
    signal burst_star_n : std_logic := '0';

    -- DUT outputs. MUST be millivolts_t, matching the ports exactly: for a
    -- scalar `out` port VHDL requires the actual's subtype to match the
    -- formal's, and GHDL enforces it ("range of formal is different"). xsim is
    -- lenient here, so a plain INTEGER passes there and fails under GHDL.
    --
    -- Nothing is lost by constraining them: the PORTS are already millivolts_t,
    -- so an out-of-range value trips the DUT's own subtype check before it
    -- could ever reach these signals. The asserts below are kept as a belt-
    -- and-braces check on the reference models.
    signal y_n : millivolts_t;
    signal u   : millivolts_t;
    signal v   : millivolts_t;

    signal checks : integer := 0;

    -- Convert a sink current to its millivolt contribution across R2,
    -- rounding half up -- the same arithmetic used to derive the DUT's
    -- constants, but applied here to the currents directly.

    -- r_ohms defaults to the Y resistor; the U model passes r_u_ohms.

    function contrib (
        i_ua   : integer;
        r_ohms : integer := r2_ohms
    ) return integer is
    begin

        return (i_ua * r_ohms + 500) / 1000;

    end function contrib;

    -- Reference model: sum the conducting sinks, subtract from the top of
    -- range, then apply the saturation clamp.

    function expected_y (
        sync,
        hl,
        r,
        g,
        b : std_logic
    ) return integer is

        variable total : integer := 0;
        variable raw   : integer;

    begin

        -- sync_n is ACTIVE LOW: asserted ('0') turns the sink OFF, which is
        -- what lets the output rise to the top of its range.
        if (sync = '1') then
            total := total + contrib(i_sync_ua);
        end if;

        -- hl_n is ACTIVE LOW: '0' selects the bright (larger) current.
        -- With a gun off there is no term at all, which is why black does
        -- not move when bright changes.
        if (r = '1') then
            if (hl = '0') then
                total := total + contrib(i_red_br_ua);
            else
                total := total + contrib(i_red_ua);
            end if;
        end if;

        if (g = '1') then
            if (hl = '0') then
                total := total + contrib(i_green_br_ua);
            else
                total := total + contrib(i_green_ua);
            end if;
        end if;

        if (b = '1') then
            if (hl = '0') then
                total := total + contrib(i_blue_br_ua);
            else
                total := total + contrib(i_blue_ua);
            end if;
        end if;

        raw := v_top - total;

        if (raw < v_min) then
            return v_min; -- transistor saturated
        else
            return raw;
        end if;

    end function expected_y;

    -- Drive one combination, let it settle, check y_n against the model.

    procedure check_y (
        signal sync_s : out std_logic;
        signal hl_s   : out std_logic;
        signal r_s    : out std_logic;
        signal g_s    : out std_logic;
        signal b_s    : out std_logic;

        signal y_o      : in    integer;
        signal n_checks : inout integer;

        sync,
        hl,
        r,
        g,
        b : in std_logic
    ) is

        variable exp : integer;

    begin

        sync_s <= sync;
        hl_s   <= hl;
        r_s    <= r;
        g_s    <= g;
        b_s    <= b;
        wait for settle;

        exp := expected_y(sync, hl, r, g, b);

        assert y_o = exp
            report "FAIL: sync_n=" & std_logic'image(sync)
                   & " hl_n=" & std_logic'image(hl)
                   & " rgb=" & std_logic'image(r)
                   & std_logic'image(g) & std_logic'image(b)
                   & " - expected " & integer'image(exp)
                   & " mV, got " & integer'image(y_o) & " mV"
            severity failure;

        n_checks <= n_checks + 1;
        wait for 0 ns;

    end procedure check_y;

    -- U reference model. Every sink conducts when its input is '1'; the
    -- black-level sink always conducts. No BRIGHT term, no clamp.

    function expected_u (
        r_n,
        g_n,
        b,
        burst_n : std_logic
    ) return integer is

        variable total : integer;

    begin

        total := contrib(i_black_u_ua, r_u_ohms); -- always on

        if (r_n = '1') then -- '1' = red ABSENT
            total := total + contrib(i_red_u_ua, r_u_ohms);
        end if;

        if (g_n = '1') then -- '1' = green ABSENT
            total := total + contrib(i_green_u_ua, r_u_ohms);
        end if;

        if (b = '1') then -- '1' = blue PRESENT
            total := total + contrib(i_blue_u_ua, r_u_ohms);
        end if;

        if (burst_n = '1') then -- '1' = OUTSIDE the burst
            total := total + contrib(i_burst_u_ua, r_u_ohms);
        end if;

        return v_top - total;

    end function expected_u;

    -- Drive one U combination, let it settle, check u against the model.

    procedure check_u (
        signal r_s     : out std_logic;
        signal g_s     : out std_logic;
        signal b_s     : out std_logic;
        signal burst_s : out std_logic;

        signal u_o      : in    integer;
        signal n_checks : inout integer;

        r_n,
        g_n,
        b,
        burst_n : in std_logic
    ) is

        variable exp : integer;

    begin

        r_s     <= r_n;
        g_s     <= g_n;
        b_s     <= b;
        burst_s <= burst_n;
        wait for settle;

        exp := expected_u(r_n, g_n, b, burst_n);

        assert u_o = exp
            report "FAIL U: red_ii_n=" & std_logic'image(r_n)
                   & " green_ii_n=" & std_logic'image(g_n)
                   & " blue_ii=" & std_logic'image(b)
                   & " burst_ii_n=" & std_logic'image(burst_n)
                   & " - expected " & integer'image(exp)
                   & " mV, got " & integer'image(u_o) & " mV"
            severity failure;

        n_checks <= n_checks + 1;
        wait for 0 ns;

    end procedure check_u;

    -- V reference model. Every sink conducts when its input is '1'. No fixed
    -- sink, no clamp.

    function expected_v (
        r,
        g_n,
        b_n,
        burst,
        burst_n : std_logic
    ) return integer is

        variable total : integer := 0;

    begin

        if (r = '1') then -- red PRESENT (or black)
            total := total + contrib(i_red_v_ua, r_v_ohms);
        end if;

        if (g_n = '1') then -- green ABSENT
            total := total + contrib(i_green_v_ua, r_v_ohms);
        end if;

        if (b_n = '1') then -- blue ABSENT
            total := total + contrib(i_blue_v_ua, r_v_ohms);
        end if;

        if (burst = '1') then -- burst, even lines only
            total := total + contrib(i_burst_v_ua, r_v_ohms);
        end if;

        if (burst_n = '1') then -- on except burst on odd lines
            total := total + contrib(i_burst_n_v_ua, r_v_ohms);
        end if;

        return v_top - total;

    end function expected_v;

    -- Drive one V combination, let it settle, check v against the model.

    procedure check_v (
        signal r_s       : out std_logic;
        signal g_s       : out std_logic;
        signal b_s       : out std_logic;
        signal burst_s   : out std_logic;
        signal burst_n_s : out std_logic;

        signal v_o      : in    integer;
        signal n_checks : inout integer;

        r,
        g_n,
        b_n,
        burst,
        burst_n : in std_logic
    ) is

        variable exp : integer;

    begin

        r_s       <= r;
        g_s       <= g_n;
        b_s       <= b_n;
        burst_s   <= burst;
        burst_n_s <= burst_n;
        wait for settle;

        exp := expected_v(r, g_n, b_n, burst, burst_n);

        assert v_o = exp
            report "FAIL V: red_star=" & std_logic'image(r)
                   & " green_star_n=" & std_logic'image(g_n)
                   & " blue_star_n=" & std_logic'image(b_n)
                   & " burst_star=" & std_logic'image(burst)
                   & " burst_star_n=" & std_logic'image(burst_n)
                   & " - expected " & integer'image(exp)
                   & " mV, got " & integer'image(v_o) & " mV"
            severity failure;

        n_checks <= n_checks + 1;
        wait for 0 ns;

    end procedure check_v;

    -- PAIR SUM: drive a colour's normal-line sink pattern, then its
    -- inverted-line pattern (active video, so burst_star='0', burst_star_n='1'),
    -- and assert the two sum to 2 x the V zero point within v_pair_tol.

    procedure check_v_pair (
        signal r_s       : out std_logic;
        signal g_s       : out std_logic;
        signal b_s       : out std_logic;
        signal burst_s   : out std_logic;
        signal burst_n_s : out std_logic;

        signal v_o      : in    integer;
        signal n_checks : inout integer;

        name   : in string;
        v_zero : in integer;
        n_r,
        n_g_n,
        n_b_n,
        i_r,
        i_g_n,
        i_b_n  : in std_logic
    ) is

        variable v_norm : integer;
        variable v_inv  : integer;

    begin

        check_v(r_s, g_s, b_s, burst_s, burst_n_s, v_o, n_checks,
                n_r, n_g_n, n_b_n, '0', '1');
        v_norm := v_o;

        check_v(r_s, g_s, b_s, burst_s, burst_n_s, v_o, n_checks,
                i_r, i_g_n, i_b_n, '0', '1');
        v_inv := v_o;

        assert abs(v_norm + v_inv - 2 * v_zero) <= v_pair_tol
            report "FAIL V: " & name & " pair sum " & integer'image(v_norm)
                   & " + " & integer'image(v_inv) & " = "
                   & integer'image(v_norm + v_inv) & " mV, expected "
                   & integer'image(2 * v_zero) & " +/- "
                   & integer'image(v_pair_tol)
            severity failure;

    end procedure check_v_pair;

begin

    dut : entity work.yuv(behavioural)
        port map (
            hl_n         => hl_n,
            red_i        => red_i,
            green_i      => green_i,
            blue_i       => blue_i,
            sync_n       => sync_n,
            y_n          => y_n,
            red_ii_n     => red_ii_n,
            green_ii_n   => green_ii_n,
            blue_ii      => blue_ii,
            burst_ii_n   => burst_ii_n,
            u            => u,
            red_star     => red_star,
            green_star_n => green_star_n,
            blue_star_n  => blue_star_n,
            burst_star   => burst_star,
            burst_star_n => burst_star_n,
            v            => v
        );

    stim : process is

        -- captured U levels for the ordering and symmetry checks
        variable u_zero    : integer;
        variable u_yellow  : integer;
        variable u_blue    : integer;
        variable u_green   : integer;
        variable u_magenta : integer;
        variable u_red     : integer;
        variable u_cyan    : integer;

        -- captured V levels
        variable v_zero       : integer;
        variable v_red        : integer;
        variable v_cyan       : integer;
        variable v_burst_even : integer;
        variable v_burst_odd  : integer;

    begin

        --------------------------------------------------------------
        -- EXHAUSTIVE SWEEP: all 32 combinations of the five Y inputs.
        -- Silent; a mismatch is fatal inside check_y.
        --------------------------------------------------------------
        for s in 0 to 1 loop

            for h in 0 to 1 loop

                for r in 0 to 1 loop

                    for g in 0 to 1 loop

                        for b in 0 to 1 loop

                            check_y(sync_n, hl_n, red_i, green_i, blue_i,
                                    y_n, checks,
                                    std_logic'val(s + 2), std_logic'val(h + 2),
                                    std_logic'val(r + 2), std_logic'val(g + 2),
                                    std_logic'val(b + 2));

                        end loop;

                    end loop;

                end loop;

            end loop;

        end loop;

        report "PASS: exhaustive sweep of all 32 Y input combinations"
            severity note;

        --------------------------------------------------------------
        -- LANDMARK CASES. These re-run the same checker, so they also
        -- add to the count; the value is in naming what each proves.
        --------------------------------------------------------------

        -- SYNC: sink off, output rises to the top of range. Must be 4300
        -- regardless of the colour bits -- the case that catches the sync
        -- contribution being subtracted unconditionally.
        check_y(sync_n, hl_n, red_i, green_i, blue_i, y_n, checks,
                '0', '1', '0', '0', '0');
        report "PASS: sync asserted, black  -> 4300 mV (top of range)"
            severity note;

        check_y(sync_n, hl_n, red_i, green_i, blue_i, y_n, checks,
                '0', '0', '1', '1', '1');
        report "PASS: sync asserted, bright white -> 4300 mV (colour ignored)"
            severity note;

        -- BLACK INVARIANCE: with no guns conducting there is nothing for
        -- BRIGHT to scale, so both must give 2449.
        check_y(sync_n, hl_n, red_i, green_i, blue_i, y_n, checks,
                '1', '1', '0', '0', '0');
        report "PASS: active video, black, normal -> 2449 mV"
            severity note;

        check_y(sync_n, hl_n, red_i, green_i, blue_i, y_n, checks,
                '1', '0', '0', '0', '0');
        report "PASS: active video, black, BRIGHT -> 2449 mV (unchanged by hl)"
            severity note;

        -- BRIGHT POLARITY: bright must be BRIGHTER, i.e. a LOWER y_n, since
        -- y_n is inverted luminance. Swapped polarity fails these.
        check_y(sync_n, hl_n, red_i, green_i, blue_i, y_n, checks,
                '1', '1', '0', '0', '1');
        report "PASS: blue, normal -> 2164 mV"
            severity note;

        check_y(sync_n, hl_n, red_i, green_i, blue_i, y_n, checks,
                '1', '0', '0', '0', '1');
        report "PASS: blue, BRIGHT -> 2083 mV (lower = brighter)"
            severity note;

        -- CLAMP: the only combination that saturates the output transistor.
        -- Unclamped this would reach -59 mV.
        check_y(sync_n, hl_n, red_i, green_i, blue_i, y_n, checks,
                '1', '0', '1', '1', '1');
        report "PASS: bright white -> 259 mV (saturation clamp, would be -59)"
            severity note;

        -- The row immediately below the clamp, to prove the limit is in the
        -- right place: bright yellow needs 3993 mV of drop, just inside 4041.
        check_y(sync_n, hl_n, red_i, green_i, blue_i, y_n, checks,
                '1', '0', '1', '1', '0');
        report "PASS: bright yellow -> 307 mV (just inside the linear region)"
            severity note;

        --==============================================================
        -- U CHANNEL
        --==============================================================

        --------------------------------------------------------------
        -- EXHAUSTIVE SWEEP: all 16 combinations of the four U inputs.
        -- Some are unreachable from real RGB (e.g. every colour sink off
        -- with blue absent), but each is electrically defined, so all
        -- are checked against the model.
        --------------------------------------------------------------
        for r in 0 to 1 loop

            for g in 0 to 1 loop

                for b in 0 to 1 loop

                    for bu in 0 to 1 loop

                        check_u(red_ii_n, green_ii_n, blue_ii, burst_ii_n,
                                u, checks,
                                std_logic'val(r + 2), std_logic'val(g + 2),
                                std_logic'val(b + 2), std_logic'val(bu + 2));

                    end loop;

                end loop;

            end loop;

        end loop;

        report "PASS: exhaustive sweep of all 16 U input combinations"
            severity note;

        --------------------------------------------------------------
        -- LANDMARKS, driven as the real pixel colours produce them via
        -- yuv_control_signals (red_ii_n / green_ii_n are '1' when that
        -- colour is ABSENT; blue_ii is '1' when blue is PRESENT; black
        -- gives the same pattern as white -- blue sink only).
        -- Active video throughout: burst_ii_n = '1'.
        --------------------------------------------------------------

        -- zero point (black / white): only the blue sink conducts
        check_u(red_ii_n, green_ii_n, blue_ii, burst_ii_n, u, checks,
                '0', '0', '1', '1');
        u_zero := u;
        assert u_zero = 2015
            report "FAIL U: zero expected 2015 mV, got " & integer'image(u_zero)
            severity failure;
        report "PASS: U zero (black/white) -> 2015 mV"
            severity note;

        -- yellow: no colour sinks conduct -> TOP of the U range (book 3.027 V)
        check_u(red_ii_n, green_ii_n, blue_ii, burst_ii_n, u, checks,
                '0', '0', '0', '1');
        u_yellow := u;
        assert u_yellow = 3026
            report "FAIL U: yellow expected 3026 mV, got " & integer'image(u_yellow)
            severity failure;
        report "PASS: U yellow -> 3026 mV (top of range, book 3.027 V)"
            severity note;

        -- blue: all colour sinks conduct -> BOTTOM of the U range (book 1.013 V)
        check_u(red_ii_n, green_ii_n, blue_ii, burst_ii_n, u, checks,
                '1', '1', '1', '1');
        u_blue := u;
        assert u_blue = 1012
            report "FAIL U: blue expected 1012 mV, got " & integer'image(u_blue)
            severity failure;
        report "PASS: U blue -> 1012 mV (bottom of range, book 1.013 V)"
            severity note;

        -- the remaining pairs, captured for the symmetry check
        check_u(red_ii_n, green_ii_n, blue_ii, burst_ii_n, u, checks,
                '1', '0', '0', '1');                                                     -- green
        u_green   := u;
        check_u(red_ii_n, green_ii_n, blue_ii, burst_ii_n, u, checks,
                '0', '1', '1', '1');                                                     -- magenta
        u_magenta := u;
        check_u(red_ii_n, green_ii_n, blue_ii, burst_ii_n, u, checks,
                '0', '1', '0', '1');                                                     -- red
        u_red     := u;
        check_u(red_ii_n, green_ii_n, blue_ii, burst_ii_n, u, checks,
                '1', '0', '1', '1');                                                     -- cyan
        u_cyan    := u;

        -- ORDERING: yellow above zero above blue. This is what catches an
        -- inverted U sum; the symmetry check below cannot.
        assert (u_yellow > u_zero) and (u_zero > u_blue)
            report "FAIL U: ordering wrong - yellow " & integer'image(u_yellow)
                   & ", zero " & integer'image(u_zero)
                   & ", blue " & integer'image(u_blue)
                   & " (expected yellow > zero > blue; U sum inverted?)"
            severity failure;
        report "PASS: U ordering yellow > zero > blue"
            severity note;

        -- SYMMETRY: each complementary pair straddles zero. Tolerance, not
        -- equality -- the book's currents make every pair 8 mV asymmetric.
        assert abs(u_yellow + u_blue - 2 * u_zero) <= u_sym_tol
            report "FAIL U: yellow/blue not symmetric about zero, error "
                   & integer'image(u_yellow + u_blue - 2 * u_zero) & " mV"
            severity failure;
        assert abs(u_green + u_magenta - 2 * u_zero) <= u_sym_tol
            report "FAIL U: green/magenta not symmetric about zero, error "
                   & integer'image(u_green + u_magenta - 2 * u_zero) & " mV"
            severity failure;
        assert abs(u_red + u_cyan - 2 * u_zero) <= u_sym_tol
            report "FAIL U: red/cyan not symmetric about zero, error "
                   & integer'image(u_red + u_cyan - 2 * u_zero) & " mV"
            severity failure;
        report "PASS: U complementary pairs symmetric about zero (+/-"
               & integer'image(u_sym_tol) & " mV)"
            severity note;

        -- BURST: during the burst window the pixel is blanked (black/white sinks on)
        -- and the burst sink switches OFF, stepping U up by ~910 mV.
        check_u(red_ii_n, green_ii_n, blue_ii, burst_ii_n, u, checks,
                '0', '0', '1', '0');
        assert u = 2925
            report "FAIL U: burst expected 2925 mV, got " & integer'image(u)
            severity failure;
        report "PASS: U during burst (blanked) -> 2925 mV, step of "
               & integer'image(u - u_zero) & " mV above zero"
            severity note;

        --==============================================================
        -- V CHANNEL
        --==============================================================

        --------------------------------------------------------------
        -- EXHAUSTIVE SWEEP: all 32 combinations of the five V inputs.
        --------------------------------------------------------------
        for r in 0 to 1 loop

            for g in 0 to 1 loop

                for b in 0 to 1 loop

                    for bu in 0 to 1 loop

                        for bn in 0 to 1 loop

                            check_v(red_star, green_star_n, blue_star_n,
                                    burst_star, burst_star_n, v, checks,
                                    std_logic'val(r + 2), std_logic'val(g + 2),
                                    std_logic'val(b + 2), std_logic'val(bu + 2),
                                    std_logic'val(bn + 2));

                        end loop;

                    end loop;

                end loop;

            end loop;

        end loop;

        report "PASS: exhaustive sweep of all 32 V input combinations"
            severity note;

        --------------------------------------------------------------
        -- LANDMARKS. Sink patterns as real pixels produce them via
        -- yuv_control_signals. Active video: burst_star='0',
        -- burst_star_n='1'. Order of the arguments below is
        -- red_star, green_star_n, blue_star_n, burst_star, burst_star_n.
        --------------------------------------------------------------

        -- zero point (black / white): only the red sink conducts
        check_v(red_star, green_star_n, blue_star_n, burst_star, burst_star_n,
                v, checks, '1', '0', '0', '0', '1');
        v_zero := v;
        assert v_zero = 1925
            report "FAIL V: zero expected 1925 mV, got " & integer'image(v_zero)
            severity failure;
        report "PASS: V zero (black/white) -> 1925 mV"
            severity note;

        -- red, normal line: all three colour sinks on -> bottom of range (+V)
        check_v(red_star, green_star_n, blue_star_n, burst_star, burst_star_n,
                v, checks, '1', '1', '1', '0', '1');
        v_red := v;
        assert v_red = 496
            report "FAIL V: red expected 496 mV, got " & integer'image(v_red)
            severity failure;
        report "PASS: V red (normal line) -> 496 mV (bottom of range)"
            severity note;

        -- cyan, normal line: no colour sinks on -> top of range (-V)
        check_v(red_star, green_star_n, blue_star_n, burst_star, burst_star_n,
                v, checks, '0', '0', '0', '0', '1');
        v_cyan := v;
        assert v_cyan = 3342
            report "FAIL V: cyan expected 3342 mV, got " & integer'image(v_cyan)
            severity failure;
        report "PASS: V cyan (normal line) -> 3342 mV (top of range)"
            severity note;

        -- ORDERING: catches an inverted V sum, which the pair sum cannot.
        assert (v_cyan > v_zero) and (v_zero > v_red)
            report "FAIL V: ordering wrong - cyan " & integer'image(v_cyan)
                   & ", zero " & integer'image(v_zero)
                   & ", red " & integer'image(v_red)
                   & " (expected cyan > zero > red; V sum inverted?)"
            severity failure;
        report "PASS: V ordering cyan > zero > red (normal line)"
            severity note;

        -- PAIR SUMS: normal-line pattern then inverted-line pattern for each
        -- colour. Arguments: normal (red_star, green_star_n, blue_star_n),
        -- then inverted (same order).
        check_v_pair(red_star, green_star_n, blue_star_n, burst_star, burst_star_n,
                     v, checks, "blue", v_zero,
                     '0', '1', '0', '1', '0', '1');
        check_v_pair(red_star, green_star_n, blue_star_n, burst_star, burst_star_n,
                     v, checks, "red", v_zero,
                     '1', '1', '1', '0', '0', '0');
        check_v_pair(red_star, green_star_n, blue_star_n, burst_star, burst_star_n,
                     v, checks, "magenta", v_zero,
                     '1', '1', '0', '0', '0', '1');
        check_v_pair(red_star, green_star_n, blue_star_n, burst_star, burst_star_n,
                     v, checks, "green", v_zero,
                     '0', '0', '1', '1', '1', '0');
        check_v_pair(red_star, green_star_n, blue_star_n, burst_star, burst_star_n,
                     v, checks, "cyan", v_zero,
                     '0', '0', '0', '1', '1', '1');
        check_v_pair(red_star, green_star_n, blue_star_n, burst_star, burst_star_n,
                     v, checks, "yellow", v_zero,
                     '1', '0', '1', '0', '1', '0');
        report "PASS: V pair sums, every colour within +/-"
               & integer'image(v_pair_tol) & " mV of 2 x zero ("
               & integer'image(2 * v_zero) & " mV)"
            severity note;

        -- BURST. The pixel is blanked black, so the red sink stays on.
        -- Even lines: both burst sinks on -> +V, 135 deg.
        check_v(red_star, green_star_n, blue_star_n, burst_star, burst_star_n,
                v, checks, '1', '0', '0', '1', '1');
        v_burst_even := v;
        assert v_burst_even = 967
            report "FAIL V: even-line burst expected 967 mV, got "
                   & integer'image(v_burst_even)
            severity failure;
        report "PASS: V burst, even line -> 967 mV (both burst sinks on, +V)"
            severity note;

        -- Odd lines: both burst sinks off -> -V, 225 deg. The book prints
        -- 3.112 V here; that is an arithmetic slip (see header).
        check_v(red_star, green_star_n, blue_star_n, burst_star, burst_star_n,
                v, checks, '1', '0', '0', '0', '0');
        v_burst_odd := v;
        assert v_burst_odd = 2883
            report "FAIL V: odd-line burst expected 2883 mV, got "
                   & integer'image(v_burst_odd)
            severity failure;
        report "PASS: V burst, odd line -> 2883 mV (both burst sinks off, -V)"
            severity note;

        -- the burst pair is exactly symmetric about zero (equal burst sinks)
        assert abs(v_burst_even + v_burst_odd - 2 * v_zero) <= v_pair_tol
            report "FAIL V: burst pair sum " & integer'image(v_burst_even + v_burst_odd)
                   & " mV, expected " & integer'image(2 * v_zero)
            severity failure;
        report "PASS: V burst swings +/-"
               & integer'image(v_zero - v_burst_even) & " mV about zero, pair sum "
               & integer'image(v_burst_even + v_burst_odd) & " mV"
            severity note;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
