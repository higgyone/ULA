----------------------------------------------------------------------------------
-- arty_top — smoke test: the ULA running on the Digilent Arty A7-35T
--
-- Step 5 of "the ULA is complete". Proves the gate-level ULA (FPGA build:
-- ula_build_pkg_fpga.vhd) runs on real silicon, with no CPU, no memory and no
-- video out: just its clocks, counters and interrupt, watched on LEDs and a
-- scope. The ULA itself is unchanged; everything board-specific is here.
--
--   CLK100MHZ (pin E3) --> clk_wiz_14 (MMCM, Clocking Wizard IP) --> 14.000 MHz
--                                  |  locked --> led(1)
--                                  v
--                                ula   CPU strobes inactive, keys up, no tape
--                                  |
--     int_n --> edge detect --> count 25 frames --> toggle --> led(0)  (1 Hz)
--     int_n, phicpu_n, ras_n, cas_n, a0 --> Pmod JA (ja(0)..ja(4)) for the scope
--
-- ── What the LEDs show ───────────────────────────────────────────────
--   led(1) (LD5) on      the MMCM has locked: 14 MHz is running.
--   led(0) (LD4) 1 Hz    /INT arrives once per frame (50.08 Hz); 25 frames on,
--                        25 off. A steady 1 Hz blink proves the crystal clock,
--                        the 14 -> 7 MHz divider, the horizontal and vertical
--                        counters and the interrupt decode all run at the
--                        right rate on the FPGA.
--
-- ── What the scope should show (Pmod JA, 3.3 V; GND = pins 5 / 11) ─────
--   ja(0)  pin 1  /INT     low 64 pixels = 9.14 us, every 19.97 ms
--   ja(1)  pin 2  /phicpu  the CPU clock, inverted: 3.5 MHz (285.7 ns)
--   ja(2)  pin 3  /RAS     video fetch bursts in the 256 display pixels of
--   ja(3)  pin 4  /CAS     each display line; nothing in the border
--   ja(4)  pin 7  A0       the video address bit during fetches
--
-- ── Notes ────────────────────────────────────────────────────────────
--   * clk_wiz_14 is IP: instantiated through a component declaration copied
--     from its .vho (IP is compiled separately, so its ports are declared
--     here). Regenerating it with different ports means updating that.
--   * The ULA's inout pins (k0, a0, d0..d4, d6, d7) connect to internal
--     signals: with no real bus they need something to attach to. Synthesis
--     turns their 'H' / 'Z' drivers into plain logic here.
--   * Edge detect: /INT compared with its one-tick-delayed copy, so each frame
--     counts once (not once per tick of the ~128-tick low pulse). The test is
--     "was not '0', is '0'": int_n is open collector, '0' or 'H', and 'H' is
--     not '1' in simulation, so comparing with '1' would never match there.
--   * /INT comes from the ULA's own logic, not a clk_14 flip-flop, so the
--     first register can very rarely catch it mid-change. Harmless for an
--     LED (one count a tick late at worst); a real design would add a
--     second register first (a synchroniser).
--   * No reset: the registers start from their initial values, which the
--     bitstream loads at power-up.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity arty_top is
    port (
        clk100mhz : in    std_logic;                    -- board oscillator (pin E3)
        led       : out   std_logic_vector(3 downto 0); -- LD4..LD7
        ja        : out   std_logic_vector(7 downto 0)  -- Pmod JA, for the scope
    );
end entity arty_top;

architecture behavioral of arty_top is

    -- clocking
    signal s_clk_14 : std_logic;
    signal s_locked : std_logic;

    -- the ULA's inout pins (each needs a signal to connect to)
    signal s_k0 : std_logic;
    signal s_a0 : std_logic;
    signal s_d0 : std_logic;
    signal s_d1 : std_logic;
    signal s_d2 : std_logic;
    signal s_d3 : std_logic;
    signal s_d4 : std_logic;
    signal s_d6 : std_logic;
    signal s_d7 : std_logic;

    -- ULA outputs we want to see on the scope
    signal s_int_n    : std_logic;
    signal s_phicpu_n : std_logic;
    signal s_ras_n    : std_logic;
    signal s_cas_n    : std_logic;

    -- the 1 Hz blinker
    signal s_int_n_d   : std_logic             := '1'; -- /INT one clock ago (for edge detect)
    signal s_frame_cnt : integer range 0 to 24 := 0;   -- counts frames 0..24
    signal s_blink     : std_logic             := '0'; -- the LED, toggled every 25 frames

    -- the Clocking Wizard's MMCM (IP: declared here, compiled separately)
    component clk_wiz_14 is
        port (
            clk_out1 : out   std_logic;
            locked   : out   std_logic;
            clk_in1  : in    std_logic
        );
    end component clk_wiz_14;

begin

    master_clock_14 : component clk_wiz_14
        port map (
            -- Clock out ports
            clk_out1 => s_clk_14,
            -- Status and control signals
            locked => s_locked,
            -- Clock in ports
            clk_in1 => clk100mhz
        );

    ula_subsystem : entity work.ula(structural)
        port map (
            clk_14  => s_clk_14,
            reset   => '0',
            rd_n    => '1',
            wr_n    => '1',
            mreq_n  => '1',
            ioreq_n => '1',
            a14     => '0',
            a15     => '0',
            tape_mv => 0,

            k0 => s_k0,
            k1 => '1',
            k2 => '1',
            k3 => '1',
            k4 => '1',

            ras_n    => s_ras_n,
            cas_n    => s_cas_n,
            we_n     => open,
            rom_cs_n => open,
            int_n    => s_int_n,
            phicpu_n => s_phicpu_n,

            a0 => s_a0,
            a1 => open,
            a2 => open,
            a3 => open,
            a4 => open,
            a5 => open,
            a6 => open,

            y_n => open,
            u   => open,
            v   => open,

            sound => open,

            d0 => s_d0,
            d1 => s_d1,
            d2 => s_d2,
            d3 => s_d3,
            d4 => s_d4,
            d5 => '1',
            d6 => s_d6,
            d7 => s_d7
        );

    blinker : process (s_clk_14) is
    begin

        if rising_edge(s_clk_14) then
            s_int_n_d <= s_int_n;                            -- remember this tick's /INT for next tick

            if (s_int_n_d /= '0' and s_int_n = '0') then     -- was not low, is now low: /INT just fell then
                if (s_frame_cnt = 24) then
                    s_frame_cnt <= 0;
                    s_blink     <= not(s_blink);
                else
                    s_frame_cnt <= s_frame_cnt + 1;
                end if;
            end if;
        end if;

    end process blinker;

    led(0)          <= s_blink;
    led(1)          <= s_locked;
    led(3 downto 2) <= "00";

    ja(0)          <= s_int_n;
    ja(1)          <= s_phicpu_n;
    ja(2)          <= s_ras_n;
    ja(3)          <= s_cas_n;
    ja(4)          <= s_a0;
    ja(7 downto 5) <= "000";

end architecture behavioral;
