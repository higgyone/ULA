----------------------------------------------------------------------
-- d_ff_nor — D flip-flop, negative-edge triggered (structural)
--
-- Master-slave D flip-flop built from six NOR gates. This is the
-- gate-accurate primitive used as the base for every other flip-flop
-- in the ULA library (clk_div_2, trc_ff, tce_ff, trce_ff). The
-- topology mirrors the discrete NOR-gate flip-flops drawn in Chris
-- Smith's "The ZX Spectrum ULA" schematic.
--
-- Topology:
--
--      a_o = NOR(d_o, b_o)               -.
--      b_o = NOR(a_o, clk)                | master latch
--      c_o = NOR(b_o, clk, d_o)           | (4 NORs, gated by clk)
--      d_o = NOR(d,   c_o)               -'
--
--      e_o = NOR(b_o, f_o)               -. slave SR latch
--      f_o = NOR(c_o, e_o)               -' (2 cross-coupled NORs)
--
--      q    = e_o
--      qbar = f_o
--
-- Behaviour by clk phase:
--   clk='1'  : b_o = c_o = 0, slave is in HOLD. Master is transparent
--              to d (a_o = d, d_o = not d).
--   clk='0'  : master is locked; whichever of b_o/c_o went high at
--              the falling edge resets the corresponding side of the
--              slave SR latch, setting q to the value of d sampled
--              just before the edge.
--
-- Characteristic table:
--
--   clk        d  |  q(next)   qbar(next)
--   --------   -- |  -------   ----------
--   no edge    X  |  q         not q       (hold)
--   ↓ (fall)   0  |  0         1
--   ↓ (fall)   1  |  1         0
--
-- No reset/preset inputs. Reset semantics for the wrapper FFs
-- (clk_div_2, trc_ff, trce_ff) are implemented synchronously by
-- gating the d input — not by extending this NOR network.
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity d_ff_nor is
    Port ( clk  : in  STD_LOGIC;
           d    : in  STD_LOGIC;
           q    : out STD_LOGIC;
           qbar : out STD_LOGIC);
end d_ff_nor;

architecture Behavioral of d_ff_nor is
    signal a_o : std_logic;
    signal b_o : std_logic;
    signal c_o : std_logic;
    signal d_o : std_logic;
    signal e_o : std_logic;
    signal f_o : std_logic;
begin
    a_o <= not (d_o or b_o);
    b_o <= not (a_o or clk);
    c_o <= not (b_o or clk or d_o);
    d_o <= not (d   or c_o);
    e_o <= not (b_o or f_o);
    f_o <= not (c_o or e_o);

    q    <= e_o;
    qbar <= f_o;
end Behavioral;
