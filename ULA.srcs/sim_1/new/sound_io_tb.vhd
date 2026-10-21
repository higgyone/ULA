----------------------------------------------------------------------------------
-- sound_io_tb — self-checking TB for pin 28 (SOUND): the MIC / speaker output
-- level and the EAR input comparator.
--
-- The tape is modelled as what reaches pin 28 through the EAR network: an AC
-- signal around 0 mV (tape_mv), sine-shaped because tape and the recorder
-- round off the square wave that was saved. Spectrum tape tones:
--   pilot ~807 Hz, data '1' ~1023 Hz, data '0' ~2047 Hz.
--
-- What it proves:
--   1. OUTPUT LEVELS: all 4 (speaker, mic) combinations give the book's level
--      (342 / 652 / 3591 / 3753 mV), and with no tape ear follows the speaker
--      bit only (issue 3 behaviour).
--   2. SWITCH POINT: with MIC = 1 (652 mV), a tape offset of +62 mV (pin at
--      exactly 714 mV) reads '0', +63 mV reads '1', and -100 mV reads '0'.
--   3. LOAD: MIC = 1, speaker = 0, a +/-100 mV sine tape at each tone. ear
--      toggles once per half-cycle: 2 edges per cycle, and its rising edges
--      are one tape period apart.
--   4. BIAS MATTERS: the same +/-100 mV tape with MIC = 0 (342 mV) never
--      reaches 714 mV, so ear stays '0': the MIC bias is what makes loading
--      work.
--   5. SPEAKER ON: with speaker = 1 the pin sits ~3.6 V and the tape is not
--      heard: ear stays '1'.
--   6. SAVE: toggling MIC with speaker = 0 swings the pin 342 <-> 652 mV and
--      does not trip ear.
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.math_real.all;
    use work.yuv_levels_pkg.all;

library std;
    use std.env.all;

entity sound_io_tb is
end entity sound_io_tb;

architecture behavioral of sound_io_tb is

    constant settle : time := 1 ns;
    constant t_step : time := 2 us; -- tape waveform sample step

    signal speaker : std_logic := '0';
    signal mic     : std_logic := '0';
    signal tape_mv : integer   := 0;

    signal sound : millivolts_t; -- must match the DUT port's subtype
    signal ear   : std_logic;

    -- ear rising-edge timing, published by the monitor
    signal ear_rises  : integer := 0;
    signal ear_falls  : integer := 0;
    signal t_rise     : time    := 0 ns;
    signal t_rise_old : time    := 0 ns;

begin

    dut : entity work.sound_io(behavioral)
        port map (
            speaker => speaker,
            mic     => mic,
            tape_mv => tape_mv,
            sound   => sound,
            ear     => ear
        );

    ear_mon : process (ear) is
    begin

        if rising_edge(ear) then
            ear_rises  <= ear_rises + 1;
            t_rise_old <= t_rise;
            t_rise     <= now;
        elsif falling_edge(ear) then
            ear_falls <= ear_falls + 1;
        end if;

    end process ear_mon;

    stim : process is

        variable checks_v : integer := 0;
        variable r0       : integer;
        variable f0       : integer;

        type level_array_t is array (0 to 3) of integer;

        constant levels : level_array_t := (342, 652, 3591, 3753);

        type freq_array_t is array (0 to 2) of real;

        constant freqs : freq_array_t := (807.0, 1023.0, 2047.0);

        procedure expect_ear (
            want : std_logic;
            what : string
        ) is
        begin

            assert ear = want
                report "FAIL " & what & ": ear = " & std_logic'image(ear)
                       & ", expected " & std_logic'image(want)
                       & " (sound = " & integer'image(sound)
                       & " mV, tape = " & integer'image(tape_mv) & " mV)"
                severity failure;
            checks_v := checks_v + 1;

        end procedure expect_ear;

        -- play a sine of the given frequency and peak amplitude on tape_mv
        -- for n full cycles, sampled every t_step

        procedure play_tone (
            f_hz   : real;
            amp_mv : real;
            n      : integer
        ) is

            variable t_s     : real := 0.0;
            variable samples : integer;

        begin

            samples := integer(real(n) / f_hz / (real(t_step / 1 ns) * 1.0e-9));

            for i in 0 to samples - 1 loop

                t_s     := real(i) * real(t_step / 1 ns) * 1.0e-9;
                tape_mv <= integer(round(amp_mv * sin(math_2_pi * f_hz * t_s)));
                wait for t_step;

            end loop;

            tape_mv <= 0;
            wait for t_step;

        end procedure play_tone;

        variable period : time;
        variable got    : time;

    begin

        wait for settle;

        --------------------------------------------------------------
        -- 1) output levels, no tape
        --------------------------------------------------------------
        for k in 0 to 3 loop

            if (k >= 2) then
                speaker <= '1';
            else
                speaker <= '0';
            end if;

            if (k mod 2 = 1) then
                mic <= '1';
            else
                mic <= '0';
            end if;

            wait for settle;

            assert sound = levels(k)
                report "FAIL level (speaker, mic) = " & integer'image(k) & ": sound = "
                       & integer'image(sound) & " mV, expected "
                       & integer'image(levels(k)) & " mV"
                severity failure;
            checks_v := checks_v + 1;

            if (k >= 2) then
                expect_ear('1', "no tape, speaker on");
            else
                expect_ear('0', "no tape, speaker off");
            end if;

        end loop;

        report "PASS: output levels 342 / 652 / 3591 / 3753 mV; with no tape ear follows the speaker bit"
            severity note;

        --------------------------------------------------------------
        -- 2) the switch point, MIC = 1 (652 mV)
        --------------------------------------------------------------
        speaker <= '0';
        mic     <= '1';
        tape_mv <= 62;
        wait for settle;
        expect_ear('0', "pin at exactly 714 mV");
        tape_mv <= 63;
        wait for settle;
        expect_ear('1', "pin at 715 mV");
        tape_mv <= -100;
        wait for settle;
        expect_ear('0', "pin at 552 mV");
        tape_mv <= 0;
        wait for settle;

        report "PASS: EAR switches just above 714 mV"
            severity note;

        --------------------------------------------------------------
        -- 3) LOAD: MIC = 1, +/-100 mV sine at each tape tone
        --------------------------------------------------------------
        for k in freqs'range loop

            period := integer(1.0e9 / freqs(k)) * 1 ns;

            r0 := ear_rises;
            f0 := ear_falls;
            play_tone(freqs(k), 100.0, 10);

            assert ear_rises - r0 = 10 and ear_falls - f0 = 10
                report "FAIL load at " & integer'image(integer(freqs(k)))
                       & " Hz: " & integer'image(ear_rises - r0) & " rises, "
                       & integer'image(ear_falls - f0) & " falls, expected 10 each"
                severity failure;

            got      := t_rise - t_rise_old;
            assert abs (got - period) <= 2 * t_step
                report "FAIL load at " & integer'image(integer(freqs(k)))
                       & " Hz: ear rising edges " & time'image(got)
                       & " apart, expected " & time'image(period)
                severity failure;
            checks_v := checks_v + 2;

            report "PASS: load at " & integer'image(integer(freqs(k))) & " Hz: ear toggles "
                   & "once per half-cycle, rises " & time'image(got) & " apart"
                severity note;

        end loop;

        --------------------------------------------------------------
        -- 4) MIC = 0: the same tape never reaches the switch point
        --------------------------------------------------------------
        mic      <= '0';
        wait for settle;
        r0       := ear_rises;
        play_tone(1023.0, 100.0, 10);
        assert ear_rises = r0
            report "FAIL MIC = 0: the tape flipped ear without the MIC bias"
            severity failure;
        checks_v := checks_v + 1;
        expect_ear('0', "MIC = 0, after the tone");

        report "PASS: without the MIC bias (342 mV) a +/-100 mV tape is not heard"
            severity note;

        --------------------------------------------------------------
        -- 5) speaker on: the tape is not heard
        --------------------------------------------------------------
        speaker  <= '1';
        wait for settle;
        f0       := ear_falls;
        play_tone(1023.0, 100.0, 10);
        assert ear_falls = f0
            report "FAIL speaker on: the tape pulled ear low"
            severity failure;
        checks_v := checks_v + 1;
        expect_ear('1', "speaker on, after the tone");

        report "PASS: with the speaker on the pin sits ~3.6 V and ear stays '1'"
            severity note;

        --------------------------------------------------------------
        -- 6) SAVE: toggling MIC swings the pin without tripping ear
        --------------------------------------------------------------
        speaker <= '0';
        r0      := ear_rises;

        for i in 1 to 20 loop

            mic <= not mic;
            wait for 244 us;           -- a data '0' half-period

            assert (mic = '1' and sound = 652) or (mic = '0' and sound = 342)
                report "FAIL save: MIC = " & std_logic'image(mic) & " gave "
                       & integer'image(sound) & " mV"
                severity failure;
            checks_v := checks_v + 1;

        end loop;

        assert ear_rises = r0
            report "FAIL save: toggling MIC tripped ear"
            severity failure;
        checks_v := checks_v + 1;

        report "PASS: save: MIC toggles the pin 342 <-> 652 mV, ear stays '0'"
            severity note;

        report "ALL TESTS PASSED (" & integer'image(checks_v) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
