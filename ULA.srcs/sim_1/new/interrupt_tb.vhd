----------------------------------------------------------------------------------
-- interrupt_tb — self-checking TB for the once-a-frame /INT.
--
-- Two copies of the DUT run side by side from the same counters:
--   REAL  t_int_lag = 100 ns, the real chip's propagation + ripple lag
--   FPGA  t_int_lag = 0 ns, what synthesis gives (it ignores `after`)
-- Each /INT is a collector follower with an ON-CHIP pull-up ('0' or 'H'). The
-- TB adds NO pull-up, so a released line must read 'H' from the DUT itself.
--
-- What it proves:
--   1. DECODE: all 2**7 = 128 combinations of vsync, v0..v2, c6..c8. /INT is
--      pulled low for exactly ONE: vsync = '1' with the other six '0'.
--   2. WHERE AND HOW LONG: over a full frame of the real 448 x 312 raster,
--      /INT is pulled low once, at line 248 pixel 0 (+ t_int_lag), for 64
--      pixels = 32 T-states, and the next pulse is exactly one frame later.
--   3. SETUP: the Z80 runs on c0 and samples /INT on its rising edge, at the
--      start of pixel 1. REAL gives 143 - 100 = 43 ns of setup (the ~42 ns of
--      the real machine, below the Z80's 80 ns spec); FPGA gives 143 ns,
--      within spec.
--   4. SAME EDGE: both copies are first seen low at the SAME Z80 rising edge,
--      so the lag changes nothing the software can see.
--   5. SHARED LINE: another device can pull /INT low as well (wired-OR):
--      the line reads '0' with no 'X', and returns to 'H' when both release.
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity interrupt_tb is
end entity interrupt_tb;

architecture behavioral of interrupt_tb is

    constant settle   : time    := 5 ns;
    constant t_pix    : time    := 143 ns;
    constant lag_real : time    := 100 ns;
    constant pixels   : integer := 448;
    constant lines    : integer := 312;
    constant t_frame  : time    := pixels * lines * t_pix;
    constant t_pulse  : time    := 64 * t_pix; -- 32 T-states
    constant t_setup  : time    := 80 ns;      -- Z80 /INT setup to rising edge

    -- inputs: from the test steps or from the raster counters
    signal use_counter : boolean := false;

    signal s_v    : std_logic_vector(2 downto 0) := "000"; -- v2..v0 (steps)
    signal s_c    : std_logic_vector(2 downto 0) := "000"; -- c8..c6 (steps)
    signal s_sync : std_logic                    := '0';

    signal r_v    : std_logic_vector(2 downto 0) := "000"; -- from the counters
    signal r_c    : std_logic_vector(2 downto 0) := "000";
    signal r_sync : std_logic                    := '0';

    signal v     : std_logic_vector(2 downto 0);
    signal c     : std_logic_vector(2 downto 0);
    signal vsync : std_logic;

    signal zclk   : std_logic := '0'; -- the Z80's clock = c0
    signal line_n : integer   := 0;
    signal pix_n  : integer   := 0;

    -- time of the most recent line 248 pixel 0 (frame start)
    signal t_line248 : time := 0 ns;

    -- the two /INT lines (each DUT, plus another device on FPGA's)
    signal int_real  : std_logic;
    signal int_fpga  : std_logic;
    signal int_other : std_logic := 'Z';

    -- results published by the monitors
    signal edge_real : time    := 0 ns; -- first rising edge seeing '0'
    signal edge_fpga : time    := 0 ns;
    signal pulses_r  : integer := 0;
    signal pulses_f  : integer := 0;

    function bits3 (
        n : integer
    ) return std_logic_vector is

        variable b : std_logic_vector(2 downto 0);

    begin

        for i in 0 to 2 loop

            if ((n / (2 ** i)) mod 2 = 1) then
                b(i) := '1';
            else
                b(i) := '0';
            end if;

        end loop;

        return b;

    end function bits3;

begin

    v     <= r_v when use_counter else
             s_v;
    c     <= r_c when use_counter else
             s_c;
    vsync <= r_sync when use_counter else
             s_sync;

    -- another device on the FPGA copy's /INT line (no pull-up here: the
    -- ULA's own pull-up must supply the 'H')
    int_fpga <= int_other;

    dut_real : entity work.interrupt(structural)
        generic map (
            t_int_lag => lag_real
        )
        port map (
            v0    => v(0),
            v1    => v(1),
            v2    => v(2),
            c6    => c(0),
            c7    => c(1),
            c8    => c(2),
            vsync => vsync,
            int_n => int_real
        );

    dut_fpga : entity work.interrupt(structural)
        generic map (
            t_int_lag => 0 ns
        )
        port map (
            v0    => v(0),
            v1    => v(1),
            v2    => v(2),
            c6    => c(0),
            c7    => c(1),
            c8    => c(2),
            vsync => vsync,
            int_n => int_fpga
        );

    ------------------------------------------------------------------
    -- the raster: 448 pixels x 312 lines, starting at line 247
    ------------------------------------------------------------------
    raster : process is

        variable p : integer := 0;
        variable l : integer := 247;

    begin

        wait until use_counter;

        loop

            pix_n  <= p;
            line_n <= l;
            r_c    <= bits3(p / 64);                -- c8..c6
            r_v    <= bits3(l mod 8);               -- v2..v0

            if (l >= 248 and l <= 251) then
                r_sync <= '1';
            else
                r_sync <= '0';
            end if;

            if (p mod 2 = 1) then
                -- Z80 rising edge at the start of odd pixels
                zclk <= '1';
            else
                zclk <= '0';
            end if;

            if (l = 248 and p = 0) then
                t_line248 <= now;
            end if;

            wait for t_pix;
            p := p + 1;

            if (p = pixels) then
                p := 0;
                l := (l + 1) mod lines;
            end if;

        end loop;

    end process raster;

    ------------------------------------------------------------------
    -- monitor: REAL copy
    ------------------------------------------------------------------
    mon_real : process is

        variable t_fall : time;
        variable n      : integer := 0;
        variable last   : time    := 0 ns;

    begin

        -- only the raster's interrupts (part 1 pulls /INT low on purpose)
        wait until use_counter;

        loop

            wait until int_real = '0';
            t_fall := now;
            n      := n + 1;

            assert t_fall - t_line248 = lag_real
                report "FAIL REAL /INT fell " & time'image(t_fall - t_line248)
                       & " after line 248 pixel 0, expected " & time'image(lag_real)
                severity failure;

            if (n > 1) then
                assert t_fall - last = t_frame
                    report "FAIL REAL /INT pulses " & time'image(t_fall - last)
                           & " apart, expected one frame " & time'image(t_frame)
                    severity failure;
            end if;

            last := t_fall;

            -- the Z80 rising edge that first sees it
            wait until rising_edge(zclk);

            assert now - t_fall = t_pix - lag_real
                report "FAIL REAL setup " & time'image(now - t_fall)
                       & ", expected " & time'image(t_pix - lag_real)
                severity failure;

            if (n = 1) then
                edge_real <= now;
                report "REAL: /INT setup before the Z80 rising edge = "
                       & time'image(now - t_fall) & " (real machine ~42 ns, spec 80 ns)"
                    severity note;
            end if;

            wait until int_real = 'H';

            assert now - t_fall = t_pulse
                report "FAIL REAL /INT low for " & time'image(now - t_fall)
                       & ", expected " & time'image(t_pulse) & " (32 T-states)"
                severity failure;

            pulses_r <= n;
            exit when n = 2;              -- two frames timed: done

        end loop;

        wait;

    end process mon_real;

    ------------------------------------------------------------------
    -- monitor: FPGA copy (only while no other device is driving)
    ------------------------------------------------------------------
    mon_fpga : process is

        variable t_fall : time;
        variable n      : integer := 0;

    begin

        -- only the raster's interrupts (part 1 pulls /INT low on purpose)
        wait until use_counter;

        loop

            wait until int_fpga = '0' and int_other = 'Z';
            t_fall := now;
            n      := n + 1;

            assert t_fall = t_line248
                report "FAIL FPGA /INT fell " & time'image(t_fall - t_line248)
                       & " after line 248 pixel 0, expected at once"
                severity failure;

            wait until rising_edge(zclk);

            assert now - t_fall >= t_setup
                report "FAIL FPGA setup " & time'image(now - t_fall)
                       & " is below the Z80's " & time'image(t_setup)
                severity failure;

            if (n = 1) then
                edge_fpga <= now;
                report "FPGA: /INT setup before the Z80 rising edge = "
                       & time'image(now - t_fall) & " (within the 80 ns spec)"
                    severity note;
            end if;

            wait until int_fpga = 'H';

            assert now - t_fall = t_pulse
                report "FAIL FPGA /INT low for " & time'image(now - t_fall)
                       & ", expected " & time'image(t_pulse)
                severity failure;

            pulses_f <= n;
            exit when n = 2;              -- two frames timed: done

        end loop;

        wait;

    end process mon_fpga;

    stim : process is

        variable checks : integer := 0;
        variable want   : std_logic;

    begin

        --------------------------------------------------------------
        -- 1) DECODE: all 128 input combinations
        --------------------------------------------------------------
        for n in 0 to 127 loop

            s_v    <= bits3(n mod 8);
            s_c    <= bits3((n / 8) mod 8);
            s_sync <= bits3(n / 64)(0);
            wait for lag_real + settle;

            -- only vsync = '1' with all others '0' (n = 64) pulls /INT low
            if (n = 64) then
                want := '0';
            else
                want := 'H';
            end if;

            assert int_real = want and int_fpga = want
                report "FAIL decode combination " & integer'image(n) & ": /INT REAL "
                       & std_logic'image(int_real) & " FPGA " & std_logic'image(int_fpga)
                       & ", expected " & std_logic'image(want)
                severity failure;

            checks := checks + 1;

        end loop;

        s_sync <= '0';
        wait for lag_real + settle;

        report "PASS: /INT is pulled low for exactly 1 of 128 input combinations"
            severity note;

        --------------------------------------------------------------
        -- 2) + 3) + 4) the raster: two frames' interrupts
        --------------------------------------------------------------
        use_counter <= true;

        wait until pulses_r = 2 and pulses_f = 2;

        assert edge_real = edge_fpga
            report "FAIL REAL first seen at " & time'image(edge_real)
                   & " but FPGA at " & time'image(edge_fpga)
                   & ": the lag changed which Z80 edge takes the interrupt"
            severity failure;

        checks := checks + 1;

        report "PASS: one 32 T-state /INT per frame at line 248, seen at the same "
               & "Z80 edge with and without the 100 ns lag"
            severity note;

        --------------------------------------------------------------
        -- 5) SHARED LINE: another device on the FPGA copy's line
        --------------------------------------------------------------
        -- line 100: well away from the ULA's own pulse
        wait until line_n = 100;
        int_other <= '0';
        wait for settle;

        assert int_fpga = '0'
            report "FAIL wired-OR: other device pulls /INT low but it reads "
                   & std_logic'image(int_fpga)
            severity failure;

        int_other <= 'Z';
        wait for settle;

        assert int_fpga = 'H'
            report "FAIL wired-OR: both released but /INT reads " & std_logic'image(int_fpga)
            severity failure;

        checks := checks + 2;

        report "PASS: /INT is shared: another device can pull it low, no clash"
            severity note;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks, plus "
               & integer'image(pulses_r + pulses_f) & " interrupt pulses timed)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
