----------------------------------------------------------------------------------
-- yuv — Y, U and V output levels of the ULA's analogue video DAC
--
-- Last stage of the video signal strand. Takes the gating signals from
-- yuv_control_signals (colour, BRIGHT, sync) and pal_v_burst (colour burst)
-- and produces the three voltages the ULA puts out for the PCB's video
-- encoder: inverted luminance y_n, and the colour differences u and v.
--
-- ⚠ NOT GATE-ACCURATE — deliberately. The real ULA builds these levels with an
-- analogue resistor summing network, which has no gate-level equivalent. This
-- block models its OUTPUT behaviourally, as integer millivolts. Same exception
-- status as ras_cas_generation.
--
-- ── Units: integer MILLIVOLTS ────────────────────────────────────────
--   Every voltage is an integer number of millivolts (1 LSB = 1 mV), measured
--   at the output transistor's EMITTER. This is fixed point with an implicit,
--   decimal scale of 1/1000 V. It is used instead of ieee.fixed_pkg because
--   the block does no arithmetic worth that library, and because the source
--   data is decimal: binary fixed point cannot hold e.g. 0.702 exactly, which
--   would force the testbench to compare with a tolerance and blind it to
--   1 mV errors. `integer` needs no library at all.
--
--   millivolts_t and v_top live in yuv_levels_pkg (below, in this file)
--   because the port list is elaborated before the architecture exists, so a
--   named type or constant used in a port must come from a package.
--
-- ── The circuit: a current-summing DAC ───────────────────────────────
--   Each channel is a summing node. Every asserted input switches a current
--   sink into that node; the total current develops a drop across the
--   channel's resistor, and an emitter follower passes the result out less
--   one Vbe:
--
--     output = 4300 - (sum of the conducting sinks' currents) x R    [mV]
--
--   4300 mV = 5.0 V rail - 0.7 V Vbe, the no-sinks-conducting state. More
--   current means a LOWER output.
--
--   Each constant below is I x R computed ONCE, at design time, rounded half
--   up to the nearest mV. That folds the resistor into the constants, so the
--   body needs only integer ADDITION -- no multiply or divide in hardware.
--   Each constant's comment shows the current it came from.
--
-- ── THE SINK RULE: every sink conducts when its input is '1' ─────────
--   Whatever the input's name. The _n suffix does NOT mean "sink on when
--   low"; it encodes the SIGN of that colour's coefficient in U or V.
--   E.g. red_ii_n = NOR(red, black_ii) is HIGH when red is ABSENT, so the red
--   sink conducts on the absence of red -- that is how the network builds a
--   negative coefficient. sync_n follows the same rule: '1' (no sync) turns
--   its sink on; asserting sync turns it off and the output rises to 4300.
--
--   Negative terms (_n)         Positive terms (no suffix)
--     U: red_ii_n, green_ii_n     U: blue_ii          U = -0.147R -0.289G +0.436B
--     V: green_star_n, blue_star_n V: red_star        V = +0.615R -0.515G -0.100B
--
-- ── Y (y_n): inverted luminance, R = 3.1k ────────────────────────────
--   Sinks: sync 0.597 mA; red 0.178 / 0.234 mA, green 0.348 / 0.457 mA,
--   blue 0.092 / 0.118 mA (normal / BRIGHT).
--   y_n is INVERTED -- the Spectrum's composite video circuit inverts it
--   back -- so sync (the most negative excursion of normal video) comes out
--   as the HIGHEST voltage, 4300.
--   BRIGHT (hl_n, active low) does not draw current of its own; it SELECTS
--   which current each colour leg draws. With every gun off there is no leg
--   to select, so black is 2449 mV with BRIGHT set or clear.
--   SATURATION: the output transistor can drop at most 4041 mV across R, so
--   y_n cannot fall below 4300 - 4041 = 259 mV. Only BRIGHT WHITE reaches it
--   (it would otherwise be -59 mV); hence the clamp and the signed y_raw_y.
--
-- ── U: R = 1550 ohm ──────────────────────────────────────────────────
--   Sinks: fixed black-level 0.235 mA (ALWAYS on), red_ii_n 0.216 mA,
--   green_ii_n 0.431 mA, blue_ii 0.652 mA, burst_ii_n 0.587 mA.
--   No BRIGHT term (BRIGHT is luminance-only), no clamp: every state lies
--   between blue 1012 mV and yellow 3026 mV.
--
-- ── V: R = 3.1k ──────────────────────────────────────────────────────
--   Sinks: red_star 0.457 mA, green_star_n 0.383 mA, blue_star_n 0.078 mA,
--   burst_star 0.309 mA, burst_star_n 0.309 mA. No fixed sink, no clamp.
--   The PAL V-switch is applied UPSTREAM (yuv_control_signals, via timing),
--   so the same pixel arrives here as a different sink pattern on even and
--   odd lines; this block needs no timing input. Each even-line value and its
--   odd-line counterpart sum to about 2 x the V zero point (3850 mV).
--
-- ── The U/V zero point (the book's "black/white") ────────────────────
--   U = 0.493(B-Y) and V = 0.877(R-Y) are colour DIFFERENCES: any grey
--   (R=G=B) gives U = V = 0, so black and white share one point and only Y
--   tells them apart. The circuit cannot output negative volts, so zero is
--   offset to mid-range: U zero = 2015 mV, V zero = 1925 mV.
--
--   Black is ENCODED AS WHITE: black_ii / black_star catch R=G=B=0 and
--   substitute white's sink pattern (U: blue on, /red /green off; V: red on,
--   /green /blue off -- all three colours "present"). Black's literal pattern
--   would draw almost the same current (blue ~= red + green in U, red ~= green
--   + blue in V), so the substitution makes black EXACTLY equal to white and
--   independent of resistor matching, rather than stopping it reading as a
--   colour.
--
-- ── Colour burst ─────────────────────────────────────────────────────
--   The burst is a DC offset in U and V on the back porch; the encoder chip on
--   the PCB turns it into subcarrier at phase atan2(V, U). The TV locks its
--   oscillator to it (phase reference) and sets colour gain from it.
--     U: burst_ii_n switches its sink OFF during the burst -> U rises ~910 mV
--        (-U) on every line.
--     V: in active video burst_star_n is on and burst_star off. During the
--        burst, EVEN lines turn both on (V falls 958 mV, +V, 135 deg) and ODD
--        lines turn both off (V rises 958 mV, -V, 225 deg).
--   The ±V swing averages to -U (180 deg, as NTSC) and tells the decoder which
--   lines carry inverted V. The pixel is blanked black during the burst, so
--   the colour sinks stay in the zero-point pattern.
--
-- ── Source of truth: the CURRENTS, not the book's voltage tables ─────
--   The book prints voltage truth tables derived from these currents, but
--   they are inconsistently rounded and contain outright errors: the U table's
--   current columns are copies of Y's (its voltage columns are right), and the
--   V table's odd-line burst reads 3.112 V where its own currents give ~2.87 V
--   (it drops the blue term). Where they disagree, THESE constants are right.
--   Do not "correct" them to match the printed tables. The design agrees with
--   the book's figures to within a few mV everywhere else.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   Y group  hl_n, red_i, green_i, blue_i, sync_n  -> y_n
--   U group  red_ii_n, green_ii_n, blue_ii, burst_ii_n  -> u
--   V group  red_star, green_star_n, blue_star_n, burst_star, burst_star_n -> v
--   Inputs come from yuv_control_signals (colour, BRIGHT, sync) and
--   pal_v_burst (burst). Outputs are millivolts_t. Converting to DAC codes
--   belongs in a separate boundary module, so the DAC choice stays out of here.
--
-- Verified by yuv_tb (111 checks): exhaustive sweeps of all three channels
-- against reference models built independently from the currents, plus the
-- book's anchor values, ordering, symmetry and pair-sum checks.
----------------------------------------------------------------------------------

package yuv_levels_pkg is

    -- Top of range: 5.0 V rail - 0.7 V Vbe, no current sinks conducting.
    constant v_top : integer := 4300;

    -- All video voltages in this design are integer MILLIVOLTS,
    -- measured at the output transistor's emitter.

    subtype millivolts_t is integer range 0 to V_TOP;

end package yuv_levels_pkg;

library ieee;
    use ieee.std_logic_1164.all;
    use work.yuv_levels_pkg.all;

entity yuv is
    port (
        -- Y_n group
        hl_n    : in    std_logic;
        red_i   : in    std_logic;
        green_i : in    std_logic;
        blue_i  : in    std_logic;
        sync_n  : in    std_logic;
        y_n     : out   millivolts_t; -- millivolts

        -- U group
        red_ii_n   : in    std_logic;
        green_ii_n : in    std_logic;
        blue_ii    : in    std_logic;
        burst_ii_n : in    std_logic;
        u          : out   millivolts_t; -- millivolts

        -- V group
        red_star     : in    std_logic;
        green_star_n : in    std_logic;
        blue_star_n  : in    std_logic;
        burst_star   : in    std_logic;
        burst_star_n : in    std_logic;
        v            : out   millivolts_t -- millivolts
    );
end entity yuv;

architecture behavioural of yuv is

    -- Y Channel
    -- ── Voltage contributions, in millivolts ────────────────────────
    -- Output transistor saturates: it can drop at most 4.041 V across R2,
    -- so y_n cannot fall below 4.300 - 4.041 = 0.259 V. Only bright white
    -- (sum 4359 mV) exceeds this; every other combination is below the limit.
    constant v_min_y : integer := 259;

    -- Sync
    constant v_sync_y : integer := 1851; -- 0.597 mA x 3.1k = 1850.7 mV

    -- Blue
    constant v_blue_y    : integer := 285; -- 0.092 mA x 3.1k =  285.2 mV
    constant v_blue_br_y : integer := 366; -- 0.118 mA x 3.1k =  365.8 mV

    -- Red
    constant v_red_y    : integer := 552; -- 0.178 mA x 3.1k =  551.8 mV
    constant v_red_br_y : integer := 725; -- 0.234 mA x 3.1k =  725.4 mV

    -- Green
    constant v_green_y    : integer := 1079; -- 0.348 mA x 3.1k =  1078.8 mV
    constant v_green_br_y : integer := 1417; -- 0.457 mA x 3.1k =  1416.7 mV

    -- Unclamped sum. MUST allow negative values
    -- bright white reaches -59 mV before clamping, so this cannot be millivolts_t.
    signal y_raw_y : integer range -100 to V_TOP;
    -- ── Per-signal contributions selected by the colour inputs ──────
    signal v_sync_c_y  : millivolts_t;
    signal v_red_c_y   : millivolts_t;
    signal v_green_c_y : millivolts_t;
    signal v_blue_c_y  : millivolts_t;

    -- U channel
    constant v_black_u : integer := 364;  -- 0.235 mA x 1.55k =  364.3 mV  (always on)
    constant v_red_u   : integer := 335;  -- 0.216 mA x 1.55k =  334.8 mV
    constant v_green_u : integer := 668;  -- 0.431 mA x 1.55k =  668.1 mV
    constant v_blue_u  : integer := 1011; -- 0.652 mA x 1.55k = 1010.6 mV
    constant v_burst_u : integer := 910;  -- 0.587 mA x 1.55k =  909.9 mV

    signal v_red_c_u   : millivolts_t;
    signal v_green_c_u : millivolts_t;
    signal v_blue_c_u  : millivolts_t;
    signal v_burst_c_u : millivolts_t;

    -- V channel

    constant v_red_v     : integer := 1417; -- 0.457 mA x 3.1k = 1416.7 mV
    constant v_green_v   : integer := 1187; -- 0.383 mA x 3.1k = 1187.3 mV
    constant v_blue_v    : integer := 242;  -- 0.078 mA x 3.1k =  241.8 mV
    constant v_burst_v   : integer := 958;  -- 0.309 mA x 3.1k =  957.9 mV (burst_star sink)
    constant v_burst_n_v : integer := 958;  -- 0.309 mA x 3.1k =  957.9 mV (burst_star_n sink)

    signal v_red_c_v     : millivolts_t;
    signal v_green_c_v   : millivolts_t;
    signal v_blue_c_v    : millivolts_t;
    signal v_burst_c_v   : millivolts_t;
    signal v_burst_n_c_v : millivolts_t;

begin

    -- Y channel
    v_blue_c_y <= 0 when blue_i = '0' else
                  v_blue_br_y when hl_n = '0' else
                  v_blue_y;

    v_red_c_y <= 0 when red_i = '0' else
                 v_red_br_y when hl_n = '0' else
                 v_red_y;

    v_green_c_y <= 0 when green_i = '0' else
                   v_green_br_y when hl_n = '0' else
                   v_green_y;

    v_sync_c_y <= 0 when sync_n = '0' else
                  v_sync_y;

    y_raw_y <= V_TOP - v_sync_c_y - v_blue_c_y - v_red_c_y - v_green_c_y;
    y_n     <= v_min_y when y_raw_y < v_min_y else
               y_raw_y; -- clamp the bright white output above 0 volts

    -- U channel
    v_red_c_u   <= v_red_u when red_ii_n = '1' else
                   0;
    v_green_c_u <= v_green_u when green_ii_n = '1' else
                   0;
    v_blue_c_u  <= v_blue_u when blue_ii = '1' else
                   0;
    v_burst_c_u <= v_burst_u when burst_ii_n = '1' else
                   0;

    u <= V_TOP - v_red_c_u - v_green_c_u - v_blue_c_u - v_burst_c_u - v_black_u;

    -- V channel
    v_red_c_v     <= v_red_v when red_star = '1' else
                     0;
    v_green_c_v   <= v_green_v when green_star_n = '1' else
                     0;
    v_blue_c_v    <= v_blue_v when blue_star_n = '1' else
                     0;
    v_burst_c_v   <= v_burst_v when burst_star = '1' else
                     0;
    v_burst_n_c_v <= v_burst_n_v when burst_star_n = '1' else
                     0;

    v <= V_TOP - v_red_c_v - v_green_c_v - v_blue_c_v - v_burst_c_v - v_burst_n_c_v;

end architecture behavioural;
