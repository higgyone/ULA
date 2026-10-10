----------------------------------------------------------------------------------
-- yuv_control_signals_tb — self-checking TB for the PAL colour-difference
-- (YUV) encoder control-signal block.
--
-- The DUT is pure combinational with SIX inputs (timing, red, green, blue, hl,
-- sync_n), so the TB is fully EXHAUSTIVE: it drives all 2**6 = 64 input
-- combinations and checks all 11 outputs against an independent reference
-- model, giving 64 x 11 = 704 checks.
--
-- What it proves:
--   1. PAL V-SWITCH. Each colour passes through a four-NOR network that must
--      evaluate to x_3_out = x XNOR timing:
--        timing='1' -> colour passed straight through
--        timing='0' -> colour sense INVERTED
--      This is the line-by-line phase alternation that puts the "PAL" in PAL.
--      The TB models the XNOR directly rather than replicating the four NORs,
--      so a mis-wired gate inside the network shows up as a mismatch.
--   2. BLACK GATING, both domains.
--        black_star = NOR(r_3_out, g_3_out, b_3_out)  -- ALTERNATED domain
--        black_ii   = NOR(red, green, blue)           -- direct domain
--      Because black_star is built from the alternated signals, on an inverted
--      line (timing='0') it asserts on WHITE, not black. That is deliberate,
--      and the exhaustive sweep pins the behaviour down so a later "fix" that
--      makes black_star phase-independent is caught as a regression.
--   3. OUTPUT POLARITIES ENCODE THE U/V COEFFICIENT SIGNS. PAL carries colour
--      as two colour-difference components:
--        V = 0.877*(R-Y) = +0.615*R  -0.515*G  -0.100*B
--        U = 0.493*(B-Y) = -0.147*R  -0.289*G  +0.436*B
--      A NEGATIVE coefficient is exposed as the bare NOR (active low, `_n`
--      suffix); the single POSITIVE coefficient in each component takes an
--      extra buffering inversion and comes out ACTIVE HIGH (no suffix):
--
--        family    R             G              B             component
--        --------+-------------+--------------+-------------+----------
--        *_star  | red_star  + | green_star_n -| blue_star_n -|   V
--        *_ii    | red_ii_n  - | green_ii_n   -| blue_ii     +|   U
--
--      R is V's only positive term and B is U's only positive term, which is
--      why `red_star` and `blue_ii` are the two ports without an `_n` and the
--      two that carry the extra inversion. The reference model encodes each
--      polarity independently, so swapping any one of them fails.
--   4. WHICH FAMILY ALTERNATES. V is the component PAL flips line to line
--      (hence "V-switch"), so `timing` is applied to the *_star family ONLY.
--      The *_ii (U) family is built from the raw colour inputs and must be
--      completely independent of `timing` -- the exhaustive sweep proves that,
--      since every U output is checked against a model with no timing term.
--   5. BUFFERS: red_i / green_i / blue_i / sync_i_n are the book's not(not())
--      buffers and must behave as identity; hl_n is a plain inverter. These are
--      checked to be independent of every other input -- the exhaustive sweep
--      covers that by construction, since hl and sync_n are swept against all
--      colour/timing combinations.
--
-- Pure combinational, so there is no clock: the TB drives inputs, waits SETTLE
-- for the modelled gate delays to work through, then checks. Per-combination
-- notes would be 64 lines of noise, so the sweep is silent and only a curated
-- set of landmark cases reports; any mismatch is fatal. A clean run prints
-- "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity yuv_control_signals_tb is
end entity yuv_control_signals_tb;

architecture behavioral of yuv_control_signals_tb is

    constant settle : time := 10 ns; -- > worst-case path (4-NOR XNOR + output NOR)

    -- DUT inputs
    signal timing : std_logic := '0';
    signal red    : std_logic := '0';
    signal green  : std_logic := '0';
    signal blue   : std_logic := '0';
    signal hl     : std_logic := '0';
    signal sync_n : std_logic := '0';

    -- DUT outputs
    signal red_star     : std_logic;
    signal red_i        : std_logic;
    signal red_ii_n     : std_logic;
    signal green_star_n : std_logic;
    signal green_i      : std_logic;
    signal green_ii_n   : std_logic;
    signal blue_star_n  : std_logic;
    signal blue_i       : std_logic;
    signal blue_ii      : std_logic;
    signal hl_n         : std_logic;
    signal sync_i_n     : std_logic;

    signal checks : integer := 0;

    -- ---------------------------------------------------------------
    -- Reference model, written from the block's SPECIFICATION (the
    -- header of yuv_control_signals.vhd), not from its gate netlist.
    -- ---------------------------------------------------------------

    -- the PAL V-switch: colour XNOR timing

    function v_switch (
        t,
        c : std_logic
    ) return std_logic is
    begin

        return not (t xor c);

    end function v_switch;

    -- one exhaustive step: drive, settle, check every output.

    procedure check_all (
        signal t_s  : out std_logic;
        signal r_s  : out std_logic;
        signal g_s  : out std_logic;
        signal b_s  : out std_logic;
        signal h_s  : out std_logic;
        signal sn_s : out std_logic;

        signal o_red_star     : in std_logic;
        signal o_red_i        : in std_logic;
        signal o_red_ii_n     : in std_logic;
        signal o_green_star_n : in std_logic;
        signal o_green_i      : in std_logic;
        signal o_green_ii_n   : in std_logic;
        signal o_blue_star_n  : in std_logic;
        signal o_blue_i       : in std_logic;
        signal o_blue_ii      : in std_logic;
        signal o_hl_n         : in std_logic;
        signal o_sync_i_n     : in std_logic;

        signal n_checks : inout integer;

        t,
        r,
        g,
        b,
        h,
        sn : in std_logic
    ) is

        variable r3         : std_logic;
        variable g3         : std_logic;
        variable b3         : std_logic;
        variable black_star : std_logic;
        variable black_ii   : std_logic;

        variable e_red_star     : std_logic;
        variable e_red_i        : std_logic;
        variable e_red_ii_n     : std_logic;
        variable e_green_star_n : std_logic;
        variable e_green_i      : std_logic;
        variable e_green_ii_n   : std_logic;
        variable e_blue_star_n  : std_logic;
        variable e_blue_i       : std_logic;
        variable e_blue_ii      : std_logic;
        variable e_hl_n         : std_logic;
        variable e_sync_i_n     : std_logic;

    begin

        t_s  <= t;
        r_s  <= r;
        g_s  <= g;
        b_s  <= b;
        h_s  <= h;
        sn_s <= sn;
        wait for settle;

        -- phase-alternated colour signals
        r3 := v_switch(t, r);
        g3 := v_switch(t, g);
        b3 := v_switch(t, b);

        -- black detect in each domain
        black_star := not (r3 or g3 or b3);
        black_ii   := not (r or g or b);

        -- star family -- note the differing polarities
        e_red_star     := black_star or r3;       -- ACTIVE HIGH
        e_green_star_n := not (g3 or black_star); -- ACTIVE LOW
        e_blue_star_n  := not (b3 or black_star); -- ACTIVE LOW

        -- buffers (identity) and the BRIGHT inverter
        e_red_i    := r;
        e_green_i  := g;
        e_blue_i   := b;
        e_hl_n     := not h;
        e_sync_i_n := sn;

        -- direct (U) family. The two NEGATIVE U terms are bare NORs (active
        -- low); the POSITIVE term takes the extra buffering inversion and is
        -- active HIGH -- the mirror of red_star in the V family.
        e_red_ii_n   := not (r or black_ii);       -- U coeff -0.147, active low
        e_green_ii_n := not (g or black_ii);       -- U coeff -0.289, active low
        e_blue_ii    := not (not (b or black_ii)); -- U coeff +0.436, ACTIVE HIGH

        assert o_red_star = e_red_star
            report "FAIL red_star: timing=" & std_logic'image(t) & " rgb="
                   & std_logic'image(r) & std_logic'image(g) & std_logic'image(b)
                   & " expected " & std_logic'image(e_red_star)
                   & " got " & std_logic'image(o_red_star)
            severity failure;

        assert o_green_star_n = e_green_star_n
            report "FAIL green_star_n: timing=" & std_logic'image(t) & " rgb="
                   & std_logic'image(r) & std_logic'image(g) & std_logic'image(b)
                   & " expected " & std_logic'image(e_green_star_n)
                   & " got " & std_logic'image(o_green_star_n)
            severity failure;

        assert o_blue_star_n = e_blue_star_n
            report "FAIL blue_star_n: timing=" & std_logic'image(t) & " rgb="
                   & std_logic'image(r) & std_logic'image(g) & std_logic'image(b)
                   & " expected " & std_logic'image(e_blue_star_n)
                   & " got " & std_logic'image(o_blue_star_n)
            severity failure;

        assert o_red_ii_n = e_red_ii_n
            report "FAIL red_ii_n: rgb=" & std_logic'image(r)
                   & std_logic'image(g) & std_logic'image(b)
                   & " expected " & std_logic'image(e_red_ii_n)
                   & " got " & std_logic'image(o_red_ii_n)
            severity failure;

        assert o_green_ii_n = e_green_ii_n
            report "FAIL green_ii_n: rgb=" & std_logic'image(r)
                   & std_logic'image(g) & std_logic'image(b)
                   & " expected " & std_logic'image(e_green_ii_n)
                   & " got " & std_logic'image(o_green_ii_n)
            severity failure;

        assert o_blue_ii = e_blue_ii
            report "FAIL blue_ii: rgb=" & std_logic'image(r)
                   & std_logic'image(g) & std_logic'image(b)
                   & " expected " & std_logic'image(e_blue_ii)
                   & " got " & std_logic'image(o_blue_ii)
            severity failure;

        assert o_red_i = e_red_i
            report "FAIL red_i buffer: expected " & std_logic'image(e_red_i)
                   & " got " & std_logic'image(o_red_i)
            severity failure;

        assert o_green_i = e_green_i
            report "FAIL green_i buffer: expected " & std_logic'image(e_green_i)
                   & " got " & std_logic'image(o_green_i)
            severity failure;

        assert o_blue_i = e_blue_i
            report "FAIL blue_i buffer: expected " & std_logic'image(e_blue_i)
                   & " got " & std_logic'image(o_blue_i)
            severity failure;

        assert o_hl_n = e_hl_n
            report "FAIL hl_n: hl=" & std_logic'image(h)
                   & " expected " & std_logic'image(e_hl_n)
                   & " got " & std_logic'image(o_hl_n)
            severity failure;

        assert o_sync_i_n = e_sync_i_n
            report "FAIL sync_i_n buffer: sync_n=" & std_logic'image(sn)
                   & " expected " & std_logic'image(e_sync_i_n)
                   & " got " & std_logic'image(o_sync_i_n)
            severity failure;

        n_checks <= n_checks + 11;
        wait for 0 ns;

    end procedure check_all;

begin

    dut : entity work.yuv_control_signals(structural)
        port map (
            timing       => timing,
            red          => red,
            green        => green,
            blue         => blue,
            hl           => hl,
            sync_n       => sync_n,
            red_star     => red_star,
            red_i        => red_i,
            red_ii_n     => red_ii_n,
            green_star_n => green_star_n,
            green_i      => green_i,
            green_ii_n   => green_ii_n,
            blue_star_n  => blue_star_n,
            blue_i       => blue_i,
            blue_ii      => blue_ii,
            hl_n         => hl_n,
            sync_i_n     => sync_i_n
        );

    stim : process is
    begin

        --------------------------------------------------------------
        -- EXHAUSTIVE SWEEP: all 64 combinations of the six inputs.
        -- Silent (a note per combination would be 64 lines of noise);
        -- any mismatch is fatal inside check_all.
        --------------------------------------------------------------
        for t in 0 to 1 loop

            for r in 0 to 1 loop

                for g in 0 to 1 loop

                    for b in 0 to 1 loop

                        for h in 0 to 1 loop

                            for sn in 0 to 1 loop

                                check_all(timing, red, green, blue, hl, sync_n,
                                          red_star, red_i, red_ii_n,
                                          green_star_n, green_i, green_ii_n,
                                          blue_star_n, blue_i, blue_ii,
                                          hl_n, sync_i_n,
                                          checks,
                                          std_logic'val(t + 2), std_logic'val(r + 2),
                                          std_logic'val(g + 2), std_logic'val(b + 2),
                                          std_logic'val(h + 2), std_logic'val(sn + 2));

                            end loop;

                        end loop;

                    end loop;

                end loop;

            end loop;

        end loop;

        report "PASS: exhaustive sweep of all 64 input combinations"
            severity note;

        --------------------------------------------------------------
        -- LANDMARK CASES -- re-driven so the waveform and the log show
        -- the behaviour that matters, with the reasoning spelled out.
        -- These re-run the same checker, so they also add to the count.
        --------------------------------------------------------------

        -- PAL V-switch, non-inverted line: timing='1' passes colour through.
        -- Pure red -> r_3_out='1', g_3_out='0', b_3_out='0' -> black_star='0',
        -- so red_star = '1' and green/blue star_n stay HIGH (de-asserted).
        check_all(timing, red, green, blue, hl, sync_n,
                  red_star, red_i, red_ii_n, green_star_n, green_i, green_ii_n,
                  blue_star_n, blue_i, blue_ii, hl_n, sync_i_n, checks,
                  '1', '1', '0', '0', '0', '1');
        report "PASS: timing='1' (pass-through), pure RED"
            severity note;

        -- Same pixel on the ALTERNATED line: timing='0' inverts every colour.
        -- r_3_out flips to '0' and g/b_3_out to '1' -- the V-switch in action.
        check_all(timing, red, green, blue, hl, sync_n,
                  red_star, red_i, red_ii_n, green_star_n, green_i, green_ii_n,
                  blue_star_n, blue_i, blue_ii, hl_n, sync_i_n, checks,
                  '0', '1', '0', '0', '0', '1');
        report "PASS: timing='0' (inverted line), same RED pixel - V-switch flips it"
            severity note;

        -- TRUE BLACK on a pass-through line: black_ii='1' AND black_star='1',
        -- so both domains agree.
        check_all(timing, red, green, blue, hl, sync_n,
                  red_star, red_i, red_ii_n, green_star_n, green_i, green_ii_n,
                  blue_star_n, blue_i, blue_ii, hl_n, sync_i_n, checks,
                  '1', '0', '0', '0', '0', '1');
        report "PASS: timing='1', BLACK - black_star and black_ii both assert"
            severity note;

        -- BLACK on an inverted line: black_ii still='1' (raw inputs are black),
        -- but black_star='0' because the alternated signals are all '1'.
        -- This is the deliberate asymmetry -- the star family lives entirely in
        -- the alternated domain.
        check_all(timing, red, green, blue, hl, sync_n,
                  red_star, red_i, red_ii_n, green_star_n, green_i, green_ii_n,
                  blue_star_n, blue_i, blue_ii, hl_n, sync_i_n, checks,
                  '0', '0', '0', '0', '0', '1');
        report "PASS: timing='0', BLACK - black_ii asserts but black_star does NOT"
            severity note;

        -- WHITE on an inverted line: the mirror of the case above -- the
        -- alternated signals are all '0', so black_star asserts on WHITE.
        check_all(timing, red, green, blue, hl, sync_n,
                  red_star, red_i, red_ii_n, green_star_n, green_i, green_ii_n,
                  blue_star_n, blue_i, blue_ii, hl_n, sync_i_n, checks,
                  '0', '1', '1', '1', '0', '1');
        report "PASS: timing='0', WHITE - black_star asserts (alternated domain)"
            severity note;

        -- BRIGHT set, and sync asserted (sync_n='0') -- both paths are
        -- independent of the colour/timing logic.
        check_all(timing, red, green, blue, hl, sync_n,
                  red_star, red_i, red_ii_n, green_star_n, green_i, green_ii_n,
                  blue_star_n, blue_i, blue_ii, hl_n, sync_i_n, checks,
                  '1', '0', '1', '1', '1', '0');
        report "PASS: BRIGHT set + sync asserted - hl_n and sync_i_n track independently"
            severity note;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
