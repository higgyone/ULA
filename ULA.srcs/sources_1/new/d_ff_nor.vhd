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
--      s_a_out = NOR(s_d_out, s_b_out)               -.
--      s_b_out = NOR(s_a_out, clk)                | master latch
--      s_c_out = NOR(s_b_out, clk, s_d_out)           | (4 NORs, gated by clk)
--      s_d_out = NOR(d,   s_c_out)               -'
--
--      s_e_out = NOR(s_b_out, s_f_out)               -. slave SR latch
--      s_f_out = NOR(s_c_out, s_e_out)               -' (2 cross-coupled NORs)
--
--      q    = s_e_out
--      q_n = s_f_out
--
-- Behaviour by clk phase:
--   clk='1'  : s_b_out = s_c_out = 0, slave is in HOLD. Master is transparent
--              to d (s_a_out = d, s_d_out = not d).
--   clk='0'  : master is locked; whichever of s_b_out/s_c_out went high at
--              the falling edge resets the corresponding side of the
--              slave SR latch, setting q to the value of d sampled
--              just before the edge.
--
-- Characteristic table:
--
--   clk          d  |  q(next)   q_n(next)
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
-- pairs (s_a_out↔s_b_out, s_c_out↔s_d_out, s_e_out↔s_f_out) re-evaluate within the same
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
        clk : in    std_logic;
        d   : in    std_logic;
        q   : out   std_logic;
        q_n : out   std_logic
    );
end entity d_ff_nor;

architecture behavioral of d_ff_nor is

    -- All six internal NOR-network signals are initialised to the
    -- "Case A" stable state:  d=0 captured, clk='0' phase, q='0'.
    --
    -- Check: s_a_out = NOR(s_d_out, s_b_out) = NOR(1, 1) = 0 ✓
    --        s_b_out = NOR(s_a_out, clk) = NOR(0, 0) = 1 ✓
    --        s_c_out = NOR(s_b_out, clk, s_d_out) = NOR(1, 0, 1) = 0 ✓
    --        s_d_out = NOR(d, s_c_out) = NOR(0, 0) = 1 ✓     (d=0 from reset)
    --        s_e_out = NOR(s_b_out, s_f_out) = NOR(1, 1) = 0 ✓ => q=0
    --        s_f_out = NOR(s_c_out, s_e_out) = NOR(0, 0) = 1 ✓ => q_n=1
    --
    -- Synthesis ignores these — real silicon power-up state is whatever
    -- the layout produces. The init values exist solely to give xsim a
    -- consistent starting point and avoid a known U-propagation quirk
    -- where cross-coupled NORs with one input still 'U' would never
    -- trigger their partner's re-evaluation.
    signal s_a_out : std_logic := '0';
    signal s_b_out : std_logic := '1';
    signal s_c_out : std_logic := '0';
    signal s_d_out : std_logic := '1';
    signal s_e_out : std_logic := '0';
    signal s_f_out : std_logic := '1';

    constant tg : time := 1 ns;   -- modelled NOR propagation delay (sim only)

begin

    s_a_out <= not (s_d_out or s_b_out)        after tg;
    s_b_out <= not (s_a_out or clk)        after tg;
    s_c_out <= not (s_b_out or clk or s_d_out) after tg;
    s_d_out <= not (d   or s_c_out)        after tg;
    s_e_out <= not (s_b_out or s_f_out)        after tg;
    s_f_out <= not (s_c_out or s_e_out)        after tg;

    q   <= s_e_out;
    q_n <= s_f_out;

end architecture behavioral;
