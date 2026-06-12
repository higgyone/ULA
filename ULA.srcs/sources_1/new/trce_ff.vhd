----------------------------------------------------------------------
-- trce_ff — Toggle FF with Reset, Carry and Enable (structural)
--
-- T-flip-flop built from d_ff_nor with reset + enable feeding the d
-- input. Priority: reset > enable.
--
--   d = '0'   when reset='1'                  (sync clear)
--   d = qbar  when reset='0' and enable='1'   (toggle)
--   d = q     when reset='0' and enable='0'   (hold)
--
-- Falling-edge triggered. Reset is SYNCHRONOUS — q clears on the
-- next falling edge of clk while reset is asserted.
--
-- NOTE: `carry` is electrically identical to `qbar`. Retained for
-- schematic symmetry with the original ULA drawings; not consumed.
--
-- Characteristic table:
--
--   reset  enable  clk       |  q(next)   qbar(next)
--   -----  ------  --------  |  -------   ----------
--     1    X       ↓         |  0         1
--     0    1       ↓         |  not q     not qbar    (toggle)
--     0    0       ↓         |  q         qbar        (hold)
--     X    X       no edge   |  q         qbar        (hold)
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity trce_ff is
    Port ( enable : in  STD_LOGIC := '1';
           clk    : in  STD_LOGIC;
           reset  : in  STD_LOGIC;
           carry  : out STD_LOGIC;
           q      : out STD_LOGIC;
           qbar   : out STD_LOGIC);
end trce_ff;

architecture Behavioral of trce_ff is
    signal d_in     : std_logic;
    signal q_int    : std_logic;
    signal qbar_int : std_logic;
begin
    -- Priority: reset > enable.
    d_in <= '0'      when reset  = '1'
       else qbar_int when enable = '1'
       else q_int;

    ff : entity work.d_ff_nor(Behavioral)
        port map ( clk  => clk,
                   d    => d_in,
                   q    => q_int,
                   qbar => qbar_int );

    q     <= q_int;
    qbar  <= qbar_int;
    carry <= qbar_int;  -- alias of qbar (documented in header)
end Behavioral;
