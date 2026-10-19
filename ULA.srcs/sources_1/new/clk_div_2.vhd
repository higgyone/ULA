----------------------------------------------------------------------
-- clk_div_2 — divide-by-2 toggle flip-flop (structural)
--
-- Divides clk_in by 2 by wiring a d_ff_nor as a T-flip-flop:
-- d = q_n, so q toggles on every falling edge of clk_in.
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
--   clk_out_n = q_n  (inverse)
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

    signal s_d   : std_logic;
    signal s_q   : std_logic;
    signal s_q_n : std_logic;

begin

    -- T-FF via D-FF: d = q_n (toggle) unless reset clears it.
    s_d <= '0' when reset = '1' else
           s_q_n;

    ff : entity work.d_ff_nor(Behavioral)
        port map (
            clk => clk_in,
            d   => s_d,
            q   => s_q,
            q_n => s_q_n
        );

    clk_out   <= s_q;
    clk_out_n <= s_q_n;

end architecture behavioral;
