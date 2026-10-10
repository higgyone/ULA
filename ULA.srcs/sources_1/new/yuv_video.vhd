----------------------------------------------------------------------------------
-- yuv_video — the ULA's complete analogue video strand (strand B), as one block
--
-- Pure wiring: instantiates the three strand-B cells and joins them. No logic
-- of its own. Takes the digital pixel colour and the counter taps, and gives
-- out the three voltages the ULA drives to the PCB's PAL encoder: inverted
-- luminance y_n and the colour differences u and v.
--
-- ── The three cells ──────────────────────────────────────────────────
--
--   c4..c6, c7_n, c8_n, v0, sync_n
--              │
--              ▼
--       ┌─────────────┐  burst_ii_n, burst_star, burst_star_n
--       │ pal_v_burst │─────────────────────────────────────┐
--       │  burst_gen  │                                     │
--       └─────────────┘                                     │
--              │ timing                                     │
--              ▼                                            ▼
--       ┌─────────────────────┐  *_i, *_ii*, *_star*,  ┌─────────┐
--       │ yuv_control_signals │  hl_n, sync_i_n        │   yuv   │──► y_n
--       │   control_signals   │───────────────────────►│ yuv_dac │──► u
--       └─────────────────────┘                        └─────────┘──► v
--              ▲
--              │
--   red, green, blue, hl, sync_n
--
--   burst_gen        Gates the colour burst onto the back porch (pixels
--                    384..399) and latches the line parity (v0) during sync.
--                    Gives the PAL phase `timing` and the three burst sinks.
--   control_signals  The PAL V-switch (per-colour XNOR with `timing`) and the
--                    U / V sink-control families, plus hl_n and the buffered
--                    sync.
--   yuv_dac          The current-summing DAC, modelled behaviourally in
--                    integer millivolts (NOT gate-accurate, see yuv.vhd).
--
-- ── Joins ────────────────────────────────────────────────────────────
--   Every join is same-name, same-polarity: no inverters are needed anywhere
--   in this block. The one choice made here is SYNC:
--     raw sync_n  -> burst_gen and control_signals
--     sync_i_n    -> yuv_dac  (the buffered copy, as in the book)
--   Both carry the same value; the buffer is kept for schematic traceability.
--
-- ── Line parity ──────────────────────────────────────────────────────
--   v0 is latched while sync_n is LOW and held for the rest of the line.
--     v0 = '0'  timing = '1'  normal line   V passed straight through,
--                                           burst at +V (both V burst sinks on)
--     v0 = '1'  timing = '0'  inverted line V reflected about its zero point,
--                                           burst at -V (both V burst sinks off)
--   U and Y do not alternate.
--
-- ── Assumption the caller must meet: BLANKING ────────────────────────
--   red/green/blue must be '0' during horizontal blanking. The burst window
--   lies inside it, and the V channel relies on the pixel being black while the
--   burst is on: a coloured pixel during an even-line burst would drive v below
--   0 mV, outside millivolts_t (see yuv_tb). The digital RGB path upstream is
--   responsible for this blanking; this block does not enforce it.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   red, green, blue  pixel colour bits, active high (black during blanking)
--   hl                BRIGHT, active high
--   sync_n            composite sync, active low
--   c4..c6            horizontal counter bits (true)
--   c7_n, c8_n        horizontal counter bits (complement)
--   v0                vertical counter bit 0 = line parity
--   y_n, u, v         output levels, millivolts_t (see yuv_levels_pkg)
--
-- Verified by yuv_video_tb: every input state against a colour-level reference
-- model on both line parities and all 32 burst-counter codes, plus the book's
-- landmark voltages, the PAL alternation and the parity latch.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use work.yuv_levels_pkg.all;

entity yuv_video is
    port (
        red    : in    std_logic;
        green  : in    std_logic;
        blue   : in    std_logic;
        hl     : in    std_logic;
        sync_n : in    std_logic;
        c4     : in    std_logic;
        c5     : in    std_logic;
        c6     : in    std_logic;
        c7_n   : in    std_logic;
        c8_n   : in    std_logic;
        v0     : in    std_logic;
        y_n    : out   millivolts_t; -- millivolts
        u      : out   millivolts_t; -- millivolts
        v      : out   millivolts_t  -- millivolts
    );
end entity yuv_video;

architecture structural of yuv_video is

    signal s_burst_ii_n   : std_logic;
    signal s_burst_star_n : std_logic;
    signal s_burst_star   : std_logic;
    signal s_timing       : std_logic;

    signal s_red_star     : std_logic;
    signal s_red_i        : std_logic;
    signal s_red_ii_n     : std_logic;
    signal s_green_star_n : std_logic;
    signal s_green_i      : std_logic;
    signal s_green_ii_n   : std_logic;
    signal s_blue_star_n  : std_logic;
    signal s_blue_i       : std_logic;
    signal s_blue_ii      : std_logic;
    signal s_hl_n         : std_logic;
    signal s_sync_i_n     : std_logic;

begin

    burst_gen : entity work.pal_v_burst
        port map (
            c4           => c4,
            c5           => c5,
            c6           => c6,
            c7_n         => c7_n,
            c8_n         => c8_n,
            v0           => v0,
            sync_n       => sync_n,
            burst_ii_n   => s_burst_ii_n,
            burst_star_n => s_burst_star_n,
            burst_star   => s_burst_star,
            timing       => s_timing
        );

    yuv_dac : entity work.yuv
        port map (
            -- Y group
            hl_n    => s_hl_n,
            red_i   => s_red_i,
            green_i => s_green_i,
            blue_i  => s_blue_i,
            sync_n  => s_sync_i_n,
            y_n     => y_n,

            -- U group
            red_ii_n   => s_red_ii_n,
            green_ii_n => s_green_ii_n,
            blue_ii    => s_blue_ii,
            burst_ii_n => s_burst_ii_n,
            u          => u,

            -- V group
            red_star     => s_red_star,
            green_star_n => s_green_star_n,
            blue_star_n  => s_blue_star_n,
            burst_star   => s_burst_star,
            burst_star_n => s_burst_star_n,
            v            => v
        );

    control_signals : entity work.yuv_control_signals
        port map (
            timing       => s_timing,
            red          => red,
            green        => green,
            blue         => blue,
            hl           => hl,
            sync_n       => sync_n,
            red_star     => s_red_star,
            red_i        => s_red_i,
            red_ii_n     => s_red_ii_n,
            green_star_n => s_green_star_n,
            green_i      => s_green_i,
            green_ii_n   => s_green_ii_n,
            blue_star_n  => s_blue_star_n,
            blue_i       => s_blue_i,
            blue_ii      => s_blue_ii,
            hl_n         => s_hl_n,
            sync_i_n     => s_sync_i_n
        );

end architecture structural;
