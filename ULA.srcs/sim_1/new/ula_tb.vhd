----------------------------------------------------------------------------------
-- ula_tb — system testbench for the whole ULA
--
-- Drives only the ULA's pins, through a model of the Spectrum board around
-- it, and checks the chip end to end. Internal nets (RGB, the counters) are
-- read through VHDL-2008 external names, because the chip's only video
-- outputs are the analogue /Y, U and V levels.
--
-- ── The board model ──────────────────────────────────────────────────
--   * 14 MHz crystal on clk_14; reset (sim only) for 200 ns
--   * lower-16K DRAM (4116s): RAS latches the row from A0..A6, CAS the
--     column; reads drive D0..D7 t_cac after CAS falls. Preloaded with a test
--     screen (no FLASH): each display byte and attribute is different, and
--     ink /= paper, so a wrong address or a wrong pixel shows up
--   * the '157 address mux on A0..A6: a weak 'L' / 'H' (behind its resistor),
--     so the ULA's tri-state drive wins during its fetches
--   * data bus: 8k2 pull-ups ('H'); the Z80 drives it only during its own
--     port write, never during a video fetch (a simplification: the real
--     board isolates the Z80 behind 470 ohm)
--   * keyboard: 10k pull-ups ('H') on K0..K4; one key held on column 2
--   * pin 32: 1k pull-up, then the NPN with 180 ohm on the Z80's clock
--   * issue 3 board: nothing on the far end of RAS (no /RFSH link)
--   * tape_mv = 0 (no tape)
--
-- ── What it checks ───────────────────────────────────────────────────
--   1. PIXELS: every display pixel of frame 0 against the test
--      screen in DRAM (lines 2..191): ink / paper by the pixel bit, the colour
--      and BRIGHT from the attribute. The pipeline delay (counter position ->
--      pixel on the RGB nets) is measured once on line 2, then held fixed. This
--      covers the clock phase into ras_cas_generation, the fetch strobes,
--      the DRAM addressing and the shift register (no delay chain) at once.
--   2. BORDER: after OUT (0xFE),5 the border is cyan (vertical border of
--      frame 0, horizontal border of frame 1); h-blank is black.
--   3. /INT: exactly one pulse per frame, starting on line 248, about 64
--      pixels (32 T-states) long.
--   4. Z80 CLOCK: free-running at 3.5 MHz (286 ns) in the border.
--   5. PORT READ: IN (0xFE) with a key on column 2 reads D0..D4 = 11011,
--      D6 = EAR = 0, and D5 / D7 = 1 (pull-ups).
--   6. RAS: released ('Z') during a ROM-area MREQ in the border.
--   7. NOTE (not a pass / fail): a ROM-area MREQ across the end of a display
--      line, reporting whether RAS is ever released while a video RAS is
--      active (the open vid_ras / border_n question).
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use work.yuv_levels_pkg.all;

library std;
    use std.env.all;

entity ula_tb is
end entity ula_tb;

architecture behavioral of ula_tb is

    constant t_14  : time := 71428 ps; -- 14.000 MHz
    constant t_cac : time := 40 ns;    -- DRAM access time from CAS
    constant t_pix : time := 2 * t_14;

    -- pins
    signal clk_14   : std_logic := '0';
    signal reset    : std_logic := '1';
    signal rd_n     : std_logic := '1';
    signal wr_n     : std_logic := '1';
    signal mreq_n   : std_logic := '1';
    signal ioreq_n  : std_logic := '1';
    signal a14      : std_logic := '0';
    signal a15      : std_logic := '1';
    signal tape_mv  : integer   := 0;
    signal k        : std_logic_vector(4 downto 0);
    signal ras_n    : std_logic;
    signal cas_n    : std_logic;
    signal we_n     : std_logic;
    signal rom_cs_n : std_logic;
    signal int_n    : std_logic;
    signal phicpu_n : std_logic;
    signal a        : std_logic_vector(6 downto 0);
    signal y_n      : millivolts_t;
    signal u        : millivolts_t;
    signal v        : millivolts_t;
    signal sound    : millivolts_t;
    signal d        : std_logic_vector(7 downto 0);

    -- board drivers
    signal mux_a   : std_logic_vector(6 downto 0) := (others => 'L'); -- the '157, weak
    signal dram_d  : std_logic_vector(7 downto 0) := (others => 'Z');
    signal z80_d   : std_logic_vector(7 downto 0) := (others => 'Z');
    signal keys    : std_logic_vector(4 downto 0) := (others => 'Z'); -- '0' = key down
    signal z80_clk : std_logic;
    signal done    : boolean                      := false;

    -- mirrors of internal nets (from the external names)
    signal red     : std_logic;
    signal green   : std_logic;
    signal blue    : std_logic;
    signal hl      : std_logic;
    signal pclk    : std_logic;
    signal vid_ras : std_logic;
    signal cnum    : integer := 0;
    signal vnum    : integer := 0;

    -- results shared between processes
    signal pixel_checks : integer := 0;
    signal pixel_delay  : integer := -1;
    signal int_pulses   : integer := 0;

    ------------------------------------------------------------------
    -- the test screen
    ------------------------------------------------------------------

    type mem_t is array (0 to 16383) of std_logic_vector(7 downto 0);

    function disp_byte (
        y  : integer;
        xb : integer
    ) return std_logic_vector is
    begin

        return std_logic_vector(to_unsigned((y * 7 + xb * 13 + 5) mod 256, 8));

    end function disp_byte;

    function attr_byte (
        row : integer;
        col : integer
    ) return std_logic_vector is

        variable ink    : integer;
        variable paper  : integer;
        variable bright : integer;

    begin

        paper := row mod 8;
        ink   := col mod 8;

        if (ink = paper) then
            ink := (paper + 1) mod 8;
        end if;

        bright := (row + col) mod 2;

        -- b7 FLASH = 0 | b6 BRIGHT | b5..3 PAPER | b2..0 INK
        return std_logic_vector(to_unsigned(bright * 64 + paper * 8 + ink, 8));

    end function attr_byte;

    function screen return mem_t is

        variable m : mem_t := (others => (others => '0'));
        variable o : integer;

    begin

        for y in 0 to 191 loop

            for xb in 0 to 31 loop

                o    := (y / 64) * 2048 + (y mod 8) * 256 + ((y / 8) mod 8) * 32 + xb;
                m(o) := disp_byte(y, xb);

            end loop;

        end loop;

        for row in 0 to 23 loop

            for col in 0 to 31 loop

                m(6144 + row * 32 + col) := attr_byte(row, col);

            end loop;

        end loop;

        return m;

    end function screen;

    -- expected r g b hl for display pixel (x, y)

    function exp_pixel (
        x : integer;
        y : integer
    ) return std_logic_vector is

        variable b   : std_logic_vector(7 downto 0);
        variable at  : std_logic_vector(7 downto 0);
        variable col : std_logic_vector(2 downto 0);

    begin

        b  := disp_byte(y, x / 8);
        at := attr_byte(y / 8, x / 8);

        if (b(7 - (x mod 8)) = '1') then
            col := at(2 downto 0); -- ink
        else
            col := at(5 downto 3); -- paper
        end if;

        -- colour bits: 0 blue, 1 red, 2 green
        return col(1) & col(2) & col(0) & at(6); -- r g b hl

    end function exp_pixel;

    function rgbh (
        r,
        g,
        b,
        h : std_logic
    ) return std_logic_vector is
    begin

        return to_x01(r) & to_x01(g) & to_x01(b) & to_x01(h);

    end function rgbh;

begin

    ------------------------------------------------------------------
    -- the ULA
    ------------------------------------------------------------------
    dut : entity work.ula(structural)
        port map (
            clk_14   => clk_14,
            reset    => reset,
            rd_n     => rd_n,
            wr_n     => wr_n,
            mreq_n   => mreq_n,
            ioreq_n  => ioreq_n,
            a14      => a14,
            a15      => a15,
            tape_mv  => tape_mv,
            k0       => k(0),
            k1       => k(1),
            k2       => k(2),
            k3       => k(3),
            k4       => k(4),
            ras_n    => ras_n,
            cas_n    => cas_n,
            we_n     => we_n,
            rom_cs_n => rom_cs_n,
            int_n    => int_n,
            phicpu_n => phicpu_n,
            a0       => a(0),
            a1       => a(1),
            a2       => a(2),
            a3       => a(3),
            a4       => a(4),
            a5       => a(5),
            a6       => a(6),
            y_n      => y_n,
            u        => u,
            v        => v,
            sound    => sound,
            d0       => d(0),
            d1       => d(1),
            d2       => d(2),
            d3       => d(3),
            d4       => d(4),
            d5       => d(5),
            d6       => d(6),
            d7       => d(7)
        );

    ------------------------------------------------------------------
    -- the board
    ------------------------------------------------------------------
    clk_14 <= not clk_14 after t_14 / 2 when not done else
              clk_14;

    reset <= '0' after 200 ns;

    -- data bus: 8k2 pull-ups, the DRAM, the Z80 (behind 470 ohm)
    d <= (others => 'H');
    d <= dram_d;
    d <= z80_d;

    -- address bus: the '157 behind its resistor
    a <= mux_a;

    -- keyboard: 10k pull-ups and the key matrix
    k <= (others => 'H');
    k <= keys;

    -- pin 32: 1k pull-up; the NPN (180 ohm on the Z80 clock) inverts it
    phicpu_n <= 'H';
    z80_clk  <= '0' when to_x01(phicpu_n) = '1' else
                'H' when to_x01(phicpu_n) = '0' else
                'U';

    -- the lower-16K DRAM
    dram : process (ras_n, cas_n) is

        variable mem : mem_t   := screen;
        variable row : integer := 0;
        variable o   : integer;

    begin

        if falling_edge(ras_n) then
            if (is_x(to_x01(a))) then
                report "DRAM: undefined row address at RAS " & to_string(a)
                    severity warning;
                row := 0;
            else
                row := to_integer(unsigned(to_x01(a)));
            end if;
        end if;

        if falling_edge(cas_n) then
            if (is_x(to_x01(a))) then
                report "DRAM: undefined column address at CAS " & to_string(a)
                    severity warning;
            else
                o := to_integer(unsigned(to_x01(a))) * 128 + row;

                if (to_x01(we_n) = '0') then
                    mem(o) := to_x01(d);
                else
                    dram_d <= mem(o) after t_cac;
                end if;
            end if;
        end if;

        if rising_edge(cas_n) then
            dram_d <= (others => 'Z');
        end if;

    end process dram;

    ------------------------------------------------------------------
    -- mirror the internal nets we check
    ------------------------------------------------------------------
    taps : process is

        alias e_red   is << signal .ula_tb.dut.s_red : std_logic >>;
        alias e_green is << signal .ula_tb.dut.s_green : std_logic >>;
        alias e_blue  is << signal .ula_tb.dut.s_blue : std_logic >>;
        alias e_hl    is << signal .ula_tb.dut.s_hl : std_logic >>;
        alias e_pclk  is << signal .ula_tb.dut.s_clk_7_pixel : std_logic >>;
        alias e_vras  is << signal .ula_tb.dut.s_vid_ras : std_logic >>;
        alias e_c0    is << signal .ula_tb.dut.s_c0 : std_logic >>;
        alias e_c1    is << signal .ula_tb.dut.s_c1 : std_logic >>;
        alias e_c2    is << signal .ula_tb.dut.s_c2 : std_logic >>;
        alias e_c3    is << signal .ula_tb.dut.s_c3 : std_logic >>;
        alias e_c4    is << signal .ula_tb.dut.s_c4 : std_logic >>;
        alias e_c5    is << signal .ula_tb.dut.s_c5 : std_logic >>;
        alias e_c6    is << signal .ula_tb.dut.s_c6 : std_logic >>;
        alias e_c7    is << signal .ula_tb.dut.s_c7 : std_logic >>;
        alias e_c8    is << signal .ula_tb.dut.s_c8 : std_logic >>;
        alias e_v0    is << signal .ula_tb.dut.s_v0 : std_logic >>;
        alias e_v1    is << signal .ula_tb.dut.s_v1 : std_logic >>;
        alias e_v2    is << signal .ula_tb.dut.s_v2 : std_logic >>;
        alias e_v3    is << signal .ula_tb.dut.s_v3 : std_logic >>;
        alias e_v4    is << signal .ula_tb.dut.s_v4 : std_logic >>;
        alias e_v5    is << signal .ula_tb.dut.s_v5 : std_logic >>;
        alias e_v6    is << signal .ula_tb.dut.s_v6 : std_logic >>;
        alias e_v7    is << signal .ula_tb.dut.s_v7 : std_logic >>;
        alias e_v8    is << signal .ula_tb.dut.s_v8 : std_logic >>;

        variable cv : std_logic_vector(8 downto 0);
        variable vv : std_logic_vector(8 downto 0);

    begin

        loop

            red     <= e_red;
            green   <= e_green;
            blue    <= e_blue;
            hl      <= e_hl;
            pclk    <= e_pclk;
            vid_ras <= e_vras;
            cv      := e_c8 & e_c7 & e_c6 & e_c5 & e_c4 & e_c3 & e_c2 & e_c1 & e_c0;
            vv      := e_v8 & e_v7 & e_v6 & e_v5 & e_v4 & e_v3 & e_v2 & e_v1 & e_v0;

            if (not is_x(cv)) then
                cnum <= to_integer(unsigned(cv));
            end if;

            if (not is_x(vv)) then
                vnum <= to_integer(unsigned(vv));
            end if;

            wait on e_red, e_green, e_blue, e_hl, e_pclk, e_vras,
                    e_c0, e_c1, e_c2, e_c3, e_c4, e_c5, e_c6, e_c7, e_c8,
                    e_v0, e_v1, e_v2, e_v3, e_v4, e_v5, e_v6, e_v7, e_v8;

        end loop;

    end process taps;

    ------------------------------------------------------------------
    -- 1. pixels of frame 0, sampled mid-pixel
    ------------------------------------------------------------------
    pixels : process is

        type line_t is array (0 to 447) of std_logic_vector(3 downto 0);

        variable line0  : line_t;
        variable lat    : integer := -1;
        variable ok     : boolean;
        variable got    : std_logic_vector(3 downto 0);
        variable x      : integer;
        variable n      : integer := 0;
        variable prev_c : integer := -1;

    begin

        wait until reset = '0';

        -- line 2 of frame 0 (lines 0 and 1 have run, so the prefetch of each
        -- line's first bytes has happened): record every pixel
        loop

            wait until rising_edge(pclk);
            exit when vnum = 2 and cnum = 0;

        end loop;

        loop

            line0(cnum) := rgbh(red, green, blue, hl);
            exit when cnum = 447;
            wait until rising_edge(pclk);

        end loop;

        -- find the pipeline delay: the offset at which line 2 matches
        for l in 0 to 63 loop

            ok := true;

            for xi in 0 to 255 loop

                if (line0(xi + l) /= exp_pixel(xi, 2)) then
                    ok := false;
                    exit;
                end if;

            end loop;

            if (ok) then
                lat := l;
                exit;
            end if;

        end loop;

        assert lat >= 0
            report "FAIL pixels: line 2 matches the test screen at no pipeline delay "
                   & "0..63 (first display byte expected " & to_string(disp_byte(2, 0))
                   & ", pixels at c=0..15: "
                   & to_string(line0(0)) & to_string(line0(1)) & to_string(line0(2))
                   & to_string(line0(3)) & to_string(line0(4)) & to_string(line0(5))
                   & to_string(line0(6)) & to_string(line0(7)) & to_string(line0(8))
                   & to_string(line0(9)) & to_string(line0(10)) & to_string(line0(11)) & ")"
            severity failure;

        pixel_delay <= lat;
        report "pixels: pipeline delay is " & integer'image(lat)
               & " pixels (counter position -> RGB)"
            severity note;
        n           := 256;

        -- lines 3..191: every display pixel at that delay
        loop

            wait until rising_edge(pclk);
            exit when vnum = 192;

            if (vnum >= 3 and vnum <= 191 and cnum >= lat and cnum < lat + 256) then
                x   := cnum - lat;
                got := rgbh(red, green, blue, hl);

                assert got = exp_pixel(x, vnum)
                    report "FAIL pixel (" & integer'image(x) & ", " & integer'image(vnum)
                           & "): rgb/hl = " & to_string(got) & ", expected "
                           & to_string(exp_pixel(x, vnum))
                    severity failure;
                n := n + 1;
            end if;

        end loop;

        pixel_checks <= n;
        report "PASS: all " & integer'image(n) & " display pixels of frame 0 match the test screen"
            severity note;
        wait;

    end process pixels;

    ------------------------------------------------------------------
    -- 3. /INT pulses
    ------------------------------------------------------------------
    int_watch : process is

        variable t_fall : time;
        variable n      : integer := 0;

    begin

        wait until reset = '0';

        loop

            wait until to_x01(int_n) = '0' or done;
            exit when done;
            t_fall := now;
            n      := n + 1;

            assert vnum = 248 and cnum < 4
                report "FAIL /INT fell at line " & integer'image(vnum) & ", pixel "
                       & integer'image(cnum) & " (expected line 248, pixel 0)"
                severity failure;

            wait until to_x01(int_n) = '1';

            assert abs ((now - t_fall) - 64 * t_pix) < 2 * t_pix
                report "FAIL /INT was low for " & time'image(now - t_fall)
                       & ", expected about " & time'image(64 * t_pix)
                severity failure;

            int_pulses <= n;
            report "/INT pulse " & integer'image(n) & ": line 248, low for "
                   & time'image(now - t_fall)
                severity note;

        end loop;

        wait;

    end process int_watch;

    ------------------------------------------------------------------
    -- 7. note: RAS released while a video RAS is active?
    ------------------------------------------------------------------
    ras_watch : process is

        variable n : integer := 0;

    begin

        loop

            wait on ras_n, vid_ras, done;
            exit when done;

            if (ras_n = 'Z' and to_x01(vid_ras) = '1') then
                n := n + 1;

                if (n <= 3) then
                    report "NOTE: RAS released while a video RAS is active, line "
                           & integer'image(vnum) & " pixel " & integer'image(cnum)
                        severity note;
                end if;
            end if;

        end loop;

        report "NOTE: RAS released during a video RAS " & integer'image(n) & " time(s)"
            severity note;
        wait;

    end process ras_watch;

    ------------------------------------------------------------------
    -- the Z80 and the remaining checks
    ------------------------------------------------------------------
    z80 : process is

        variable got   : std_logic_vector(3 downto 0);
        variable t0    : time;
        variable rises : integer;
        variable n     : integer := 0;

        -- wait for a given line and pixel

        procedure wait_for (
            line : integer;
            pix  : integer
        ) is
        begin

            loop

                wait until rising_edge(pclk);
                exit when vnum = line and cnum = pix;

            end loop;

        end procedure wait_for;

        -- check the border colour on the current pixel

        procedure check_border (
            colour : std_logic_vector(2 downto 0);
            what   : string
        ) is

            variable want : std_logic_vector(3 downto 0);

        begin

            want := colour(1) & colour(2) & colour(0) & '0';
            got  := rgbh(red, green, blue, hl);

            assert got = want
                report "FAIL border " & what & " at line " & integer'image(vnum)
                       & " pixel " & integer'image(cnum) & ": rgb/hl = " & to_string(got)
                       & ", expected " & to_string(want)
                severity failure;
            n := n + 1;

        end procedure check_border;

    begin

        wait until reset = '0';

        -- 2. OUT (0xFE),5 in the vertical border of frame 0 (no fetches)
        wait_for(200, 0);
        mux_a(0) <= 'L';                                                                          -- A0 = 0: even port
        z80_d    <= "00000101";                                                                   -- cyan border, MIC = 0, speaker = 0
        ioreq_n  <= '0';                                                                          -- /IORQ OR A0 on the board
        wr_n     <= '0';
        wait for 3 us;
        wr_n     <= '1';
        ioreq_n  <= '1';
        wait for 50 ns;
        z80_d    <= (others => 'Z');

        for line in 205 to 240 loop

            wait_for(line, 100);
            check_border("101", "(vertical, after OUT)");

        end loop;

        report "PASS: border is cyan after OUT (0xFE),5"
            severity note;

        -- 4. the Z80 clock, free-running in the border
        wait_for(241, 0);
        t0    := now;
        rises := 0;

        while now - t0 < 10 us loop

            wait until rising_edge(z80_clk) or now - t0 >= 10 us;

            if (to_x01(z80_clk) = '1') then
                rises := rises + 1;
            end if;

        end loop;

        assert rises >= 34 and rises <= 36
            report "FAIL Z80 clock: " & integer'image(rises)
                   & " rising edges in 10 us, expected 35 (3.5 MHz)"
            severity failure;
        n := n + 1;
        report "PASS: Z80 clock " & integer'image(rises) & " cycles in 10 us (3.5 MHz)"
            severity note;

        -- 5. IN (0xFE) with a key held on column 2
        wait_for(260, 0);
        keys(2)  <= '0';
        mux_a(0) <= 'L';
        ioreq_n  <= '0';
        rd_n     <= '0';
        wait for 2 us;

        assert to_x01(d) = "10111011"
            report "FAIL IN (0xFE): D7..D0 = " & to_string(to_x01(d))
                   & ", expected 10111011 (key on column 2, EAR = 0, D5/D7 pulled up)"
            severity failure;
        n := n + 1;

        rd_n    <= '1';
        ioreq_n <= '1';
        keys(2) <= 'Z';
        report "PASS: IN (0xFE) reads the key, EAR and the pull-ups"
            severity note;

        -- 6. a ROM-area MREQ in the border releases RAS
        wait_for(270, 0);
        a14    <= '0';
        a15    <= '0';
        mreq_n <= '0';
        wait for 500 ns;

        assert ras_n = 'Z'
            report "FAIL RAS: " & std_logic'image(ras_n)
                   & " during a border ROM-area MREQ, expected 'Z' (released)"
            severity failure;
        n := n + 1;

        mreq_n <= '1';
        a15    <= '1';
        report "PASS: RAS released during a border ROM-area MREQ"
            severity note;

        -- 2. horizontal border and h-blank in frame 1, cyan border
        for line in 1 to 8 loop

            wait_for(line, (pixel_delay + 256 + 320) / 2);
            check_border("101", "(right, frame 1)");
            wait_for(line, 360);
            check_border("000", "(h-blank)");
            wait_for(line, 430);
            check_border("101", "(left, frame 1)");

        end loop;

        report "PASS: horizontal border cyan, h-blank black"
            severity note;

        -- 7. a ROM-area MREQ across the end of a display line
        wait_for(20, 240);
        a14    <= '0';
        a15    <= '0';
        mreq_n <= '0';
        wait_for(20, 300);
        mreq_n <= '1';
        a15    <= '1';

        wait_for(30, 0);
        done <= true;
        wait for 1 us;

        -- lines 2..191 x 256 pixels; fewer means a line or pixel was skipped
        assert pixel_checks = 190 * 256
            report "FAIL: " & integer'image(pixel_checks) & " pixels were checked, expected "
                   & integer'image(190 * 256) & " (lines 2..191 x 256)"
            severity failure;
        assert int_pulses = 1
            report "FAIL: " & integer'image(int_pulses) & " /INT pulses in one frame, expected 1"
            severity failure;

        report "ALL TESTS PASSED (" & integer'image(pixel_checks) & " pixels, "
               & integer'image(n) & " other checks, " & integer'image(int_pulses)
               & " /INT pulse)"
            severity note;
        finish;

    end process z80;

end architecture behavioral;
