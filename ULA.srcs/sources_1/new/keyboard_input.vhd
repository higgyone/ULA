----------------------------------------------------------------------------------
-- keyboard_input — keyboard half-row onto data bits D0..D4 (ULA port read)
--
-- When the Z80 reads the ULA's I/O port (IN from any even address, e.g.
-- 0xFE), the five keyboard lines k0..k4 are put on D0..D4.
--
-- ── The keyboard ─────────────────────────────────────────────────────
--   The Spectrum's 40 keys form an 8 x 5 matrix. The eight half-row lines
--   are driven by the Z80's upper address bits A8..A15 (a '0' selects that
--   half-row); the five column lines come back to the ULA as k0..k4, pulled
--   up on the PCB. A pressed key in a selected half-row pulls its column LOW.
--   So k0..k4 are ACTIVE LOW: '0' = a key is down.
--
--     A8  CAPS SHIFT Z X C V       A12 0 9 8 7 6
--     A9  A S D F G                A13 P O I U Y
--     A10 Q W E R T                A14 ENTER L K J H
--     A11 1 2 3 4 5                A15 SPACE SYM SHIFT M N B
--   (first key listed = k0 / D0, last = k4 / D4)
--
--   Selecting several half-rows at once (several A8..A15 bits '0') ANDs them:
--   any key down in any selected half-row reads '0'. The matrix is on the PCB,
--   not in the ULA.
--
-- ── The gates ────────────────────────────────────────────────────────
--   s_dX_n = NOR(port_rd_n, kX)    '1' only while reading the port AND key X
--                                  is down
--   dX     = NOT s_dX_n            (gate array), then the D-pin output stage
--
--     port_rd_n  kX | s_dX_n | dX pin
--     --------------+--------+----------------------------------------
--         0      0  |   1    |  '0'  pulled low: key down
--         0      1  |   0    |  'H'  released, weak pull-up: key up
--         1      X  |   0    |  'H'  released, weak pull-up: not reading
--
-- ── The D-pin pads (book) ────────────────────────────────────────────
--   Like pin 32 (phicpu_n in contention_handler_3), D0..D7 are driven by
--   peripheral transistors in the chip's pad circuitry, not by the gate array
--   directly:
--     OUTPUT  non-inverting COLLECTOR FOLLOWER (open collector) with a WEAK
--             PULL-UP inside the ULA. It can only pull a pin LOW; for a '1'
--             it lets go and the weak pull-up holds the pin high.
--     INPUT   coupled to the same pin, an EMITTER FOLLOWER buffer converts
--             the external TTL levels to the ULA's internal CML levels. This
--             is how the ULA reads the bus: DRAM data in video fetches, and
--             the CPU's writes to the ULA port. (Not part of this block.)
--     D5 is INPUT ONLY: it has no output transistor, so nothing in the ULA
--             can drive it.
--
--   That matters because D0..D7 are a SHARED bus. A weak pull-up is easily
--   overridden, so whenever this block is not pulling a pin low, any other
--   device (the DRAM, the CPU) can drive it either way without a clash. A
--   key down is the only thing that pulls a pin low, and only during a port
--   read; a key up simply reads '1' through the pull-up, active low as the
--   Spectrum ROM expects.
--
--   Modelled as '0' / 'H': 'H' is VHDL's weak '1', which resolves to the other
--   driver's value whenever another driver is present.
--
-- ── Not covered here ─────────────────────────────────────────────────
--   D5..D7 of the port read: bit 6 is the EAR input, D5 is input only, and
--   bit 7 is not driven by this block.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   k0..k4     keyboard column lines, active low ('0' = key down)
--   port_rd_n  ULA port read, active low (an even-address I/O read; the
--              gate that makes it is not built yet)
--   d0..d4     data bus bits 0..4: '0' for a key down during a read,
--              otherwise 'H' (open collector released, weak on-chip pull-up)
--
-- Verified by keyboard_input_tb.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity keyboard_input is
    port (
        k0        : in    std_logic; -- keyboard column 0, active low
        k1        : in    std_logic; -- keyboard column 1, active low
        k2        : in    std_logic; -- keyboard column 2, active low
        k3        : in    std_logic; -- keyboard column 3, active low
        k4        : in    std_logic; -- keyboard column 4, active low
        port_rd_n : in    std_logic; -- ULA port read, active low
        d0        : out   std_logic; -- data bus bit 0
        d1        : out   std_logic; -- data bus bit 1
        d2        : out   std_logic; -- data bus bit 2
        d3        : out   std_logic; -- data bus bit 3
        d4        : out   std_logic  -- data bus bit 4
    );
end entity keyboard_input;

architecture structural of keyboard_input is

    signal s_d0_n : std_logic;
    signal s_d1_n : std_logic;
    signal s_d2_n : std_logic;
    signal s_d3_n : std_logic;
    signal s_d4_n : std_logic;

begin

    -- '1' only while the port is read AND that key line is low (key down)
    s_d0_n <= not(port_rd_n or k0);
    s_d1_n <= not(port_rd_n or k1);
    s_d2_n <= not(port_rd_n or k2);
    s_d3_n <= not(port_rd_n or k3);
    s_d4_n <= not(port_rd_n or k4);

    -- onto the data bus through the D-pin pads (collector follower + weak
    -- pull-up): pull the pin LOW for a key down, otherwise release it to the
    -- weak pull-up ('H')
    d0 <= '0' when s_d0_n = '1' else
          'H';
    d1 <= '0' when s_d1_n = '1' else
          'H';
    d2 <= '0' when s_d2_n = '1' else
          'H';
    d3 <= '0' when s_d3_n = '1' else
          'H';
    d4 <= '0' when s_d4_n = '1' else
          'H';

end architecture structural;
