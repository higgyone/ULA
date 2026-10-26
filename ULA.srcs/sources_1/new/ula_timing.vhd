----------------------------------------------------------------------------------
-- ula_timing — timing subsystem: clocks, H/V counters, sync, test modes
--
-- One of the ULA.vhd subsystems. Everything else in the chip runs off the
-- clocks and counter taps that come out of here.
--
--   clk_14 inverter     the book's common-emitter input stage -> s_clk_14_n
--   clk_div_2           14 -> 7 MHz: clk_7 and /clk7 (clk_7_n)
--   video_sync          horizontal counter C0..C8 (448 pixels per line) and
--                       vertical counter V0..V8 (312 lines per frame), with
--                       the decodes: hblank_n, vsync, border / border_n and
--                       the composite sync
--   test_modes          wafer test modes A and B (MREQ and IORQ low together):
--                       tclk_a clocks C6..C8, tclk_b clocks the FLASH divider,
--                       and test B drives v8 out on K0
--
--      clk_14 --NOT--> clk_div_2 --clk_7_n--> video_sync --> taps, sync, border
--                          |                    ^      |
--                          +--> clk_7    tclk_a |      | v8_n
--                                               |      v
--      rd_n, wr_n, mreq_n, ioreq_n ------> test_modes --> tclk_b, k0
--
-- Pure wiring: no logic of its own apart from the clk_14 inverter.
--
-- Outputs: only the counter taps something outside uses are exported
-- (c0..c8, c0_n..c3_n, c7_n, c8_n, v0..v8, v8_n); the rest are open. v8 has
-- no consumer in the design but ula_tb reads s_v8 through an external name.
-- Add a tap here (one port, one line) when a new block needs it.
--
-- Composite sync: only the 6C001 timing (sync_6c_n) leaves the subsystem;
-- the 5C timing outputs of video_sync are open.
--
-- clk_7_n and v8_n are both outputs AND read inside (by video_sync and
-- test_modes), so they are driven onto internal signals (s_clk_7_n,
-- s_v8_n) and copied to the ports: VHDL-93 can't read an out port.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity ula_timing is
    port (
        clk_14  : in    std_logic; -- 14 MHz crystal
        reset   : in    std_logic; -- simulation only (the real chip has none)
        rd_n    : in    std_logic; -- CPU strobes, for the wafer test modes
        wr_n    : in    std_logic;
        mreq_n  : in    std_logic;
        ioreq_n : in    std_logic;
        k0      : out   std_logic; -- keyboard pin K0 (inout at the top): only driven here, test B puts v8 on it

        clk_7   : out   std_logic; -- 7 MHz, clk_14 divided by 2
        clk_7_n : out   std_logic; -- /clk7, clocks the horizontal counter
        tclk_b  : out   std_logic; -- test B clock, to flash_clock

        hblank_n  : out   std_logic; -- horizontal blanking, active low
        vsync     : out   std_logic; -- vertical sync, lines 248..251
        border    : out   std_logic; -- '1' in the border
        border_n  : out   std_logic; -- '0' in the border
        sync_6c_n : out   std_logic; -- composite sync (6C001 timing), active low

        -- horizontal counter taps
        c0   : out   std_logic;
        c1   : out   std_logic;
        c2   : out   std_logic;
        c3   : out   std_logic;
        c4   : out   std_logic;
        c5   : out   std_logic;
        c6   : out   std_logic;
        c7   : out   std_logic;
        c8   : out   std_logic;
        c0_n : out   std_logic;
        c1_n : out   std_logic;
        c2_n : out   std_logic;
        c3_n : out   std_logic;
        c7_n : out   std_logic;
        c8_n : out   std_logic;

        -- vertical counter taps
        v0   : out   std_logic;
        v1   : out   std_logic;
        v2   : out   std_logic;
        v3   : out   std_logic;
        v4   : out   std_logic;
        v5   : out   std_logic;
        v6   : out   std_logic;
        v7   : out   std_logic;
        v8   : out   std_logic;
        v8_n : out   std_logic
    );
end entity ula_timing;

architecture structural of ula_timing is

    signal s_clk_14_n : std_logic;
    signal s_clk_7_n  : std_logic;
    signal s_tclk_a   : std_logic;
    signal s_v8_n     : std_logic;

begin

    s_clk_14_n <= not clk_14;
    clk_7_n    <= s_clk_7_n;
    v8_n       <= s_v8_n;

    master_clock : entity work.clk_div_2(behavioral)
        port map (
            clk_in    => s_clk_14_n,
            reset     => '0',
            clk_out   => clk_7,
            clk_out_n => s_clk_7_n
        );

    test_clocks : entity work.test_modes(structural)
        port map (
            v8_n    => s_v8_n,
            rd_n    => rd_n,
            ioreq_n => ioreq_n,
            mreq_n  => mreq_n,
            wr_n    => wr_n,
            k0      => k0,
            tclk_b  => tclk_b,
            tclk_a  => s_tclk_a
        );

    video_timing : entity work.video_sync(behavioral)
        port map (
            clk_7_n   => s_clk_7_n,
            reset     => reset,
            tclk_a    => s_tclk_a,
            hsync_5c  => open,
            hsync_6c  => open,
            hblank_n  => hblank_n,
            vsync     => vsync,
            border_n  => border_n,
            border    => border,
            sync_5c_n => open,
            sync_6c_n => sync_6c_n,

            c0   => c0,
            c0_n => c0_n,
            c1   => c1,
            c1_n => c1_n,
            c2   => c2,
            c2_n => c2_n,
            c3   => c3,
            c3_n => c3_n,
            c4   => c4,
            c4_n => open,
            c5   => c5,
            c5_n => open,
            c6   => c6,
            c6_n => open,
            c7   => c7,
            c7_n => c7_n,
            c8   => c8,
            c8_n => c8_n,
            v0   => v0,
            v0_n => open,
            v1   => v1,
            v1_n => open,
            v2   => v2,
            v2_n => open,
            v3   => v3,
            v3_n => open,
            v4   => v4,
            v4_n => open,
            v5   => v5,
            v5_n => open,
            v6   => v6,
            v6_n => open,
            v7   => v7,
            v7_n => open,
            v8   => v8,
            v8_n => s_v8_n
        );

end architecture structural;
