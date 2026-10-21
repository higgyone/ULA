----------------------------------------------------------------------------------
-- video_address_generation — video DRAM row/column address multiplexer
--
-- Drives the 7 shared DRAM address pins a6..a0 for the VIDEO side of the memory
-- (Chris Smith, "The ZX Spectrum ULA"). The display RAM is read with a multiplexed
-- row/column address, so one set of pins carries three different things across a
-- fetch. This block selects which, and freezes the row while RAS is low.
--
-- ── The three mux phases ─────────────────────────────────────────────
--   Selected by vid_ras_n (from ras_cas_generation) and c1:
--     s_rsel_n   = not vid_ras_n     ROW       phase: vid_ras_n = '1' (RAS high)
--     cdatasel = NOR(vid_ras_n,c1) DISPLAY   column: RAS low, c1 = '0'
--     cattrsel = NOR(c1_n,vid_ras_n) ATTRIBUTE column: RAS low, c1 = '1'
--   The row is presented BEFORE RAS falls (so RAS captures it), then the mux
--   switches to the column for the rest of the RAS-low period. c1 picks which of
--   the two bytes of the pair is being fetched — display byte or attribute byte.
--
-- ── Address map (what lands on a6..a0 in each phase) ─────────────────
--   phase      | a6  a5  a4  a3  a2  a1  a0
--   -----------+----------------------------
--   ROW        | v4  v3  c7  c6  c5  c4  c2(latched)
--   DISPLAY    | 0   v7  v6  v2  v1  v0  v5
--   ATTRIBUTE  | 0   1   1   0   v7  v6  v5
--   The attribute column's constant 1 1 0 is the 0x1800 attribute-file base,
--   hardwired into the decode rather than counted. This scrambling (v2..v0 and
--   v7..v6 landing in different weights than v5) is what produces the Spectrum's
--   famously non-linear screen layout.
--
--   Each bit is built as a 3-leg NOR-NOR mux: every leg is NOR(value, select_n),
--   so an unselected leg contributes '0' and the final NOR of the legs passes the
--   selected value through unchanged. Bits with fewer than three legs take their
--   constant from a select line fed straight into the output NOR (a3 gets 0 in the
--   attribute phase via cattrsel; a6 gets 0 in both column phases).
--
-- ── Why a0 uses LATCHED c2 (and not c3, and not the book's delay+invert) ──
--   The full reasoning is inline at the row_a0_latch instance below. In short:
--   the fetch slides one c2 period late so c3 is the wrong bit, c2 is the only
--   bit that moves between the burst's two RAS cycles, and the book's delay and
--   inversion must be dropped TOGETHER on an FPGA (the delay cannot exist, and
--   without it the inversion would put the wrong state on the bus). The real
--   requirement — a row held stable for the whole RAS-low period, satisfying
--   tRAH — is expressed as a transparent latch instead of a delay.
--
-- ── ae_n (address enable, active-low) ────────────────────────────────
--   ae   = NOR(s_r_out, border),  s_r_out = NOR(s_q_out, c3),  s_q_out = NOR(c0_n,c1_n,c2_n)
--   i.e. ae = (c0.c1.c2 + c3) AND NOT border
--   Opens the tri-state address drivers one pixel before the c3 fetch window
--   (the c0.c1.c2 term) and holds them through it (the c3 term), while keeping
--   them shut in the border so the CPU can reach the DRAM.
--
-- ── The address pins: tri-state (pins 5..11) ─────────────────────────
--   aN = s_aN when s_ae = '1', else 'Z'          (N = 0..6)
--   The pads are TRI-STATE TOTEM POLES: strong '0' / '1' while /AE is active,
--   high impedance otherwise. While the ULA lets go, the PCB's '157 muxes put
--   the CPU's address on the same pins (row or column, switched by ras_n), so
--   the ULA may only drive them during its own video fetch.
--
--   A0 is special: it also has a TTL input. While the ULA lets go, the Z80's A0
--   reaches pin 5 through the '157 and a bus-isolating resistor, and the ULA
--   reads it for the I/O port decode (io_port_decode_0xfe). This block only
--   drives a0; the top level makes the pin inout and the port decode reads the
--   resolved pin. A1..A6 have no input buffer. See docs/pinout.md.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   vid_ras_n  video RAS tap from ras_cas_generation, active-low. Phase select.
--   c0_n..c7   master horizontal counter taps (true/complement as each leg needs)
--   v0..v7     vertical line counter taps
--   border     border-region flag; forces ae_n de-asserted outside the display
--   a0..a6     multiplexed DRAM address out: tri-state, driven only while ae_n
--              = '0', otherwise 'Z' (the '157 muxes drive the pins)
--   ae_n       address enable, active-low (also exported for the TB / top level)
--
-- Gate style: NOR-with-inverted-inputs throughout, matching the rest of the
-- design. No `after TG` delays are modelled here — the mux is feedback-free
-- combinational logic, and the one stateful element (row_a0_latch) is a
-- data_latch_1_bit instance that carries its own gate delays.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity video_address_generation is
    port (
        vid_ras_n : in    std_logic;
        c0_n      : in    std_logic;
        c1        : in    std_logic;
        c1_n      : in    std_logic;
        c2        : in    std_logic;
        c2_n      : in    std_logic;
        c3        : in    std_logic;
        c4        : in    std_logic;
        c5        : in    std_logic;
        c6        : in    std_logic;
        c7        : in    std_logic;
        v0        : in    std_logic;
        v1        : in    std_logic;
        v2        : in    std_logic;
        v3        : in    std_logic;
        v4        : in    std_logic;
        v5        : in    std_logic;
        v6        : in    std_logic;
        v7        : in    std_logic;
        border    : in    std_logic;

        a0 : out   std_logic;
        a1 : out   std_logic;
        a2 : out   std_logic;
        a3 : out   std_logic;
        a4 : out   std_logic;
        a5 : out   std_logic;
        a6 : out   std_logic;

        ae_n : out   std_logic -- address enable: a0..a6 driven while '0', else 'Z'
    );
end entity video_address_generation;

architecture structural of video_address_generation is

    signal s_rsel_n     : std_logic;
    signal s_cdatasel   : std_logic;
    signal s_cdatasel_n : std_logic;
    signal s_cattrsel   : std_logic;
    signal s_cattrsel_n : std_logic;

    signal s_c2_latched : std_logic;

    signal s_a_out : std_logic;
    signal s_b_out : std_logic;
    signal s_c_out : std_logic;
    signal s_d_out : std_logic;
    signal s_e_out : std_logic;
    signal s_f_out : std_logic;
    signal s_g_out : std_logic;
    signal s_h_out : std_logic;
    signal s_i_out : std_logic;
    signal s_j_out : std_logic;
    signal s_k_out : std_logic;
    signal s_l_out : std_logic;
    signal s_m_out : std_logic;
    signal s_n_out : std_logic;
    signal s_o_out : std_logic;
    signal s_p_out : std_logic;
    signal s_q_out : std_logic;
    signal s_r_out : std_logic;

    signal s_a0 : std_logic;
    signal s_a1 : std_logic;
    signal s_a2 : std_logic;
    signal s_a3 : std_logic;
    signal s_a4 : std_logic;
    signal s_a5 : std_logic;
    signal s_a6 : std_logic;
    signal s_ae : std_logic;

begin

    s_rsel_n <= not(vid_ras_n);

    s_cdatasel   <= not(vid_ras_n or c1);
    s_cdatasel_n <= not(s_cdatasel);

    s_cattrsel   <= not(not(c1) or vid_ras_n);
    s_cattrsel_n <= not(s_cattrsel);

    -- Row address bit a0 -- why c2 stands in for c3, and why it is LATCHED.
    --
    -- The video controller delays the pixel output to give itself time to fetch
    -- the first display/attribute pair, so the byte fetches slide one c2 period
    -- later and the FIRST ras_n falls while c3 is still HIGH. That rules out
    -- both obvious candidates for a0:
    --   c3    is '1' for the whole of its own high window -- but the first fetch
    --         needs '0';
    --   c3_n  is '0' for the whole window -- so the SECOND fetch would get '0'
    --         too, when it needs the next character.
    -- c2 is the only bit that moves between the two RAS cycles of the burst
    -- (counts 8..11 -> '0', counts 12..15 -> '1'), so it supplies the 0 -> 1 the
    -- two consecutive characters need. It is "what c3 would have been" had the
    -- fetch not been shifted.
    --
    -- In the book c2 is both DELAYED and INVERTED, and the two go together:
    --   * the DELAY makes c2 change state only after ras_n has been asserted,
    --     protecting the DRAM row-address hold time (tRAH) and making up for the
    --     propagation delay of the master counter;
    --   * the INVERSION corrects the value, because that delay puts c2's PREVIOUS
    --     state on the address bus. c2 is a toggling counter bit, so its previous
    --     state is the complement of its current one -- inverting the stale value
    --     therefore yields the correct current one.
    -- Net effect at each ras_n falling edge: a0 sees c2's CURRENT (post-transition)
    -- state, giving the two fetches of the burst 0 -> 1, while the actual signal
    -- edge lands safely after RAS has captured the row.
    --
    -- On an FPGA neither half is needed, and they must be dropped TOGETHER:
    -- an inverter chain is 0 ns in simulation and is optimised to a wire by
    -- synthesis, so the delay cannot exist -- and without the delay there is no
    -- stale value for the inversion to correct, so keeping the inversion alone
    -- would put the WRONG state on the bus. There is also nothing to compensate
    -- for: the counter here has no propagation-delay problem. So c2 is used
    -- directly, un-inverted.
    --
    -- What remains is the real requirement, expressed as a LATCH rather than a
    -- delay: in a page read only the COLUMN changes, so the ROW must stay frozen
    -- for the whole RAS-low period. Transparent while ras_n is high (a0 tracks the
    -- counter and settles), held from ras_n falling until it releases -- no edge
    -- races RAS, and tRAH is satisfied by construction.
    row_a0_latch : entity work.data_latch_1_bit
        port map (
            e   => s_rsel_n,
            d   => c2,
            q   => s_c2_latched,
            q_n => open
        );

    s_a_out <= not(s_c2_latched or s_rsel_n);
    s_b_out <= not(v5 or s_cdatasel_n);
    s_c_out <= not(v5 or s_cattrsel_n);

    -- each bit: the NOR-NOR mux onto s_aN, then the tri-state totem-pole pad,
    -- driven only while the address enable is active, otherwise 'Z'
    s_a0 <= not(s_a_out or s_b_out or s_c_out);
    a0   <= s_a0 when s_ae = '1' else
            'Z';

    s_d_out <= not(c4 or s_rsel_n);
    s_e_out <= not(v0 or s_cdatasel_n);
    s_f_out <= not(v6 or s_cattrsel_n);
    s_a1    <= not(s_d_out or s_e_out or s_f_out);
    a1      <= s_a1 when s_ae = '1' else
               'Z';

    s_g_out <= not(c5 or s_rsel_n);
    s_h_out <= not(v1 or s_cdatasel_n);
    s_i_out <= not(v7 or s_cattrsel_n);
    s_a2    <= not(s_g_out or s_h_out or s_i_out);
    a2      <= s_a2 when s_ae = '1' else
               'Z';

    s_j_out <= not(c6 or s_rsel_n);
    s_k_out <= not(v2 or s_cdatasel_n);
    s_a3    <= not(s_j_out or s_k_out or s_cattrsel);
    a3      <= s_a3 when s_ae = '1' else
               'Z';

    s_l_out <= not(c7 or s_rsel_n);
    s_m_out <= not(v6 or s_cdatasel_n);
    s_a4    <= not(s_l_out or s_m_out);
    a4      <= s_a4 when s_ae = '1' else
               'Z';

    s_n_out <= not(v3 or s_rsel_n);
    s_o_out <= not(v7 or s_cdatasel_n);
    s_a5    <= not(s_n_out or s_o_out);
    a5      <= s_a5 when s_ae = '1' else
               'Z';

    s_p_out <= not(v4 or s_rsel_n);
    s_a6    <= not(s_p_out or s_cdatasel or s_cattrsel);
    a6      <= s_a6 when s_ae = '1' else
               'Z';

    s_q_out <= not(c0_n or c1_n or c2_n);
    s_r_out <= not(s_q_out or c3);
    s_ae    <= not(s_r_out or border);
    ae_n    <= not(s_ae);

end architecture structural;
