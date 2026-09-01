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

        ae_n : out   std_logic
    );
end entity video_address_generation;

architecture behavioral of video_address_generation is

    signal rsel_n     : std_logic;
    signal cdatasel   : std_logic;
    signal cdatasel_n : std_logic;
    signal cattrsel   : std_logic;
    signal cattrsel_n : std_logic;

    signal c2_latched : std_logic;

    signal a_out : std_logic;
    signal b_out : std_logic;
    signal c_out : std_logic;
    signal d_out : std_logic;
    signal e_out : std_logic;
    signal f_out : std_logic;
    signal g_out : std_logic;
    signal h_out : std_logic;
    signal i_out : std_logic;
    signal j_out : std_logic;
    signal k_out : std_logic;
    signal l_out : std_logic;
    signal m_out : std_logic;
    signal n_out : std_logic;
    signal o_out : std_logic;
    signal p_out : std_logic;
    signal q_out : std_logic;
    signal r_out : std_logic;

    signal ae : std_logic;

begin

    rsel_n <= not(vid_ras_n);

    cdatasel   <= not(vid_ras_n or c1);
    cdatasel_n <= not(cdatasel);

    cattrsel   <= not(not(c1) or vid_ras_n);
    cattrsel_n <= not(cattrsel);

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
            e     => rsel_n,
            d     => c2,
            q     => c2_latched,
            q_bar => open
        );

    a_out <= not(c2_latched or rsel_n);
    b_out <= not(v5 or cdatasel_n);
    c_out <= not(v5 or cattrsel_n);
    a0    <= not(a_out or b_out or c_out);

    d_out <= not(c4 or rsel_n);
    e_out <= not(v0 or cdatasel_n);
    f_out <= not(v6 or cattrsel_n);
    a1    <= not(d_out or e_out or f_out);

    g_out <= not(c5 or rsel_n);
    h_out <= not(v1 or cdatasel_n);
    i_out <= not(v7 or cattrsel_n);
    a2    <= not(g_out or h_out or i_out);

    j_out <= not(c6 or rsel_n);
    k_out <= not(v2 or cdatasel_n);
    a3    <= not(j_out or k_out or cattrsel);

    l_out <= not(c7 or rsel_n);
    m_out <= not(v6 or cdatasel_n);
    a4    <= not(l_out or m_out);

    n_out <= not(v3 or rsel_n);
    o_out <= not(v7 or cdatasel_n);
    a5    <= not(n_out or o_out);

    p_out <= not(v4 or rsel_n);
    a6    <= not(p_out or cdatasel or cattrsel);

    q_out <= not(c0_n or c1_n or c2_n);
    r_out <= not(q_out or c3);
    ae    <= not(r_out or border);
    ae_n  <= not(ae);

end architecture behavioral;
