----------------------------------------------------------------------------------
-- yuv_control_signals — PAL colour-difference (YUV) encoder control signals
--
-- First block of the analogue video-signal strand: takes the digital RGB (+
-- BRIGHT) coming out of the colour back-end and produces the gating signals the
-- YUV / colour-difference encoder needs, with the PAL line-by-line phase
-- alternation already applied.
--
-- ── The PAL V-switch (the 4-NOR XNOR per colour) ─────────────────────
--   Each colour runs through the same four-NOR network:
--     x_0_out = NOR(timing, x)
--     x_1_out = NOR(timing, x_0_out)
--     x_2_out = NOR(x_0_out, x)
--     x_3_out = NOR(x_1_out, x_2_out)
--   which evaluates to a gate-level XNOR:
--
--     timing  x | x_0_out  x_1_out  x_2_out | x_3_out
--     ----------+---------------------------+---------
--       0     0 |    1        0        0    |    1
--       0     1 |    0        1        0    |    0
--       1     0 |    0        0        1    |    0
--       1     1 |    0        0        0    |    1
--
--     => x_3_out = x XNOR timing
--        timing='1' -> x_3_out =     x   (colour passed straight through)
--        timing='0' -> x_3_out = NOT x   (colour sense INVERTED)
--
--   `timing` comes from pal_v_burst (its `timing` output = q_bar, the
--   complement of the per-line latched v0 parity). It therefore alternates
--   every line, and this XNOR is the PAL **V-switch**: Phase Alternating Line.
--   Because pal_v_burst freezes the parity during sync, the phase cannot move
--   mid-line.
--
-- ── Why there are two families: they are U and V ─────────────────────
--   PAL carries colour as two colour-difference components, each a weighted
--   sum of R, G and B:
--
--     V = 0.877*(R-Y) = +0.615*R  -0.515*G  -0.100*B
--     U = 0.493*(B-Y) = -0.147*R  -0.289*G  +0.436*B
--
--   The SIGN of each coefficient is what the port naming encodes — an `_n`
--   suffix marks a NEGATIVE term, no suffix marks a POSITIVE one:
--
--     family        R              G               B              component
--     -----------+--------------+---------------+--------------+-----------
--     *_star     | red_star  +  | green_star_n -| blue_star_n -|    V
--     *_ii       | red_ii_n  -  | green_ii_n   -| blue_ii     +|    U
--
--   So R is the single positive term in V, and B is the single positive term
--   in U — which is exactly why `red_star` and `blue_ii` are the two ports
--   without an `_n`, and why each of them carries an extra buffering inversion
--   to bring it out active HIGH while its siblings expose the NOR directly.
--
--   This also explains which family alternates. V is the component PAL flips
--   line to line — hence "V-switch" — so `timing` is applied to the *_star
--   (V) family only. The *_ii (U) family is derived from the raw red/green/
--   blue inputs and does NOT alternate.
--
--     black_star = NOR(r_3_out, g_3_out, b_3_out)   -- black in the ALTERNATED domain
--     black_ii   = NOR(red, green, blue)            -- true black (all guns off)
--
--   Note the consequence, and it is deliberate rather than a bug: on an
--   inverted line (timing='0') the x_3_out signals are the complements, so
--   `black_star` actually asserts on WHITE. That is self-consistent — the star
--   family is defined entirely within the alternated domain.
--
--   `black_star` is OR'd into each star output so that an all-black (or, on
--   inverted lines, all-white) pixel drives the three star outputs to the same
--   state, giving zero chroma difference between them.
--
-- ── Output polarities — READ THIS BEFORE WIRING ──────────────────────
--   The star outputs are NOT uniform in polarity:
--     red_star      ACTIVE HIGH  = black_star OR r_3_out
--     green_star_n  ACTIVE LOW   = NOR(g_3_out, black_star)
--     blue_star_n   ACTIVE LOW   = NOR(b_3_out, black_star)
--
--   Red differs DELIBERATELY and matches the book: the schematic takes the NOR
--   and then buffers it through a second inversion, i.e.
--     red_star = not( not(black_star or r_3_out) )
--   written here as the internal tap `red_star_n` (the NOR) followed by the
--   buffering inverter. That is the same not(not()) buffer idiom used on red_i /
--   green_i / blue_i / sync_i_n, so red simply exposes the buffered ACTIVE-HIGH
--   side while green and blue expose the ACTIVE-LOW NOR directly.
--
--   Consequence for whoever wires the encoder: compare ASSERTIONS, not raw
--   levels — the same trap documented on pal_v_burst's burst_star /
--   burst_star_n pair.
--
--   The direct (U) family follows the same rule — the two negative terms are
--   the bare NORs, and the positive term takes the extra buffering inversion:
--     red_ii_n    = NOR(red,   black_ii)        active low   (U coeff -0.147)
--     green_ii_n  = NOR(green, black_ii)        active low   (U coeff -0.289)
--     blue_ii     = not(NOR(blue, black_ii))    ACTIVE HIGH  (U coeff +0.436)
--
-- ── Buffers (DELIBERATE — do not "simplify" these away) ──────────────
--   red_i / green_i / blue_i / sync_i_n are written as double inversions
--   `not(not(x))`. This is INTENTIONAL: they are the book's buffers, there for
--   drive and a slight propagation delay, and they are kept in that form for
--   schematic traceability. A future cleanup pass must NOT collapse them to a
--   plain `x <= y` assignment.
--
--   Caveat for anyone reasoning about timing: the delay is real on silicon but
--   NOT reproducible on an FPGA — a not(not()) pair is 0 ns in simulation and
--   synthesis optimises it to a wire. So treat these as identity functions for
--   any logic that depends on their VALUE, and do not build a timing
--   relationship that relies on the delay existing (the same reason the
--   inverter-chain delays were dropped in latch_and_shift_reg_control_clks and
--   video_address_generation — there the delay was load-bearing, here it is not).
--
--   hl_n is a plain inverter on the BRIGHT bit.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   timing    per-line PAL phase from pal_v_burst ('1' pass, '0' invert)
--   red/green/blue  digital colour bits from the colour back-end
--   hl        BRIGHT bit
--   sync_n    composite sync, active low
--   red_star      phase-alternated red,   ACTIVE HIGH
--   green_star_n  phase-alternated green, ACTIVE LOW
--   blue_star_n   phase-alternated blue,  ACTIVE LOW
--   red_i/green_i/blue_i   buffered direct colour bits
--   red_ii_n/green_ii_n   U's negative terms, active low
--   blue_ii               U's positive term,  ACTIVE HIGH
--   hl_n      inverted BRIGHT
--   sync_i_n  buffered composite sync, active low
--
-- Gate style: NOR-with-inverted-inputs throughout. No `after TG` delays — the
-- block is feedback-free combinational logic with no state, same decision as
-- video_address_generation.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity yuv_control_signals is
    port (
        timing       : in    std_logic;
        red          : in    std_logic;
        green        : in    std_logic;
        blue         : in    std_logic;
        hl           : in    std_logic;
        sync_n       : in    std_logic;
        red_star     : out   std_logic;
        red_i        : out   std_logic;
        red_ii_n     : out   std_logic;
        green_star_n : out   std_logic;
        green_i      : out   std_logic;
        green_ii_n   : out   std_logic;
        blue_star_n  : out   std_logic;
        blue_i       : out   std_logic;
        blue_ii      : out   std_logic;
        hl_n         : out   std_logic;
        sync_i_n     : out   std_logic
    );
end entity yuv_control_signals;

architecture structural of yuv_control_signals is

    signal r_0_out : std_logic;
    signal r_1_out : std_logic;
    signal r_2_out : std_logic;
    signal r_3_out : std_logic;

    signal g_0_out : std_logic;
    signal g_1_out : std_logic;
    signal g_2_out : std_logic;
    signal g_3_out : std_logic;

    signal b_0_out : std_logic;
    signal b_1_out : std_logic;
    signal b_2_out : std_logic;
    signal b_3_out : std_logic;

    signal black_star : std_logic;
    signal black_ii   : std_logic;

    signal red_star_n : std_logic;
    signal blue_ii_n  : std_logic;

begin

    -- PAL V-switch, red: four NORs forming r_3_out = red XNOR timing.
    -- timing='1' -> r_3_out = red; timing='0' -> r_3_out = NOT red.
    r_0_out <= not(timing or red);
    r_1_out <= not(timing or r_0_out);
    r_2_out <= not(r_0_out or red);
    r_3_out <= not(r_1_out or r_2_out);

    -- PAL V-switch, green (identical network)
    g_0_out <= not(timing or green);
    g_1_out <= not(timing or g_0_out);
    g_2_out <= not(g_0_out or green);
    g_3_out <= not(g_1_out or g_2_out);

    -- PAL V-switch, blue (identical network)
    b_0_out <= not(timing or blue);
    b_1_out <= not(timing or b_0_out);
    b_2_out <= not(b_0_out or blue);
    b_3_out <= not(b_1_out or b_2_out);

    -- black detect in each domain. black_star works on the ALTERNATED signals, so
    -- on an inverted line (timing='0') it asserts on white -- deliberate, the star
    -- family is defined entirely within the alternated domain. black_ii works on
    -- the raw inputs, so it is true black (all guns off) on every line.
    black_star <= not(r_3_out or g_3_out or b_3_out);
    black_ii   <= not(red or green or blue);

    -- RED. Per the book this leg is not(not(black_star or r_3_out)): the NOR is
    -- tapped as red_star_n, then buffered through a second inversion, so red_star
    -- comes out ACTIVE HIGH while the green/blue star outputs expose the NOR
    -- directly and are ACTIVE LOW. black_star is folded in so an all-black
    -- (alternated: all-white) pixel drives all three stars alike.
    red_star_n <= not(black_star or r_3_out); -- the NOR - internal tap
    red_star   <= not(red_star_n);            -- buffering inverter -> ACTIVE HIGH
    red_i      <= not(not(red));              -- book buffer (see header) - keep the double not
    red_ii_n   <= not(red or black_ii);       -- direct domain, active low

    -- GREEN
    green_star_n <= not(g_3_out or black_star); -- ACTIVE LOW
    green_i      <= not(not(green));            -- book buffer - keep the double not
    green_ii_n   <= not(green or black_ii);     -- direct domain, active low

    -- BLUE
    -- BLUE. blue_ii is U's single POSITIVE term (+0.436), so like red_star in V it
    -- takes the NOR plus a buffering inversion to come out ACTIVE HIGH; blue_star_n
    -- is V's negative blue term (-0.100) and stays the bare NOR, active low.
    blue_star_n <= not(black_star or b_3_out); -- ACTIVE LOW  (V coeff -0.100)
    blue_i      <= not(not(blue));             -- book buffer - keep the double not
    blue_ii_n   <= not(black_ii or blue);      -- the NOR - internal tap
    blue_ii     <= not(blue_ii_n);             -- buffering inverter -> ACTIVE HIGH (U coeff +0.436)

    hl_n     <= not(hl);          -- inverted BRIGHT
    sync_i_n <= not(not(sync_n)); -- book buffer - keep the double not; stays active low

end architecture structural;
