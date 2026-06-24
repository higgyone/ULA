----------------------------------------------------------------------
-- Vert_Line_counter — 9-bit vertical (scan-line) counter (see pg 92)
--
-- Counts which PAL scan line the raster is on, 0..311 = 312 lines per
-- frame, then wraps. Non-interlaced: a single 312-line field rather
-- than the interlaced 625 (= 312.5 × 2). A half line is not possible,
-- so this design uses 312 whole lines, not 312.5.
--
-- Clocking / control (two distinct roles — do not confuse them):
--   Clk_HC6  — the CLOCK. The counter only moves on its FALLING edge.
--               Sourced from the horizontal block (= C5).
--   HCrst    — a synchronous ENABLE, not a clock. It is the horizontal
--               counter's wrap pulse (hc_rst): "a line just completed →
--               advance one line". So the vertical counter increments
--               exactly once per scan line.
--
-- Why this is immune to the hc_rst ripple glitch: HCrst is only ever
-- read at the falling edge of Clk_HC6. The FF library's `after TG`
-- gate delays place the hc_rst ripple glitch *after* that edge, so it
-- has settled long before the next sample. An edge-sampled consumer
-- never sees the glitch — exactly how the real ULA tolerates the
-- ripple. (Keep hc_rst away from any LEVEL-sensitive consumer.)
--
-- Architectures:
--   T_Structure — gate-faithful structural form using tce_ff / trce_ff
--                 (primary; matches Smith pg 92)
--   Behavioral  — reference `output_cnt + 1` model (kept for comparison)
--
-- Outputs:
--   V0..V8     — the nine counter bits, tapped for downstream decode
--   V0_n..V8_n — complemented taps (qbar), used directly by NOR gates
--                in video_sync to avoid extra inverters
--   Vrst       — frame-wrap indicator. T_Structure: combinational, high
--                while count = 311 with HCrst asserted (fires at end of
--                last line). Behavioral: registered, high during count = 0
--                (fires at start of first line of new frame). Currently
--                wired `Vrst => open` in video_sync; resolve for Phase 5.
----------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Vert_Line_counter is
    Port (
           HCrst : in STD_LOGIC;
           Clk_HC6 : in STD_LOGIC;

           V0   : out STD_LOGIC;
           V0_n : out STD_LOGIC;
           V1   : out STD_LOGIC;
           V1_n : out STD_LOGIC;
           V2   : out STD_LOGIC;
           V2_n : out STD_LOGIC;
           V3   : out STD_LOGIC;
           V3_n : out STD_LOGIC;
           V4   : out STD_LOGIC;
           V4_n : out STD_LOGIC;
           V5   : out STD_LOGIC;
           V5_n : out STD_LOGIC;
           V6   : out STD_LOGIC;
           V6_n : out STD_LOGIC;
           V7   : out STD_LOGIC;
           V7_n : out STD_LOGIC;
           V8   : out STD_LOGIC;
           V8_n : out STD_LOGIC;
           Vrst : out std_logic
           );
end Vert_Line_counter;

----------------------------------------------------------------------
-- T_Structure: nine chained T flip-flops matching Smith pg 92.
--
-- Two-tier structure:
--   V0–V2  tce_ff  (Toggle + Enable + Carry, no reset)
--   V3–V8  trce_ff (Toggle + Reset + Enable + Carry)
--
-- The schematic has no reset on V0–V2. This is safe because at the
-- only wrap point (count = 311 = "100110111") V0=V1=V2=1, so the
-- carry chain enables all three and they toggle 1→0, landing on 0
-- without needing an explicit reset. V3–V8 are reset by v3_8_reset.
--
-- Carry chain: HCrst feeds V0's enable; each stage's carry output
-- (= enable AND q) feeds the next stage's enable, so HCrst propagates
-- automatically to all stages — no separate enable tree needed.
--
-- Reset decode (v3_8_reset):
--   311 = "100110111" → V8·V5·V4·V2·V1·V0 = 1, V3·V6·V7 = 0.
--   The NOR gate checks V4_n, V5_n, V8_n (= 0 when Vx = 1) plus
--   not(s_v2_c). Using s_v2_c (= HCrst·V0·V1·V2) rather than V2
--   directly gates the reset with HCrst: without this, trce_ff's
--   reset-overrides-enable rule would clear V3–V8 on the very next
--   non-enabled Clk_HC6 edge after reaching 311, cutting that line
--   short. V3, V6, V7 are not checked: within 0–311 they are always 0
--   when the other bits are 1, so checking them is redundant.
----------------------------------------------------------------------
architecture T_Structure of Vert_Line_counter is

  -- Per-stage q, qbar, and carry signals
  signal s_v0   : std_logic;
  signal s_v0_n : std_logic;
  signal s_v0_c : std_logic;
  signal s_v1   : std_logic;
  signal s_v1_n : std_logic;
  signal s_v1_c : std_logic;
  signal s_v2   : std_logic;
  signal s_v2_n : std_logic;
  signal s_v2_c : std_logic;
  signal s_v3   : std_logic;
  signal s_v3_n : std_logic;
  signal s_v3_c : std_logic;
  signal s_v4   : std_logic;
  signal s_v4_n : std_logic;
  signal s_v4_c : std_logic;
  signal s_v5   : std_logic;
  signal s_v5_n : std_logic;
  signal s_v5_c : std_logic;
  signal s_v6   : std_logic;
  signal s_v6_n : std_logic;
  signal s_v6_c : std_logic;
  signal s_v7   : std_logic;
  signal s_v7_n : std_logic;
  signal s_v7_c : std_logic;
  signal s_v8   : std_logic;
  signal s_v8_n : std_logic;

  signal v3_8_reset : std_logic;   -- synchronous reset for V3–V8; fires at count=311 with HCrst

  begin

    -- NOR decode: high when HCrst·V0·V1·V2·V4·V5·V8 = 1 (count = 311, line enabled)
    v3_8_reset <= not (not(s_v2_c) or s_v4_n or s_v5_n or s_v8_n);
    Vrst <= v3_8_reset;

    V0    <= s_v0;
    V0_n  <= s_v0_n;
    V1    <= s_v1;
    V1_n  <= s_v1_n;
    V2    <= s_v2;
    V2_n  <= s_v2_n;
    V3    <= s_v3;
    V3_n  <= s_v3_n;
    V4    <= s_v4;
    V4_n  <= s_v4_n;
    V5    <= s_v5;
    V5_n  <= s_v5_n;
    V6    <= s_v6;
    V6_n  <= s_v6_n;
    V7    <= s_v7;
    V7_n  <= s_v7_n;
    V8    <= s_v8;
    V8_n  <= s_v8_n;

  -- V0–V2: tce_ff (no reset — schematic pg 92 has none on lower stages)
  v_count_0: entity work.tce_ff
  port map(
            clk     => Clk_HC6,
            enable  => HCrst,
            q       => s_v0,
            qbar    => s_v0_n,
            carry   => s_v0_c
    );

  v_count_1: entity work.tce_ff
  port map(
            clk     => Clk_HC6,
            enable  => s_v0_c,
            q       => s_v1,
            qbar    => s_v1_n,
            carry   => s_v1_c
    );

  v_count_2: entity work.tce_ff
  port map(
            clk     => Clk_HC6,
            enable  => s_v1_c,
            q       => s_v2,
            qbar    => s_v2_n,
            carry   => s_v2_c
    );

  -- V3–V8: trce_ff (reset by v3_8_reset on wrap)
  v_count_3: entity work.trce_ff
  port map(
            clk     => Clk_HC6,
            reset   => v3_8_reset,
            enable  => s_v2_c,
            q       => s_v3,
            qbar    => s_v3_n,
            carry   => s_v3_c
    );

  v_count_4: entity work.trce_ff
  port map(
            clk     => Clk_HC6,
            reset   => v3_8_reset,
            enable  => s_v3_c,
            q       => s_v4,
            qbar    => s_v4_n,
            carry   => s_v4_c
    );

  v_count_5: entity work.trce_ff
  port map(
            clk     => Clk_HC6,
            reset   => v3_8_reset,
            enable  => s_v4_c,
            q       => s_v5,
            qbar    => s_v5_n,
            carry   => s_v5_c
    );

  v_count_6: entity work.trce_ff
  port map(
            clk     => Clk_HC6,
            reset   => v3_8_reset,
            enable  => s_v5_c,
            q       => s_v6,
            qbar    => s_v6_n,
            carry   => s_v6_c
    );

  v_count_7: entity work.trce_ff
  port map(
            clk     => Clk_HC6,
            reset   => v3_8_reset,
            enable  => s_v6_c,
            q       => s_v7,
            qbar    => s_v7_n,
            carry   => s_v7_c
    );

  v_count_8: entity work.trce_ff
  port map(
            clk     => Clk_HC6,
            reset   => v3_8_reset,
            enable  => s_v7_c,
            q       => s_v8,
            qbar    => s_v8_n,
            carry   => open
    );

end T_Structure;

----------------------------------------------------------------------
-- Behavioral: reference model — kept for cross-checking in simulation.
-- Vrst here is registered: high during count = 0 (start of new frame),
-- unlike T_Structure where Vrst is combinational at count = 311.
----------------------------------------------------------------------
architecture Behavioral of Vert_Line_counter is
constant v_max : unsigned( 8 downto 0 ) := "100110111";  -- 311
signal output_cnt : unsigned( 8 downto 0 ) := (others => '0');
signal vrst_set   : std_logic := '0';
begin

process (Clk_HC6)
  begin
    if falling_edge(Clk_HC6) then
      if HCrst = '1' then
        output_cnt <= output_cnt + 1;
        vrst_set <= '0';
        if output_cnt = v_max then
            output_cnt <= (others => '0');
            vrst_set <= '1';
        end if;
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

V0_n <= not (output_cnt(0));
V1_n <= not (output_cnt(1));
V2_n <= not (output_cnt(2));
V3_n <= not (output_cnt(3));
V4_n <= not (output_cnt(4));
V5_n <= not (output_cnt(5));
V6_n <= not (output_cnt(6));
V7_n <= not (output_cnt(7));
V8_n <= not (output_cnt(8));

Vrst <= vrst_set;
end Behavioral;
