----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 21.10.2026 16:37:50
-- Design Name:
-- Module Name: ULA - Behavioral
-- Project Name:
-- Target Devices:
-- Tool Versions:
-- Description:
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use work.yuv_levels_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
-- use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
-- library UNISIM;
-- use UNISIM.VComponents.all;

entity ula is
    port (
        clk_14  : in    std_logic;
        reset   : in    std_logic;
        rd_n    : in    std_logic;
        wr_n    : in    std_logic;
        mreq_n  : in    std_logic;
        ioreq_n : in    std_logic;
        a14     : in    std_logic;
        a15     : in    std_logic;
        tape_mv : in    integer;

        k0 : inout std_logic;
        k1 : in    std_logic;
        k2 : in    std_logic;
        k3 : in    std_logic;
        k4 : in    std_logic;

        ras_n    : out   std_logic;
        cas_n    : out   std_logic;
        we_n     : out   std_logic;
        rom_cs_n : out   std_logic;
        int_n    : out   std_logic;
        phicpu_n : out   std_logic;

        a0 : inout std_logic;
        a1 : out   std_logic;
        a2 : out   std_logic;
        a3 : out   std_logic;
        a4 : out   std_logic;
        a5 : out   std_logic;
        a6 : out   std_logic;

        y_n : out   millivolts_t;
        u   : out   millivolts_t;
        v   : out   millivolts_t;

        sound : out   millivolts_t;

        d0 : inout std_logic;
        d1 : inout std_logic;
        d2 : inout std_logic;
        d3 : inout std_logic;
        d4 : inout std_logic;
        d5 : in    std_logic;
        d6 : inout std_logic;
        d7 : inout std_logic
    );
end entity ula;

architecture structural of ula is

    -- data
    signal s_d : std_logic_vector(7 downto 0);

    -- clocks
    signal s_clk_14_n    : std_logic;
    signal s_clk_7       : std_logic;
    signal s_clk_7_n     : std_logic;
    signal s_clk_7_pixel : std_logic;

    -- test clocks
    signal s_tclk_a : std_logic;
    signal s_tclk_b : std_logic;

    -- control clocks
    signal s_vid_c3_n            : std_logic;
    signal s_pixel_data_latch_n  : std_logic;
    signal s_attr_data_latch_n   : std_logic;
    signal s_attr_output_latch_n : std_logic;
    signal s_sload               : std_logic;
    signal s_video_en            : std_logic;

    -- video
    signal s_border    : std_logic;
    signal s_border_n  : std_logic;
    signal s_vsync     : std_logic;
    signal s_hblank_n  : std_logic;
    signal s_sync_6c_n : std_logic;

    signal s_c0   : std_logic;
    signal s_c0_n : std_logic;
    signal s_c1   : std_logic;
    signal s_c1_n : std_logic;
    signal s_c2   : std_logic;
    signal s_c2_n : std_logic;
    signal s_c3   : std_logic;
    signal s_c3_n : std_logic;
    signal s_c4   : std_logic;
    signal s_c4_n : std_logic;
    signal s_c5   : std_logic;
    signal s_c5_n : std_logic;
    signal s_c6   : std_logic;
    signal s_c6_n : std_logic;
    signal s_c7   : std_logic;
    signal s_c7_n : std_logic;
    signal s_c8   : std_logic;
    signal s_c8_n : std_logic;

    signal s_v0   : std_logic;
    signal s_v0_n : std_logic;
    signal s_v1   : std_logic;
    signal s_v1_n : std_logic;
    signal s_v2   : std_logic;
    signal s_v2_n : std_logic;
    signal s_v3   : std_logic;
    signal s_v3_n : std_logic;
    signal s_v4   : std_logic;
    signal s_v4_n : std_logic;
    signal s_v5   : std_logic;
    signal s_v5_n : std_logic;
    signal s_v6   : std_logic;
    signal s_v6_n : std_logic;
    signal s_v7   : std_logic;
    signal s_v7_n : std_logic;
    signal s_v8   : std_logic;
    signal s_v8_n : std_logic;

    -- DRAM
    signal s_vid_ras    : std_logic;
    signal s_vid_ras_n  : std_logic;
    signal s_vid_cas_ac : std_logic;
    signal s_vid_cas_bd : std_logic;

    -- colours
    signal s_flash_clk     : std_logic;
    signal s_border_colour : std_logic_vector(2 downto 0);
    signal s_red           : std_logic;
    signal s_green         : std_logic;
    signal s_blue          : std_logic;
    signal s_hl            : std_logic;

    -- cpu
    signal s_ioreqtw3_n : std_logic;
    signal s_port_rd_n  : std_logic;
    signal s_port_wr_n  : std_logic;

    -- sounds
    signal s_mic     : std_logic;
    signal s_speaker : std_logic;
    signal s_ear     : std_logic;

begin

    s_d <= d7 & d6 & d5 & d4 & d3 & d2 & d1 & d0; -- the data bus as one byte, for the two video fetch latches (read only)

    s_clk_14_n <= not clk_14;

    master_clock : entity work.clk_div_2(behavioral)
        port map (
            clk_in    => s_clk_14_n,
            reset     => '0',
            clk_out   => s_clk_7,
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
            tclk_b  => s_tclk_b,
            tclk_a  => s_tclk_a
        );

    video_timing : entity work.video_sync(behavioral)
        port map (
            clk_7_n   => s_clk_7_n,
            reset     => reset,
            tclk_a    => s_tclk_a,
            hsync_5c  => open,
            hsync_6c  => open,
            hblank_n  => s_hblank_n,
            vsync     => s_vsync,
            border_n  => s_border_n,
            border    => s_border,
            sync_5c_n => open,
            sync_6c_n => s_sync_6c_n,

            c0   => s_c0,
            c0_n => s_c0_n,
            c1   => s_c1,
            c1_n => s_c1_n,
            c2   => s_c2,
            c2_n => s_c2_n,
            c3   => s_c3,
            c3_n => s_c3_n,
            c4   => s_c4,
            c4_n => s_c4_n,
            c5   => s_c5,
            c5_n => s_c5_n,
            c6   => s_c6,
            c6_n => s_c6_n,
            c7   => s_c7,
            c7_n => s_c7_n,
            c8   => s_c8,
            c8_n => s_c8_n,
            v0   => s_v0,
            v0_n => s_v0_n,
            v1   => s_v1,
            v1_n => s_v1_n,
            v2   => s_v2,
            v2_n => s_v2_n,
            v3   => s_v3,
            v3_n => s_v3_n,
            v4   => s_v4,
            v4_n => s_v4_n,
            v5   => s_v5,
            v5_n => s_v5_n,
            v6   => s_v6,
            v6_n => s_v6_n,
            v7   => s_v7,
            v7_n => s_v7_n,
            v8   => s_v8,
            v8_n => s_v8_n
        );

    latch_shift_clks : entity work.latch_and_shift_reg_control_clks (structural)
        port map (
            clk_7_n             => s_clk_7_n,
            c0_n                => s_c0_n,
            c0                  => s_c0,
            c3_n                => s_c3_n,
            c1                  => s_c1,
            c1_n                => s_c1_n,
            c2_n                => s_c2_n,
            border_n            => s_border_n,
            vid_c3_n            => s_vid_c3_n,
            clk_7_pixel         => s_clk_7_pixel,
            vid_cas_pulse       => open,
            pixel_data_latch_n  => s_pixel_data_latch_n,
            attr_data_latch_n   => s_attr_data_latch_n,
            video_en            => s_video_en,
            sload               => s_sload,
            attr_output_latch_n => s_attr_output_latch_n
        );

    strobe_generation : entity work.ras_cas_generation(synchronous)
        port map (
            clk_14     => clk_14,
            clk_7      => s_clk_7,
            c0         => s_c0,
            c1         => s_c1,
            vid_c3_n   => s_vid_c3_n,
            vid_ras    => s_vid_ras,
            vid_cas_ac => s_vid_cas_ac,
            vid_cas_bd => s_vid_cas_bd,
            vid_ras_n  => s_vid_ras_n
        );

    mem_access : entity work.cpu_memory_access(structural)
        port map (
            a14        => a14,
            a15        => a15,
            mreq_n     => mreq_n,
            wr_n       => wr_n,
            rd_n       => rd_n,
            vid_ras    => s_vid_ras,
            vid_cas_ac => s_vid_cas_ac,
            vid_cas_bd => s_vid_cas_bd,
            border_n   => s_border_n,
            ram_16     => open,
            rom_cs_n   => rom_cs_n,
            ras_n      => ras_n,
            cas_n      => cas_n,
            we_n       => we_n
        );

    video_addressing : entity work.video_address_generation(structural)
        port map (
            vid_ras_n => s_vid_ras_n,
            c0_n      => s_c0_n,
            c1        => s_c1,
            c1_n      => s_c1_n,
            c2        => s_c2,
            c2_n      => s_c2_n,
            c3        => s_c3,
            c4        => s_c4,
            c5        => s_c5,
            c6        => s_c6,
            c7        => s_c7,
            v0        => s_v0,
            v1        => s_v1,
            v2        => s_v2,
            v3        => s_v3,
            v4        => s_v4,
            v5        => s_v5,
            v6        => s_v6,
            v7        => s_v7,
            border    => s_border,
            a0        => a0,
            a1        => a1,
            a2        => a2,
            a3        => a3,
            a4        => a4,
            a5        => a5,
            a6        => a6,
            ae_n      => open
        );

end architecture structural;
