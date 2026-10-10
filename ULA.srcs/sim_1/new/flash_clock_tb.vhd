----------------------------------------------------------------------------------
-- flash_clock_tb — self-checking TB for the FLASH attribute clock.
--
-- What it proves:
--   1. Divide ratio — flash_clk toggles once every 16 frames and so has a full
--      period of 32 frames. At 50 Hz PAL that is 0.64 s = 1.5625 Hz, the
--      Spectrum's FLASH rate (INK/PAPER swap every 16 frames).
--   2. Edge selection — the chain advances on the FRAME WRAP. clock_in is
--      NOR(v8_n, tclkb_n) = v8 with tclkb_n low, and d_ff_nor triggers on the
--      falling edge, so a frame tick is a RISING edge of v8_n (v8 falling).
--      Driving frames one at a time and counting toggles verifies exactly one
--      count per frame -- a chain clocked on the wrong edge, or on both, would
--      give the wrong toggle spacing.
--   3. tclkb_n gating — holding tclkb_n HIGH forces clock_in low regardless of
--      v8_n, so the counter must freeze. This is what makes tying it to '0' the
--      correct normal-operation setting.
--   4. Determinism from reset — d_ff_nor's init values mean the chain starts at
--      a known state, so flash_clk begins at '0'.
--
-- A "frame" here is one v8_n pulse. Real frames are 20 ms; the TB uses a short
-- pulse since only the edge count matters to the divider.
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity flash_clock_tb is
end entity flash_clock_tb;

architecture behavioral of flash_clock_tb is

    constant settle : time := 10 ns; -- > worst-case ripple settle through 5 stages

    -- FLASH toggles every 16 frames; a full period is 32 frames
    constant frames_per_toggle : integer := 16;

    signal v8_n      : std_logic := '1';
    signal tclkb_n   : std_logic := '0'; -- normal operation: tied low
    signal flash_clk : std_logic;

begin

    dut : entity work.flash_clock(structural)
        port map (
            v8_n      => v8_n,
            tclkb_n   => tclkb_n,
            flash_clk => flash_clk
        );

    stim : process is

        variable checks    : integer := 0;
        variable toggles   : integer := 0;
        variable since     : integer := 0;
        variable prev      : std_logic;
        variable frozen_at : std_logic;

        -- one frame: v8 high (lines 256..311) then the 311->0 wrap.
        -- v8_n rising = v8 falling = the frame tick the chain counts.

        procedure frame is
        begin

            v8_n <= '0';
            wait for settle;
            v8_n <= '1';
            wait for settle;

        end procedure frame;

    begin

        --------------------------------------------------------------
        -- 1) known starting state (d_ff_nor init values)
        --------------------------------------------------------------
        wait for settle;

        assert flash_clk = '0'
            report "FAIL flash_clk should start at '0', got " & std_logic'image(flash_clk)
            severity failure;
        checks := checks + 1;

        --------------------------------------------------------------
        -- 2) run frames and check every toggle is 16 frames apart
        --------------------------------------------------------------
        prev := flash_clk;

        -- settle past the first toggle so the measurement starts on a boundary
        while (flash_clk = prev) loop

            frame;
            since := since + 1;

            assert since <= 64
                report "FAIL flash_clk never toggled within 64 frames"
                severity failure;

        end loop;

        prev  := flash_clk;
        since := 0;

        -- now measure four consecutive toggle intervals
        for k in 1 to 4 loop

            loop

                frame;
                since := since + 1;
                exit when flash_clk /= prev;

                assert since <= 64
                    report "FAIL toggle " & integer'image(k) & ": no edge within 64 frames"
                    severity failure;

            end loop;

            assert since = frames_per_toggle
                report "FAIL toggle " & integer'image(k) & ": expected a toggle every "
                       & integer'image(frames_per_toggle) & " frames, measured "
                       & integer'image(since)
                severity failure;

            assert flash_clk = not prev
                report "FAIL toggle " & integer'image(k) & ": flash_clk did not invert"
                severity failure;

            toggles := toggles + 1;
            prev    := flash_clk;
            since   := 0;
            checks  := checks + 2;

        end loop;

        -- four toggles = two full 32-frame periods
        assert toggles = 4
            report "FAIL expected 4 toggles, counted " & integer'image(toggles)
            severity failure;
        checks := checks + 1;

        --------------------------------------------------------------
        -- 3) tclkb_n HIGH forces clock_in low -> the counter freezes
        --------------------------------------------------------------
        frozen_at := flash_clk;
        tclkb_n   <= '1';
        wait for settle;

        for f in 1 to 2 * frames_per_toggle + 4 loop -- well past a normal toggle

            frame;

            assert flash_clk = frozen_at
                report "FAIL tclkb_n='1' should freeze the counter, but flash_clk moved at frame "
                       & integer'image(f)
                severity failure;

        end loop;

        checks := checks + 1;

        --------------------------------------------------------------
        -- 4) release tclkb_n: counting resumes
        --------------------------------------------------------------
        tclkb_n <= '0';
        wait for settle;
        prev    := flash_clk;
        since   := 0;

        loop

            frame;
            since := since + 1;
            exit when flash_clk /= prev;

            assert since <= 64
                report "FAIL counter did not resume after tclkb_n released"
                severity failure;

        end loop;

        checks := checks + 1;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
