----------------------------------------------------------------------------------
-- latch_and_shift_reg_control_clks — video control clocks
--
-- Generates the strobes that drive the fetch/display double buffer in the
-- pixel/colour datapath (attr_output_latch_border_select_mux). Everything is
-- decoded from the low bits of the master horizontal counter, so the strobes
-- are automatically in step with the rest of the video timing.
--
-- ── The sequence it implements (per character cell) ──────────────────
--   1. pixel_data_latch_n  captures the DISPLAY (bitmap) byte
--   2. attr_data_latch_n   captures the ATTRIBUTE byte
--   3. s_load + attr_output_latch_n transfer that pair to the pixel shift
--      register and the attribute output latch at "output load"
--   4. while those 8 pixels are displayed, the NEXT byte pair is fetched into
--      the now-empty input latches and held, until the next output load
--   i.e. the input latches prefetch while the output latches display.
--
-- ── Strobe positions (pix = c2 c1 c0 = pixel within the character) ───
--   pix | strobe                                    | book name
--   ----+-------------------------------------------+---------------
--    1  | pixel_data_latch_n  (display byte A)      | vid_cas_ac
--    3  | attr_data_latch_n   (attribute byte B)    | vid_cas_bd
--    4  | s_load              (shift reg load)      |
--    5  | attr_output_latch_n (output load) + display byte C | vid_cas_ac
--    7  | attr_data_latch_n   (attribute byte D)    | vid_cas_bd
--   Two display bytes (pixels 1, 5) and two attribute bytes (pixels 3, 7) per
--   c3-high window = the 4-byte A/B/C/D burst covering two characters; the
--   c3-low half is left idle so the CPU can reach the DRAM (contention gap).
--
-- ── Clock ordering (why there are no delay chains here) ──────────────
--   The book builds two propagation delays with inverter chains: one to line
--   the clock up with c0-c3, and a 24 ns one so clk7 falls before the display
--   latch opens. Neither survives on an FPGA — an inverter chain is 0 ns in
--   simulation and is optimised to a wire by synthesis. Both are removed:
--     * the clock chain was 5 inverters (odd = a plain inversion of pix_clk),
--       which is just clk_7_n, already an input port;
--     * the 24 ns chain was 3 inverters (odd = an inversion), replaced by a
--       single not().
--   The ORDERING the 24 ns delay bought is preserved as a logic condition:
--   vid_cas_pulse = pix_clk AND c0 enters the strobe NOR, so the strobe
--   cannot assert while the pixel clock is high. See the body comments.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   clk_7_n     inverted 7 MHz clock — the clock the logic runs on (book name)
--   c0/c0_n, c1/c1_n, c2_n, c3_n
--               horizontal counter taps (true and complement as needed)
--   nborder     active-low border flag from video_sync
--   vid_c3_n    active-low display-qualified c3. DEFERRED input.
--   clk_7_pixel pixel clock = not(clk_7_n)
--   vid_cas_pulse         video CAS pulse (also used internally)
--   pixel_data_latch_n    -> integration cell (active-low)
--   attr_data_latch_n     -> integration cell (active-low)
--   video_en              -> integration cell (border-latched display enable)
--   s_load                -> integration cell (active-high)
--   attr_output_latch_n   -> integration cell (active-low: '0' transparent)
--
-- NOTE: the display leg qualifies itself with a locally decoded vid_c3
-- (a_out = nborder AND c3) while the attribute leg uses the vid_c3_n input
-- port. The two are equivalent when the input is driven consistently; kept as
-- the book draws it. s_load (pixel 4) leads attr_output_latch_n (pixel 5) by
-- one pixel rather than firing together.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity latch_and_shift_reg_control_clks is
    port (
        clk_7_n             : in    std_logic; -- inverted 7 MHz clock (book's clk_7_n); logic runs on this
        c0_n                : in    std_logic; -- horizontal counter bit 0, complement
        c0                  : in    std_logic; -- horizontal counter bit 0
        c3_n                : in    std_logic; -- horizontal counter bit 3, complement
        c1                  : in    std_logic; -- horizontal counter bit 1
        c1_n                : in    std_logic; -- horizontal counter bit 1, complement
        c2_n                : in    std_logic; -- horizontal counter bit 2, complement
        nborder             : in    std_logic; -- border region flag from video_sync (active-low)
        vid_c3_n            : in    std_logic; -- active-low display-qualified c3; deferred input
        clk_7_pixel         : out   std_logic; -- pixel clock = not(clk_7_n)
        vid_cas_pulse       : out   std_logic; -- video CAS pulse
        pixel_data_latch_n  : out   std_logic; -- -> integration cell pixel_data_latch_n (active-low)
        attr_data_latch_n   : out   std_logic; -- -> integration cell attr_data_latch_n  (active-low)
        video_en            : out   std_logic; -- -> integration cell video_en
        s_load              : out   std_logic; -- -> integration cell s_load
        attr_output_latch_n : out   std_logic  -- -> integration cell attr_output_latch_n (ACTIVE-LOW)
    );
end entity latch_and_shift_reg_control_clks;

architecture structural of latch_and_shift_reg_control_clks is

    signal pix_clk         : std_logic;
    signal s_vid_cas_pulse : std_logic;
    signal s_border        : std_logic;
    signal a_out           : std_logic;
    signal a_out_n         : std_logic;
    signal b_out           : std_logic;
    signal c_out           : std_logic;
    signal c_out_n         : std_logic;
    signal s_vid_en        : std_logic;
    signal s_vid_en_n      : std_logic;
    signal s_s_load        : std_logic;
    signal s_a_latch       : std_logic;

begin

    gd_latch : entity work.data_latch_1_bit
        port map (
            e     => c3_n,
            d     => nborder,
            q     => s_vid_en,
            q_bar => s_vid_en_n
        );

    pix_clk     <= not(clk_7_n);
    clk_7_pixel <= pix_clk;

    -- Video CAS pulse: high only while the pixel clock is LOW and c0='1'.
    --
    -- The book delays the clock through an inverter chain here so it "lines up"
    -- with the c0-c3 counter bits. That chain is an ANALOG propagation delay and
    -- has no FPGA equivalent: an even/odd chain of not() is 0 ns in simulation
    -- and is optimised away to a wire by synthesis, so it cannot create the
    -- alignment. It is also unnecessary -- the chain was 5 inverters (odd), i.e.
    -- a plain inversion of pix_clk, and since pix_clk = not(clk_7_n) that is
    -- simply clk_7_n, which we already have as an input port. So the delayed
    -- clock is replaced by clk_7_n directly: same logic, no phantom delay.
    s_vid_cas_pulse <= not(clk_7_n or c0_n);
    vid_cas_pulse   <= s_vid_cas_pulse;

    s_border <= not(nborder);
    a_out    <= not(s_border or c3_n);
    a_out_n  <= not(a_out);

    -- DISPLAY (bitmap) byte capture -- fires at c1='0', c0='1' (pixels 1 and 5
    -- of the character cell), i.e. the book's vid_cas_ac / "first and third byte".
    -- Expanding the NOR: b_out = not(pix_clk) AND vid_c3 AND c0 AND not(c1),
    -- so the strobe is ALREADY gated by the clock being low -- it cannot assert
    -- while the pixel clock is high. That is the ordering the book buys with its
    -- 24 ns delay ("clk7 goes low before the latch"), obtained here as a logic
    -- condition instead of a propagation delay, which is what actually works on
    -- an FPGA. The book's 3-inverter delay chain on the output was an odd count,
    -- i.e. just an inversion, so a single not() replaces it exactly.
    b_out              <= not(s_vid_cas_pulse or a_out_n or c0_n or c1);
    pixel_data_latch_n <= not(b_out);

    c_out             <= not(s_vid_cas_pulse or vid_c3_n or c0_n or c1_n);
    c_out_n           <= not(c_out);
    attr_data_latch_n <= c_out_n;

    video_en <= s_vid_en;

    s_s_load <= not(s_vid_en_n or c1 or c0 or c2_n);
    s_load   <= s_s_load;

    s_a_latch           <= not(c2_n or c0_n or c1);
    attr_output_latch_n <= not(s_a_latch);

end architecture structural;
