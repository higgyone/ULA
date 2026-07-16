----------------------------------------------------------------------
-- single_bit_shift_register — one cell of the pixel shift register
--
-- Gate-accurate single bit of the ULA video shift register, built from
-- nine NOR gates (plus one inverter). It is a negative-edge D flip-flop
-- with a 2:1 input mux on the front, so each cell can either LOAD a
-- parallel data bit or SHIFT in the bit from the neighbouring cell.
-- Topology mirrors the discrete NOR-gate schematic in Chris Smith's
-- "The ZX Spectrum ULA". Both data inputs arrive inverted (active-low),
-- matching the source drawing.
--
-- Topology:
--
--   input mux (set selects the source):
--      e_out = NOT(set)                     -- inverter
--      d_out = NOR(e_out, data_n)           -- parallel-load path (set='1')
--      f_out = NOR(set,   data_1_n)         -- shift-in path      (set='0')
--
--   master latch (gated by clk, 4 NORs):
--      c_out = NOR(clk, b_out)
--      b_out = NOR(clk, a_out)
--      a_out = NOR(b_out, i_out)
--      i_out = NOR(c_out, d_out, f_out)     -- folds mux output into master
--
--   slave SR latch (2 cross-coupled NORs):
--      h_out = NOR(c_out, g_out)
--      g_out = NOR(b_out, h_out)
--
--      q     = g_out
--      q_bar = h_out
--
-- Mux / load-vs-shift semantics:
--   set='1' : e_out=0 => d_out = data (from data_n), f_out = 0.
--             Master input = data      -> LOADS the parallel bit.
--   set='0' : e_out=1 => d_out = 0,     f_out = data-1 (from data_1_n).
--             Master input = data-1    -> SHIFTS in the neighbour bit.
--
-- Behaviour by clk phase:
--   clk='1' : b_out = c_out = 0. Master is transparent (a_out follows the
--             mux output); slave is in HOLD.
--   clk='0' : master is locked on the value sampled at the falling edge;
--             the slave becomes transparent, so q takes that value.
--   => q updates on the falling edge of clk. In a chain sharing one clk,
--      every cell samples its neighbour's stable held output while clk is
--      high, then all slaves update together on the edge — no shift race.
--   q and q_bar are complementary in both phases.
--
-- Gate delay `TG` (simulation only). Each NOR assignment carries an
-- `after TG` inertial delay. Without it the cross-coupled pairs
-- (a_out<->b_out, g_out<->h_out) re-evaluate within the same simulation
-- instant, spinning delta cycles at a fixed `t` until xsim hits its
-- iteration guard (a t=0 hang). Real gates have propagation delay, so the
-- loop advances through time and settles; `after TG` models exactly that.
-- Same treatment as d_ff_nor. TG is kept small (1 ns): the worst-case
-- master path is ~4 gates (data -> e_out -> d_out -> i_out -> a_out) ≈
-- 4·TG, which must settle inside the testbench setup margin.
--
-- Initial values seed a valid "holding 0" resting state (clk='0', set='0',
-- q='0') so the network has a consistent starting point and avoids the
-- U-propagation quirk where cross-coupled NORs with a still-'U' input
-- never trigger their partner's re-evaluation. `after` and the init
-- values are ignored by synthesis — real silicon power-up state comes from
-- place-and-route.
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

-- Operating modes (in plain words):
--   The cell remembers one bit and, on each falling edge of clk, replaces it
--   with a new bit taken from one of two sources. `set` picks the source:
--
--     set = '1'  LOAD mode  -- take the next bit from data_n (parallel load,
--                              jamming a fresh bit in from outside).
--     set = '0'  SHIFT mode -- take the next bit from data_1_n (the bit handed
--                              over from the neighbouring cell in the chain).
--
--   Both data inputs are ACTIVE-LOW: the wire carries the inverse of the bit,
--   so drive '0' to mean a 1 and '1' to mean a 0 (data = not data_n,
--   data-1 = not data_1_n). LOAD wins over SHIFT if set = '1'.
--
--   clk is only the timing: nothing changes until clk falls 1->0. While clk is
--   high the cell samples the chosen input; on the falling edge it stores that
--   bit and then holds it steady on q (and its inverse on q_bar) until the next
--   falling edge.

entity single_bit_shift_register is
    port (
        clk      : in    std_logic;
        data_n   : in    std_logic; -- active-low parallel-load bit (LOAD, set='1')
        data_1_n : in    std_logic; -- active-low shift-in bit from neighbour (SHIFT, set='0')
        set      : in    std_logic; -- '1' = LOAD from data_n, '0' = SHIFT from data_1_n
        q        : out   std_logic;
        q_bar    : out   std_logic
    );
end entity single_bit_shift_register;

architecture structure of single_bit_shift_register is

    -- Seeded to the "holding 0" state (clk='0', set='0', q='0'):
    --   a_out=0 b_out=1 c_out=0  master holding 0
    --   g_out=0 h_out=1          slave  holding 0  => q=0, q_bar=1
    --   e_out=1 d_out=0 f_out=0 i_out=1  mux/fold nets consistent
    signal a_out : std_logic := '0';
    signal b_out : std_logic := '1';
    signal c_out : std_logic := '0';
    signal d_out : std_logic := '0';
    signal e_out : std_logic := '1';
    signal f_out : std_logic := '0';
    signal g_out : std_logic := '0';
    signal h_out : std_logic := '1';
    signal i_out : std_logic := '1';

    constant tg : time := 1 ns;   -- modelled NOR propagation delay (sim only)

begin

    -- input mux: set selects parallel data (data_n) vs shift-in (data_1_n)
    f_out <= not(set or data_1_n)         after tg;
    e_out <= not(set)                     after tg;
    d_out <= not(e_out or data_n)         after tg;

    -- master latch (gated by clk)
    c_out <= not(clk or b_out)            after tg;
    b_out <= not(clk or a_out)            after tg;
    a_out <= not(b_out or i_out)          after tg;
    i_out <= not(c_out or d_out or f_out) after tg;

    -- slave SR latch
    h_out <= not(c_out or g_out)          after tg;
    g_out <= not(b_out or h_out)          after tg;

    q     <= g_out;
    q_bar <= h_out;

end architecture structure;
