----------------------------------------------------------------------------------
-- pal_v_burst_tb — self-checking TB for the PAL colour-burst gate.
--
-- What it proves:
--   1. Burst window — burst is NOR(c4,c5,c6,c7_n,c8_n), active only for
--      c8='1', c7='1', c6='0', c5='0', c4='0'. All 32 combinations of c8..c4
--      are swept and exactly one opens the window. With c3..c0 undecoded that
--      is a 16-pixel window at PIXELS 384..399 -- inside horizontal blanking
--      (320..415) and after the hsync pulse (336..367), i.e. on the BACK
--      PORCH, where a PAL burst belongs. 16 pixels at 7 MHz = 2.29 us against
--      the real ~2.25 us (10 cycles of 4.43 MHz).
--
--   2. Full output table — every (burst, parity) combination is checked
--      against an independent reference model:
--
--        burst  q | burst_ii_n  burst_star_n  burst_star  timing
--        -------- + ------------------------------------------
--          0    0 |     1            1             0         1
--          0    1 |     1            1             0         0
--          1    0 |     0            1             1         1   <- NOT q phase
--          1    1 |     0            0             0         0   <- q phase
--
--      Note the two starred outputs carry OPPOSITE polarities:
--        burst_star_n = NOT(burst AND q)    -- ACTIVE LOW
--        burst_star   =     burst AND NOT q -- ACTIVE HIGH
--      so they are compared by ASSERTION, not by raw level.
--
--   3. PAL alternation — exactly one phase is asserted inside the window, it
--      swaps with line parity, and neither is asserted outside the window.
--      Never both at once: that exclusivity is what Phase Alternating Line
--      depends on.
--
--   4. Line-parity latch — v0 goes through data_latch_1_bit with an active-low
--      enable driven by sync_n, so the parity is sampled DURING sync
--      (sync_n='0', transparent) and HELD for the rest of the line
--      (sync_n='1'). The TB moves v0 mid-line and checks the burst phase does
--      not follow, then checks it tracks again once sync re-opens the latch.
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity pal_v_burst_tb is
end entity pal_v_burst_tb;

architecture behavioral of pal_v_burst_tb is

    constant settle : time := 20 ns; -- > worst-case settle incl. the latch's after-tg

    -- the one c8..c4 code that opens the burst window: c8 c7 c6 c5 c4 = 1 1 0 0 0
    constant burst_code : integer := 24;

    signal c4     : std_logic := '0';
    signal c5     : std_logic := '0';
    signal c6     : std_logic := '0';
    signal c7_n   : std_logic := '1';
    signal c8_n   : std_logic := '1';
    signal v0     : std_logic := '0';
    signal sync_n : std_logic := '0'; -- '0' = in sync, latch transparent

    signal burst_ii_n   : std_logic;
    signal burst_star_n : std_logic;
    signal burst_star   : std_logic;
    signal timing       : std_logic;

    signal checks : integer := 0;

    -- reference model, from the table in the header

    function burst_ref (
        code : integer
    ) return std_logic is
    begin

        if (code = burst_code) then
            return '1';
        end if;

        return '0';

    end function burst_ref;

    function ii_n_ref (
        b : std_logic
    ) return std_logic is
    begin

        return not b;

    end function ii_n_ref;

    function star_n_ref (
        b : std_logic;
        q : std_logic
    ) return std_logic is
    begin

        return not (b and q);

    end function star_n_ref;

    function star_ref (
        b : std_logic;
        q : std_logic
    ) return std_logic is
    begin

        return b and not q;

    end function star_ref;

begin

    dut : entity work.pal_v_burst(structural)
        port map (
            c4           => c4,
            c5           => c5,
            c6           => c6,
            c7_n         => c7_n,
            c8_n         => c8_n,
            v0           => v0,
            sync_n       => sync_n,
            burst_ii_n   => burst_ii_n,
            burst_star_n => burst_star_n,
            burst_star   => burst_star,
            timing       => timing
        );

    stim : process is

        variable checks_v : integer := 0;

        -- drive c8..c4 from a 5-bit code (bit4 = c8 ... bit0 = c4)

        procedure set_code (
            code : in integer
        ) is
        begin

            if ((code / 16) mod 2 = 1) then
                c8_n <= '0'; -- c8 = '1'
            else
                c8_n <= '1';
            end if;

            if ((code / 8) mod 2 = 1) then
                c7_n <= '0'; -- c7 = '1'
            else
                c7_n <= '1';
            end if;

            if ((code / 4) mod 2 = 1) then
                c6 <= '1';
            else
                c6 <= '0';
            end if;

            if ((code / 2) mod 2 = 1) then
                c5 <= '1';
            else
                c5 <= '0';
            end if;

            if (code mod 2 = 1) then
                c4 <= '1';
            else
                c4 <= '0';
            end if;

            wait for settle;

        end procedure set_code;

        -- capture a line parity: pulse sync_n low (transparent), then hold

        procedure latch_parity (
            p : in std_logic
        ) is
        begin

            v0     <= p;
            sync_n <= '0';   -- in sync: latch transparent
            wait for settle;
            sync_n <= '1';   -- out of sync: parity held
            wait for settle;

        end procedure latch_parity;

        -- check all four outputs against the reference for the current state

        procedure check_all (
            code : in integer;
            q    : in std_logic;
            note : in string
        ) is

            variable b : std_logic;

        begin

            b := burst_ref(code);

            assert burst_ii_n = ii_n_ref(b)
                report "FAIL " & note & ": burst_ii_n expected "
                       & std_logic'image(ii_n_ref(b)) & " got " & std_logic'image(burst_ii_n)
                severity failure;

            assert burst_star_n = star_n_ref(b, q)
                report "FAIL " & note & ": burst_star_n expected "
                       & std_logic'image(star_n_ref(b, q)) & " got "
                       & std_logic'image(burst_star_n)
                severity failure;

            assert burst_star = star_ref(b, q)
                report "FAIL " & note & ": burst_star expected "
                       & std_logic'image(star_ref(b, q)) & " got "
                       & std_logic'image(burst_star)
                severity failure;

            assert timing = not q
                report "FAIL " & note & ": timing expected " & std_logic'image(not q)
                       & " got " & std_logic'image(timing)
                severity failure;

            -- exclusivity, by ASSERTION not level: burst_star_n is active low,
            -- burst_star active high, so both asserted at once is illegal
            assert not (burst_star_n = '0' and burst_star = '1')
                report "FAIL " & note & ": both burst phases asserted at once"
                severity failure;

            checks_v := checks_v + 5;

        end procedure check_all;

    begin

        --------------------------------------------------------------
        -- 1) sweep every c8..c4 code on both line parities and check
        --    the full output table
        --------------------------------------------------------------
        for p in 0 to 1 loop

            if (p = 0) then
                latch_parity('0');
            else
                latch_parity('1');
            end if;

            for code in 0 to 31 loop

                set_code(code);

                if (p = 0) then
                    check_all(code, '0', "parity 0, code " & integer'image(code));
                else
                    check_all(code, '1', "parity 1, code " & integer'image(code));
                end if;

            end loop;

        end loop;

        report "burst window confirmed at c8..c4 = 11000 -> pixels "
               & integer'image(burst_code * 16) & ".."
               & integer'image(burst_code * 16 + 15) & " (back porch)"
            severity note;

        --------------------------------------------------------------
        -- 2) the phase actually alternates: inside the window, exactly
        --    one phase is asserted and it swaps with parity
        --------------------------------------------------------------
        set_code(burst_code);

        latch_parity('0');                                                               -- even line -> NOT q phase

        assert burst_star = '1' and burst_star_n = '1'
            report "FAIL even line: expected the NOT-q phase asserted (burst_star='1') "
                   & "with burst_star_n idle ('1'), got "
                   & std_logic'image(burst_star) & std_logic'image(burst_star_n)
            severity failure;
        checks_v := checks_v + 1;

        latch_parity('1');                                                               -- odd line -> q phase

        assert burst_star_n = '0' and burst_star = '0'
            report "FAIL odd line: expected the q phase asserted (burst_star_n='0') "
                   & "with burst_star idle ('0'), got "
                   & std_logic'image(burst_star_n) & std_logic'image(burst_star)
            severity failure;
        checks_v := checks_v + 1;

        --------------------------------------------------------------
        -- 3) parity latch holds for the whole line: with sync_n high,
        --    moving v0 must not disturb the burst phase
        --------------------------------------------------------------
        latch_parity('1');                                                               -- capture odd, then hold
        set_code(burst_code);

        v0 <= '0';                                                                       -- v0 moves mid-line
        wait for settle;

        check_all(burst_code, '1', "parity held after v0 moved mid-line");

        -- and it follows again once sync re-opens the latch
        sync_n <= '0';
        wait for settle;

        check_all(burst_code, '0', "parity re-tracked while sync_n low");

        sync_n <= '1';
        wait for settle;

        checks <= checks_v;
        wait for 1 ns;

        report "ALL TESTS PASSED (" & integer'image(checks_v) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
