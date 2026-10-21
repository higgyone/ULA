----------------------------------------------------------------------------------
-- sound_io — pin 28 (SOUND): MIC / speaker output level and the EAR input
--
-- Pin 28 is one ANALOGUE pin doing three jobs: it drives the MIC socket and
-- the speaker, and it reads the EAR (tape) input back on the same pin. This
-- block models the ULA's two analogue cells on it (cells 32, 33), in integer
-- millivolts like yuv. It is deliberately NOT gate-accurate: it is analogue
-- circuitry with no gate-level equivalent (cf. yuv, ras_cas_generation).
--
-- ── Output level (book) ──────────────────────────────────────────────
--   set by the port-write bits latched in cassette_speaker_out:
--
--     speaker (D4)  mic (D3)  |  pin 28
--     -------------------------+---------
--          0           0      |   342 mV
--          0           1      |   652 mV
--          1           0      |  3591 mV
--          1           1      |  3753 mV
--
--   The speaker is fed through two diode drops (~1.4 V) on the PCB, so only
--   the speaker bit's levels are heard; the MIC bit's small swing reaches only
--   the MIC socket (680 ohm + 100 nF, AC-coupled).
--
-- ── EAR input ────────────────────────────────────────────────────────
--   The bistable input switches at 0.714 V:
--     ear = '1' when pin > 714 mV, else '0'
--   The tape signal arrives AC-coupled through 4k1 + 100 nF (10 nF on pin 28
--   to ground). To LOAD, the ROM sets MIC = 1, speaker = 0, parking the pin at
--   652 mV, just 62 mV under the switch point, so a small tape swing flips
--   ear. To SAVE, the ROM toggles MIC (342 <-> 652 mV). With no tape, ear
--   follows the speaker bit only (issue 3 behaviour).
--
-- ── The pin is split into its two directions ────────────────────────
--   VHDL cannot resolve two integer drivers on one net, so the analogue pin
--   is modelled as:
--     sound    OUT  the ULA's own level (342..3753 mV)
--     tape_mv  IN   the tape's contribution through the EAR network: AC, so
--                   it swings both sides of 0 (a plain integer, not
--                   millivolts_t, which cannot go negative)
--   and inside:  pin = sound + tape_mv,  ear = pin > 714 mV.
--   The board model / system TB supplies tape_mv. On the FPGA, pin 28 would
--   become separate pins: a MIC / speaker output and an EAR input.
--   Board circuit and levels: see docs/pinout.md.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   speaker  speaker bit (D4 of the last port write), from cassette_speaker_out
--   mic      MIC bit (D3 of the last port write), from cassette_speaker_out
--   tape_mv  tape signal coupled onto pin 28, in mV (0 = no tape; can be < 0)
--   sound    pin 28 level the ULA drives, in mV
--   ear      EAR as a logic level, to cassette_input (-> D6 on a port read)
--
-- Uses millivolts_t from yuv_levels_pkg (yuv.vhd): analyse yuv.vhd first.
-- Verified by sound_io_tb.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use work.yuv_levels_pkg.all;

entity sound_io is
    port (
        speaker : in    std_logic;
        mic     : in    std_logic;
        tape_mv : in    integer;
        sound   : out   millivolts_t;
        ear     : out   std_logic
    );
end entity sound_io;

architecture behavioral of sound_io is

    signal s_sound_sel : std_logic_vector(1 downto 0);
    signal s_sound     : millivolts_t;
    signal s_pin_mv    : integer;

begin

    s_sound_sel <= speaker & mic;
    with s_sound_sel select s_sound <=
        342 when "00",    -- speaker 0, MIC 0
        652 when "01",    -- speaker 0, MIC 1
        3591 when "10",   -- speaker 1, MIC 0
        3753 when others; -- speaker 1, MIC 1  ("11")

    sound <= s_sound;

    s_pin_mv <= s_sound + tape_mv;
    ear      <= '1' when s_pin_mv > 714 else
                '0'; -- EAR switches at 0.714 V; MIC = 1 biases the pin to 652 mV, just under it

end architecture behavioral;
