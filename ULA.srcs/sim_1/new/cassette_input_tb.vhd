----------------------------------------------------------------------------------
-- cassette_input_tb — self-checking TB for the EAR input on data bit 6.
--
-- The DUT's do_6 pin is open collector with a weak on-chip pull-up: it pulls
-- LOW ('0') or releases to 'H'. The TB adds NO pull-up of its own and checks
-- the RESOLVED bus, so a released pin must read exactly 'H' (a bare 'Z' or a
-- strongly driven '1' would fail).
--
-- What it proves:
--   1. EXHAUSTIVE: all 4 combinations of port_rd_n and ear. During a read
--      bit 6 = EAR (EAR low pulls the pin low); otherwise the pin is released.
--   2. SHARED BUS: outside a read another device can drive D6 either way and
--      the bus reads exactly that value: no 'X'.
--   3. TAPE LOADER: EAR carries a square wave and a model of the ROM's
--      loading loop reads the port every 2 us, as the real loader polls bit 6.
--      Every sample must equal EAR at that moment, and the loop must count
--      every edge of the wave.
--   4. A WHOLE PORT READ: with keyboard_input on the same bus, one read gives
--      the keyboard on D0..D4 and EAR on D6 together, as IN A,(0xFE) does.
--      (D5 and D7 are not driven by either block.)
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity cassette_input_tb is
end entity cassette_input_tb;

architecture behavioral of cassette_input_tb is

    constant settle : time := 5 ns;

    -- tape loader model
    constant t_half   : time    := 20 us;  -- EAR square wave, half period
    constant t_poll   : time    := 2 us;   -- loader reads the port this often
    constant t_rd     : time    := 400 ns; -- read strobe low
    constant n_halves : integer := 10;     -- run for 10 half periods

    signal ear_stim  : std_logic := '1'; -- EAR set by the test steps
    signal ear_tape  : std_logic := '1'; -- EAR from the tape model
    signal ear       : std_logic;        -- what the DUT sees
    signal port_rd_n : std_logic := '1';

    -- the data bus D7..D0: the DUT on D6, keyboard_input on D0..D4, and one
    -- other device that can drive D6
    signal d        : std_logic_vector(7 downto 0);
    signal d6_other : std_logic := 'Z';

    -- keyboard columns into keyboard_input (k4..k0, '0' = key down)
    signal k : std_logic_vector(4 downto 0) := "11111";

    signal tape_on : boolean := false;
    signal checks  : integer := 0;

    -- what the bus should read for a value from an open-collector pin

    function on_bus (
        v : std_logic
    ) return std_logic is
    begin

        if (v = '0') then
            return '0';
        end if;

        return 'H';

    end function on_bus;

begin

    dut : entity work.cassette_input(structural)
        port map (
            port_rd_n => port_rd_n,
            ear       => ear,
            do_6      => d(6)
        );

    -- another device that can drive D6 (no pull-up here: the ULA's own weak
    -- pull-up must supply the '1')
    d(6) <= d6_other;

    -- keyboard on the same bus, same port read
    kbd : entity work.keyboard_input(structural)
        port map (
            k0        => k(0),
            k1        => k(1),
            k2        => k(2),
            k3        => k(3),
            k4        => k(4),
            port_rd_n => port_rd_n,
            do_0      => d(0),
            do_1      => d(1),
            do_2      => d(2),
            do_3      => d(3),
            do_4      => d(4)
        );

    -- EAR comes from the tape while it plays, otherwise from the test steps
    -- (one driver each: two processes driving one signal would resolve to 'X')
    ear <= ear_tape when tape_on else
           ear_stim;

    ------------------------------------------------------------------
    -- the tape: a square wave on ear_tape while tape_on
    ------------------------------------------------------------------
    tape : process is
    begin

        wait until tape_on;

        while tape_on loop

            wait for t_half;
            ear_tape <= not ear_tape;

        end loop;

        wait;

    end process tape;

    stim : process is

        variable checks_v : integer := 0;
        variable last     : std_logic;
        variable edges    : integer;
        variable sample   : std_logic;

        procedure expect_d6 (
            want : in std_logic;
            what : in string
        ) is
        begin

            assert d(6) = want
                report "FAIL " & what & ": D6 expected " & std_logic'image(want)
                       & " got " & std_logic'image(d(6))
                severity failure;

            checks_v := checks_v + 1;

        end procedure expect_d6;

    begin

        --------------------------------------------------------------
        -- 1) EXHAUSTIVE: port_rd_n x ear
        --------------------------------------------------------------
        for rd in 0 to 1 loop

            for e in 0 to 1 loop

                if (rd = 0) then
                    port_rd_n <= '0';
                else
                    port_rd_n <= '1';
                end if;

                if (e = 0) then
                    ear_stim <= '0';
                else
                    ear_stim <= '1';
                end if;

                wait for settle;

                if (rd = 0 and e = 0) then
                    expect_d6('0', "reading, EAR low");
                else
                    expect_d6('H', "port_rd_n=" & integer'image(rd) & " ear="
                              & integer'image(e) & " (released)");
                end if;

            end loop;

        end loop;

        port_rd_n <= '1';
        ear_stim  <= '1';

        report "PASS: all 4 combinations: bit 6 = EAR during a read, released otherwise"
            severity note;

        --------------------------------------------------------------
        -- 2) SHARED BUS: another device drives D6 while not reading
        --------------------------------------------------------------
        for v in 0 to 1 loop

            for e in 0 to 1 loop

                if (e = 0) then
                    ear_stim <= '0';
                else
                    ear_stim <= '1';
                end if;

                if (v = 0) then
                    d6_other <= '0';
                else
                    d6_other <= '1';
                end if;

                wait for settle;

                assert d(6) = d6_other
                    report "FAIL shared bus: another device drives "
                           & std_logic'image(d6_other) & " but D6 reads "
                           & std_logic'image(d(6))
                    severity failure;

                checks_v := checks_v + 1;

            end loop;

        end loop;

        d6_other <= 'Z';
        ear_stim <= '1';
        wait for settle;

        report "PASS: outside a read the ULA never fights another driver on D6"
            severity note;

        --------------------------------------------------------------
        -- 3) TAPE LOADER: poll bit 6 and count the edges of the wave
        --------------------------------------------------------------
        tape_on <= true;
        last    := '1';
        edges   := 0;

        for i in 1 to (n_halves * (t_half / t_poll)) - 1 loop

            wait for t_poll - t_rd;
            port_rd_n <= '0';
            wait for t_rd / 2;

            -- the sample must be EAR's level right now
            expect_d6(on_bus(ear), "loader poll " & integer'image(i));

            if (d(6) = '0') then
                sample := '0';
            else
                sample := '1';
            end if;

            if (sample /= last) then
                edges := edges + 1;
                last  := sample;
            end if;

            wait for t_rd / 2;
            port_rd_n <= '1';

        end loop;

        tape_on <= false;

        assert edges = n_halves - 1
            report "FAIL tape loader: counted " & integer'image(edges)
                   & " edges, expected " & integer'image(n_halves - 1)
            severity failure;

        checks_v := checks_v + 1;

        report "PASS: the loader loop sees every EAR level and counts all "
               & integer'image(edges) & " edges"
            severity note;

        --------------------------------------------------------------
        -- 4) A WHOLE PORT READ: keyboard on D0..D4, EAR on D6
        --------------------------------------------------------------
        wait for t_half;                      -- let the tape process finish

        -- Z down (column 1) and EAR high
        k         <= "11101";
        ear_stim  <= '1';
        port_rd_n <= '0';
        wait for settle;

        assert d(4 downto 0) = "HHH0H" and d(6) = 'H'
            report "FAIL whole read, Z down, EAR high: D6, D4..D0 = "
                   & std_logic'image(d(6)) & " " & to_string(d(4 downto 0))
            severity failure;

        checks_v := checks_v + 1;

        -- no key down and EAR low
        k        <= "11111";
        ear_stim <= '0';
        wait for settle;

        assert d(4 downto 0) = "HHHHH" and d(6) = '0'
            report "FAIL whole read, no key, EAR low: D6, D4..D0 = "
                   & std_logic'image(d(6)) & " " & to_string(d(4 downto 0))
            severity failure;

        checks_v := checks_v + 1;

        port_rd_n <= '1';
        wait for settle;

        report "PASS: one port read gives the keyboard on D0..D4 and EAR on D6 together"
            severity note;

        checks <= checks_v;
        wait for 1 ns;

        report "ALL TESTS PASSED (" & integer'image(checks_v) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
