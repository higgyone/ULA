----------------------------------------------------------------------
-- Vert_Line_counter — 9-bit vertical (scan-line) counter (see pg 92)
--
-- Counts which PAL scan line the raster is on, 0..311 = 312 lines per
-- frame, then wraps. Non-interlaced: a single 312-line field rather
-- than the interlaced 625 (= 312.5 × 2). A half line is not possible,
-- so this design uses 312 whole lines, not 312.5.
--
-- Clocking / control (two distinct roles — do not confuse them):
--   Clk_HC6      — the CLOCK. The counter only moves on its FALLING
--                  edge. Sourced from the horizontal block (= C5).
--   HCrst_Enable — a synchronous ENABLE, not a clock. It is the
--                  horizontal counter's wrap pulse (hc_rst): "a line
--                  just completed → advance one line". So the vertical
--                  counter increments exactly once per scan line.
--
-- Why this is immune to the hc_rst ripple glitch: HCrst_Enable is only
-- ever read at the falling edge of Clk_HC6. The FF library's `after TG`
-- gate delays place the hc_rst ripple glitch *after* that edge, so it
-- has settled long before the next sample. An edge-sampled consumer
-- never sees the glitch — exactly how the real ULA tolerates the
-- ripple. (Keep hc_rst away from any LEVEL-sensitive consumer.)
--
-- This counter is currently BEHAVIOURAL (`output_cnt + 1`), unlike the
-- gate-faithful ripple horizontal counter. See the gate-friendly
-- conversion TODO in CLAUDE.md.
--
-- Outputs:
--   V0..V8 — the nine counter bits, tapped for downstream decode
--   Vrst   — frame-wrap pulse, high for the one line where the count is
--            0 (first line of the new frame). For Phase 5's flash /
--            frame counter. Currently wired `Vrst => open` in video_sync.
----------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Vert_Line_counter is
    Port ( 
           HCrst_Enable : in STD_LOGIC;
           Clk_HC6 : in STD_LOGIC;
           
           V0 : out STD_LOGIC;
           V1 : out STD_LOGIC;
           V2 : out STD_LOGIC;
           V3 : out STD_LOGIC;
           V4 : out STD_LOGIC;
           V5 : out STD_LOGIC;
           V6 : out STD_LOGIC;
           V7 : out STD_LOGIC;
           V8 : out STD_LOGIC;    
           Vrst : out std_logic     -- vertical reset pulse on wrap (line 311 → 0) which is 312 PAL lines
           );
end Vert_Line_counter;

architecture Behavioral of Vert_Line_counter is
-- v_max = 311 (the last valid line). The counter visits 0..311 = 312
-- states = 312 PAL lines, then wraps to 0.
constant v_max : unsigned( 8 downto 0 ) := "100110111";
signal output_cnt:  unsigned( 8 downto 0 ) := (others => '0');
signal vrst_set : std_logic := '0';
begin
-- Purely clocked process: sensitive to Clk_HC6 only. HCrst_Enable is a
-- synchronous enable, read inside the falling-edge guard, so it does not
-- belong in the sensitivity list (it would wake the process and do
-- nothing — and synthesis ignores it for an edge-triggered process).
process (Clk_HC6)
  begin
    if falling_edge(Clk_HC6) then
      if HCrst_Enable = '1' then              -- a horizontal line just completed
        output_cnt <= output_cnt + 1;          -- advance one line ...
        vrst_set <= '0';
        if output_cnt = v_max then             -- ... unless we are at line 311:
            output_cnt <= (others => '0');     -- wrap to 0 (last assignment wins,
            vrst_set <= '1';                   -- overriding the +1 above) and
        end if;                                -- raise the frame-wrap pulse.
      end if;
    end if;
  end process;

V0 <= output_cnt(0);
V1 <= output_cnt(1);
V2 <= output_cnt(2);
V3 <= output_cnt(3);
V4 <= output_cnt(4);
V5 <= output_cnt(5);
V6 <= output_cnt(6);
V7 <= output_cnt(7);
V8 <= output_cnt(8);

Vrst <= vrst_set;
end Behavioral;
