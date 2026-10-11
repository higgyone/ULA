----------------------------------------------------------------------------------
-- cassette_speaker_out_tb — self-checking TB for the MIC and speaker latches.
--
-- What it proves:
--   1. POWER-ON: before any write, MIC and speaker are both '0', from
--      data_latch_1_bit's seed.
--   2. ALL 4 COMBINATIONS: an OUT to the ULA port with each value of
--      (bit 4, bit 3) sets speaker and mic to it -- bit 3 to mic, bit 4 to
--      speaker, not swapped.
--   3. HOLD: after the write, the data bus carries every other pattern (as
--      it does all the time: DRAM data, other I/O) and neither output moves.
--   4. TRANSPARENT DURING THE WRITE: while port_wr_n is low the outputs
--      follow the bus. That is the book's latch, not an edge flip-flop.
--   5. THE VALUE AT THE END OF THE WRITE STICKS: if the bus changes part-way
--      through a write, the value present when port_wr_n rises is kept.
--   6. Z80 TIMING: the data is put on the bus before the write strobe falls
--      and removed after it rises, as the Z80 does in an OUT; the value
--      written is the value held.
--   7. INDEPENDENT BITS: toggling only the speaker leaves MIC alone and vice
--      versa -- the beeper and cassette-save routines each rewrite one bit
--      while expecting the other to stay put.
--
-- Same structure as border_reg_tb, which latches bits 0..2 from the same
-- port write. Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity cassette_speaker_out_tb is
end entity cassette_speaker_out_tb;

architecture behavioral of cassette_speaker_out_tb is

    constant settle : time := 10 ns;  -- > the latch's after-tg chain
    constant t_data : time := 50 ns;  -- Z80: data before WR falls, and after it rises
    constant t_wr   : time := 400 ns; -- write strobe low

    -- bus bits 4..3 as one vector: (1) = bit 4 = speaker, (0) = bit 3 = mic
    signal di        : std_logic_vector(1 downto 0) := "00";
    signal port_wr_n : std_logic                    := '1';

    signal mic     : std_logic;
    signal speaker : std_logic;

    -- value n (0..3) as (speaker, mic)

    function bits_of (
        n : integer
    ) return std_logic_vector is

        variable v : std_logic_vector(1 downto 0);

    begin

        for i in 0 to 1 loop

            if ((n / (2 ** i)) mod 2 = 1) then
                v(i) := '1';
            else
                v(i) := '0';
            end if;

        end loop;

        return v;

    end function bits_of;

begin

    dut : entity work.cassette_speaker_out(structural)
        port map (
            di_3      => di(0),
            di_4      => di(1),
            port_wr_n => port_wr_n,
            mic       => mic,
            speaker   => speaker
        );

    stim : process is

        variable checks_v : integer := 0;

        procedure expect (
            want : in std_logic_vector(1 downto 0);
            what : in string
        ) is
        begin

            assert (speaker = want(1)) and (mic = want(0))
                report "FAIL " & what & ": (speaker, mic) expected "
                       & to_string(want) & " got "
                       & std_logic'image(speaker) & std_logic'image(mic)
                severity failure;

            checks_v := checks_v + 1;

        end procedure expect;

        -- an OUT to the ULA port with Z80 timing: data first, then the strobe,
        -- data held a little after the strobe ends, then the bus moves on

        procedure out_port (
            value : in integer
        ) is
        begin

            di        <= bits_of(value);
            wait for t_data;
            port_wr_n <= '0';
            wait for t_wr;
            port_wr_n <= '1';
            wait for t_data;
            di        <= not bits_of(value);   -- bus moves on to other traffic
            wait for settle;

        end procedure out_port;

    begin

        --------------------------------------------------------------
        -- 1) POWER-ON: both low before any write
        --------------------------------------------------------------
        -- bus busy, but no write
        di <= "11";
        wait for settle;
        expect("00", "power-on, before any write");

        report "PASS: MIC and speaker are low at power-on"
            severity note;

        --------------------------------------------------------------
        -- 2) + 3) + 6) every combination, written then held while the bus
        --    carries every other pattern
        --------------------------------------------------------------
        for value in 0 to 3 loop

            out_port(value);
            expect(bits_of(value), "after OUT with (speaker, mic) = "
                   & to_string(bits_of(value)));

            for other in 0 to 3 loop

                di <= bits_of(other);
                wait for settle;
                expect(bits_of(value), "holding " & to_string(bits_of(value))
                       & " with bus = " & to_string(bits_of(other)));

            end loop;

        end loop;

        report "PASS: all 4 (speaker, mic) values written with Z80 timing and held while the bus moves"
            severity note;

        --------------------------------------------------------------
        -- 7) independent bits: change one, the other stays
        --------------------------------------------------------------
        -- mic on, speaker off
        out_port(1);
        expect("01", "set mic only");
        -- speaker on, mic still on
        out_port(3);
        expect("11", "turn speaker on, mic unchanged");
        -- speaker off again, mic still on
        out_port(1);
        expect("01", "turn speaker off, mic unchanged");
        out_port(0);                                                                                    -- mic off
        expect("00", "turn mic off");
        -- speaker on, mic stays off
        out_port(2);
        expect("10", "turn speaker on, mic stays off");

        report "PASS: speaker and mic change independently (bit 3 -> mic, bit 4 -> speaker)"
            severity note;

        --------------------------------------------------------------
        -- 4) transparent while port_wr_n is low
        --------------------------------------------------------------
        port_wr_n <= '0';

        for value in 0 to 3 loop

            di <= bits_of(value);
            wait for settle;
            expect(bits_of(value), "transparent during write, bus = "
                   & to_string(bits_of(value)));

        end loop;

        report "PASS: outputs follow the bus while the write strobe is low (latch)"
            severity note;

        --------------------------------------------------------------
        -- 5) the value present when port_wr_n rises is the one kept
        --------------------------------------------------------------
        -- mic at the start of the write, speaker by the end of it
        di        <= bits_of(1);
        wait for settle;
        di        <= bits_of(2);
        wait for settle;
        port_wr_n <= '1';
        wait for settle;
        di        <= bits_of(1);
        wait for settle;
        expect(bits_of(2), "value at the end of the write (speaker only) kept");

        report "PASS: the value on the bus when the write ends is the one held"
            severity note;

        report "ALL TESTS PASSED (" & integer'image(checks_v) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
