----------------------------------------------------------------------------------
-- yuv_tb — self-checking TB for the yuv luminance (Y) channel.
--
-- SCOPE: the Y channel ONLY. The U and V channels are not implemented yet, so
-- their inputs are tied low and their outputs are left open. When they land,
-- extend this TB with the same pattern rather than replacing it.
--
-- ── What the DUT models ──────────────────────────────────────────────
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
--
-- Pure combinational with no modelled gate delays, so SETTLE only has to cover
-- the delta chain (contributions -> raw sum -> clamp). The sweep is silent --
-- 32 notes would be noise -- and only landmark cases report. Any mismatch is
-- fatal; a clean run prints "ALL TESTS PASSED".
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

    -- DUT inputs, Y group
    signal hl_n    : std_logic := '1'; -- ACTIVE LOW: '0' = bright
    signal red_i   : std_logic := '0';
    signal green_i : std_logic := '0';
    signal blue_i  : std_logic := '0';
    signal sync_n  : std_logic := '1'; -- ACTIVE LOW: '0' = sync applied

    -- DUT inputs, U and V groups -- not exercised, tied low so they are driven
    signal red_ii_n     : std_logic := '0';
    signal green_ii_n   : std_logic := '0';
    signal blue_ii      : std_logic := '0';
    signal burst_ii_n   : std_logic := '0';
    signal red_star     : std_logic := '0';
    signal green_star_n : std_logic := '0';
    signal blue_star_n  : std_logic := '0';
    signal burst_star   : std_logic := '0';
    signal burst_star_n : std_logic := '0';

    -- DUT output. Declared as plain INTEGER (the base type) rather than
    -- millivolts_t so an out-of-range result is reported by the assert below
    -- instead of only tripping a subtype check.
    signal y_n : integer;

    signal checks : integer := 0;

    -- Convert a sink current to its millivolt contribution across R2,
    -- rounding half up -- the same arithmetic used to derive the DUT's
    -- constants, but applied here to the currents directly.

    function contrib (
        i_ua : integer
    ) return integer is
    begin

        return (i_ua * r2_ohms + 500) / 1000;

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
            u            => open,
            red_star     => red_star,
            green_star_n => green_star_n,
            blue_star_n  => blue_star_n,
            burst_star   => burst_star,
            burst_star_n => burst_star_n,
            v            => open
        );

    stim : process is
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

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
