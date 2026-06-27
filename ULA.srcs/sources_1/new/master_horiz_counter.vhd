----------------------------------------------------------------------
-- master_horiz_counter — 9-bit horizontal pixel counter
--
-- 448 counts per line at 7 MHz pixel clock = 64 us PAL.
-- Counts 0..447 (binary 000 000 000 .. 110 111 111), then wraps.
--
-- Structurally split to match the Chris Smith schematic (pg 90):
--   C0..C5 — six clk_div_2 cells (each = d_ff_nor wired as a T-FF)
--            with NOR-gated clocks derived from clk7 and the lower
--            bits. This is the ULA's "gated clock" style rather than
--            a pure ripple chain, and keeps the +1 timing tight.
--   C6..C8 — bit3_counter (modulo-7, three d_ff_nor cells) clocked
--            by clk_hc6 (= C5 with the always-zero tclk_a).
--
-- Outputs:
--   c0..c8  — counter taps, used by horiz_timing to decode
--             hsync/blank windows.
--   clk_hc6 — clock for the C6..C8 stage, exposed for external use
--             (e.g. driving Vert_Line_counter).
--   hc_rst  — single-cycle pulse on counter wrap (line-end trigger
--             for the vertical line counter).
--
-- NOR-gated clock derivation per cell (read: "C_n toggles when all
-- lower bits are 1 at the next clk7 edge"):
--
--   clk_c0 = NOT clk7                            ; C0 always toggles
--   clk_c1 = NOR(c0_n, clk7)         = c0 . !clk7; C1 toggles when c0=1
--   clk_c2 = NOR(c0_n, c1_n, clk7)   = c0.c1.!clk7
--   clk_c3 = NOR(c0_n..c2_n, clk7)   = c0.c1.c2.!clk7
--   clk_c4 = NOT c3_n                = c3        ; C4 ripples off C3
--   clk_c5 = NOR(c3_n, c4_n)         = c3 . c4   ; C5 falls when c3.c4 falls
--
-- (The mix of styles — gated for C0..C3, ripple for C4..C5 — mirrors
-- the original ULA layout; it is not a uniform ripple counter.)
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity master_horiz_counter is
port(
      clk7         : in     std_logic;          -- master clock
      reset        : in     std_logic;
      tclk_a       : in     std_logic := '0';   -- always assumed to be '0'
      c0           : out    std_logic;
      c1           : out    std_logic;
      c2           : out    std_logic;
      c3           : out    std_logic;
      c4           : out    std_logic;
      c5           : out    std_logic;
      c6           : out    std_logic;
      c7           : out    std_logic;
      c8           : out    std_logic;
      clk_hc6      : out    std_logic;            -- clock for 3 bit counter, same as c5
      hc_rst       : out    std_logic             -- horizontal counter reset
   );
end master_horiz_counter;

architecture Behavioral of master_horiz_counter is

    signal c0_n : std_logic;
    signal c1_n : std_logic;
    signal c2_n : std_logic;
    signal c3_n : std_logic;
    signal c4_n : std_logic;
    signal c5_n : std_logic;
    signal clk_c0 : std_logic;
    signal clk_c1 : std_logic;
    signal clk_c2 : std_logic;
    signal clk_c3 : std_logic;
    signal clk_c4 : std_logic;
    signal clk_c5 : std_logic;
    
    signal clk8_6 : std_logic_vector (2 downto 0);
    signal s_clkhc6 : std_logic;

begin
    --------------------------------------------------------------
    -- NOR-gated clock chain for C0..C5 (see header for derivation)
    --------------------------------------------------------------
    clk_c0 <= not clk7;
    clk_c1 <= c0_n nor clk7;
    clk_c2 <= not(c0_n or c1_n or clk7);
    clk_c3 <= not(c2_n or c1_n or c0_n or clk7);
    clk_c4 <= not c3_n;
    clk_c5 <= c4_n nor c3_n;

    -- clk_hc6 drives the C6..C8 bit3_counter. tclk_a is always '0'
    -- in this design, so the NOR reduces to NOT c5_n = c5.
    s_clkhc6 <= tclk_a nor c5_n;
    clk_hc6  <= s_clkhc6;

    -- C6..C8 are the three bits of the modulo-7 bit3_counter.
    c6 <= clk8_6(0);
    c7 <= clk8_6(1);
    c8 <= clk8_6(2);

--******************************************************************
--  Counter cell instances (C0..C5 = clk_div_2; C6..C8 = bit3_counter)
--******************************************************************
count_0: entity work.clk_div_2
  port map(
     clk_in  => clk_c0,
     reset => reset,
     clk_out => c0,
     clk_out_n => c0_n
     );
     
count_1: entity work.clk_div_2
  port map(
     clk_in => clk_c1,
     reset => reset,
     clk_out => c1,
     clk_out_n => c1_n
     );

count_2: entity work.clk_div_2
  port map(
     clk_in => clk_c2,
     reset => reset,
     clk_out => c2,
     clk_out_n => c2_n
     );

count_3: entity work.clk_div_2
  port map(
     clk_in => clk_c3,
     reset => reset,
     clk_out => c3,
     clk_out_n => c3_n
     );
     
count_4: entity work.clk_div_2
  port map(
     clk_in => clk_c4,
     reset => reset,
     clk_out => c4,
     clk_out_n => c4_n
     );

count_5: entity work.clk_div_2
  port map(
     clk_in => clk_c5,
     reset => reset,
     clk_out => c5,
     clk_out_n => c5_n
     );     
     
-- C6..C8 use the schematic-faithful T_Structure architecture (chained
-- trc_ff/trce_ff with a rippling carry), verified modulo-7 equivalent to
-- the Structural/Reference archs at every clock boundary. Its outputs
-- ripple-glitch between states (gate-delayed, like the real ULA); these
-- settle well before they are sampled downstream.
b3c: entity work.bit3_counter(T_Structure)
port map(
      clk => s_clkhc6,
      reset => reset,
      output => clk8_6,
      overflow => hc_rst
   );
     
end Behavioral;