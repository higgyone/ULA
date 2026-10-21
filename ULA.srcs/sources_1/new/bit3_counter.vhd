----------------------------------------------------------------------
-- bit3_counter — 3-bit synchronous counter, modulo-7
--
-- Counts 0..6 (7 states) on the falling edge of clk and wraps back
-- to 0 on the next edge. `overflow` is asserted while the count
-- equals "110" (= 6) — i.e. the cycle in which the counter is about
-- to wrap.
--
-- Used as the C6..C8 cells of master_horiz_counter. Together with
-- the six clk_div_2 cells (C0..C5), this gives the 9-bit horizontal
-- counter modulo 448 (= 64 × 7) at 7 MHz for 64 µs PAL lines.
--
-- Reset is synchronous: when reset='1', the count clears on the next
-- falling edge of clk.
--
-- Structural implementation: three d_ff_nor cells (one per bit) with
-- combinational next-state logic on each d input. The next-state per
-- bit follows the standard binary ripple-carry "+1 rule":
--
--   d(0) = not q(0)                       (LSB always flips)
--   d(1) = q(1) xor q(0)                  (flip when q(0)=1)
--   d(2) = q(2) xor (q(1) and q(0))       (flip when q(1) and q(0)=1)
--
-- Modulo-7 wrap is enforced by ANDing every d-bit with `not wrap`,
-- where `wrap = q(2) and q(1) and not q(0)` detects state "110".
-- Synchronous reset uses the same trick: AND every d-bit with
-- `not reset`. Both reset and wrap leave the clock path untouched —
-- they only change what gets sampled on the next falling edge.
--
-- A glitch into the unused state "111" is self-correcting: wrap is 0
-- there (it requires q(0)=0), the +1 rule gives "000", and the
-- counter rejoins the legal sequence on the next clock.
--
-- A behavioural reference architecture is preserved below as
-- `architecture Reference` — selectable at instantiation by name.
-- The testbench instantiates BOTH architectures in parallel as a
-- design-oracle pattern: same clk/reset into both, assert their
-- outputs match cycle-by-cycle. Any divergence is a bug in the
-- structural next-state logic or wrap detection.
--
-- State sequence:
--
--   output  : 000 → 001 → 010 → 011 → 100 → 101 → 110 → 000 → ...
--   overflow:  0     0     0     0     0     0     1     0
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity bit3_counter is
    port (
        clk      : in    std_logic;
        reset    : in    std_logic;
        output   : out   std_logic_vector(2 downto 0);
        overflow : out   std_logic
    );
end entity bit3_counter;

architecture structural of bit3_counter is

    signal s_q    : std_logic_vector(2 downto 0); -- current state
    signal s_d    : std_logic_vector(2 downto 0); -- next state into FFs
    signal s_wrap : std_logic;                    -- 1 when at "110"

begin

    -- detect we're at the wrap state
    s_wrap <= s_q(2) and s_q(1) and (not s_q(0)); -- "110"

    -- next-state combinational logic per bit (binary +1, forced to 0 at wrap, forced to 0 at reset)
    s_d(0) <= (not reset) and (not s_wrap) and (not s_q(0));
    s_d(1) <= (not reset) and (not s_wrap) and (s_q(1) xor s_q(0));
    s_d(2) <= (not reset) and (not s_wrap) and (s_q(2) xor (s_q(1) and s_q(0)));

    -- three d_ff_nor instances — one per bit
    ff0 : entity work.d_ff_nor
        port map (
            clk => clk,
            d   => s_d(0),
            q   => s_q(0),
            q_n => open
        );

    ff1 : entity work.d_ff_nor
        port map (
            clk => clk,
            d   => s_d(1),
            q   => s_q(1),
            q_n => open
        );

    ff2 : entity work.d_ff_nor
        port map (
            clk => clk,
            d   => s_d(2),
            q   => s_q(2),
            q_n => open
        );

    output   <= s_q;
    overflow <= s_wrap;

end architecture structural;

architecture t_structure of bit3_counter is

    signal s_carry_count_6 : std_logic;
    signal s_count_6_q_out : std_logic;
    signal s_carry_count_7 : std_logic;
    signal s_count_7_q_out : std_logic;
    signal s_count_7_q_n   : std_logic;
    signal s_count_8_q_out : std_logic;
    signal s_count_8_q_n   : std_logic;
    signal s_ff_rst        : std_logic;
    signal s_hcrst         : std_logic;

begin

    count_6 : entity work.trc_ff
        port map (
            clk   => clk,
            reset => s_ff_rst,
            q     => s_count_6_q_out,
            q_n   => open,
            carry => s_carry_count_6
        );

    count_7 : entity work.trce_ff
        port map (
            clk    => clk,
            reset  => s_ff_rst,
            enable => s_carry_count_6,
            q      => s_count_7_q_out,
            q_n    => s_count_7_q_n,
            carry  => s_carry_count_7
        );

    count_8 : entity work.trce_ff
        port map (
            clk    => clk,
            reset  => s_ff_rst,
            enable => s_carry_count_7,
            q      => s_count_8_q_out,
            q_n    => s_count_8_q_n,
            carry  => open
        );

    s_hcrst  <= not (s_count_7_q_n or s_count_8_q_n);
    s_ff_rst <= reset or s_hcrst;
    output   <= s_count_8_q_out & s_count_7_q_out & s_count_6_q_out;
    overflow <= s_hcrst;

end architecture t_structure;

----------------------------------------------------------------------
-- Reference architecture — behavioural arithmetic oracle.
--
-- Increments an `unsigned` counter on every falling edge of clk;
-- wraps from "110" to "000"; synchronous reset clears the count.
-- Not synthesised in the real design — used only by bit3_counter_tb
-- as the side-by-side reference for the Structural architecture.
----------------------------------------------------------------------

architecture reference of bit3_counter is

    signal s_output : unsigned(2 downto 0) := "000";

begin

    process (clk) is
    begin

        if falling_edge(clk) then
            if (reset = '1') then
                s_output <= "000";
            else
                s_output <= s_output + 1;
                if (s_output = "110") then
                    s_output <= "000";
                end if;
            end if;
        end if;

    end process;

    output   <= std_logic_vector(s_output);
    overflow <= '1' when s_output = "110" else
                '0';

end architecture reference;
