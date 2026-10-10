----------------------------------------------------------------------
-- clk_div_2 — divide-by-2 toggle flip-flop (structural)
--
-- Divides clk_in by 2 by wiring a d_ff_nor as a T-flip-flop:
-- d = qbar, so q toggles on every falling edge of clk_in.
--
-- Used as the C0..C5 cells in master_horiz_counter (the lower 6 bits
-- of the 9-bit horizontal counter), each chained by NOR-gated clocks
-- rather than by clk-out daisy-chaining.
--
-- Reset is SYNCHRONOUS: when reset='1', the d input is forced to '0'
-- so q clears on the next falling edge of clk_in. (The previous
-- behavioural model used an asynchronous reset; in practice the
-- master_horiz_counter holds reset for many clock cycles at power-on,
-- so the difference is not observable in this design.)
--
-- Characteristic table:
--
--   reset  clk_in    |  q(next)
--   -----  --------  |  -------
--     1    ↓       |  0
--     0    ↓       |  not q   (toggle)
--     X    no edge   |  q       (hold)
--
--   clk_out   = q     (divided clock)
--   clk_out_n = qbar  (inverse)
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity clk_div_2 is
    port (
        clk_in    : in    std_logic;
        reset     : in    std_logic;
        clk_out   : out   std_logic;
        clk_out_n : out   std_logic
    );
end entity clk_div_2;

architecture behavioral of clk_div_2 is

    signal d_in     : std_logic;
    signal q_int    : std_logic;
    signal qbar_int : std_logic;

begin

    -- T-FF via D-FF: d = qbar (toggle) unless reset clears it.
    d_in <= '0' when reset = '1' else
            qbar_int;

    ff : entity work.d_ff_nor(Behavioral)
        port map (
            clk  => clk_in,
            d    => d_in,
            q    => q_int,
            qbar => qbar_int
        );

    clk_out   <= q_int;
    clk_out_n <= qbar_int;

end architecture behavioral;
