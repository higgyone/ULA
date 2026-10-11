----------------------------------------------------------------------------------
-- cassette_input — EAR (tape input) onto data bit D6 (ULA port read)
--
-- When the Z80 reads the ULA's I/O port (IN from any even address, e.g.
-- 0xFE), the level of the EAR input is put on bit 6. The ROM's tape loader
-- reads this bit in a tight loop and times the edges to decode the tape.
-- (Bits 0..4 of the same read are the keyboard: keyboard_input.)
--
-- ── The gates ────────────────────────────────────────────────────────
--   s_d6_n = NOR(port_rd_n, ear)   '1' only while reading the port AND EAR is
--                                  low
--   d6     = NOT s_d6_n            (gate array), then the D6 pin's output stage
--
--     port_rd_n  ear | s_d6_n | d6 pin
--     ---------------+--------+-----------------------------------------
--         0       0  |   1    |  '0'  pulled low: EAR low
--         0       1  |   0    |  'H'  released, weak pull-up: EAR high
--         1       X  |   0    |  'H'  released, weak pull-up: not reading
--
--   During a read, bit 6 = EAR, not inverted.
--
-- ── The D6 pin pad ───────────────────────────────────────────────────
--   As for D0..D4 (keyboard_input): a non-inverting collector follower (open
--   collector) with a WEAK on-chip pull-up. It can only pull the pin low;
--   otherwise it lets go and the weak pull-up holds it high, so the shared
--   data bus (DRAM data, CPU port writes) is never fought. Modelled as
--   '0' / 'H', VHDL's weak '1'.
--
-- ── What `ear` is ────────────────────────────────────────────────────
--   The EAR input already turned into a logic level by the pin's input
--   circuitry. On the real machine the EAR socket shares the ULA's pin with
--   the MIC and speaker outputs (port bits 3 and 4), so with no tape playing
--   the level read here depends on what was last written to those bits, and
--   issue 2 and issue 3 boards differ in exactly how. That analogue pin
--   sharing is outside this block: it only passes on the level it is given.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   ear        tape input level ('1' high, '0' low)
--   port_rd_n  ULA port read, active low (an even-address I/O read; the
--              gate that makes it is not built yet)
--   d6         data bus bit 6: '0' for EAR low during a read, otherwise 'H'
--              (open collector released, weak on-chip pull-up)
--
-- Verified by cassette_input_tb.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity cassette_input is
    port (
        port_rd_n : in    std_logic; -- ULA port read, active low
        ear       : in    std_logic; -- tape input level
        d6        : out   std_logic  -- data bus bit 6
    );
end entity cassette_input;

architecture structural of cassette_input is

    signal s_d6_n : std_logic;

begin

    -- '1' only while the port is read AND EAR is low
    s_d6_n <= not(port_rd_n or ear);

    -- onto the data bus through the D6 pad (collector follower + weak
    -- pull-up): pull the pin LOW for EAR low, otherwise release it ('H')
    d6 <= '0' when s_d6_n = '1' else
          'H';

end architecture structural;
