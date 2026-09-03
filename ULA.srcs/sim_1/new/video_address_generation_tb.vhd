----------------------------------------------------------------------------------
-- video_address_generation_tb — self-checking TB for the video address generator
-- (the row/column multiplexer onto the 7 shared DRAM address pins, plus ae_n).
--
-- What it proves:
--   1. The three mux phases put the right counter bits on a6..a0, checked against
--      an independent reference model written from the ULA address map, over
--      several bit patterns chosen so any swapped or stuck bit shows up:
--        ROW        (ras_n high)          a6..a0 = v4 v3 c7 c6 c5 c4 c2
--        DISPLAY    (ras_n low,  c1='0')  a6..a0 = 0  v7 v6 v2 v1 v0 v5
--        ATTRIBUTE  (ras_n low,  c1='1')  a6..a0 = 0  1  1  0  v7 v6 v5
--      The attribute column's 1 1 0 is the 0x1800 base, hardwired.
--   2. Page-read invariant — while ras_n is LOW the address must not move except
--      for the column select. Toggling c2 during the RAS-low period must leave
--      the address untouched: in a page read only the COLUMN changes, the ROW is
--      frozen. This is what the a0 latch is there for.
--   3. Row tracks c2 while ras_n is HIGH (latch transparent), so the row is
--      settled before RAS falls.
--   4. ae_n = NOT( (c0.c1.c2 + c3) AND NOT border ) — the address-enable that
--      opens the tri-state drivers one pixel before the c3 fetch window, and
--      keeps them shut in the border.
--
-- a0 note: c2 is used directly and un-inverted. The book delays AND inverts c2
-- (the delay pushes its edge past ras_n for DRAM tRAH and covers the master
-- counter's propagation delay; the inversion then corrects the stale value the
-- delay puts on the bus). Neither is reproducible or needed on an FPGA, and they
-- must be dropped together -- see the header of video_address_generation.vhd.
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity video_address_generation_tb is
end entity video_address_generation_tb;

architecture behavioral of video_address_generation_tb is

    constant settle : time := 20 ns; -- > worst-case settle incl. the latch's after-tg

    -- cv = c7..c0, vv = v7..v0
    signal cv    : std_logic_vector(7 downto 0) := (others => '0');
    signal vv    : std_logic_vector(7 downto 0) := (others => '0');
    signal ras_n : std_logic                    := '1';
    signal brdr  : std_logic                    := '0';

    signal a0   : std_logic;
    signal a1   : std_logic;
    signal a2   : std_logic;
    signal a3   : std_logic;
    signal a4   : std_logic;
    signal a5   : std_logic;
    signal a6   : std_logic;
    signal ae_n : std_logic;

    signal addr : std_logic_vector(6 downto 0); -- a6..a0, for comparison

    signal checks : integer := 0;

    -- reference model, from the address map (returns a6..a0)

    function row_ref (
        c : std_logic_vector(7 downto 0);
        v : std_logic_vector(7 downto 0)
    ) return std_logic_vector is
    begin

        return v(4) & v(3) & c(7) & c(6) & c(5) & c(4) & c(2);

    end function row_ref;

    function disp_ref (
        v : std_logic_vector(7 downto 0)
    ) return std_logic_vector is
    begin

        return '0' & v(7) & v(6) & v(2) & v(1) & v(0) & v(5);

    end function disp_ref;

    function attr_ref (
        v : std_logic_vector(7 downto 0)
    ) return std_logic_vector is
    begin

        return '0' & '1' & '1' & '0' & v(7) & v(6) & v(5);

    end function attr_ref;

    function ae_n_ref (
        c : std_logic_vector(7 downto 0);
        b : std_logic
    ) return std_logic is

        variable ae : std_logic;

    begin

        ae := ((c(0) and c(1) and c(2)) or c(3)) and not b;

        return not ae;

    end function ae_n_ref;

    function to_bin (
        x : std_logic_vector
    ) return string is

        variable s : string(1 to x'length);
        variable i : integer := 1;

    begin

        for k in x'range loop

            if (x(k) = '1') then
                s(i) := '1';
            else
                s(i) := '0';
            end if;

            i := i + 1;

        end loop;

        return s;

    end function to_bin;

begin

    dut : entity work.video_address_generation(structural)
        port map (
            vid_ras_n => ras_n,
            c0_n      => not cv(0),
            c1        => cv(1),
            c1_n      => not cv(1),
            c2        => cv(2),
            c2_n      => not cv(2),
            c3        => cv(3),
            c4        => cv(4),
            c5        => cv(5),
            c6        => cv(6),
            c7        => cv(7),
            v0        => vv(0),
            v1        => vv(1),
            v2        => vv(2),
            v3        => vv(3),
            v4        => vv(4),
            v5        => vv(5),
            v6        => vv(6),
            v7        => vv(7),
            border    => brdr,
            a0        => a0,
            a1        => a1,
            a2        => a2,
            a3        => a3,
            a4        => a4,
            a5        => a5,
            a6        => a6,
            ae_n      => ae_n
        );

    addr <= a6 & a5 & a4 & a3 & a2 & a1 & a0;

    stim : process is

        variable held : std_logic_vector(6 downto 0);

        -- the DUT takes c0/c1/c2 complements as separate ports; drive them
        -- consistently from cv, then let the phase select ras_n / c1

        procedure apply (
            c : in std_logic_vector(7 downto 0);
            v : in std_logic_vector(7 downto 0)
        ) is
        begin

            cv <= c;
            vv <= v;
            wait for settle;

        end procedure apply;

        procedure check_addr (
            expect : in std_logic_vector(6 downto 0);
            phase  : in string
        ) is
        begin

            assert addr = expect
                report "FAIL " & phase & ": a6..a0 expected " & to_bin(expect)
                       & " got " & to_bin(addr)
                severity failure;
            checks <= checks + 1;
            wait for 1 ns;

        end procedure check_addr;

        -- run one counter pattern through all three mux phases

        procedure sweep_phases (
            c : in std_logic_vector(7 downto 0);
            v : in std_logic_vector(7 downto 0);
            n : in string
        ) is

            variable cd : std_logic_vector(7 downto 0);

        begin

            -- ROW: ras_n high, latch transparent
            ras_n <= '1';
            apply(c, v);
            check_addr(row_ref(c, v), "ROW " & n);

            -- DISPLAY column: ras_n low, c1 = '0'
            cd    := c;
            cd(1) := '0';
            ras_n <= '1';                 -- settle the row first, then assert RAS
            apply(cd, v);
            ras_n <= '0';
            wait for settle;
            check_addr(disp_ref(v), "DISPLAY COL " & n);

            -- ATTRIBUTE column: ras_n low, c1 = '1'
            cd(1) := '1';
            apply(cd, v);
            check_addr(attr_ref(v), "ATTR COL " & n);

            ras_n <= '1';
            wait for settle;

        end procedure sweep_phases;

    begin

        --------------------------------------------------------------
        -- 1) the three mux phases, over several bit patterns
        --------------------------------------------------------------
        sweep_phases("10101010", "11010101", "pattern A");
        sweep_phases("01010101", "00101010", "pattern B");
        sweep_phases("11111111", "11111111", "all ones");
        sweep_phases("00000000", "00000000", "all zeros");
        sweep_phases("11001010", "10110011", "pattern C");

        --------------------------------------------------------------
        -- 2) page-read invariant: with ras_n LOW, toggling c2 must not
        --    disturb the address. Only the column may change.
        --------------------------------------------------------------
        ras_n <= '1';
        apply("10101010", "11010101");                                                  -- c2 = '0' here
        ras_n <= '0';                                                                   -- RAS asserted: row frozen
        wait for settle;

        held := addr;

        cv(2) <= '1';                                                                   -- c2 moves during the page read
        wait for settle;

        assert addr = held
            report "FAIL page read: address moved when c2 changed during RAS-low ("
                   & to_bin(held) & " -> " & to_bin(addr) & ")"
            severity failure;

        cv(2) <= '0';
        wait for settle;

        assert addr = held
            report "FAIL page read: address moved when c2 returned during RAS-low"
            severity failure;

        checks <= checks + 2;
        wait for 1 ns;

        ras_n <= '1';
        wait for settle;

        --------------------------------------------------------------
        -- 3) while ras_n is HIGH the row tracks c2 (latch transparent),
        --    so the row is settled before RAS falls
        --------------------------------------------------------------
        apply("10101010", "11010101");

        cv(2) <= '0';
        wait for settle;

        assert a0 = '0'
            report "FAIL row phase: a0 should track c2='0', got " & std_logic'image(a0)
            severity failure;

        cv(2) <= '1';
        wait for settle;

        assert a0 = '1'
            report "FAIL row phase: a0 should track c2='1', got " & std_logic'image(a0)
            severity failure;

        checks <= checks + 2;
        wait for 1 ns;

        --------------------------------------------------------------
        -- 4) ae_n: opens for the c3 window plus the c0.c1.c2 pre-pixel,
        --    and stays shut in the border
        --------------------------------------------------------------
        for b in 0 to 1 loop

            if (b = 0) then
                brdr <= '0';
            else
                brdr <= '1';
            end if;

            for k in 0 to 15 loop

                cv(3) <= '0';
                cv(2) <= '0';
                cv(1) <= '0';
                cv(0) <= '0';

                if (k >= 8) then
                    cv(3) <= '1';
                end if;

                if ((k / 4) mod 2 = 1) then
                    cv(2) <= '1';
                end if;

                if ((k / 2) mod 2 = 1) then
                    cv(1) <= '1';
                end if;

                if (k mod 2 = 1) then
                    cv(0) <= '1';
                end if;

                wait for settle;

                assert ae_n = ae_n_ref(cv, brdr)
                    report "FAIL ae_n at count " & integer'image(k) & " border="
                           & std_logic'image(brdr) & ": expected "
                           & std_logic'image(ae_n_ref(cv, brdr))
                           & " got " & std_logic'image(ae_n)
                    severity failure;
                checks <= checks + 1;
                wait for 1 ns;

            end loop;

        end loop;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
