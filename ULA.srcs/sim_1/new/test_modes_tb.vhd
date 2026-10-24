----------------------------------------------------------------------------------
-- test_modes_tb — self-checking TB for the wafer-test clock modes.
--
-- Test modes are entered with MREQ and IORQ held low TOGETHER, which a real
-- Z80 never does. The level of the other strobe picks the mode, and the
-- strobe that is left free becomes a fast test clock:
--   A  WR high, rd_n is the clock -> tclk_a = NOT rd_n (C6..C8 via tclk_a)
--   B  RD high, wr_n is the clock -> tclk_b = NOT wr_n (flash counter)
-- In test B, the K0 pin carries v8_n (while wr_n is low) for the wafer probe.
-- Outside a test mode tclk_a and tclk_b are '0'.
--
-- K0 is open collector with a WEAK on-chip pull-up: the DUT pulls it LOW
-- ('0') or releases it to 'H'. The TB adds NO pull-up of its own, so a
-- released pin must read exactly 'H' from the DUT itself. key_k0 models a
-- key on keyboard column 0 sharing the pin ('Z' = no key, '0' = key down).
--
-- flash_clock is instantiated on tclk_b, so the TB also proves the test
-- clock reaches the flash counter with the right polarity.
--
-- What it proves:
--   1. EXHAUSTIVE: all 2**5 = 32 combinations of rd_n, wr_n, ioreq_n,
--      mreq_n and v8_n match the model above.
--   2. NORMAL Z80 CYCLES: idle, memory read / write, refresh, I/O read /
--      write and interrupt acknowledge (IORQ without MREQ) never enter a
--      test mode: test clocks '0' and K0 released ('H'), with v8_n either way.
--   3. TEST A CLOCK: rd_n toggled at 20 MHz; tclk_a follows it inverted on
--      every half cycle, tclk_b stays '0', K0 stays released.
--   4. TEST B CLOCK: wr_n toggled at 20 MHz; tclk_b follows it inverted,
--      tclk_a stays '0', K0 = v8_n ('0' / 'H') while wr_n is low.
--   5. FLASH, NORMAL: with the bus idle, 64 frames of v8 give exactly 4
--      flash_clk edges (one every 16 frames). This fails if tclk_b is '1'
--      outside test mode, which blocks v8 at flash_clock's NOR.
--   6. FLASH, TEST B: v8_n low, 64 wr_n cycles at 20 MHz give exactly 4
--      flash_clk edges, 800 ns apart: 625 kHz instead of 1.5625 Hz.
--   7. FLASH, TEST B BLOCKED: v8_n high, the same 64 wr_n cycles give no
--      flash_clk edges and K0 stays released ('H').
--   8. SHARED K0 PIN: outside test B, a key on column 0 pulls K0 low and
--      releasing it returns the pin to 'H', in every normal Z80 cycle and in
--      test A, with no 'X'. In test B, a key and the DUT pulling low together
--      read '0' (wired-OR), not 'X'.
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity test_modes_tb is
end entity test_modes_tb;

architecture behavioral of test_modes_tb is

    constant settle   : time := 5 ns;
    constant t_half   : time := 25 ns;  -- 20 MHz test clock, half period
    constant t_frame  : time := 1 us;   -- synthetic v8 period (normal mode)
    constant t_ripple : time := 200 ns; -- flash ripple chain settle

    signal rd_n    : std_logic := '1';
    signal wr_n    : std_logic := '1';
    signal ioreq_n : std_logic := '1';
    signal mreq_n  : std_logic := '1';
    signal v8_n    : std_logic := '1';

    signal k0     : std_logic;
    signal key_k0 : std_logic := 'Z'; -- a key on column 0 ('0' = down)
    signal tclk_a : std_logic;
    signal tclk_b : std_logic;

    signal flash_clk : std_logic;

    -- flash_clk edge counter
    signal flash_edges : integer := 0;
    signal t_last_edge : time    := 0 ns;
    signal t_prev_edge : time    := 0 ns;

begin

    -- the keyboard matrix on the same pin (no pull-up here: the ULA's own
    -- weak pull-up must supply the 'H')
    k0 <= key_k0;

    dut : entity work.test_modes(structural)
        port map (
            v8_n    => v8_n,
            rd_n    => rd_n,
            ioreq_n => ioreq_n,
            mreq_n  => mreq_n,
            wr_n    => wr_n,
            k0      => k0,
            tclk_b  => tclk_b,
            tclk_a  => tclk_a
        );

    flash : entity work.flash_clock(structural)
        port map (
            v8_n      => v8_n,
            tclk_b    => tclk_b,
            flash_clk => flash_clk
        );

    -- wait-based, not a sensitivity list: it reads the signals it drives
    count_flash : process is
    begin

        wait on flash_clk;

        if (rising_edge(flash_clk) or falling_edge(flash_clk)) then
            flash_edges <= flash_edges + 1;
            t_prev_edge <= t_last_edge;
            t_last_edge <= now;
        end if;

    end process count_flash;

    stim : process is

        variable checks_v : integer := 0;
        variable base_v   : integer;

        procedure set_bus (
            mreq,
            ioreq,
            rd,
            wr : std_logic
        ) is
        begin

            mreq_n  <= mreq;
            ioreq_n <= ioreq;
            rd_n    <= rd;
            wr_n    <= wr;

        end procedure set_bus;

        -- compare all three outputs with the model, from the current inputs

        procedure check (
            what : string
        ) is

            variable test_a : boolean;
            variable test_b : boolean;
            variable exp_a  : std_logic;
            variable exp_b  : std_logic;
            variable exp_k0 : std_logic;

        begin

            test_a := mreq_n = '0' and ioreq_n = '0' and wr_n = '1';
            test_b := mreq_n = '0' and ioreq_n = '0' and rd_n = '1';

            exp_a := '0';

            if (test_a and rd_n = '0') then
                exp_a := '1';
            end if;

            exp_b := '0';

            if (test_b and wr_n = '0') then
                exp_b := '1';
            end if;

            -- K0 pin: pulled low in test B while wr_n is low and v8 is high
            -- (pin = v8_n), otherwise released to the weak pull-up
            exp_k0 := 'H';

            if (exp_b = '1' and v8_n = '0') then
                exp_k0 := '0';
            end if;

            assert tclk_a = exp_a
                report "FAIL " & what & ": tclk_a = " & std_logic'image(tclk_a)
                       & ", expected " & std_logic'image(exp_a)
                severity failure;
            assert tclk_b = exp_b
                report "FAIL " & what & ": tclk_b = " & std_logic'image(tclk_b)
                       & ", expected " & std_logic'image(exp_b)
                severity failure;
            assert k0 = exp_k0
                report "FAIL " & what & ": k0 = " & std_logic'image(k0)
                       & ", expected " & std_logic'image(exp_k0)
                severity failure;
            checks_v := checks_v + 3;

        end procedure check;

        procedure expect_edges (
            what : string;
            want : integer
        ) is
        begin

            assert flash_edges - base_v = want
                report "FAIL " & what & ": " & integer'image(flash_edges - base_v)
                       & " flash_clk edges, expected " & integer'image(want)
                severity failure;
            checks_v := checks_v + 1;

        end procedure expect_edges;

        type cycle_t is record
            mreq, ioreq, rd, wr : std_logic;
        end record cycle_t;

        type cycle_array_t is array (natural range <>) of cycle_t;

        constant cycles : cycle_array_t :=
        (
            (
                '1',
                '1',
                '1',
                '1'
            ), -- idle
            (
                '0',
                '1',
                '0',
                '1'
            ), -- memory read
            (
                '0',
                '1',
                '1',
                '0'
            ), -- memory write
            (
                '0',
                '1',
                '1',
                '1'
            ), -- refresh (MREQ alone)
            (
                '1',
                '0',
                '0',
                '1'
            ), -- I/O read
            (
                '1',
                '0',
                '1',
                '0'
            ), -- I/O write
            (
                '1',
                '0',
                '1',
                '1'
            )  -- interrupt acknowledge (IORQ, no RD / WR)
        );

        variable bits_v : integer;

    begin

        wait for settle;

        -- 1. exhaustive ---------------------------------------------------
        for n in 0 to 31 loop

            bits_v := n;

            for i in 0 to 4 loop

                case i is

                    when 0 =>

                        rd_n <= '1' when bits_v mod 2 = 1 else '0';

                    when 1 =>

                        wr_n <= '1' when bits_v mod 2 = 1 else '0';

                    when 2 =>

                        ioreq_n <= '1' when bits_v mod 2 = 1 else '0';

                    when 3 =>

                        mreq_n <= '1' when bits_v mod 2 = 1 else '0';

                    when others =>

                        v8_n <= '1' when bits_v mod 2 = 1 else '0';

                end case;

                bits_v := bits_v / 2;

            end loop;

            wait for settle;
            check("combination " & integer'image(n));

        end loop;

        report "PASS: all 32 input combinations match the model";

        -- 2. normal Z80 cycles never enter a test mode ----------------------
        for c in cycles'range loop

            for v in 0 to 1 loop

                v8_n     <= '1' when v = 1 else '0';
                set_bus(cycles(c).mreq, cycles(c).ioreq, cycles(c).rd, cycles(c).wr);
                wait for settle;
                assert tclk_a = '0' and tclk_b = '0' and k0 = 'H'
                    report "FAIL normal cycle " & integer'image(c)
                           & ": a test clock is not '0' or K0 is not released"
                    severity failure;
                checks_v := checks_v + 1;

            end loop;

        end loop;

        report "PASS: normal Z80 cycles never enter a test mode (test clocks '0', K0 released)";

        -- 3. test A: rd_n is the clock ------------------------------------
        v8_n <= '0';
        set_bus('0', '0', '1', '1');
        wait for settle;

        for i in 1 to 40 loop

            rd_n <= not rd_n;
            wait for t_half;
            check("test A, rd_n half cycle " & integer'image(i));

        end loop;

        report "PASS: test A: tclk_a follows rd_n (inverted) at 20 MHz";

        -- 4. test B: wr_n is the clock ------------------------------------
        for v in 0 to 1 loop

            v8_n <= '1' when v = 1 else '0';
            set_bus('0', '0', '1', '1');
            wait for settle;

            for i in 1 to 40 loop

                wr_n <= not wr_n;
                wait for t_half;
                check("test B, v8_n = " & integer'image(v)
                      & ", wr_n half cycle " & integer'image(i));

            end loop;

        end loop;

        report "PASS: test B: tclk_b follows wr_n (inverted), K0 = v8_n while wr_n is low";

        -- 5. flash counter in normal operation: clocked by v8 --------------
        set_bus('1', '1', '1', '1');
        v8_n   <= '1';
        wait for t_ripple;
        base_v := flash_edges;

        for f in 1 to 64 loop

            -- v8 rises, then falls: the frame wrap, which clocks stage 0
            v8_n <= '0';
            wait for t_frame / 2;
            v8_n <= '1';
            wait for t_frame / 2;

        end loop;

        wait for t_ripple;
        expect_edges("normal mode, 64 frames of v8", 4);
        report "PASS: normal mode: 64 frames of v8 give 4 flash_clk edges (one per 16 frames)";

        -- 6. flash counter in test B: clocked by wr_n ----------------------
        -- open the gate (the probe sees v8_n low on K0)
        set_bus('0', '0', '1', '1');
        v8_n   <= '0';
        wait for t_ripple;
        base_v := flash_edges;

        for i in 1 to 64 loop

            wr_n <= '0';
            wait for t_half;
            wr_n <= '1';
            wait for t_half;

        end loop;

        wait for t_ripple;
        expect_edges("test B, v8_n low, 64 wr_n cycles", 4);

        -- 16 wr_n cycles per edge. Allow 2 ns: flash_clk's rise and fall
        -- come through different NORs of the d_ff_nor latch, one 1 ns gate
        -- delay apart, so consecutive edges are 799 / 801 ns apart.
        assert abs (t_last_edge - t_prev_edge - 32 * t_half) <= 2 ns
            report "FAIL test B: flash_clk edges " & time'image(t_last_edge - t_prev_edge)
                   & " apart, expected " & time'image(32 * t_half)
            severity failure;
        checks_v := checks_v + 1;

        report "PASS: test B: 64 wr_n cycles at 20 MHz give 4 flash_clk edges, "
               & time'image(t_last_edge - t_prev_edge) & " apart (625 kHz)";

        -- 7. test B with v8_n high: the gate is shut ------------------------
        v8_n   <= '1';
        wait for t_ripple;
        base_v := flash_edges;

        for i in 1 to 64 loop

            wr_n     <= '0';
            wait for t_half;
            assert k0 = 'H'
                report "FAIL test B, v8_n high: K0 = " & std_logic'image(k0)
                       & ", expected 'H' (released)"
                severity failure;
            checks_v := checks_v + 1;
            wr_n     <= '1';
            wait for t_half;

        end loop;

        wait for t_ripple;
        expect_edges("test B, v8_n high, 64 wr_n cycles", 0);
        report "PASS: test B with v8_n high: wr_n is blocked, no flash_clk edges, K0 released";

        -- 8. K0 shared with the keyboard ------------------------------------
        -- outside test B: normal cycles (v8_n either way) and test A
        for c in cycles'range loop

            for v in 0 to 1 loop

                v8_n     <= '1' when v = 1 else '0';
                set_bus(cycles(c).mreq, cycles(c).ioreq, cycles(c).rd, cycles(c).wr);
                key_k0   <= '0';
                wait for settle;
                assert k0 = '0'
                    report "FAIL normal cycle " & integer'image(c)
                           & ", key down: K0 = " & std_logic'image(k0) & ", expected '0'"
                    severity failure;
                key_k0   <= 'Z';
                wait for settle;
                assert k0 = 'H'
                    report "FAIL normal cycle " & integer'image(c)
                           & ", key up: K0 = " & std_logic'image(k0) & ", expected 'H'"
                    severity failure;
                checks_v := checks_v + 2;

            end loop;

        end loop;

        v8_n     <= '0';
        set_bus('0', '0', '0', '1'); -- test A, rd_n low
        key_k0   <= '0';
        wait for settle;
        assert k0 = '0'
            report "FAIL test A, key down: K0 = " & std_logic'image(k0)
            severity failure;
        key_k0   <= 'Z';
        wait for settle;
        assert k0 = 'H'
            report "FAIL test A, key up: K0 = " & std_logic'image(k0)
            severity failure;
        checks_v := checks_v + 2;

        -- test B with the DUT pulling K0 low (v8 high, wr_n low) and a key
        -- down at the same time: both pull low, so the pin reads '0'
        set_bus('0', '0', '1', '0');
        key_k0   <= '0';
        wait for settle;
        assert k0 = '0'
            report "FAIL test B, DUT and key both low: K0 = " & std_logic'image(k0)
            severity failure;
        key_k0   <= 'Z';
        wait for settle;
        assert k0 = '0'
            report "FAIL test B, DUT alone low: K0 = " & std_logic'image(k0)
            severity failure;
        checks_v := checks_v + 2;

        report "PASS: K0 is shared with the keyboard: a key reads cleanly outside test B, no 'X'";

        report "ALL TESTS PASSED (" & integer'image(checks_v) & " checks)";
        finish;

    end process stim;

end architecture behavioral;
