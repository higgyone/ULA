----------------------------------------------------------------------------------
-- latch_and_shift_reg_control_clks_sync_tb — self-checking TB for the
-- SYNCHRONOUS architecture of latch_and_shift_reg_control_clks
--
-- latch_and_shift_reg_control_clks_tb covers the book's gates (structural)
-- with the clocks tied off. This TB covers the registered strobes that ULA.vhd
-- actually uses, with REAL timing: the stimulus is ula_timing itself (the
-- 14 MHz clock, the divider and the gate-level counters), so clk_7 and the
-- counter taps arrive with the same delays as in the chip.
--
-- ── What is checked, every clk_14 tick ───────────────────────────────
--   tick = c2 c1 c0 clk_7 (0..15; pixel p = ticks 2p, 2p+1; the counter
--   advances on clk_7's falling edge, so each pixel starts with clk_7 = '0').
--   Everything is sampled mid-tick (35 ns after the clk_14 edge, when the
--   counter ripple has settled). A registered strobe is active during the tick
--   AFTER the one it decodes, so the gating terms are taken from the previous
--   sample. Expected (from the header's table):
--     pixel_data_latch_n  '0' in ticks 2, 10  when the fetch window was open
--     attr_data_latch_n   '0' in ticks 6, 14  when the fetch window was open
--     sload               '1' in ticks 7, 8   when video_en was '1'
--     attr_output_latch_n '0' in ticks 8, 9   (always)
--   and, combinationally:
--     vid_c3_n    = NOT (c3 AND border_n)       (the fetch window)
--     video_en    = border_n while c3 = '1', held while c3 = '0'
--     clk_7_pixel = NOT clk_7_n
--
-- ── The race rule (ula_tb bug 5) ─────────────────────────────────────
--   The shift register clocks on the FALLING edge of clk_7_pixel. sload must
--   not change within 20 ns either side of any such edge. Checked at every
--   falling edge with 'stable.
--
-- ── Coverage ─────────────────────────────────────────────────────────
--   The run goes from line 0 to line 193, so it sees display lines, the
--   horizontal border (c8) on every line, and the vertical border (line 192+).
--   At the end it requires: display and attribute strobes in the display,
--   strobes suppressed in both the horizontal and the vertical border, and
--   sload both given and suppressed.
--
-- Ends with finish (std.env), so "run all" terminates.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library std;
    use std.env.all;

entity latch_and_shift_reg_control_clks_sync_tb is
end entity latch_and_shift_reg_control_clks_sync_tb;

architecture behavioral of latch_and_shift_reg_control_clks_sync_tb is

    constant t_14     : time    := 71428 ps; -- 14 MHz crystal
    constant settle   : time    := 35 ns;    -- mid-tick sample point
    constant race_win : time    := 20 ns;    -- sload must be stable this long either side
    constant end_line : natural := 194;      -- stop when this line starts

    signal clk_14   : std_logic := '0';
    signal reset    : std_logic := '1';
    signal k0       : std_logic := 'H';
    signal sim_done : boolean   := false;

    -- from ula_timing
    signal clk_7    : std_logic;
    signal clk_7_n  : std_logic;
    signal border_n : std_logic;
    signal c0       : std_logic;
    signal c1       : std_logic;
    signal c2       : std_logic;
    signal c3       : std_logic;
    signal c8       : std_logic;
    signal c0_n     : std_logic;
    signal c1_n     : std_logic;
    signal c2_n     : std_logic;
    signal c3_n     : std_logic;
    signal v0       : std_logic;
    signal v1       : std_logic;
    signal v2       : std_logic;
    signal v3       : std_logic;
    signal v4       : std_logic;
    signal v5       : std_logic;
    signal v6       : std_logic;
    signal v7       : std_logic;
    signal v8       : std_logic;

    -- DUT outputs
    signal vid_c3_n            : std_logic;
    signal clk_7_pixel         : std_logic;
    signal pixel_data_latch_n  : std_logic;
    signal attr_data_latch_n   : std_logic;
    signal video_en            : std_logic;
    signal sload               : std_logic;
    signal attr_output_latch_n : std_logic;

    signal race_checks : natural := 0;

begin

    clk_14 <= not clk_14 after t_14 / 2 when not sim_done else
              clk_14;
    reset  <= '0' after 200 ns;

    -- stimulus: the real timing subsystem
    timing : entity work.ula_timing(structural)
        port map (
            clk_14    => clk_14,
            reset     => reset,
            rd_n      => '1',
            wr_n      => '1',
            mreq_n    => '1',
            ioreq_n   => '1',
            k0        => k0,
            clk_7     => clk_7,
            clk_7_n   => clk_7_n,
            tclk_b    => open,
            hblank_n  => open,
            vsync     => open,
            border    => open,
            border_n  => border_n,
            sync_6c_n => open,
            c0        => c0,
            c1        => c1,
            c2        => c2,
            c3        => c3,
            c4        => open,
            c5        => open,
            c6        => open,
            c7        => open,
            c8        => c8,
            c0_n      => c0_n,
            c1_n      => c1_n,
            c2_n      => c2_n,
            c3_n      => c3_n,
            c7_n      => open,
            c8_n      => open,
            v0        => v0,
            v1        => v1,
            v2        => v2,
            v3        => v3,
            v4        => v4,
            v5        => v5,
            v6        => v6,
            v7        => v7,
            v8        => v8,
            v8_n      => open
        );

    dut : entity work.latch_and_shift_reg_control_clks(synchronous)
        port map (
            clk_14              => clk_14,
            clk_7               => clk_7,
            clk_7_n             => clk_7_n,
            c0_n                => c0_n,
            c0                  => c0,
            c3_n                => c3_n,
            c1                  => c1,
            c1_n                => c1_n,
            c2                  => c2,
            c2_n                => c2_n,
            border_n            => border_n,
            vid_c3_n            => vid_c3_n,
            clk_7_pixel         => clk_7_pixel,
            vid_cas_pulse       => open,
            pixel_data_latch_n  => pixel_data_latch_n,
            attr_data_latch_n   => attr_data_latch_n,
            video_en            => video_en,
            sload               => sload,
            attr_output_latch_n => attr_output_latch_n
        );

    -- sload must be stable RACE_WIN either side of every falling pixel-clock edge
    race_check : process is
    begin

        wait until reset = '0';
        wait for 2 us;

        while not sim_done loop

            wait until falling_edge(clk_7_pixel) or sim_done;
            exit when sim_done;
            wait for race_win;
            assert sload'stable(2 * race_win)
                report "FAIL race: sload changed within " & time'image(race_win)
                       & " of a falling pixel-clock edge at "
                       & time'image(now - race_win)
                severity failure;
            race_checks <= race_checks + 1;

        end loop;

        wait;

    end process race_check;

    checker : process is

        variable tick      : natural;
        variable line      : natural;
        variable window    : std_logic;        -- fetch window this tick
        variable prev_win  : std_logic := '0';
        variable ve        : std_logic := '0'; -- golden video_en
        variable prev_ve   : std_logic := '0';
        variable exp_pdl_n : std_logic;
        variable exp_adl_n : std_logic;
        variable exp_sload : std_logic;
        variable exp_aol_n : std_logic;
        variable checks    : natural   := 0;
        -- coverage
        variable n_pdl      : natural := 0;    -- display-byte strobes given
        variable n_adl      : natural := 0;    -- attribute-byte strobes given
        variable n_off_h    : natural := 0;    -- fetch ticks suppressed, horizontal border
        variable n_off_v    : natural := 0;    -- fetch ticks suppressed, vertical border
        variable n_sload    : natural := 0;    -- sload given
        variable n_sload_no : natural := 0;    -- sload suppressed (video_en = '0')

        procedure check (
            name     : string;
            actual   : std_logic;
            expected : std_logic
        ) is
        begin

            assert actual = expected
                report "FAIL " & name & " at tick " & natural'image(tick)
                       & ", line " & natural'image(line) & ", " & time'image(now)
                       & ": got " & std_logic'image(actual)
                       & ", expected " & std_logic'image(expected)
                severity failure;
            checks := checks + 1;

        end procedure check;

    begin

        wait until reset = '0';
        -- let the counters and the video_en latch settle (one full c3 cycle)
        wait for 5 us;
        -- prime the "previous tick" values. video_en is a latch, so the golden
        -- only knows it once it has seen c3 = '1' (the latch transparent).
        loop

            wait until rising_edge(clk_14);
            wait for settle;
            exit when c3 = '1';

        end loop;

        prev_win := c3 and border_n;
        ve       := border_n;
        prev_ve  := ve;

        loop

            wait until rising_edge(clk_14);
            wait for settle;

            tick := to_integer(unsigned'(c2 & c1 & c0 & clk_7));
            line := to_integer(unsigned'(v8 & v7 & v6 & v5 & v4 & v3 & v2 & v1 & v0));
            exit when line = end_line;

            window := c3 and border_n;

            if (c3 = '1') then
                ve := border_n;
            end if;

            -- combinational outputs, this tick
            check("vid_c3_n", vid_c3_n, not window);
            check("video_en", video_en, ve);
            check("clk_7_pixel", clk_7_pixel, not clk_7_n);

            -- registered strobes: decoded from the PREVIOUS tick
            exp_pdl_n := '1';
            exp_adl_n := '1';
            exp_sload := '0';
            exp_aol_n := '1';

            if ((tick = 2 or tick = 10) and prev_win = '1') then
                exp_pdl_n := '0';
            end if;

            if ((tick = 6 or tick = 14) and prev_win = '1') then
                exp_adl_n := '0';
            end if;

            if ((tick = 7 or tick = 8) and prev_ve = '1') then
                exp_sload := '1';
            end if;

            if (tick = 8 or tick = 9) then
                exp_aol_n := '0';
            end if;

            check("pixel_data_latch_n", pixel_data_latch_n, exp_pdl_n);
            check("attr_data_latch_n", attr_data_latch_n, exp_adl_n);
            check("sload", sload, exp_sload);
            check("attr_output_latch_n", attr_output_latch_n, exp_aol_n);

            -- coverage
            if (exp_pdl_n = '0') then
                n_pdl := n_pdl + 1;
            end if;

            if (exp_adl_n = '0') then
                n_adl := n_adl + 1;
            end if;

            if ((tick = 2 or tick = 6 or tick = 10 or tick = 14) and prev_win = '0' and c3 = '1') then
                -- a fetch tick with c3 high, suppressed by the border
                if (line >= 192) then
                    n_off_v := n_off_v + 1;
                elsif (c8 = '1') then
                    n_off_h := n_off_h + 1;
                end if;
            end if;

            if (tick = 7 or tick = 8) then
                if (prev_ve = '1') then
                    n_sload := n_sload + 1;
                else
                    n_sload_no := n_sload_no + 1;
                end if;
            end if;

            prev_win := window;
            prev_ve  := ve;

        end loop;

        assert n_pdl > 0 and n_adl > 0
            report "FAIL coverage: no fetch strobes seen in the display"
            severity failure;
        assert n_off_h > 0
            report "FAIL coverage: no fetch suppressed in the horizontal border"
            severity failure;
        assert n_off_v > 0
            report "FAIL coverage: no fetch suppressed in the vertical border"
            severity failure;
        assert n_sload > 0 and n_sload_no > 0
            report "FAIL coverage: sload not seen both given and suppressed"
            severity failure;
        assert race_checks > 0
            report "FAIL coverage: no pixel-clock edges race-checked"
            severity failure;

        report "coverage: " & natural'image(n_pdl) & " display-byte strobes, "
               & natural'image(n_adl) & " attribute-byte strobes, "
               & natural'image(n_off_h) & " fetches suppressed in the horizontal border, "
               & natural'image(n_off_v) & " in the vertical border, sload "
               & natural'image(n_sload) & " given / " & natural'image(n_sload_no)
               & " suppressed, " & natural'image(race_checks) & " race checks"
            severity note;
        report "ALL TESTS PASSED (" & natural'image(checks) & " checks, lines 0.."
               & natural'image(end_line - 1) & ")"
            severity note;

        sim_done <= true;
        finish;

    end process checker;

end architecture behavioral;
