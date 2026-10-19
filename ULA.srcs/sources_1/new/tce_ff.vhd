----------------------------------------------------------------------
-- tce_ff — Toggle FF with Carry and Enable (structural)
--
-- T-flip-flop built from d_ff_nor with an enable mux on the d input:
--
--   d = q_n  when enable='1'   (toggle on next falling edge of clk)
--   d = q     when enable='0'   (hold)
--
-- Falling-edge triggered. No reset port — for that, use trce_ff.
--
-- NOTE: `carry` is the stage carry-out, combinational:
--   carry = enable AND q   (built as NOR(not enable, q_n), gate-faithful).
-- It feeds the `enable` of the next counter stage. Consumed by
-- bit3_counter(T_Structure) to chain C6 → C7 → C8. (Formerly aliased to
-- q_n; redefined to a real carry-out for enable-chaining.)
--
-- Characteristic table (q/q_n are edge-driven; carry is combinational):
--
--   enable  clk       |  q(next)   q_n(next)
--   ------  --------  |  -------   ----------
--     1     ↓       |  not q     not q_n     (toggle)
--     0     ↓       |  q         q_n         (hold)
--     X     no edge   |  q         q_n         (hold)
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity tce_ff is
    port (
        clk    : in    std_logic;
        enable : in    std_logic;
        q      : out   std_logic;
        q_n    : out   std_logic;
        carry  : out   std_logic
    );
end entity tce_ff;

architecture behavioral of tce_ff is

    signal s_d   : std_logic;
    signal s_q   : std_logic;
    signal s_q_n : std_logic;

begin

    -- Enable mux: toggle when enabled, hold otherwise.
    s_d <= s_q_n when enable = '1' else
           s_q;

    ff : entity work.d_ff_nor(Behavioral)
        port map (
            clk => clk,
            d   => s_d,
            q   => s_q,
            q_n => s_q_n
        );

    q     <= s_q;
    q_n   <= s_q_n;
    carry <= not ((not enable) or s_q_n); -- = enable and q : stage carry-out

end architecture behavioral;
