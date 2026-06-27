----------------------------------------------------------------------
-- tce_ff — Toggle FF with Carry and Enable (structural)
--
-- T-flip-flop built from d_ff_nor with an enable mux on the d input:
--
--   d = qbar  when enable='1'   (toggle on next falling edge of clk)
--   d = q     when enable='0'   (hold)
--
-- Falling-edge triggered. No reset port — for that, use trce_ff.
--
-- NOTE: `carry` is the stage carry-out, combinational:
--   carry = enable AND q   (built as NOR(not enable, qbar), gate-faithful).
-- It feeds the `enable` of the next counter stage. Consumed by
-- bit3_counter(T_Structure) to chain C6 → C7 → C8. (Formerly aliased to
-- qbar; redefined to a real carry-out for enable-chaining.)
--
-- Characteristic table (q/qbar are edge-driven; carry is combinational):
--
--   enable  clk       |  q(next)   qbar(next)
--   ------  --------  |  -------   ----------
--     1     ↓       |  not q     not qbar     (toggle)
--     0     ↓       |  q         qbar         (hold)
--     X     no edge   |  q         qbar         (hold)
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tce_ff is
    Port ( clk    : in  STD_LOGIC;
           enable : in  STD_LOGIC;
           q      : out STD_LOGIC;
           qbar   : out STD_LOGIC;
           carry  : out STD_LOGIC);
end tce_ff;

architecture Behavioral of tce_ff is
    signal d_in     : std_logic;
    signal q_int    : std_logic;
    signal qbar_int : std_logic;
begin
    -- Enable mux: toggle when enabled, hold otherwise.
    d_in <= qbar_int when enable = '1' else q_int;

    ff : entity work.d_ff_nor(Behavioral)
        port map ( clk  => clk,
                   d    => d_in,
                   q    => q_int,
                   qbar => qbar_int );

    q     <= q_int;
    qbar  <= qbar_int;
    carry <= not ((not enable) or qbar_int);   -- = enable and q : stage carry-out
end Behavioral;
