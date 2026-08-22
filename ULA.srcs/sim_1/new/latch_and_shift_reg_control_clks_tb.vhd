----------------------------------------------------------------------------------
-- latch_and_shift_reg_control_clks_tb — self-checking TB for the video control
-- clocks.
--
-- What it proves:
--   1. Strobe positions — walking the pixel index c2c1c0 = 0..7 through a
--      character cell (display fetch active, pixel clock low) puts each strobe
--      exactly where the header table says:
--        pixel 1, 5 -> pixel_data_latch_n  (display bytes A and C)
--        pixel 3, 7 -> attr_data_latch_n   (attribute bytes B and D)
--        pixel 4    -> s_load
--        pixel 5    -> attr_output_latch_n (output load)
--      Two display + two attribute captures per pass = the 4-byte A/B/C/D burst.
--   2. Clock gating — with the pixel clock HIGH the two capture strobes must
--      stay de-asserted at every pixel. This is the ordering the book buys with
--      its 24 ns delay ("clk7 low before the latch opens"), here enforced as a
--      logic condition, so it is checked directly.
--   3. Border gating — nborder='0' (border region) suppresses the display
--      capture; vid_c3_n='1' (outside the display-qualified c3 window)
--      suppresses the attribute capture.
--   4. video_en latch — the data_latch_1_bit is transparent while c3='1' and
--      holds when c3='0', so video_en tracks nborder then freezes it.
--
-- Everything is compared against an independent reference model written from
-- the header table, not from the gate equations. Any mismatch is fatal; a clean
-- run prints "ALL TESTS PASSED".
--
-- Polarity reminders: clk_7_n is the INVERTED clock, so pix_clk = not(clk_7_n)
-- and "pixel clock low" means clk_7_n='1'. nborder and vid_c3_n are active-low.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library std;
    use std.env.all;

entity latch_and_shift_reg_control_clks_tb is
end entity latch_and_shift_reg_control_clks_tb;

architecture behavioral of latch_and_shift_reg_control_clks_tb is

    constant settle : time := 20 ns; -- > worst-case settle incl. the latch's after-tg

    signal clk_7_n  : std_logic := '1'; -- '1' => pix_clk low (strobes enabled)
    signal c0       : std_logic := '0';
    signal c0_n     : std_logic := '1';
    signal c1       : std_logic := '0';
    signal c1_n     : std_logic := '1';
    signal c2_n     : std_logic := '1';
    signal c3_n     : std_logic := '0'; -- '0' => c3='1' (fetch burst window)
    signal nborder  : std_logic := '1'; -- '1' => inside display (not border)
    signal vid_c3_n : std_logic := '0'; -- '0' => display-qualified c3 active

    signal clk_7_pixel         : std_logic;
    signal vid_cas_pulse       : std_logic;
    signal pixel_data_latch_n  : std_logic;
    signal attr_data_latch_n   : std_logic;
    signal video_en            : std_logic;
    signal s_load              : std_logic;
    signal attr_output_latch_n : std_logic;

    signal checks : integer := 0;

    ------------------------------------------------------------------
    -- reference model, written from the header table
    ------------------------------------------------------------------

    -- display byte captured at c1='0', c0='1', clock low, inside display

    function exp_pdl (
        p     : integer;
        clkn  : std_logic;
        nb    : std_logic;
        c3neg : std_logic
    ) return std_logic is
    begin

        if (clkn = '1' and (p mod 2) = 1 and ((p / 2) mod 2) = 0
            and nb = '1' and c3neg = '0') then
            return '0'; -- asserted (active-low)
        end if;

        return '1';

    end function exp_pdl;

    -- attribute byte captured at c1='1', c0='1', clock low, vid_c3 active

    function exp_adl (
        p     : integer;
        clkn  : std_logic;
        vc3n  : std_logic
    ) return std_logic is
    begin

        if (clkn = '1' and (p mod 2) = 1 and ((p / 2) mod 2) = 1
            and vc3n = '0') then
            return '0'; -- asserted (active-low)
        end if;

        return '1';

    end function exp_adl;

    -- output load: c2='1', c1='0', c0='1' (pixel 5); not clock gated

    function exp_aol (
        p : integer
    ) return std_logic is
    begin

        if (p = 5) then
            return '0'; -- asserted (active-low)
        end if;

        return '1';

    end function exp_aol;

    -- shift-register load: c2='1', c1='0', c0='0' (pixel 4), gated by video_en

    function exp_sload (
        p   : integer;
        ven : std_logic
    ) return std_logic is
    begin

        if (p = 4 and ven = '1') then
            return '1'; -- active-high
        end if;

        return '0';

    end function exp_sload;

begin

    dut : entity work.latch_and_shift_reg_control_clks(structural)
        port map (
            clk_7_n             => clk_7_n,
            c0_n                => c0_n,
            c0                  => c0,
            c3_n                => c3_n,
            c1                  => c1,
            c1_n                => c1_n,
            c2_n                => c2_n,
            nborder             => nborder,
            vid_c3_n            => vid_c3_n,
            clk_7_pixel         => clk_7_pixel,
            vid_cas_pulse       => vid_cas_pulse,
            pixel_data_latch_n  => pixel_data_latch_n,
            attr_data_latch_n   => attr_data_latch_n,
            video_en            => video_en,
            s_load              => s_load,
            attr_output_latch_n => attr_output_latch_n
        );

    stim : process is

        -- drive the pixel index onto the counter taps (true + complement)

        procedure set_pix (
            p : in integer
        ) is

            variable pv : std_logic_vector(2 downto 0);

        begin

            pv   := std_logic_vector(to_unsigned(p, 3));
            c0   <= pv(0);
            c0_n <= not pv(0);
            c1   <= pv(1);
            c1_n <= not pv(1);
            c2_n <= not pv(2);

        end procedure set_pix;

        -- walk pixels 0..7 and check every strobe against the reference model

        procedure sweep (
            phase : in string
        ) is
        begin

            for p in 0 to 7 loop

                set_pix(p);
                wait for settle;

                assert pixel_data_latch_n = exp_pdl(p, clk_7_n, nborder, c3_n)
                    report "FAIL " & phase & " pix " & integer'image(p)
                           & ": pixel_data_latch_n expected "
                           & std_logic'image(exp_pdl(p, clk_7_n, nborder, c3_n))
                           & " got " & std_logic'image(pixel_data_latch_n)
                    severity failure;

                assert attr_data_latch_n = exp_adl(p, clk_7_n, vid_c3_n)
                    report "FAIL " & phase & " pix " & integer'image(p)
                           & ": attr_data_latch_n expected "
                           & std_logic'image(exp_adl(p, clk_7_n, vid_c3_n))
                           & " got " & std_logic'image(attr_data_latch_n)
                    severity failure;

                assert attr_output_latch_n = exp_aol(p)
                    report "FAIL " & phase & " pix " & integer'image(p)
                           & ": attr_output_latch_n expected "
                           & std_logic'image(exp_aol(p))
                           & " got " & std_logic'image(attr_output_latch_n)
                    severity failure;

                assert s_load = exp_sload(p, video_en)
                    report "FAIL " & phase & " pix " & integer'image(p)
                           & ": s_load expected " & std_logic'image(exp_sload(p, video_en))
                           & " got " & std_logic'image(s_load)
                    severity failure;

                checks <= checks + 4;
                wait for 1 ns;

            end loop;

        end procedure sweep;

    begin

        --------------------------------------------------------------
        -- 0) the pixel clock output is just the inverted input clock
        --------------------------------------------------------------
        clk_7_n <= '1';
        wait for settle;

        assert clk_7_pixel = '0'
            report "FAIL clk_7_pixel should be '0' when clk_7_n='1'"
            severity failure;

        clk_7_n <= '0';
        wait for settle;

        assert clk_7_pixel = '1'
            report "FAIL clk_7_pixel should be '1' when clk_7_n='0'"
            severity failure;

        checks <= checks + 2;
        wait for 1 ns;

        --------------------------------------------------------------
        -- 1) fetch burst, pixel clock LOW: strobes land at 1,3,4,5,7
        --------------------------------------------------------------
        clk_7_n  <= '1';                                                        -- pix_clk low -> captures enabled
        nborder  <= '1';                                                        -- inside the display
        c3_n     <= '0';                                                        -- c3='1' -> fetch window
        vid_c3_n <= '0';                                                        -- display-qualified c3 active
        wait for settle;
        sweep("clk-low");

        --------------------------------------------------------------
        -- 2) pixel clock HIGH: both capture strobes must stay idle
        --------------------------------------------------------------
        clk_7_n <= '0';                                                         -- pix_clk high -> captures blocked
        wait for settle;
        sweep("clk-high");

        --------------------------------------------------------------
        -- 3) border region: display capture suppressed by nborder='0'
        --------------------------------------------------------------
        clk_7_n <= '1';
        nborder <= '0';                                                         -- border -> a_out = 0
        wait for settle;
        sweep("border");

        --------------------------------------------------------------
        -- 4) attribute capture suppressed by vid_c3_n='1'
        --------------------------------------------------------------
        nborder  <= '1';
        vid_c3_n <= '1';                                                        -- outside the display-qualified c3
        wait for settle;
        sweep("no-vid-c3");

        --------------------------------------------------------------
        -- 5) video_en latch: transparent while c3='1', holds when c3='0'
        --------------------------------------------------------------
        vid_c3_n <= '0';
        c3_n     <= '0';                                                        -- c3='1' -> latch transparent
        nborder  <= '1';
        wait for settle;

        assert video_en = '1'
            report "FAIL video_en should follow nborder='1' while c3='1', got "
                   & std_logic'image(video_en)
            severity failure;

        nborder <= '0';                                                         -- still transparent: should follow
        wait for settle;

        assert video_en = '0'
            report "FAIL video_en should follow nborder='0' while c3='1', got "
                   & std_logic'image(video_en)
            severity failure;

        nborder <= '1';                                                         -- back to display, then freeze it
        wait for settle;
        c3_n    <= '1';                                                         -- c3='0' -> latch HOLDS
        wait for settle;

        nborder <= '0';                                                         -- must be ignored now
        wait for settle;

        assert video_en = '1'
            report "FAIL video_en should have held '1' when c3='0', got "
                   & std_logic'image(video_en)
            severity failure;

        checks <= checks + 3;
        wait for 1 ns;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
