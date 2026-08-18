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
-- ── How the timing is produced ───────────────────────────────────────
-- The RAS/CAS waveform is decoded DIRECTLY from the master horizontal counter's
-- low three bits {c2,c1,c0} = the pixel position within an 8-pixel character cell
-- (0..7). Because those bits cycle 0..7 once per character, the two-byte fetch
-- (bitmap + attribute, one RAS + two CAS) fires exactly ONCE per character cell —
-- the correct 64 bytes/line, with no separate trigger and no gap logic (the idle
-- pixels simply fall out of the decode). Edges land on 7 MHz pixel boundaries
-- (142.86 ns granularity). That is coarser than the real ULA's analog timing, but
-- still clears every DRAM AC minimum with margin:
--   RAS→CAS 143 ns (≥20) · CAS-high gap 143 ns (≥60) · CAS-low 143/286 ns (≥100) ·
--   RAS held 286 ns past last CAS↓ (≥100).
--
-- ── The 8-pixel waveform (active-low, '0' = strobe asserted) ─────────
--   pix {c2,c1,c0} | vid_ras_n | vid_cas_n | event
--   --------------+-----------+-----------+---------------------------
--     0  (000)    |    0      |    1      | RAS↓  (fetch starts)
--     1  (001)    |    0      |    0      | CAS0↓ (bitmap byte)
--     2  (010)    |    0      |    1      | CAS0↑ (precharge gap)
--     3  (011)    |    0      |    0      | CAS1↓ (attribute byte)
--     4  (100)    |    0      |    0      | RAS + CAS1 both low
--     5  (101)    |    1      |    1      | RAS↑ and CAS1↑ (fetch done)
--     6  (110)    |    1      |    1      | idle (CPU gap)
--     7  (111)    |    1      |    1      | idle (CPU gap)
--
-- ── Ports ────────────────────────────────────────────────────────────
--   clk_14     14 MHz master clock — registers the strobes (de-glitches the
--              ripple-clocked horizontal counter, gives clean clock-aligned edges).
--   c0,c1,c2   low three bits of the master horizontal counter = pixel-in-cell.
--   n_vid_c3   display-fetch enable, active-LOW ('0' = inside the pixel display
--              fetch window). Holds the VIDEO strobes de-asserted in border/blank
--              so only CPU accesses reach the DRAM there. DEFERRED input.
--   cpu_ras    CPU-side RAS, active-low. DEFERRED (real source later).
--   cpu_cas    CPU-side CAS, active-low. DEFERRED (real source later).
--   n_ras      DRAM RAS out, active-low = video RAS merged with cpu_ras.
--   n_cas      DRAM CAS out, active-low = video CAS merged with cpu_cas.
--   n_vid_ras  video RAS tap, active-low — for the address mux / contention logic.
--
-- Integration note: c0/c1/c2 come from a ripple counter; when this block is wired
-- to the real counter (not TB stimulus) a resync of those taps into the clk_14
-- domain may be needed to fully avoid sampling mid-ripple.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity ras_cas_generation is
    port (
        clk_14    : in    std_logic; -- 14 MHz master clock (register clock)
        c0        : in    std_logic; -- horizontal counter bit 0 (pixel LSB)
        c1        : in    std_logic; -- horizontal counter bit 1
        c2        : in    std_logic; -- horizontal counter bit 2 (char-cell MSB)
        n_vid_c3  : in    std_logic; -- active-low display-fetch enable; deferred
        cpu_ras   : in    std_logic; -- CPU-side RAS, active-low; deferred
        cpu_cas   : in    std_logic; -- CPU-side CAS, active-low; deferred
        n_ras     : out   std_logic; -- DRAM RAS, active-low
        n_cas     : out   std_logic; -- DRAM CAS, active-low
        n_vid_ras : out   std_logic  -- video RAS tap, active-low
    );
end entity ras_cas_generation;

architecture synchronous of ras_cas_generation is

    -- pixel position within the character cell (c2 c1 c0 = 0..7)
    signal pix : std_logic_vector(2 downto 0);

    -- registered video strobes (active-low), before the CPU merge
    signal vid_ras_n : std_logic := '1';
    signal vid_cas_n : std_logic := '1';

begin

    pix <= c2 & c1 & c0;

    ------------------------------------------------------------------
    -- Decode the 8-pixel RAS/CAS waveform (see table in header) and
    -- REGISTER it on clk_14: this cleans up the ripple counter and
    -- pins every strobe edge to a clock edge. Held de-asserted ('1')
    -- outside the display fetch window (n_vid_c3 = '1').
    ------------------------------------------------------------------
    strobe_reg : process (clk_14) is
    begin

        if rising_edge(clk_14) then
            if (n_vid_c3 = '0') then                  -- inside the display fetch window

                case pix is

                    when "000" =>

                        vid_ras_n <= '0';             -- RAS down
                        vid_cas_n <= '1';

                    when "001" =>

                        vid_ras_n <= '0';             -- CAS0 down (bitmap)
                        vid_cas_n <= '0';

                    when "010" =>

                        vid_ras_n <= '0';             -- CAS0 up (precharge gap)
                        vid_cas_n <= '1';

                    when "011" =>

                        vid_ras_n <= '0';             -- CAS1 down (attribute)
                        vid_cas_n <= '0';

                    when "100" =>

                        vid_ras_n <= '0';             -- RAS + CAS1 both low
                        vid_cas_n <= '0';

                    when "101" =>

                        vid_ras_n <= '1';             -- RAS up, CAS1 up (done)
                        vid_cas_n <= '1';

                    when others =>

                        vid_ras_n <= '1';             -- pix 6,7 (+ metavalues): idle
                        vid_cas_n <= '1';

                end case;

            else
                vid_ras_n <= '1';                     -- outside display: no video strobes
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
