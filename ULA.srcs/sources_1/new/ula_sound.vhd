----------------------------------------------------------------------------------
-- ula_sound — sound subsystem: pin 28 (MIC / speaker out, EAR in)
--
-- One of the ULA.vhd subsystems. It groups everything behind port 0xFE's
-- sound bits and the analogue SOUND pin:
--
--   cassette_speaker_out  port WRITE: latches D3 -> mic, D4 -> speaker
--   sound_io              pin 28's analogue level from mic / speaker, plus
--                         the tape's contribution (tape_mv); decides ear
--   cassette_input        port READ: ear onto D6 (open collector '0' / 'H')
--
--      d3, d4 --> cassette_speaker_out --mic, speaker--> sound_io --> sound
--                        ^ port_wr_n                       ^ tape_mv
--                                                          |
--      d6 <------ cassette_input <-------------- ear ------+
--                        ^ port_rd_n
--
-- Pure wiring: no logic of its own. mic, speaker and ear are internal nets
-- (s_mic, s_speaker, s_ear) that no other block uses. port_rd_n / port_wr_n
-- come from io_port_decode_0xfe.
--
-- Ports are named after the top-level nets (rule 2), so the instance in
-- ULA.vhd reads name => name: d3 / d4 / d6 are the data pins, sound and
-- tape_mv the two halves of the analogue pin 28 (see sound_io's header for
-- why the pin is split in two).
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use work.yuv_levels_pkg.all;

entity ula_sound is
    port (
        port_rd_n : in    std_logic;
        port_wr_n : in    std_logic;
        d3        : in    std_logic;
        d4        : in    std_logic;
        tape_mv   : in    integer;
        d6        : out   std_logic;
        sound     : out   millivolts_t
    );
end entity ula_sound;

architecture structural of ula_sound is

    signal s_mic     : std_logic;
    signal s_speaker : std_logic;
    signal s_ear     : std_logic;

begin

    cassette_ip : entity work.cassette_input(structural)
        port map (
            port_rd_n => port_rd_n,
            ear       => s_ear,
            do_6      => d6
        );

    speaker_out : entity work.cassette_speaker_out(structural)
        port map (
            di_3      => d3,
            di_4      => d4,
            port_wr_n => port_wr_n,
            mic       => s_mic,
            speaker   => s_speaker
        );

    sounds : entity work.sound_io(behavioral)
        port map (
            speaker => s_speaker,
            mic     => s_mic,
            tape_mv => tape_mv,
            sound   => sound,
            ear     => s_ear
        );

end architecture structural;
