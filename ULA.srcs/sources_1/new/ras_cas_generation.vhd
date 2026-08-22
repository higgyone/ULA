----------------------------------------------------------------------------------
-- ras_cas_generation — DRAM RAS/CAS strobe generator (SYNCHRONOUS implementation)
--
-- ⚠ DELIBERATELY NOT GATE-ACCURATE. Every other cell in this project mirrors the
-- Ferranti ULA gate-for-gate, but the ULA builds its fine DRAM timing from ANALOG
-- gate/parasitic delays, which have no reliable FPGA equivalent (`after` delays are
-- ignored by synthesis, inverter chains optimise to a wire, IDELAY maxes ~2.5 ns).
-- So this ONE block is rebuilt synchronously. The original gate-level draft (Chris
-- Smith, "The ZX Spectrum ULA", page 127) is preserved in the REFERENCE block below.
--
-- ── The DRAM cycle is 4 PIXELS, not 8 ────────────────────────────────
-- One RAS cycle fetches a BYTE PAIR (two CAS strobes) and occupies 4 pixel clocks
-- = 8 ticks of the 14 MHz master (8 x 71.4 ns = 571 ns). Two such cycles run
-- back-to-back inside the c3-high window, fetching FOUR bytes:
--     RAS#1 -> byte A (display) + byte B (attribute)   pixels 0..3
--     RAS#2 -> byte C (display) + byte D (attribute)   pixels 4..7
-- That is the book's vid_cas_ac (A and C, the first CAS of each RAS cycle) and
-- vid_cas_bd (B and D, the second). The c3-low half is left idle so the CPU can
-- reach the DRAM — the contention gap. Average 64 bytes/line, fetched in bursts.
--
-- Because the cycle is identical for both halves of the burst, the decode needs
-- only c1/c0 (which pixel of the 4) plus the half-pixel phase — not c2.
--
-- ── Time base: {c1, c0, phase} ───────────────────────────────────────
-- The 14 MHz period (71.4 ns) is half a pixel, so a tick index is formed as
--   tick = c1 & c0 & clk_7      (clk_7 = '0' first half of the pixel, '1' second)
-- giving 0..7 across the 4-pixel cycle. All DRAM AC minimums are met:
--   RAS→CAS 71 ns (≥20) · CAS-high gap 71 ns (≥60) · CAS-low 143 ns (≥100) ·
--   RAS held 143 ns past the last CAS↓ (≥100) · RAS 429 ns, high 143 ns before
--   the next cycle (precharge).
--
-- ── The 8-tick waveform (active-low, '0' = strobe asserted) ──────────
--   tick | pixel.phase | vid_ras_n | vid_cas_n | event
--   -----+-------------+-----------+-----------+------------------------
--     0  |   px0 .0    |    0      |    1      | RAS↓  (cycle starts)
--     1  |   px0 .1    |    0      |    0      | CAS↓  first byte  (A/C)
--     2  |   px1 .0    |    0      |    0      |
--     3  |   px1 .1    |    0      |    1      | CAS↑  (precharge gap)
--     4  |   px2 .0    |    0      |    0      | CAS↓  second byte (B/D)
--     5  |   px2 .1    |    0      |    0      |
--     6  |   px3 .0    |    1      |    0      | RAS↑  (CAS still low)
--     7  |   px3 .1    |    1      |    1      | CAS↑  (cycle done)
--   The byte captured by each CAS is latched a pixel later by the control-clock
--   strobes (see latch_and_shift_reg_control_clks): display bytes at pixels 1
--   and 5, attribute bytes at pixels 3 and 7.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   clk_14     14 MHz master clock — registers the strobes (de-glitches the
--              ripple-clocked horizontal counter, gives clean clock-aligned edges)
--   clk_7      pixel clock, used as the HALF-PIXEL PHASE bit (not as a clock)
--   c0, c1     horizontal counter bits 0/1 = pixel within the 4-pixel DRAM cycle
--   n_vid_c3   display-fetch enable, active-LOW ('0' = inside the fetch window).
--              Holds the video strobes de-asserted in the border/blank and in the
--              c3-low CPU gap. DEFERRED input.
--   cpu_ras    CPU-side RAS, active-low. DEFERRED (real source later).
--   cpu_cas    CPU-side CAS, active-low. DEFERRED (real source later).
--   n_ras      DRAM RAS out, active-low = video RAS merged with cpu_ras
--   n_cas      DRAM CAS out, active-low = video CAS merged with cpu_cas
--   n_vid_ras  video RAS tap, active-low — for the address mux / contention logic
--
-- Integration note: c0/c1 come from a ripple counter and clk_7 is derived from
-- clk_14 by division, so when this block is wired to the real counter (rather
-- than TB stimulus) those taps may need resyncing into the clk_14 domain to
-- avoid sampling them mid-transition.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity ras_cas_generation is
    port (
        clk_14    : in    std_logic; -- 14 MHz master clock (register clock)
        clk_7     : in    std_logic; -- pixel clock as half-pixel phase bit
        c0        : in    std_logic; -- horizontal counter bit 0
        c1        : in    std_logic; -- horizontal counter bit 1
        n_vid_c3  : in    std_logic; -- active-low display-fetch enable; deferred
        cpu_ras   : in    std_logic; -- CPU-side RAS, active-low; deferred
        cpu_cas   : in    std_logic; -- CPU-side CAS, active-low; deferred
        n_ras     : out   std_logic; -- DRAM RAS, active-low
        n_cas     : out   std_logic; -- DRAM CAS, active-low
        n_vid_ras : out   std_logic  -- video RAS tap, active-low
    );
end entity ras_cas_generation;

architecture synchronous of ras_cas_generation is

    -- position within the 4-pixel DRAM cycle: {c1, c0, half-pixel phase} = 0..7
    signal tick : std_logic_vector(2 downto 0);

    -- registered video strobes (active-low), before the CPU merge
    signal vid_ras_n : std_logic := '1';
    signal vid_cas_n : std_logic := '1';

begin

    tick <= c1 & c0 & clk_7;

    ------------------------------------------------------------------
    -- Decode the 8-tick RAS/CAS waveform (see table in header) and
    -- REGISTER it on clk_14: this cleans up the ripple counter and
    -- pins every strobe edge to a clock edge. Held de-asserted ('1')
    -- outside the display fetch window (n_vid_c3 = '1'), which covers
    -- both the border/blank and the c3-low CPU gap.
    ------------------------------------------------------------------
    strobe_reg : process (clk_14) is
    begin

        if rising_edge(clk_14) then
            if (n_vid_c3 = '0') then          -- inside the display fetch window

                case tick is

                    when "000" =>

                        vid_ras_n <= '0';     -- RAS down, cycle starts
                        vid_cas_n <= '1';

                    when "001" =>

                        vid_ras_n <= '0';     -- CAS down: first byte (A/C)
                        vid_cas_n <= '0';

                    when "010" =>

                        vid_ras_n <= '0';
                        vid_cas_n <= '0';

                    when "011" =>

                        vid_ras_n <= '0';     -- CAS up: precharge gap
                        vid_cas_n <= '1';

                    when "100" =>

                        vid_ras_n <= '0';     -- CAS down: second byte (B/D)
                        vid_cas_n <= '0';

                    when "101" =>

                        vid_ras_n <= '0';
                        vid_cas_n <= '0';

                    when "110" =>

                        vid_ras_n <= '1';     -- RAS up (CAS still low)
                        vid_cas_n <= '0';

                    when others =>

                        vid_ras_n <= '1';     -- tick 7: CAS up, cycle done
                        vid_cas_n <= '1';

                end case;

            else
                vid_ras_n <= '1';             -- outside the fetch window: idle
                vid_cas_n <= '1';
            end if;
        end if;

    end process strobe_reg;

    ------------------------------------------------------------------
    -- Merge the video strobes with the CPU side. Both active-low, so a
    -- plain AND drives the DRAM strobe low if EITHER side is asserting.
    -- n_vid_ras is tapped out separately for the address-mux / contention.
    ------------------------------------------------------------------
    n_ras     <= vid_ras_n and cpu_ras;
    n_cas     <= vid_cas_n and cpu_cas;
    n_vid_ras <= vid_ras_n;

end architecture synchronous;

----------------------------------------------------------------------------------
-- REFERENCE ONLY — original gate-level draft (Chris Smith page 127).
-- Kept for documentation of how the real ULA generates these strobes with
-- delayed logic + propagation delays. NOT synthesised and NOT used: the delays
-- here are simulation-only (0 ns in hardware) and the inverter-chain "delays"
-- (clk7_delay 6x, n_c0_delay 4x, n_c1_delay 3x, the 2x chains on
-- n_vid_ras_delay / n_cas) do not survive synthesis.
--
-- The book's CAS legs, which this block's tick decode reproduces:
--   vid_cas_ac = NOR(not vidc3, c1, not vidcaspulse, not vidras_delay)
--              = vidc3 AND not(c1) AND vidcaspulse AND vidras_delay
--              -> the FIRST CAS of each RAS cycle (bytes A and C). The
--                 vidras_delay term is the ~20 ns "chop" that opens the
--                 RAS→CAS setup; only this leg has it.
--   vid_cas_bd = NOR(not vidc3, not c1, not vidcaspulse)
--              = vidc3 AND c1 AND vidcaspulse
--              -> the SECOND CAS of each RAS cycle (bytes B and D).
--   not(vidcas) = NOR(vid_cas_ac, vid_cas_bd)
--
-- entity ras_cas_generation is
--     port (
--         cpu_cas   : in  std_logic;
--         clk       : in  std_logic;
--         n_c0      : in  std_logic;
--         c1        : in  std_logic;
--         n_c1      : in  std_logic;
--         n_vid_c3  : in  std_logic;
--         cpu_ras   : in  std_logic;
--         n_cas     : out std_logic;
--         n_vid_ras : out std_logic;
--         n_ras     : out std_logic
--     );
-- end entity ras_cas_generation;
--
-- architecture structural of ras_cas_generation is
--     signal clk7_delay       : std_logic;
--     signal n_vid_cas_pulse  : std_logic;
--     signal n_vid_ras_pulse  : std_logic;
--     signal n_c0_delay       : std_logic;
--     signal n_c1_delay       : std_logic;
--     signal n_vid_ras_delay  : std_logic;
--     signal a_out            : std_logic;
--     signal b_out            : std_logic;
--     signal c_out            : std_logic;
--     signal d_out            : std_logic;
--     signal n_c_out          : std_logic;
-- begin
--     clk7_delay      <= not(not(not(not(not(not(clk))))));       -- 6-inv align vs n_c0
--     n_vid_cas_pulse <= not(clk7_delay or n_c0);
--     n_c1_delay      <= not(not(not(c1)));                       -- = n_c1, delayed
--     n_c0_delay      <= not(not(not(not(n_c0))));                -- ~8 ns align
--     n_vid_ras_pulse <= not(n_c0_delay or n_c0 or n_c1);
--     n_vid_ras_delay <= not(not(n_c_out));                       -- (chop path)
--
--     a_out    <= not(n_vid_cas_pulse or n_vid_c3 or n_c1_delay);
--     b_out    <= not(n_vid_cas_pulse or c1 or n_vid_c3 or n_vid_ras_delay);
--     c_out    <= not(n_vid_c3 or n_vid_ras_pulse);
--     d_out    <= not(cpu_cas or a_out or b_out);
--     n_c_out  <= not(c_out);
--
--     n_ras     <= not(c_out or cpu_ras);
--     n_cas     <= not(not(d_out));                               -- 2-inv "58 ns" delay
--     n_vid_ras <= n_c_out;
-- end architecture structural;
----------------------------------------------------------------------------------
