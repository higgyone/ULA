----------------------------------------------------------------------
-- data_latch_1_bit — one bit of the ULA video data latch
--
-- Gate-accurate single bit of the 8-bit latch that captures a byte
-- returned from display RAM before it is fanned out to the pixel shift
-- register (bitmap) and the attribute path. Built from four NOR gates:
-- a feed-forward input stage gated by the enable, plus a two-NOR
-- cross-coupled SR latch. Topology mirrors the discrete NOR-gate
-- drawing in Chris Smith's "The ZX Spectrum ULA".
--
-- This is a transparent D LATCH, not an edge-triggered flip-flop: it
-- has a single gated SR latch (half the network of d_ff_nor's
-- master-slave). While the enable holds it transparent, q tracks d;
-- when the enable deasserts, q freezes the last sampled value.
--
--   Enable polarity: e is ACTIVE-LOW.
--     e='0' -> transparent (q follows d)
--     e='1' -> hold / latched (q frozen, d ignored)
--   i.e. the RISING edge of e captures the data bit. In the ULA the port
--   is driven by e = NOT datalatch, so the upstream (active-high)
--   'datalatch' strobe is transparent-high / hold-low as expected; the
--   active-low sense here is that inverter absorbed into the interface.
--
-- Topology:
--
--   input stage (feed-forward, gated by e):
--      b_o = NOR(e, d)        -- = not d when e='0'; forced 0 when e='1'
--      a_o = NOR(e, b_o)      -- =     d when e='0'; forced 0 when e='1'
--
--   SR latch (2 cross-coupled NORs):
--      c_o = NOR(a_o, d_o)
--      d_o = NOR(b_o, c_o)
--
--      q     = d_o
--      q_bar = c_o
--
--   With e='1' both a_o and b_o are 0, so the SR latch sees no set/reset
--   and holds. With e='0', a_o=d and b_o=not d drive it to q=d.
--
-- Characteristic table:
--
--   e    d   |  q(next)   q_bar(next)
--   ---  --  |  -------   -----------
--    0   0   |    0           1       transparent: q = d
--    0   1   |    1           0
--    1   X   |    q         not q     hold (latched)
--
-- Output use: q_bar is the active-low tap that feeds the pixel shift
-- register's data_n load input — the two active-low conventions cancel,
-- so the shift register loads the TRUE pixel value. q (true polarity)
-- heads toward the attribute / colour path. Both are brought out.
--
-- Gate delay `TG` and init values (simulation only). The c_o/d_o pair is
-- cross-coupled, so like d_ff_nor / single_bit_shift_register every NOR
-- carries an `after TG` inertial delay; without it the loop re-evaluates
-- within one simulation instant and xsim/GHDL delta-spin to their
-- iteration guard (a t=0 hang). The four internal signals are seeded to
-- the "transparent, holding 0" resting state (e='0', d='0', q='0') so the
-- network starts defined instead of 'U'. Both are ignored by synthesis —
-- real silicon power-up state comes from place-and-route.
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity data_latch_1_bit is
    port (
        e     : in    std_logic; -- active-low enable (= not datalatch): '0' transparent, '1' hold
        d     : in    std_logic; -- data bit in (from display RAM byte)
        q     : out   std_logic; -- latched data (true)
        q_bar : out   std_logic  -- latched data (active-low) -> shift-reg data_n
    );
end entity data_latch_1_bit;

architecture structural of data_latch_1_bit is

    -- Seeded to the "transparent, holding 0" state (e='0', d='0', q='0'):
    --   b_o = NOR(e, d)    = NOR(0,0) = 1
    --   a_o = NOR(e, b_o)  = NOR(0,1) = 0
    --   c_o = NOR(a_o,d_o) = NOR(0,0) = 1   => q_bar = 1
    --   d_o = NOR(b_o,c_o) = NOR(1,1) = 0   => q     = 0
    signal a_o : std_logic := '0';
    signal b_o : std_logic := '1';
    signal c_o : std_logic := '1';
    signal d_o : std_logic := '0';

    constant tg : time := 1 ns;   -- modelled NOR propagation delay (sim only)

begin

    -- input stage (gated by active-low enable e)
    b_o <= not (e or d)       after tg;
    a_o <= not (e or b_o)     after tg;

    -- cross-coupled SR latch
    c_o <= not (a_o or d_o)   after tg;
    d_o <= not (b_o or c_o)   after tg;

    q_bar <= c_o;
    q     <= d_o;

end architecture structural;
