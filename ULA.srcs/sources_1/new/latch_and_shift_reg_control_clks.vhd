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
--   3. sload + attr_output_latch_n transfer that pair to the pixel shift
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
--    4  | sload              (shift reg load)      |
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
--     * the clock chain was 5 inverters (odd = a plain inversion of s_pix_clk),
--       which is just clk_7_n, already an input port;
--     * the 24 ns chain was 3 inverters (odd = an inversion), replaced by a
--       single not().
--   The ORDERING the 24 ns delay bought is preserved as a logic condition:
--   vid_cas_pulse = s_pix_clk AND c0 enters the strobe NOR, so the strobe
--   cannot assert while the pixel clock is high. See the body comments.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   clk_7_n     inverted 7 MHz clock — the clock the logic runs on (book name)
--   c0/c0_n, c1/c1_n, c2_n, c3_n
--               horizontal counter taps (true and complement as needed)
--   border_n     active-low border flag from video_sync
--   vid_c3_n    OUT: the display fetch window, active low = border OR c3_n
--               ('0' while c3 is high inside the display). Generated here,
--               where the book draws it; ras_cas_generation consumes it.
--   clk_7_pixel pixel clock = not(clk_7_n)
--   vid_cas_pulse         video CAS pulse (also used internally)
--   pixel_data_latch_n    -> integration cell (active-low)
--   attr_data_latch_n     -> integration cell (active-low)
--   video_en              -> integration cell (border-latched display enable)
--   sload                -> integration cell (active-high)
--   attr_output_latch_n   -> integration cell (active-low: '0' transparent)
--
-- ── vid_c3_n: the display fetch window ───────────────────────────────
--   vid_c3_n = border OR c3_n
--   '0' only while c3 is high (the second half of each 16-pixel group, when
--   the four bytes A/B/C/D are fetched) AND the beam is inside the display.
--   Both strobe legs (display byte and attribute byte) are qualified by it,
--   and it is exported so ras_cas_generation makes the video RAS/CAS in the
--   same window: one gate, one source, two blocks.
--
-- NOTE: in the book's gates (architecture structural) sload is decoded in
-- pixel 4, one pixel before attr_output_latch_n (pixel 5). The shift
-- register still loads at the START of pixel 5, because the decoded sload
-- only changes a few ns after the counter edge (ripple).
--
-- ── Architecture synchronous ─────────────────────────────────────────
--   The four strobes are registered on clk_14 instead of decoded from the
--   counter, so they cannot glitch. The system testbench (ula_tb) showed the
--   gate strobes reopening the data latches for 1-3 ns just after the DRAM
--   released the bus (the book's 24 ns clk7 delay, dropped here, used to
--   prevent that), so the latches captured 0xFF.
--   tick = c2 c1 c0 clk_7 (0..15, pixel p = ticks 2p, 2p+1). A registered
--   strobe is active one tick AFTER the tick it decodes:
--     pixel_data_latch_n  ticks 2, 10   (pixels 1, 5 first half)
--     attr_data_latch_n   ticks 6, 14   (pixels 3, 7 first half)
--     sload               ticks 7, 8    (straddles the start of pixel 4)
--     attr_output_latch_n ticks 8, 9    (pixel 4)
--
--   WINDOWS ARE CENTRED ON THE EDGE THEY ARE FOR. A registered strobe changes
--   ON the clk_14 edge; the pixel clock changes ~3 ns AFTER that edge (it
--   comes through the divider). So a strobe whose window starts or ends at
--   the tick where the shift register clocks changes only ~3 ns before the
--   edge that samples it, and whether the load happens depends on the order
--   of simultaneous gate events (ula_tb found exactly that race). sload is
--   therefore high for a whole tick either side of the pixel-4 clock edge,
--   and the attribute output latch opens at the same pixel, so a character's
--   pixels and its attribute switch together. At pixel 4 both inputs are
--   stable: the display latch closed in pixel 1 (reopens in pixel 5), the
--   attribute latch in pixel 3 (reopens in pixel 7).
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity latch_and_shift_reg_control_clks is
    port (
        clk_14              : in    std_logic;
        clk_7               : in    std_logic;
        clk_7_n             : in    std_logic; -- inverted 7 MHz clock (book's clk_7_n); logic runs on this
        c0_n                : in    std_logic; -- horizontal counter bit 0, complement
        c0                  : in    std_logic; -- horizontal counter bit 0
        c3_n                : in    std_logic; -- horizontal counter bit 3, complement
        c1                  : in    std_logic; -- horizontal counter bit 1
        c1_n                : in    std_logic; -- horizontal counter bit 1, complement
        c2                  : in    std_logic;
        c2_n                : in    std_logic; -- horizontal counter bit 2, complement
        border_n            : in    std_logic; -- border region flag from video_sync (active-low)
        vid_c3_n            : out   std_logic; -- display fetch window, active low (border OR c3_n)
        clk_7_pixel         : out   std_logic; -- pixel clock = not(clk_7_n)
        vid_cas_pulse       : out   std_logic; -- video CAS pulse
        pixel_data_latch_n  : out   std_logic; -- -> integration cell pixel_data_latch_n (active-low)
        attr_data_latch_n   : out   std_logic; -- -> integration cell attr_data_latch_n  (active-low)
        video_en            : out   std_logic; -- -> integration cell video_en
        sload               : out   std_logic; -- -> integration cell sload
        attr_output_latch_n : out   std_logic  -- -> integration cell attr_output_latch_n (ACTIVE-LOW)
    );
end entity latch_and_shift_reg_control_clks;

architecture synchronous of latch_and_shift_reg_control_clks is

    -- keep: from structural
    signal s_pix_clk       : std_logic;
    signal s_vid_cas_pulse : std_logic;
    signal s_border        : std_logic;
    signal s_vid_en        : std_logic;
    signal s_vid_en_n      : std_logic;
    signal s_vid_c3_n      : std_logic;

    -- new: position within the 8-pixel character, {c2, c1, c0, half-pixel}
    signal s_tick : std_logic_vector(3 downto 0);

    -- new: the registered strobes, starting inactive
    signal s_pixel_data_latch_n  : std_logic := '1';
    signal s_attr_data_latch_n   : std_logic := '1';
    signal s_sload               : std_logic := '0';
    signal s_attr_output_latch_n : std_logic := '1';

begin

    -- keep: video_en latch, pixel clock, vid_cas_pulse, vid_c3_n
    gd_latch : entity work.data_latch_1_bit
        port map (
            e   => c3_n,
            d   => border_n,
            q   => s_vid_en,
            q_n => s_vid_en_n
        );

    s_pix_clk       <= not(clk_7_n);
    clk_7_pixel     <= s_pix_clk;
    s_vid_cas_pulse <= not(clk_7_n or c0_n);
    vid_cas_pulse   <= s_vid_cas_pulse;
    s_border        <= not(border_n);
    s_vid_c3_n      <= s_border or c3_n;
    vid_c3_n        <= s_vid_c3_n;
    video_en        <= s_vid_en;

    -- new: tick 0..15 = 2 x pixel + half (clk_7 = '0' first half, '1' second)
    s_tick <= c2 & c1 & c0 & clk_7;

    -- new: the strobes, registered on clk_14 so they cannot glitch.
    -- A registered output appears one tick after the tick it decodes,
    -- so each line decodes the tick BEFORE the one the strobe is active in.
    strobe_reg : process (clk_14) is
    begin

        if rising_edge(clk_14) then
            -- defaults: everything inactive
            s_pixel_data_latch_n  <= '1';
            s_attr_data_latch_n   <= '1';
            s_sload               <= '0';
            s_attr_output_latch_n <= '1';

            -- display byte: active ticks 2, 10 (pixels 1, 5 first half)
            if ((s_tick = "0001" or s_tick = "1001") and s_vid_c3_n = '0') then
                s_pixel_data_latch_n <= '0';
            end if;

            -- attribute byte: active ticks 6, 14 (pixels 3, 7 first half),
            -- only inside the fetch window
            if ((s_tick = "0101" or s_tick = "1101") and s_vid_c3_n = '0') then
                s_attr_data_latch_n <= '0';
            end if;

            -- sload: active ticks 7, 8, straddling the start of pixel 4 (the
            -- shift register loads on that edge), only when video_en
            if ((s_tick = "0110" or s_tick = "0111") and s_vid_en_n = '0') then
                s_sload <= '1';
            end if;

            -- attribute output latch: active ticks 8, 9 (pixel 4), so the attribute
            -- changes at the same edge the shift register loads
            if (s_tick = "0111" or s_tick = "1000") then
                s_attr_output_latch_n <= '0';
            end if;
        end if;

    end process strobe_reg;

    pixel_data_latch_n  <= s_pixel_data_latch_n;
    attr_data_latch_n   <= s_attr_data_latch_n;
    sload               <= s_sload;
    attr_output_latch_n <= s_attr_output_latch_n;

end architecture synchronous;

architecture structural of latch_and_shift_reg_control_clks is

    signal s_pix_clk       : std_logic;
    signal s_vid_cas_pulse : std_logic;
    signal s_border        : std_logic;
    signal s_b_out         : std_logic;
    signal s_c_out         : std_logic;
    signal s_c_out_n       : std_logic;
    signal s_vid_en        : std_logic;
    signal s_vid_en_n      : std_logic;
    signal s_sload         : std_logic;
    signal s_a_latch       : std_logic;
    signal s_vid_c3_n      : std_logic;

begin

    gd_latch : entity work.data_latch_1_bit
        port map (
            e   => c3_n,
            d   => border_n,
            q   => s_vid_en,
            q_n => s_vid_en_n
        );

    s_pix_clk   <= not(clk_7_n);
    clk_7_pixel <= s_pix_clk;

    -- Video CAS pulse: high only while the pixel clock is LOW and c0='1'.
    --
    -- The book delays the clock through an inverter chain here so it "lines up"
    -- with the c0-c3 counter bits. That chain is an ANALOG propagation delay and
    -- has no FPGA equivalent: an even/odd chain of not() is 0 ns in simulation
    -- and is optimised away to a wire by synthesis, so it cannot create the
    -- alignment. It is also unnecessary -- the chain was 5 inverters (odd), i.e.
    -- a plain inversion of s_pix_clk, and since s_pix_clk = not(clk_7_n) that is
    -- simply clk_7_n, which we already have as an input port. So the delayed
    -- clock is replaced by clk_7_n directly: same logic, no phantom delay.
    s_vid_cas_pulse <= not(clk_7_n or c0_n);
    vid_cas_pulse   <= s_vid_cas_pulse;

    s_border <= not(border_n);
    -- the display fetch window (active low): c3 high inside the display
    s_vid_c3_n <= s_border or c3_n;
    vid_c3_n   <= s_vid_c3_n;

    -- DISPLAY (bitmap) byte capture -- fires at c1='0', c0='1' (pixels 1 and 5
    -- of the character cell), i.e. the book's vid_cas_ac / "first and third byte".
    -- Expanding the NOR: s_b_out = not(s_pix_clk) AND vid_c3 AND c0 AND not(c1),
    -- so the strobe is ALREADY gated by the clock being low -- it cannot assert
    -- while the pixel clock is high. That is the ordering the book buys with its
    -- 24 ns delay ("clk7 goes low before the latch"), obtained here as a logic
    -- condition instead of a propagation delay, which is what actually works on
    -- an FPGA. The book's 3-inverter delay chain on the output was an odd count,
    -- i.e. just an inversion, so a single not() replaces it exactly.
    s_b_out            <= not(s_vid_cas_pulse or s_vid_c3_n or c0_n or c1);
    pixel_data_latch_n <= not(s_b_out);

    s_c_out           <= not(s_vid_cas_pulse or s_vid_c3_n or c0_n or c1_n);
    s_c_out_n         <= not(s_c_out);
    attr_data_latch_n <= s_c_out_n;

    video_en <= s_vid_en;

    s_sload <= not(s_vid_en_n or c1 or c0 or c2_n);
    sload   <= s_sload;

    s_a_latch           <= not(c2_n or c0_n or c1);
    attr_output_latch_n <= not(s_a_latch);

end architecture structural;
