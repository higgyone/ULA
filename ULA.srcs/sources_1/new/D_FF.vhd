----------------------------------------------------------------------
-- d_ff — D flip-flop, negative-edge triggered (behavioural)
--
-- Behavioural model of a falling-edge D flip-flop. Captures d on
-- every falling edge of clk; q drives the latched value, q_bar its
-- inverse.
--
-- For the gate-accurate ULA recreation the structural equivalent is
-- d_ff_nor, which is what clk_div_2 / trc_ff / tce_ff / trce_ff are
-- built on. d_ff is retained because its testbench (D_FF_tb) is the
-- self-toggling reference used to validate the falling-edge semantics
-- of the FF library.
--
-- Characteristic table:
--
--   clk          d  |  q(next)   q_bar(next)
--   --------     -- |  -------   -----------
--   no edge      X  |  q         not q  (hold)
--   ↓ (fall)   0  |  0         1
--   ↓ (fall)   1  |  1         0
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity d_ff is
    Port ( clk   : in  std_logic;
           d     : in  std_logic;
           q     : out std_logic;
           q_bar : out std_logic);
end d_ff;

architecture Behavioral of d_ff is
    signal d_sig : std_logic := '0';
begin
    process(clk)
    begin
        if falling_edge(clk) then
            d_sig <= d;
        end if;
    end process;

    q     <= d_sig;
    q_bar <= not d_sig;
end Behavioral;
