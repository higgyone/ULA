----------------------------------------------------------------------------------
-- test_modes_tb — self-checking TB for the wafer-test clock modes.
--
-- Test modes are entered with MREQ and IORQ held low TOGETHER, which a real
-- Z80 never does. The level of the other strobe picks the mode, and the
-- strobe that is left free becomes a fast test clock:
--   A  WR high, rd_n is the clock -> tclka_n = NOT rd_n (C6..C8 via tclk_a)
--   B  RD high, wr_n is the clock -> tclkb_n = NOT wr_n (flash counter)
-- In test B, K0 shows v8 (while wr_n is low) for the wafer probe.
-- Outside a test mode all three outputs are '0'.
--
-- flash_clock is instantiated on tclkb_n, so the TB also proves the test
-- clock reaches the flash counter with the right polarity.
--
-- What it proves:
--   1. EXHAUSTIVE: all 2**5 = 32 combinations of rd_n, wr_n, ioreq_n,
--      mreq_n and v8_n match the model above.
--   2. NORMAL Z80 CYCLES: idle, memory read / write, refresh, I/O read /
--      write and interrupt acknowledge (IORQ without MREQ) never enter a
--      test mode: all outputs '0', with v8_n either way.
--   3. TEST A CLOCK: rd_n toggled at 20 MHz; tclka_n follows it inverted on
--      every half cycle, tclkb_n and k0 stay '0'.
--   4. TEST B CLOCK: wr_n toggled at 20 MHz; tclkb_n follows it inverted,
--      tclka_n stays '0', k0 = v8 while wr_n is low.
--   5. FLASH, NORMAL: with the bus idle, 64 frames of v8 give exactly 4
--      flash_clk edges (one every 16 frames). This fails if tclkb_n is '1'
--      outside test mode, which blocks v8 at flash_clock's NOR.
--   6. FLASH, TEST B: v8_n low, 64 wr_n cycles at 20 MHz give exactly 4
--      flash_clk edges, 800 ns apart: 625 kHz instead of 1.5625 Hz.
--   7. FLASH, TEST B BLOCKED: v8_n high, the same 64 wr_n cycles give no
--      flash_clk edges and k0 stays '0'.
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

    signal k0      : std_logic;
    signal tclka_n : std_logic;
    signal tclkb_n : std_logic;

    signal flash_clk : std_logic;

    -- flash_clk edge counter
    signal flash_edges : integer := 0;
    signal t_last_edge : time    := 0 ns;
    signal t_prev_edge : time    := 0 ns;

begin

    dut : entity work.test_modes(structural)
        port map (
            v8_n    => v8_n,
            rd_n    => rd_n,
            ioreq_n => ioreq_n,
            mreq_n  => mreq_n,
            wr_n    => wr_n,
            k0      => k0,
            tclkb_n => tclkb_n,
            tclka_n => tclka_n
        );

    flash : entity work.flash_clock(structural)
        port map (
            v8_n      => v8_n,
            tclkb_n   => tclkb_n,
            flash_clk => flash_clk
        );

    count_flash : process (flash_clk) is
    begin

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

            exp_k0 := '0';

            if (exp_b = '1' and v8_n = '0') then
                exp_k0 := '1';
            end if;

            assert tclka_n = exp_a
                report "FAIL " & what & ": tclka_n = " & std_logic'image(tclka_n)
                       & ", expected " & std_logic'image(exp_a)
                severity failure;
            assert tclkb_n = exp_b
                report "FAIL " & what & ": tclkb_n = " & std_logic'image(tclkb_n)
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
                assert tclka_n = '0' and tclkb_n = '0' and k0 = '0'
                    report "FAIL normal cycle " & integer'image(c)
                           & ": a test-mode output is not '0'"
                    severity failure;
                checks_v := checks_v + 1;

            end loop;

        end loop;

        report "PASS: normal Z80 cycles never enter a test mode (all outputs '0')";

        -- 3. test A: rd_n is the clock ------------------------------------
        v8_n <= '0';
        set_bus('0', '0', '1', '1');
        wait for settle;

        for i in 1 to 40 loop

            rd_n <= not rd_n;
            wait for t_half;
            check("test A, rd_n half cycle " & integer'image(i));

        end loop;

        report "PASS: test A: tclka_n follows rd_n (inverted) at 20 MHz";

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

        report "PASS: test B: tclkb_n follows wr_n (inverted), k0 = v8 while wr_n is low";

        -- 5. flash counter in normal operation: clocked by v8 --------------
        set_bus('1', '1', '1', '1');
        v8_n   <= '1';
        wait for t_ripple;
        base_v := flash_edges;

        for f in 1 to 64 loop

            v8_n <= '0';                                                                        -- v8 rises
            wait for t_frame / 2;
            v8_n <= '1';                                                                        -- v8 falls: the frame wrap, clocks stage 0
            wait for t_frame / 2;

        end loop;

        wait for t_ripple;
        expect_edges("normal mode, 64 frames of v8", 4);
        report "PASS: normal mode: 64 frames of v8 give 4 flash_clk edges (one per 16 frames)";

        -- 6. flash counter in test B: clocked by wr_n ----------------------
        set_bus('0', '0', '1', '1');
        v8_n   <= '0';                                                                          -- open the gate (the probe sees v8 on K0)
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
            assert k0 = '0'
                report "FAIL test B, v8_n high: k0 = " & std_logic'image(k0)
                severity failure;
            checks_v := checks_v + 1;
            wr_n     <= '1';
            wait for t_half;

        end loop;

        wait for t_ripple;
        expect_edges("test B, v8_n high, 64 wr_n cycles", 0);
        report "PASS: test B with v8_n high: wr_n is blocked, no flash_clk edges, k0 = '0'";

        report "ALL TESTS PASSED (" & integer'image(checks_v) & " checks)";
        finish;

    end process stim;

end architecture behavioral;
