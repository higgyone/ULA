----------------------------------------------------------------------------------
-- attr_output_latch_border_select_mux_tb — self-checking TB for the
-- pixel/colour datapath integration cell.
--
-- What it proves, in plain words:
--   Drive a whole character cell through the block — a pixel byte and an
--   attribute byte — and check the blue/red/green (plus hl/fl) outputs, one
--   pixel at a time, against an independent reference model. It exercises
--   every row of the header's pixel table:
--     * display area, no flash        — lit pixel = INK,  background = PAPER
--     * display area, flash active    — INK/PAPER swap on the flash_clk='0' half
--     * flash bit set but flash_clk='1' — swap suppressed (flash_clk gating)
--     * BRIGHT bit                    — hl passes through in the display area
--     * border region (vid_en='0')    — background = BORDER, hl/fl forced 0
--     * blanking (v_sync / h_blank_n) — colour forced black, hl/fl unaffected
--
-- Drive sequence (mirrors pixel_serialiser_tb, which signed off the front path):
--   1. Present the attribute byte and capture it: input latch transparent
--      (attr_data_latch_n='0') -> output latch transparent
--      (attr_output_latch='1') -> then hold the output latch (='0'). This
--      freezes the cell's colours + fl/hl for all 8 pixels (double buffer).
--   2. Capture the pixel byte in its latch, then LOAD the shift register
--      (s_load='1', one falling clk edge): serial pixel = bit7 (MSB).
--   3. Hold s_load='0' and clock: bit6..bit0 appear one per falling edge.
--   The falling edge of clk_7 is the active (commit) edge for the shift
--   register; a SETTLE wait after each edge lets the `after tg` gate delays
--   finish before sampling. Any mismatch is fatal; a clean run prints
--   "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity attr_output_latch_border_select_mux_tb is
end entity attr_output_latch_border_select_mux_tb;

architecture behavioral of attr_output_latch_border_select_mux_tb is

    constant t      : time := 100 ns; -- clk_7 period
    constant settle : time := 25 ns;  -- > worst-case gate settle after an edge

    -- one stimulus case: a character cell plus its display/blank context

    type scenario_t is record
        pixel     : std_logic_vector(7 downto 0); -- 8 pixel bits (MSB painted first)
        attr      : std_logic_vector(7 downto 0); -- D7 fl|D6 hl|D5:3 paper|D2:0 ink
        border    : std_logic_vector(2 downto 0); -- border colour; b0-Blue b1-Red b2-Green
        vid_en    : std_logic;                    -- '1' display area, '0' border region
        flash_clk : std_logic;                    -- slow flash toggle (live, not latched)
        v_sync    : std_logic;                    -- '1' vertical sync -> black
        h_blank_n : std_logic;                    -- '0' horizontal blank -> black
    end record scenario_t;

    type scenario_arr is array (natural range <>) of scenario_t;

    -- ink   = attr(2:0) = "010" (Red), paper = attr(5:3) = "100" (Green)
    constant scenarios : scenario_arr :=
    (
        -- 0: display, no flash: lit=INK(red), bg=PAPER(green)
        (
            "11010010",
            "00100010",
            "000",
            '1',
            '1',
            '0',
            '1'
        ),
        -- 1: display, flash active (attr7=1, flash_clk=0): INK/PAPER swap
        (
            "11010010",
            "10100010",
            "000",
            '1',
            '0',
            '0',
            '1'
        ),
        -- 2: display, flash bit set but flash_clk=1: swap suppressed
        (
            "11010010",
            "10100010",
            "000",
            '1',
            '1',
            '0',
            '1'
        ),
        -- 3: display, BRIGHT set (attr6=1): hl='1'
        (
            "11010010",
            "01100010",
            "000",
            '1',
            '1',
            '0',
            '1'
        ),
        -- 4: border (vid_en=0): bg=BORDER(blue+red), hl/fl forced 0
        (
            "10100000",
            "10100010",
            "011",
            '0',
            '0',
            '0',
            '1'
        ),
        -- 5: blank via v_sync: colour black, hl/fl unaffected
        (
            "11110000",
            "00100010",
            "000",
            '1',
            '1',
            '1',
            '1'
        ),
        -- 6: blank via h_blank_n: colour black
        (
            "10101010",
            "00100010",
            "000",
            '1',
            '1',
            '0',
            '0'
        )
    );

    signal clk_7              : std_logic                    := '0';
    signal flash_clk          : std_logic                    := '0';
    signal s_load             : std_logic                    := '0';
    signal pixel_data_latch_n : std_logic                    := '1';
    signal pixel_data         : std_logic_vector(7 downto 0) := (others => '0');
    signal attr_data_latch_n  : std_logic                    := '1';
    signal attr_data          : std_logic_vector(7 downto 0) := (others => '0');
    signal border_colour_bgr  : std_logic_vector(2 downto 0) := (others => '0');
    signal video_en           : std_logic                    := '0';
    signal attr_output_latch  : std_logic                    := '0';
    signal v_sync             : std_logic                    := '0';
    signal h_blank_n          : std_logic                    := '1';

    signal blue  : std_logic;
    signal green : std_logic;
    signal red   : std_logic;
    signal hl    : std_logic;
    signal fl    : std_logic;

    -- reference model: expected (b,r,g) for one pixel given its serial bit.
    -- returns a vector packed as (0=>blue, 1=>red, 2=>green).

    function exp_rgb (
        sc     : scenario_t;
        serial : std_logic
    ) return std_logic_vector is

        variable fl_i : std_logic;
        variable gate : std_logic;
        variable dsn  : std_logic;

    begin

        fl_i := sc.attr(7) and sc.vid_en;  -- latched flash (gated by vid_en)
        gate := fl_i and not sc.flash_clk; -- flash swap active only on flash_clk='0'
        -- data_select_n = XNOR(serial, gate): '1' -> paper/border, '0' -> ink
        if (serial = gate) then
            dsn := '1';
        else
            dsn := '0';
        end if;

        if (sc.v_sync = '1' or sc.h_blank_n = '0') then
            return "000";               -- blanked: black
        elsif (dsn = '0') then
            return sc.attr(2 downto 0); -- INK  : b0=attr0, r=attr1, g=attr2
        elsif (sc.vid_en = '1') then
            return sc.attr(5 downto 3); -- PAPER: b0=attr3, r=attr4, g=attr5
        else
            return sc.border;           -- BORDER: b0=border0, r=border1, g=border2
        end if;

    end function exp_rgb;

    -- format a std_logic_vector as a '0'/'1' string for report messages

    function to_bin (
        v : std_logic_vector
    ) return string is

        variable s   : string(1 to v'length);
        variable idx : integer := 1;

    begin

        for i in v'range loop

            if (v(i) = '1') then
                s(idx) := '1';
            else
                s(idx) := '0';
            end if;

            idx := idx + 1;

        end loop;

        return s;

    end function to_bin;

begin

    dut : entity work.attr_output_latch_border_select_mux(structural)
        port map (
            clk_7              => clk_7,
            flash_clk          => flash_clk,
            s_load             => s_load,
            pixel_data_latch_n => pixel_data_latch_n,
            pixel_data         => pixel_data,
            attr_data_latch_n  => attr_data_latch_n,
            attr_data          => attr_data,
            border_colour_bgr  => border_colour_bgr,
            video_en           => video_en,
            attr_output_latch  => attr_output_latch,
            v_sync             => v_sync,
            h_blank_n          => h_blank_n,
            blue               => blue,
            green              => green,
            red                => red,
            hl                 => hl,
            fl                 => fl
        );

    -- free-running clock; falling edge is the active (commit) edge
    clk_gen : process is
    begin

        clk_7 <= '0';
        wait for t / 2;
        clk_7 <= '1';
        wait for t / 2;

    end process clk_gen;

    stim : process is

        variable sc     : scenario_t;
        variable ve     : std_logic_vector(2 downto 0);
        variable sbit   : std_logic;
        variable checks : integer := 0;

    begin

        for s in scenarios'range loop

            sc := scenarios(s);

            ------------------------------------------------------------------
            -- 1) present + capture the attribute byte into the double buffer
            ------------------------------------------------------------------
            attr_data         <= sc.attr;
            border_colour_bgr <= sc.border;
            video_en          <= sc.vid_en;
            attr_data_latch_n <= '0';                                                                 -- input latch transparent
            attr_output_latch <= '1';                                                                 -- output latch transparent
            wait for 2 * settle;                                                                      -- let attr flow through both latches
            attr_output_latch <= '0';                                                                 -- HOLD: freeze colours + hl/fl
            attr_data_latch_n <= '1';                                                                 -- hold input latch too
            wait for settle;

            -- live (unlatched) colour-mux context for this scenario
            flash_clk <= sc.flash_clk;
            v_sync    <= sc.v_sync;
            h_blank_n <= sc.h_blank_n;
            wait for settle;

            -- hl/fl are the latched bright/flash bits (gated by vid_en);
            -- constant across the 8 pixels, so check once here.
            assert hl = (sc.attr(6) and sc.vid_en)
                report "FAIL scn " & integer'image(s) & ": hl expected "
                       & std_logic'image(sc.attr(6) and sc.vid_en) & " got " & std_logic'image(hl)
                severity failure;
            assert fl = (sc.attr(7) and sc.vid_en)
                report "FAIL scn " & integer'image(s) & ": fl expected "
                       & std_logic'image(sc.attr(7) and sc.vid_en) & " got " & std_logic'image(fl)
                severity failure;
            checks := checks + 2;

            ------------------------------------------------------------------
            -- 2) capture the pixel byte, then LOAD the shift register
            ------------------------------------------------------------------
            pixel_data         <= sc.pixel;
            pixel_data_latch_n <= '0';                                                                -- capture pixel byte
            wait for settle;
            pixel_data_latch_n <= '1';                                                                -- hold it
            wait for settle;

            s_load <= '1';                                                                            -- load mode
            wait until falling_edge(clk_7);                                                           -- LOAD edge: serial = bit7 (MSB)
            wait for settle;

            ------------------------------------------------------------------
            -- 3) sample pixel 0 (MSB), then shift out bits 6..0
            ------------------------------------------------------------------
            sbit   := sc.pixel(7);
            ve     := exp_rgb(sc, sbit);
            assert blue = ve(0) and red = ve(1) and green = ve(2)
                report "FAIL scn " & integer'image(s) & " px 0 serial=" & std_logic'image(sbit)
                       & "  exp(b,r,g)=" & std_logic'image(ve(0)) & std_logic'image(ve(1))
                       & std_logic'image(ve(2)) & "  got=" & std_logic'image(blue)
                       & std_logic'image(red) & std_logic'image(green)
                       & "  [attr=" & to_bin(sc.attr) & " vid_en=" & std_logic'image(sc.vid_en)
                       & " fclk=" & std_logic'image(sc.flash_clk) & "]"
                severity failure;
            checks := checks + 1;

            s_load <= '0';                                                                            -- shift mode for the rest

            for i in 6 downto 0 loop

                wait until falling_edge(clk_7);
                wait for settle;
                sbit   := sc.pixel(i);
                ve     := exp_rgb(sc, sbit);
                assert blue = ve(0) and red = ve(1) and green = ve(2)
                    report "FAIL scn " & integer'image(s) & " px " & integer'image(7 - i)
                           & " serial=" & std_logic'image(sbit) & "  exp(b,r,g)="
                           & std_logic'image(ve(0)) & std_logic'image(ve(1)) & std_logic'image(ve(2))
                           & "  got=" & std_logic'image(blue) & std_logic'image(red)
                           & std_logic'image(green) & "  [attr=" & to_bin(sc.attr)
                           & " vid_en=" & std_logic'image(sc.vid_en)
                           & " fclk=" & std_logic'image(sc.flash_clk) & "]"
                    severity failure;
                checks := checks + 1;

            end loop;

        end loop;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks)"
            severity note;
        wait;

    end process stim;

end architecture behavioral;
