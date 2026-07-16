----------------------------------------------------------------------
-- Vert_Line_counter — 9-bit vertical (scan-line) counter (see pg 92)
--
-- Counts which PAL scan line the raster is on, 0..311 = 312 lines per
-- frame, then wraps. Non-interlaced: a single 312-line field rather
-- than the interlaced 625 (= 312.5 × 2). A half line is not possible,
-- so this design uses 312 whole lines, not 312.5.
--
-- Clocking / control (two distinct roles — do not confuse them):
--   clk_hc6  — the CLOCK. The counter only moves on its FALLING edge.
--               Sourced from the horizontal block (= C5).
--   hcrst    — a synchronous ENABLE, not a clock. It is the horizontal
--               counter's wrap pulse (hc_rst): "a line just completed →
--               advance one line". So the vertical counter increments
--               exactly once per scan line.
--
-- Why this is immune to the hc_rst ripple glitch: hcrst is only ever
-- read at the falling edge of clk_hc6. The FF library's `after TG`
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
--   v0..v8     — the nine counter bits, tapped for downstream decode
--   v0_n..v8_n — complemented taps (qbar), used directly by NOR gates
--                in video_sync to avoid extra inverters
--   vrst       — frame-wrap indicator. T_Structure: combinational, high
--                while count = 311 with hcrst asserted (fires at end of
--                last line). Behavioral: registered, high during count = 0
--                (fires at start of first line of new frame). Currently
--                wired `vrst => open` in video_sync; resolve for Phase 5.
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity vert_line_counter is
    port (
        hcrst   : in    std_logic;
        clk_hc6 : in    std_logic;

        v0   : out   std_logic;
        v0_n : out   std_logic;
        v1   : out   std_logic;
        v1_n : out   std_logic;
        v2   : out   std_logic;
        v2_n : out   std_logic;
        v3   : out   std_logic;
        v3_n : out   std_logic;
        v4   : out   std_logic;
        v4_n : out   std_logic;
        v5   : out   std_logic;
        v5_n : out   std_logic;
        v6   : out   std_logic;
        v6_n : out   std_logic;
        v7   : out   std_logic;
        v7_n : out   std_logic;
        v8   : out   std_logic;
        v8_n : out   std_logic;
        vrst : out   std_logic
    );
end entity vert_line_counter;

----------------------------------------------------------------------
-- T_Structure: nine chained T flip-flops matching Smith pg 92.
--
-- Two-tier structure:
--   v0–v2  tce_ff  (Toggle + Enable + Carry, no reset)
--   v3–v8  trce_ff (Toggle + Reset + Enable + Carry)
--
-- The schematic has no reset on v0–v2. This is safe because at the
-- only wrap point (count = 311 = "100110111") v0=v1=v2=1, so the
-- carry chain enables all three and they toggle 1→0, landing on 0
-- without needing an explicit reset. v3–v8 are reset by v3_8_reset.
--
-- Carry chain: hcrst feeds v0's enable; each stage's carry output
-- (= enable AND q) feeds the next stage's enable, so hcrst propagates
-- automatically to all stages — no separate enable tree needed.
--
-- Reset decode (v3_8_reset):
--   311 = "100110111" → v8·v5·v4·v2·v1·v0 = 1, v3·v6·v7 = 0.
--   The NOR gate checks v4_n, v5_n, v8_n (= 0 when Vx = 1) plus
--   not(s_v2_c). Using s_v2_c (= hcrst·v0·v1·v2) rather than v2
--   directly gates the reset with hcrst: without this, trce_ff's
--   reset-overrides-enable rule would clear v3–v8 on the very next
--   non-enabled clk_hc6 edge after reaching 311, cutting that line
--   short. v3, v6, v7 are not checked: within 0–311 they are always 0
--   when the other bits are 1, so checking them is redundant.
----------------------------------------------------------------------

architecture t_structure of vert_line_counter is

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

    signal v3_8_reset : std_logic;   -- synchronous reset for v3–v8; fires at count=311 with hcrst

begin

    -- NOR decode: high when hcrst·v0·v1·v2·v4·v5·v8 = 1 (count = 311, line enabled)
    v3_8_reset <= not (not(s_v2_c) or s_v4_n or s_v5_n or s_v8_n);
    vrst       <= v3_8_reset;

    v0   <= s_v0;
    v0_n <= s_v0_n;
    v1   <= s_v1;
    v1_n <= s_v1_n;
    v2   <= s_v2;
    v2_n <= s_v2_n;
    v3   <= s_v3;
    v3_n <= s_v3_n;
    v4   <= s_v4;
    v4_n <= s_v4_n;
    v5   <= s_v5;
    v5_n <= s_v5_n;
    v6   <= s_v6;
    v6_n <= s_v6_n;
    v7   <= s_v7;
    v7_n <= s_v7_n;
    v8   <= s_v8;
    v8_n <= s_v8_n;

    -- v0–v2: tce_ff (no reset — schematic pg 92 has none on lower stages)
    v_count_0 : entity work.tce_ff
        port map (
            clk    => clk_hc6,
            enable => hcrst,
            q      => s_v0,
            qbar   => s_v0_n,
            carry  => s_v0_c
        );

    v_count_1 : entity work.tce_ff
        port map (
            clk    => clk_hc6,
            enable => s_v0_c,
            q      => s_v1,
            qbar   => s_v1_n,
            carry  => s_v1_c
        );

    v_count_2 : entity work.tce_ff
        port map (
            clk    => clk_hc6,
            enable => s_v1_c,
            q      => s_v2,
            qbar   => s_v2_n,
            carry  => s_v2_c
        );

    -- v3–v8: trce_ff (reset by v3_8_reset on wrap)
    v_count_3 : entity work.trce_ff
        port map (
            clk    => clk_hc6,
            reset  => v3_8_reset,
            enable => s_v2_c,
            q      => s_v3,
            qbar   => s_v3_n,
            carry  => s_v3_c
        );

    v_count_4 : entity work.trce_ff
        port map (
            clk    => clk_hc6,
            reset  => v3_8_reset,
            enable => s_v3_c,
            q      => s_v4,
            qbar   => s_v4_n,
            carry  => s_v4_c
        );

    v_count_5 : entity work.trce_ff
        port map (
            clk    => clk_hc6,
            reset  => v3_8_reset,
            enable => s_v4_c,
            q      => s_v5,
            qbar   => s_v5_n,
            carry  => s_v5_c
        );

    v_count_6 : entity work.trce_ff
        port map (
            clk    => clk_hc6,
            reset  => v3_8_reset,
            enable => s_v5_c,
            q      => s_v6,
            qbar   => s_v6_n,
            carry  => s_v6_c
        );

    v_count_7 : entity work.trce_ff
        port map (
            clk    => clk_hc6,
            reset  => v3_8_reset,
            enable => s_v6_c,
            q      => s_v7,
            qbar   => s_v7_n,
            carry  => s_v7_c
        );

    v_count_8 : entity work.trce_ff
        port map (
            clk    => clk_hc6,
            reset  => v3_8_reset,
            enable => s_v7_c,
            q      => s_v8,
            qbar   => s_v8_n,
            carry  => open
        );

end architecture t_structure;

----------------------------------------------------------------------
-- Behavioral: reference model — kept for cross-checking in simulation.
-- vrst here is registered: high during count = 0 (start of new frame),
-- unlike T_Structure where vrst is combinational at count = 311.
----------------------------------------------------------------------

architecture behavioral of vert_line_counter is

    constant v_max      : unsigned( 8 downto 0) := "100110111";  -- 311
    signal   output_cnt : unsigned( 8 downto 0) := (others => '0');
    signal   vrst_set   : std_logic             := '0';

begin

    process (clk_hc6) is
    begin

        if falling_edge(clk_hc6) then
            if (hcrst = '1') then
                output_cnt <= output_cnt + 1;
                vrst_set   <= '0';
                if (output_cnt = v_max) then
                    output_cnt <= (others => '0');
                    vrst_set   <= '1';
                end if;
            end if;
        end if;

    end process;

    v0 <= output_cnt(0);
    v1 <= output_cnt(1);
    v2 <= output_cnt(2);
    v3 <= output_cnt(3);
    v4 <= output_cnt(4);
    v5 <= output_cnt(5);
    v6 <= output_cnt(6);
    v7 <= output_cnt(7);
    v8 <= output_cnt(8);

    v0_n <= not (output_cnt(0));
    v1_n <= not (output_cnt(1));
    v2_n <= not (output_cnt(2));
    v3_n <= not (output_cnt(3));
    v4_n <= not (output_cnt(4));
    v5_n <= not (output_cnt(5));
    v6_n <= not (output_cnt(6));
    v7_n <= not (output_cnt(7));
    v8_n <= not (output_cnt(8));

    vrst <= vrst_set;

end architecture behavioral;
