----------------------------------------------------------------------
-- pal_v_burst — PAL colour-burst gate with line-parity alternation
--
-- Produces the gating signals for the PAL colour burst: the burst window
-- itself, and the two phase-alternating outputs that give PAL its name.
--
-- ── Burst window ─────────────────────────────────────────────────────
--   burst = NOR(c4, c5, c6, c7_n, c8_n)
--         = c8 AND c7 AND NOT c6 AND NOT c5 AND NOT c4
--   c3..c0 are not decoded, so the window is 16 pixels wide and sits at
--   PIXELS 384..399 of the 448-pixel line. Cross-checking horiz_timing:
--     horizontal blanking  320..415   -> the burst is inside it
--     hsync pulse (5c)     336..367   -> the burst is AFTER it
--   i.e. the burst lands on the BACK PORCH, which is where a PAL burst
--   belongs. 16 pixels at 7 MHz = 2.29 us, against the real burst's
--   ~2.25 us (10 cycles of 4.43 MHz).
--   burst_ii_n is the active-low form of that window.
--
-- ── PAL line alternation ─────────────────────────────────────────────
--   PAL = Phase Alternating Line: the burst phase flips on every line.
--   v0 (vertical counter bit 0) is the line parity, and it gates the
--   burst into one of two mutually exclusive outputs:
--
--     burst_star_n = NOT(burst AND q)    -- one parity, ACTIVE LOW
--     burst_star   =     burst AND NOT q -- the other, ACTIVE HIGH
--
--   The two outputs carry OPPOSITE polarities, so each matches its own
--   name, but they are NOT a complement pair -- compare assertions, not
--   raw levels. Full table:
--
--     burst  q | burst_ii_n  burst_star_n  burst_star  timing
--     -------- + ------------------------------------------
--       0    0 |     1            1             0         1
--       0    1 |     1            1             0         0
--       1    0 |     0            1             1         1    <- NOT q phase
--       1    1 |     0            0             0         0    <- q phase
--
--   Only one phase is ever ASSERTED (burst_star_n low, or burst_star
--   high), and never both -- q and NOT q are exclusive. Note the two
--   happen to share a level inside the window; that is a consequence of
--   the opposite polarities, not a relationship between them.
--
-- ── Line-parity latch ────────────────────────────────────────────────
--   v0 is captured by a data_latch_1_bit whose active-low enable is
--   driven by sync_n:
--     sync_n='0' (in sync)     -> transparent, q follows v0
--     sync_n='1' (rest of line)-> held
--   So the parity is sampled once per line during the sync pulse and
--   then frozen, which keeps the burst phase stable for the whole line
--   rather than following any movement on v0 mid-line.
--
--   timing = q_bar = NOT(latched parity).
--
-- ── Ports ────────────────────────────────────────────────────────────
--   c4, c5, c6, c7_n, c8_n  horizontal counter taps decoding the window
--   v0                      vertical counter bit 0 = line parity
--   sync_n                  composite sync, active low; latch enable
--   burst_ii_n              burst window, active low
--   burst_star_n            burst gated by parity q      (ACTIVE LOW)
--   burst_star              burst gated by parity NOT q  (active HIGH)
--   timing                  q_bar, the complemented latched parity
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity pal_v_burst is
    port (
        c4           : in    std_logic;
        c5           : in    std_logic;
        c6           : in    std_logic;
        c7_n         : in    std_logic;
        c8_n         : in    std_logic;
        v0           : in    std_logic;
        sync_n       : in    std_logic;
        burst_ii_n   : out   std_logic;
        burst_star_n : out   std_logic;
        burst_star   : out   std_logic;
        timing       : out   std_logic
    );
end entity pal_v_burst;

architecture structural of pal_v_burst is

    signal burst : std_logic; -- burst window, active high (pixels 384..399)
    signal q     : std_logic; -- latched line parity
    signal q_bar : std_logic; -- complemented latched parity
    signal a_0   : std_logic;

begin

    -- line-parity latch: transparent during sync, held for the rest of
    -- the line, so the burst phase cannot move mid-line
    latch_0 : entity work.data_latch_1_bit
        port map (
            e     => sync_n,
            d     => v0,
            q     => q,
            q_bar => q_bar
        );

    -- burst window: c8='1', c7='1', c6='0', c5='0', c4='0' -> pixels 384..399
    burst      <= not(c4 or c5 or c6 or c7_n or c8_n);
    burst_ii_n <= not burst;

    -- gate the window into the two alternating phases. Only one is ever
    -- asserted; note the opposite polarities (see the table in the header).
    a_0          <= not(burst_ii_n or q_bar); -- = burst AND q
    burst_star_n <= not(a_0);                 -- active LOW  when burst AND q
    burst_star   <= not(q or burst_ii_n);     -- active HIGH when burst AND NOT q

    timing <= q_bar;

end architecture structural;
