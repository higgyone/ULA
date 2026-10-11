----------------------------------------------------------------------------------
-- cassette_speaker_out — MIC (cassette out) and speaker bits of the ULA port
--
-- When the CPU writes to the ULA port -- an even-address I/O write, OUT (0xFE),A
-- -- data bit 3 drives the MIC output (to the cassette recorder) and data bit
-- 4 drives the speaker. Two transparent latches capture them and hold them
-- until the next write.
--
-- ── ULA port write: what each bit is for ──────────────────────────────
--     bit  7 6 5 | 4       | 3   | 2 1 0
--          - - - | SPEAKER | MIC | border colour (border_reg)
--   This block takes bits 3 and 4; border_reg takes bits 0..2 from the same
--   write. Bits 5..7 are not used by a port write.
--
-- ── Timing: a latch, as in the book ──────────────────────────────────
--   Both data_latch_1_bit cells are enabled by port_wr_n (ACTIVE LOW):
--     port_wr_n = '0'  during the port write: transparent, outputs follow di_3/di_4
--     port_wr_n = '1'  otherwise: hold the last value written
--   A transparent latch rather than an edge flip-flop, the same as
--   border_reg. The value that sticks is whatever is on the bus when
--   port_wr_n rises at the end of the write; the Z80 holds its data valid
--   across that edge, so the value written is the value kept.
--
--   At power-on both latches start at '0' (data_latch_1_bit's seed), so MIC
--   and the speaker are low until the first write.
--
-- ── Not covered here ─────────────────────────────────────────────────
--   On the real ULA the MIC and speaker bits drive the analogue cassette
--   interface (the same circuitry the EAR input is read through -- see
--   cassette_input and the D5 / cell 31 note in keyboard_input). This block
--   gives the two LOGIC levels only; the analogue output stage is separate.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   di_3       data bus bit 3 (MIC), read by the ULA
--   di_4       data bus bit 4 (speaker), read by the ULA
--   port_wr_n  ULA port write, active low (an even-address I/O write; the
--              gate that makes it is not built yet)
--   mic        MIC output, held from the last port write
--   speaker    speaker output, held from the last port write
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity cassette_speaker_out is
    port (
        di_3      : in    std_logic;
        di_4      : in    std_logic;
        port_wr_n : in    std_logic;
        mic       : out   std_logic;
        speaker   : out   std_logic
    );
end entity cassette_speaker_out;

architecture structural of cassette_speaker_out is

begin

    -- MIC: data bit 3, transparent while port_wr_n is low, held otherwise
    latch_mic : entity work.data_latch_1_bit
        port map (
            e     => port_wr_n,
            d     => di_3,
            q     => mic,
            q_bar => open
        );

    -- speaker: data bit 4, same strobe
    latch_speaker : entity work.data_latch_1_bit
        port map (
            e     => port_wr_n,
            d     => di_4,
            q     => speaker,
            q_bar => open
        );

end architecture structural;
