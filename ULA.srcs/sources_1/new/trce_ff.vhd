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
-- All ports must be driven explicitly. Use `enable => '1'` at the
-- instantiation site for stages that should always toggle.
--
-- NOTE: `carry` is the stage carry-out, combinational: carry = enable AND q
-- (built as NOR(not enable, qbar), gate-faithful). It feeds the `enable` of the
-- next counter stage. Consumed by bit3_counter(T_Structure) to chain
-- C6 → C7 → C8. (Formerly aliased to qbar; redefined for enable-chaining.)
--
-- Characteristic table:
--
--   reset  enable  clk       |  q(next)   qbar(next)
--   -----  ------  --------  |  -------   ----------
--     1    X       ↓       |  0         1
--     0    1       ↓       |  not q     not qbar    (toggle)
--     0    0       ↓       |  q         qbar        (hold)
--     X    X       no edge   |  q         qbar        (hold)
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity trce_ff is
    port (
        clk    : in    std_logic;
        reset  : in    std_logic;
        enable : in    std_logic;
        q      : out   std_logic;
        qbar   : out   std_logic;
        carry  : out   std_logic
    );
end entity trce_ff;

architecture behavioral of trce_ff is

    signal d_in     : std_logic;
    signal q_int    : std_logic;
    signal qbar_int : std_logic;

begin

    -- Priority: reset > enable.
    d_in <= '0' when reset = '1' else
            qbar_int when enable = '1' else
            q_int;

    ff : entity work.d_ff_nor(Behavioral)
        port map (
            clk  => clk,
            d    => d_in,
            q    => q_int,
            qbar => qbar_int
        );

    q     <= q_int;
    qbar  <= qbar_int;
    carry <= not ((not enable) or qbar_int); -- = enable and q : stage carry-out

end architecture behavioral;
