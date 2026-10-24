----------------------------------------------------------------------------------
-- horiz_timing_tb — self-checking TB for the horizontal counter and the
-- sync / blank decoders.
--
-- Runs horiz_timing at the real 7 MHz pixel rate and reads its own counter
-- taps (c8..c0) every pixel. Over three full lines it proves:
--   1. COUNT: the count advances by exactly 1 per pixel and wraps 447 -> 0
--      (448 pixels per line, 64 us PAL).
--   2. COMPLEMENTS: c0_n..c8_n are the complements of c0..c8.
--   3. WINDOWS, at every pixel of the line (from the block header):
--        hsync_5c  '1' for pixels 336..367 (issue 5 hsync, active high)
--        hsync_6c  '1' for pixels 344..375 (issue 6 hsync, active high)
--        hblank_n  '0' for pixels 320..415 (horizontal blanking)
--
-- The counter advances on the rising edge of clk_7_n, so each pixel is
-- sampled on the falling edge, mid-pixel, when the ripple has settled.
--
-- Stops itself (finish); a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity horiz_timing_tb is
end entity horiz_timing_tb;

architecture behavioral of horiz_timing_tb is

    constant t              : time    := 143 ns; -- pixel period (7 MHz)
    constant lines_to_check : integer := 3;

    signal clk_7_n : std_logic := '0';
    signal tclk_a  : std_logic := '0';
    signal reset   : std_logic := '1';

    signal hsync_5c : std_logic;
    signal hsync_6c : std_logic;
    signal hblank_n : std_logic;

    signal c   : std_logic_vector(8 downto 0); -- c8..c0
    signal c_n : std_logic_vector(8 downto 0); -- c8_n..c0_n

begin

    ht : entity work.horiz_timing(behavioral)
        port map (
            clk_7_n  => clk_7_n,
            reset    => reset,
            tclk_a   => tclk_a,
            hsync_5c => hsync_5c,
            hsync_6c => hsync_6c,
            hblank_n => hblank_n,
            c0       => c(0),
            c0_n     => c_n(0),
            c1       => c(1),
            c1_n     => c_n(1),
            c2       => c(2),
            c2_n     => c_n(2),
            c3       => c(3),
            c3_n     => c_n(3),
            c4       => c(4),
            c4_n     => c_n(4),
            c5       => c(5),
            c5_n     => c_n(5),
            c6       => c(6),
            c6_n     => c_n(6),
            c7       => c(7),
            c7_n     => c_n(7),
            c8       => c(8),
            c8_n     => c_n(8),
            clk_hc6  => open,
            hc_rst   => open
        );

    -- free-running pixel clock; the checker ends the run with finish
    clk_gen : process is
    begin

        clk_7_n <= '0';
        wait for t / 2;
        clk_7_n <= '1';
        wait for t / 2;

    end process clk_gen;

    check : process is

        variable checks : integer := 0;
        variable n      : integer;
        variable last   : integer := -1;
        variable lines  : integer := 0;
        variable e5     : std_logic;
        variable e6     : std_logic;
        variable eb     : std_logic;

        impure function count return integer is

            variable v : integer := 0;

        begin

            for i in 8 downto 0 loop

                v := v * 2;

                if (c(i) = '1') then
                    v := v + 1;
                end if;

            end loop;

            return v;

        end function count;

    begin

        -- reset for a few pixels, then wait for the count to reach 0
        wait for 5 * t;
        reset <= '0';

        loop

            wait until falling_edge(clk_7_n);
            exit when count = 0;

        end loop;

        last := 0;

        -- check every pixel of lines_to_check full lines
        while lines < lines_to_check loop

            wait until falling_edge(clk_7_n);
            n := count;

            -- 1) COUNT
            assert n = (last + 1) mod 448
                report "FAIL count: " & integer'image(last) & " -> " & integer'image(n)
                severity failure;

            -- 2) COMPLEMENTS
            assert c_n = not c
                report "FAIL complements at count " & integer'image(n)
                severity failure;

            -- 3) WINDOWS
            if (n >= 336 and n <= 367) then
                e5 := '1';
            else
                e5 := '0';
            end if;

            if (n >= 344 and n <= 375) then
                e6 := '1';
            else
                e6 := '0';
            end if;

            if (n >= 320 and n <= 415) then
                eb := '0';
            else
                eb := '1';
            end if;

            assert hsync_5c = e5
                report "FAIL hsync_5c at pixel " & integer'image(n) & ": expected "
                       & std_logic'image(e5) & " got " & std_logic'image(hsync_5c)
                severity failure;

            assert hsync_6c = e6
                report "FAIL hsync_6c at pixel " & integer'image(n) & ": expected "
                       & std_logic'image(e6) & " got " & std_logic'image(hsync_6c)
                severity failure;

            assert hblank_n = eb
                report "FAIL hblank_n at pixel " & integer'image(n) & ": expected "
                       & std_logic'image(eb) & " got " & std_logic'image(hblank_n)
                severity failure;

            checks := checks + 5;
            last   := n;

            if (n = 447) then
                lines := lines + 1;
            end if;

        end loop;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks over "
               & integer'image(lines_to_check) & " lines: count, complements, "
               & "hsync 5c/6c and hblank windows)"
            severity note;
        finish;

    end process check;

end architecture behavioral;
