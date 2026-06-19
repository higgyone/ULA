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
--   clk          d  |  q(next)   qbar(next)
--   --------     -- |  -------   ----------
--   no edge      X  |  q         not q  (hold)
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
    -- All six internal NOR-network signals are initialised to the
    -- "Case A" stable state:  d=0 captured, clk='0' phase, q='0'.
    --
    -- Check: a_o = NOR(d_o, b_o) = NOR(1, 1) = 0 ✓
    --        b_o = NOR(a_o, clk) = NOR(0, 0) = 1 ✓
    --        c_o = NOR(b_o, clk, d_o) = NOR(1, 0, 1) = 0 ✓
    --        d_o = NOR(d, c_o) = NOR(0, 0) = 1 ✓     (d=0 from reset)
    --        e_o = NOR(b_o, f_o) = NOR(1, 1) = 0 ✓ => q=0
    --        f_o = NOR(c_o, e_o) = NOR(0, 0) = 1 ✓ => qbar=1
    --
    -- Synthesis ignores these — real silicon power-up state is whatever
    -- the layout produces. The init values exist solely to give xsim a
    -- consistent starting point and avoid a known U-propagation quirk
    -- where cross-coupled NORs with one input still 'U' would never
    -- trigger their partner's re-evaluation.
    signal a_o : std_logic := '0';
    signal b_o : std_logic := '1';
    signal c_o : std_logic := '0';
    signal d_o : std_logic := '1';
    signal e_o : std_logic := '0';
    signal f_o : std_logic := '1';
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
