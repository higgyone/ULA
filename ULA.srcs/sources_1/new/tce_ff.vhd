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
-- NOTE: `carry` is electrically identical to `qbar`. Retained for
-- schematic symmetry with the original ULA drawings; not consumed.
--
-- Characteristic table:
--
--   enable  clk       |  q(next)   qbar(next)   carry(next)
--   ------  --------  |  -------   ----------   -----------
--     1     ↓       |  not q     not qbar     not qbar
--     0     ↓       |  q         qbar         carry        (hold)
--     X     no edge   |  q         qbar         carry        (hold)
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
    carry <= qbar_int;  -- alias of qbar (documented in header)
end Behavioral;
