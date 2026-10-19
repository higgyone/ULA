----------------------------------------------------------------------
-- trc_ff — Toggle FF with Reset and Carry (structural)
--
-- T-flip-flop built from d_ff_nor by tying d to q_n. Falling-edge
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
-- (Formerly aliased to q_n; redefined to a real carry-out.)
--
-- Characteristic table (q/q_n are edge-driven; carry = q is combinational):
--
--   reset  clk       |  q(next)   q_n(next)
--   -----  --------  |  -------   ----------
--     1    ↓       |  0         1
--     0    ↓       |  not q     not q_n
--     X    no edge   |  q         q_n
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity trc_ff is
    port (
        clk   : in    std_logic;
        reset : in    std_logic;
        q     : out   std_logic;
        q_n   : out   std_logic;
        carry : out   std_logic
    );
end entity trc_ff;

architecture behavioral of trc_ff is

    signal d_in     : std_logic;
    signal q_int    : std_logic;
    signal qbar_int : std_logic;

begin

    -- T with sync reset: d = '0' on reset; otherwise d = q_n (toggle).
    d_in <= '0' when reset = '1' else
            qbar_int;

    ff : entity work.d_ff_nor(Behavioral)
        port map (
            clk => clk,
            d   => d_in,
            q   => q_int,
            q_n => qbar_int
        );

    q     <= q_int;
    q_n   <= qbar_int;
    carry <= q_int; -- enable hardwired '1', so carry-out = q

end architecture behavioral;
