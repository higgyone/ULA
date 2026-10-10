----------------------------------------------------------------------------------
-- keyboard_input_tb — self-checking TB for the keyboard half-row read.
--
-- The DUT's D0..D4 pins are the book's collector-follower outputs with WEAK
-- on-chip pull-ups: they pull LOW ('0') or release to the weak pull-up ('H').
-- The TB adds NO pull-up of its own and checks the RESOLVED bus, so:
--   - a released pin must read exactly 'H': proof the ULA supplies the pull-up
--     (a bare 'Z' would read 'Z' and fail);
--   - a pin the ULA wrongly drove strongly '1' would read '1' and fail, so the
--     checks prove the ULA lets go of the bus, not just that it reads high.
--
-- What it proves:
--   1. EXHAUSTIVE: all 2**6 = 64 combinations of port_rd_n and k0..k4. During
--      a port read a key down ('0') pulls its pin low and a key up releases it;
--      without a read every pin is released.
--   2. REAL KEY PRESSES through a model of the Spectrum's 8 x 5 key matrix
--      (the matrix is on the PCB, so it lives in the TB):
--        - no key down: every half-row reads 11111
--        - one key down: it reads '0' in its own half-row and column only,
--          and is invisible from the other half-rows
--        - several half-rows selected at once (A8..A15 = 0x00, as the ROM does
--          to ask "is any key down?"): presses in different half-rows combine
--        - two keys in the same column of different half-rows read as one '0'
--        - not reading the port: keys down make no difference, all released
--   3. SHARED BUS: outside a keyboard read, another device (e.g. the DRAM)
--      can drive any pattern onto D0..D4, with keys held down, and the bus
--      reads exactly that pattern: no 'X', so the ULA is not fighting it.
--
-- Matrix model: column kX is '0' if any key in column X is down in any
-- half-row whose address line (A8..A15) is '0'; otherwise '1' (pulled up).
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity keyboard_input_tb is
end entity keyboard_input_tb;

architecture behavioral of keyboard_input_tb is

    constant settle : time := 5 ns;

    -- keys down: one bit per key, (half-row 0..7)(column 0..4), '1' = down

    type key_matrix_t is array (0 to 7) of std_logic_vector(4 downto 0);

    constant no_keys : key_matrix_t := (others => "00000");

    signal keys_down : key_matrix_t                 := no_keys;
    signal a_hi      : std_logic_vector(7 downto 0) := x"FF"; -- A15..A8

    signal k         : std_logic_vector(4 downto 0); -- k4..k0 into the DUT
    signal k_drive   : std_logic_vector(4 downto 0) := "11111";
    signal use_model : boolean                      := false;
    signal port_rd_n : std_logic                    := '1';

    -- the data bus D4..D0: driven by the DUT and one other device
    signal d       : std_logic_vector(4 downto 0);
    signal d_other : std_logic_vector(4 downto 0) := "ZZZZZ";

    signal checks : integer := 0;

    -- half-row positions of the keys used below

    constant row_caps  : integer := 0; -- A8:  CAPS SHIFT Z X C V
    constant row_a     : integer := 1; -- A9:  A S D F G
    constant row_enter : integer := 6; -- A14: ENTER L K J H
    constant row_space : integer := 7; -- A15: SPACE SYM SHIFT M N B

    -- address high byte selecting one half-row: only bit `row` is '0'

    function row_sel (
        row : integer
    ) return std_logic_vector is

        variable hi : std_logic_vector(7 downto 0);

    begin

        hi      := x"FF";
        hi(row) := '0';
        return hi;

    end function row_sel;

    -- what the bus should read for a value from the ULA:
    -- '0' pulled low, '1' released (the ULA's weak pull-up gives 'H')

    function on_bus (
        v : std_logic_vector(4 downto 0)
    ) return std_logic_vector is

        variable r : std_logic_vector(4 downto 0);

    begin

        for i in 0 to 4 loop

            if (v(i) = '0') then
                r(i) := '0';
            else
                r(i) := 'H';
            end if;

        end loop;

        return r;

    end function on_bus;

begin

    ------------------------------------------------------------------
    -- another device that can drive the bus (no pull-up here: the ULA's
    -- own weak pull-ups must supply the '1's)
    ------------------------------------------------------------------
    d <= d_other;

    ------------------------------------------------------------------
    -- the key matrix (PCB): column X low if a key in column X is down in
    -- any selected half-row
    ------------------------------------------------------------------
    matrix : process (keys_down, a_hi, use_model, k_drive) is

        variable col : std_logic_vector(4 downto 0);

    begin

        col := "11111";

        for row in 0 to 7 loop

            if (a_hi(row) = '0') then
                col := col and not keys_down(row);
            end if;

        end loop;

        if (use_model) then
            k <= col;
        else
            k <= k_drive;
        end if;

    end process matrix;

    dut : entity work.keyboard_input(structural)
        port map (
            k0        => k(0),
            k1        => k(1),
            k2        => k(2),
            k3        => k(3),
            k4        => k(4),
            port_rd_n => port_rd_n,
            d0        => d(0),
            d1        => d(1),
            d2        => d(2),
            d3        => d(3),
            d4        => d(4)
        );

    stim : process is

        variable checks_v : integer := 0;
        variable e        : std_logic_vector(4 downto 0);

        -- check the resolved bus against a ULA value ('1' = released)

        procedure check_bus (
            want : in std_logic_vector(4 downto 0);
            what : in string
        ) is
        begin

            assert d = on_bus(want)
                report "FAIL " & what & ": bus D4..D0 expected " & to_string(on_bus(want))
                       & " got " & to_string(d)
                severity failure;

            checks_v := checks_v + 1;

        end procedure check_bus;

        -- read the port with the given address high byte and check D4..D0

        procedure read_port (
            hi   : in std_logic_vector(7 downto 0);
            want : in std_logic_vector(4 downto 0);
            what : in string
        ) is
        begin

            a_hi      <= hi;
            port_rd_n <= '0';
            wait for settle;
            check_bus(want, what);
            port_rd_n <= '1';
            wait for settle;

        end procedure read_port;

        -- press exactly one key (all others up)

        procedure press_only (
            row : in integer;
            col : in integer
        ) is

            variable m : key_matrix_t;

        begin

            m           := no_keys;
            m(row)(col) := '1';
            keys_down   <= m;
            wait for settle;

        end procedure press_only;

    begin

        --------------------------------------------------------------
        -- 1) EXHAUSTIVE: port_rd_n x k0..k4, all 64 combinations
        --------------------------------------------------------------
        use_model <= false;

        for n in 0 to 63 loop

            if (n >= 32) then
                port_rd_n <= '1';
            else
                port_rd_n <= '0';
            end if;

            for b in 0 to 4 loop

                if ((n / (2 ** b)) mod 2 = 1) then
                    k_drive(b) <= '1';
                else
                    k_drive(b) <= '0';
                end if;

            end loop;

            wait for settle;

            -- reading: keys pass straight through; not reading: all released
            if (port_rd_n = '0') then
                e := k_drive;
            else
                e := "11111";
            end if;

            check_bus(e, "combination " & integer'image(n));

        end loop;

        port_rd_n <= '1';

        report "PASS: all 64 combinations of port_rd_n and k0..k4 (pins only "
               & "ever '0' or released)"
            severity note;

        --------------------------------------------------------------
        -- 2) REAL KEY PRESSES through the matrix
        --------------------------------------------------------------
        use_model <= true;
        keys_down <= no_keys;
        wait for settle;

        -- no key down: every half-row reads 11111
        for row in 0 to 7 loop

            read_port(row_sel(row), "11111", "no key, half-row " & integer'image(row));

        end loop;

        -- Z (half-row A8, column 1): only D1 low, only in its own half-row
        press_only(row_caps, 1);
        read_port(x"FE", "11101", "Z down, reading A8 half-row (0xFE)");
        read_port(x"FD", "11111", "Z down, reading A9 half-row (0xFD)");
        read_port(x"7F", "11111", "Z down, reading A15 half-row (0x7F)");

        -- SPACE (half-row A15, column 0)
        press_only(row_space, 0);
        read_port(x"7F", "11110", "SPACE down, reading A15 half-row (0x7F)");
        read_port(x"FE", "11111", "SPACE down, reading A8 half-row (0xFE)");

        -- B (half-row A15, column 4)
        press_only(row_space, 4);
        read_port(x"7F", "01111", "B down, reading A15 half-row (0x7F)");

        report "PASS: single keys read only in their own half-row and column"
            severity note;

        -- A (A9, col 0) and H (A14, col 4): read all half-rows at once
        keys_down            <= no_keys;
        wait for settle;
        keys_down(row_a)     <= "00001";
        keys_down(row_enter) <= "10000";
        wait for settle;
        read_port(x"00", "01110", "A + H down, all half-rows (0x00)");
        read_port(x"FD", "11110", "A + H down, A9 only (0xFD)");
        read_port(x"BF", "01111", "A + H down, A14 only (0xBF)");

        -- CAPS SHIFT (A8, col 0) and ENTER (A14, col 0): same column
        keys_down            <= no_keys;
        wait for settle;
        keys_down(row_caps)  <= "00001";
        keys_down(row_enter) <= "00001";
        wait for settle;
        read_port(x"00", "11110", "CAPS SHIFT + ENTER, all half-rows (0x00)");
        read_port(x"BE", "11110", "CAPS SHIFT + ENTER, A8 and A14 (0xBE)");

        report "PASS: several half-rows read at once combine correctly"
            severity note;

        -- not reading: keys down make no difference, all released
        a_hi      <= x"00";
        port_rd_n <= '1';
        wait for settle;
        check_bus("11111", "not reading, keys down");

        report "PASS: without a port read, keys down make no difference"
            severity note;

        --------------------------------------------------------------
        -- 3) SHARED BUS: another device drives D0..D4 while the ULA is
        --    not reading, with keys still held down
        --------------------------------------------------------------
        for n in 0 to 31 loop

            for b in 0 to 4 loop

                if ((n / (2 ** b)) mod 2 = 1) then
                    d_other(b) <= '1';
                else
                    d_other(b) <= '0';
                end if;

            end loop;

            wait for settle;

            assert d = d_other
                report "FAIL shared bus: another device drives " & to_string(d_other)
                       & " but the bus reads " & to_string(d)
                severity failure;

            checks_v := checks_v + 1;

        end loop;

        d_other <= "ZZZZZ";

        report "PASS: outside a read the ULA never fights another driver (no 'X')"
            severity note;

        checks <= checks_v;
        wait for 1 ns;

        report "ALL TESTS PASSED (" & integer'image(checks_v) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
