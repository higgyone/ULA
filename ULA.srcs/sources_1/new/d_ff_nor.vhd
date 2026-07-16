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
--
-- Gate delay `TG` (simulation only). Each of the six NOR assignments
-- carries an `after TG` inertial delay. Without it the cross-coupled
-- pairs (a_o↔b_o, c_o↔d_o, e_o↔f_o) re-evaluate within the same
-- simulation instant: a change to one re-triggers its partner in the
-- next delta cycle, which re-triggers the first, and so on. An
-- unsettled latch then spins delta cycles at a fixed `t` until xsim
-- hits its 10000-iteration guard (observed as a t=0 hang in
-- bit3_counter_tb). Real gates have propagation delay, so the loop
-- advances through time and settles; `after TG` models exactly that.
--
-- TG is kept small (1 ns) on purpose: the worst-case master-latch path
-- is ~4 gates ≈ 4·TG, which must settle inside the testbench's setup
-- margin (T/2 = 5 ns before the falling-edge sample on the 10 ns sim
-- clock). A larger TG would miss that sample. `after` is ignored by
-- synthesis — like the init values above, this affects simulation only;
-- real silicon timing comes from place-and-route.
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity d_ff_nor is
    port (
        clk  : in    std_logic;
        d    : in    std_logic;
        q    : out   std_logic;
        qbar : out   std_logic
    );
end entity d_ff_nor;

architecture behavioral of d_ff_nor is

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

    constant tg : time := 1 ns;   -- modelled NOR propagation delay (sim only)

begin

    a_o <= not (d_o or b_o)        after tg;
    b_o <= not (a_o or clk)        after tg;
    c_o <= not (b_o or clk or d_o) after tg;
    d_o <= not (d   or c_o)        after tg;
    e_o <= not (b_o or f_o)        after tg;
    f_o <= not (c_o or e_o)        after tg;

    q    <= e_o;
    qbar <= f_o;

end architecture behavioral;
