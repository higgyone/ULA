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

    signal s_k0 : std_logic;

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

end architecture structural;
