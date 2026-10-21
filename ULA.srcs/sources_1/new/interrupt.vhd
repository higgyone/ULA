----------------------------------------------------------------------------------
-- interrupt — the Z80's once-a-frame maskable interrupt (/INT)
--
-- The ULA pulls /INT low once per frame, at the start of vertical sync, for
-- 32 T-states. The Spectrum ROM uses it to scan the keyboard and update the
-- frame counter 50 times a second.
--
-- ── What it decodes ──────────────────────────────────────────────────
--   s_int = NOR(not vsync, c6, c7, c8, v0, v1, v2)
--         = vsync AND NOT(v0 OR v1 OR v2) AND NOT(c6 OR c7 OR c8)
--
--     vsync = '1'          lines 248..251 (vertical sync, from video_sync)
--     v0 = v1 = v2 = '0'    of those, only LINE 248
--     c8 = c7 = c6 = '0'    pixels 0..63 of that line
--
--   64 pixels = 32 T-states (1 T-state = 2 pixels), the documented length of
--   the 48K interrupt. The v2 term is redundant (vsync already requires
--   v2 = '0'), but it is in the book's gate, so it is kept.
--
--   int_n: pulled low while s_int = '1', otherwise released to the on-chip
--   pull-up ('H').
--
-- ── Timing: the ~100 ns lag (t_int_lag) ──────────────────────────────
--   The Z80 samples /INT on the RISING edge of its clock and needs it settled
--   80 ns before (setup time). On pin 32 (phicpu_n, inverted) that edge is the
--   pin's FALLING edge.
--
--   int_n starts at pixel 0 of line 248, which is a Z80 FALLING edge (the Z80
--   runs on c0). The next Z80 rising edge is at pixel 1, half a T-state =
--   143 ns later. An instant int_n would give 143 ns of setup.
--
--   The real ULA gave only about 42 ns, below the Z80's 80 ns spec, though
--   the Z80 mostly coped. The book puts this down to propagation delay, made
--   worse by the ripple counters: c6..c8 ripple off c5 (bit3_counter), and the
--   line counter ripples too, so the inputs here settle long after the pixel
--   edge. 143 - 42 = about 100 ns of lag.
--
--   It is modelled as ONE lumped delay on the output, the generic t_int_lag
--   (default 100 ns), because it is measured silicon behaviour: the 1 ns
--   placeholder gate delays elsewhere in the design are far too small to
--   produce it on their own.
--
--   SIMULATION ONLY. Synthesis ignores `after`, so on the FPGA int_n arrives
--   right at the pixel-0 edge, with ~143 ns of setup: within the Z80 spec,
--   and sampled at the SAME rising edge (pixel 1) as on the real machine. What
--   software can see is which edge first samples the interrupt, and that does
--   not change, so the FPGA behaves identically. Do not delay int_n on purpose
--   in hardware. The one rule: int_n must not arrive before the previous
--   rising edge (pixel -1), or the interrupt would be taken a T-state early.
--
-- ── The /INT pin (book) ──────────────────────────────────────────────
--   The output is converted to TTL levels by a NON-INVERTING COLLECTOR
--   FOLLOWER (open collector) with a STRONG on-chip PULL-UP RESISTOR. The
--   transistor can only pull /INT LOW; when it lets go, the pull-up resistor
--   brings the line high. "Strong" means a low-value resistor, chosen for a
--   fast rise time (the D pins' pull-ups are weak); it is still a resistor,
--   so anything pulling the line low overrides it.
--
--   That matters because /INT is a shared line on the Z80: other devices
--   (e.g. on the expansion bus) can pull it low too, and none of them fights
--   the ULA (wired-OR). On the board, pin 12 reaches the Z80's /INT (and the
--   expansion bus) through a 470 ohm series resistor, which also limits the
--   current when another device pulls the line low against the ULA's pull-up.
--   See docs/pinout.md.
--
--   Modelled as '0' / 'H'. 'H' is VHDL's resistive '1', which any '0' on the
--   line overrides; VHDL has no separate "strong resistor" level, and none is
--   needed: the rise time is analogue and not modelled.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   v0, v1, v2  line counter bits 0..2
--   c6, c7, c8  horizontal counter bits 6..8
--   vsync      vertical sync, active high (lines 248..251)
--   int_n       /INT to the Z80, active low: '0', or 'H' (on-chip pull-up)
--
-- Verified by interrupt_tb.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity interrupt is
    generic (
        t_int_lag : time := 100 ns -- real-chip lag of int_n (sim only, see header)
    );
    port (
        v0    : in    std_logic; -- line counter bit 0
        v1    : in    std_logic; -- line counter bit 1
        v2    : in    std_logic; -- line counter bit 2
        c6    : in    std_logic; -- horizontal counter bit 6
        c7    : in    std_logic; -- horizontal counter bit 7
        c8    : in    std_logic; -- horizontal counter bit 8
        vsync : in    std_logic; -- vertical sync, active high
        int_n : out   std_logic  -- /INT to the Z80, active low, open collector
    );
end entity interrupt;

architecture structural of interrupt is

    signal s_vsync_n : std_logic;
    signal s_int     : std_logic;

begin

    s_vsync_n <= not(vsync);

    -- line 248 (first line of vsync), pixels 0..63
    s_int <= not(s_vsync_n or c6 or c7 or c8 or v0 or v1 or v2);

    -- collector follower: pull /INT low, otherwise release it to the
    -- on-chip pull-up; with the real chip's propagation + ripple lag
    -- (sim only)
    int_n <= '0' after t_int_lag when s_int = '1' else
             'H' after t_int_lag;

end architecture structural;
