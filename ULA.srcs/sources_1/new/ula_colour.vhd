----------------------------------------------------------------------------------
-- ula_colour — colour subsystem: fetched bytes -> RGB + BRIGHT -> Y, U, V
--
-- One of the ULA.vhd subsystems. It takes the pixel and attribute bytes off
-- the data bus (latched by the strobes from ula_video_fetch) and turns them
-- into the three analogue video outputs:
--
--   flash_clock         the FLASH toggle: v8 divided by 32 (~1.56 Hz), or
--                       the test B clock tclk_b
--   attr_output_latch_border_select_mux
--                       the whole digital datapath: pixel latch + shift
--                       register, attribute double buffer, FLASH swap,
--                       ink / paper / border mux and blanking -> red, green,
--                       blue, hl (BRIGHT)
--   yuv_video           RGB + BRIGHT + sync + colour burst -> y_n, u, v in
--                       millivolts (the analogue resistor network)
--
--      v8_n, tclk_b --> flash_clock --flash_clk--+
--                                                v
--      d, strobes, border_colour --> attr_output_latch_border_select_mux
--                                                | red, green, blue, hl
--                                                v
--      sync_6c_n, burst taps ----------------> yuv_video --> y_n, u, v
--
-- Pure wiring: no logic of its own. flash_clk is internal (s_flash_clk);
-- the FLASH bit output fl is unused (open).
--
-- red, green, blue and hl are exported as well as used inside: ula_tb reads
-- them, and digital RGB + BRIGHT is what an FPGA board would use for VGA.
-- Because they are read inside, they are driven onto s_red .. s_hl and
-- copied to the ports (VHDL-93 can't read an out port).
--
-- Blanking: attr_output_latch_border_select_mux forces RGB to '0' in h-blank
-- and vsync, which yuv_video requires (the colour burst sits in h-blank).
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use work.yuv_levels_pkg.all;

entity ula_colour is
    port (
        clk_7_pixel : in    std_logic; -- pixel clock
        tclk_b      : in    std_logic; -- test B clock for the FLASH divider
        v8_n        : in    std_logic; -- FLASH divider clock (once a frame)

        -- fetch strobes, from ula_video_fetch
        pixel_data_latch_n  : in    std_logic;
        attr_data_latch_n   : in    std_logic;
        attr_output_latch_n : in    std_logic;
        sload               : in    std_logic;
        video_en            : in    std_logic;

        d             : in    std_logic_vector(7 downto 0); -- data bus, read during fetches
        border_colour : in    std_logic_vector(2 downto 0); -- from border_reg

        vsync     : in    std_logic;
        hblank_n  : in    std_logic;
        sync_6c_n : in    std_logic;

        -- counter taps for the colour burst
        c4   : in    std_logic;
        c5   : in    std_logic;
        c6   : in    std_logic;
        c7_n : in    std_logic;
        c8_n : in    std_logic;
        v0   : in    std_logic;

        -- digital colour (also read by ula_tb; usable for VGA on the FPGA)
        red   : out   std_logic;
        green : out   std_logic;
        blue  : out   std_logic;
        hl    : out   std_logic;

        -- analogue outputs (pins)
        y_n : out   millivolts_t;
        u   : out   millivolts_t;
        v   : out   millivolts_t
    );
end entity ula_colour;

architecture structural of ula_colour is

    signal s_flash_clk : std_logic;
    signal s_red       : std_logic;
    signal s_green     : std_logic;
    signal s_blue      : std_logic;
    signal s_hl        : std_logic;

begin

    red   <= s_red;
    green <= s_green;
    blue  <= s_blue;
    hl    <= s_hl;

    flash : entity work.flash_clock(structural)
        port map (
            v8_n      => v8_n,
            tclk_b    => tclk_b,
            flash_clk => s_flash_clk
        );

    attr_select_mux : entity work.attr_output_latch_border_select_mux(structural)
        port map (
            clk_7_pixel         => clk_7_pixel,
            flash_clk           => s_flash_clk,
            sload               => sload,
            pixel_data_latch_n  => pixel_data_latch_n,
            pixel_data          => d,
            attr_data_latch_n   => attr_data_latch_n,
            attr_data           => d,
            border_colour       => border_colour,
            video_en            => video_en,
            attr_output_latch_n => attr_output_latch_n,
            vsync               => vsync,
            hblank_n            => hblank_n,
            blue                => s_blue,
            green               => s_green,
            red                 => s_red,
            hl                  => s_hl,
            fl                  => open
        );

    colour_output : entity work.yuv_video(structural)
        port map (
            red    => s_red,
            green  => s_green,
            blue   => s_blue,
            hl     => s_hl,
            sync_n => sync_6c_n,
            c4     => c4,
            c5     => c5,
            c6     => c6,
            c7_n   => c7_n,
            c8_n   => c8_n,
            v0     => v0,
            y_n    => y_n,
            u      => u,
            v      => v
        );

end architecture structural;
