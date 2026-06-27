----------------------------------------------------------------------
-- trc_ff — Toggle FF with Reset and Carry (structural)
--
-- T-flip-flop built from d_ff_nor by tying d to qbar. Falling-edge
-- triggered. Reset is SYNCHRONOUS — d is forced to '0' while reset is
-- asserted, so q clears on the next falling edge of clk.
--
-- Originally drawn in Chris Smith's schematic as part of the
-- horizontal/vertical counter chains, where chaining between stages
-- is done via NOR-gated clocks rather than the `carry` pin.
--
-- NOTE: `carry` is the stage carry-out. trc_ff has no enable (it always
-- toggles), so carry = q. It feeds the `enable` of the next counter stage.
-- Consumed by bit3_counter(T_Structure) as C6's carry into C7's enable.
-- (Formerly aliased to qbar; redefined to a real carry-out.)
--
-- Characteristic table (q/qbar are edge-driven; carry = q is combinational):
--
--   reset  clk       |  q(next)   qbar(next)
--   -----  --------  |  -------   ----------
--     1    ↓       |  0         1
--     0    ↓       |  not q     not qbar
--     X    no edge   |  q         qbar
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity trc_ff is
    Port ( clk   : in  STD_LOGIC;
           reset : in  STD_LOGIC;
           carry : out STD_LOGIC;
           q     : out STD_LOGIC;
           qbar  : out STD_LOGIC);
end trc_ff;

architecture Behavioral of trc_ff is
    signal d_in     : std_logic;
    signal q_int    : std_logic;
    signal qbar_int : std_logic;
begin
    -- T with sync reset: d = '0' on reset; otherwise d = qbar (toggle).
    d_in <= '0' when reset = '1' else qbar_int;

    ff : entity work.d_ff_nor(Behavioral)
        port map ( clk  => clk,
                   d    => d_in,
                   q    => q_int,
                   qbar => qbar_int );

    q     <= q_int;
    qbar  <= qbar_int;
    carry <= q_int;   -- enable hardwired '1', so carry-out = q
end Behavioral;
