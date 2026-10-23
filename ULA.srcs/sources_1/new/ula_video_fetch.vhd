----------------------------------------------------------------------------------
-- ula_video_fetch — video fetch subsystem: DRAM strobes, address, latch strobes
--
-- One of the ULA.vhd subsystems. In the display area the ULA reads two bytes
-- from the lower 16K DRAM every 4 pixels (pixel byte, then attribute byte),
-- twice per 8-pixel cell. This subsystem times those fetches:
--
--   latch_and_shift_reg_control_clks (synchronous)
--                       from the counter low bits: the pixel clock, the strobes
--                       that latch the two bytes off the data bus, the shift
--                       register load (sload), the attribute output latch,
--                       video_en, and vid_c3_n (= border OR c3_n) which gates
--                       the fetches to the display area
--   ras_cas_generation  the video DRAM strobes vid_ras / vid_cas_ac /
--                       vid_cas_bd (merged with the CPU's in cpu_memory_access)
--                       and vid_ras_n
--   video_address_generation
--                       the Spectrum's scrambled screen address from the C/V
--                       counters, row then column on A0..A6, switched by
--                       vid_ras_n
--
--      taps, clk_14, clk_7 --> latch_and_shift_reg_control_clks --> latch strobes,
--                                     | vid_c3_n                     pixel clock
--                                     v
--                              ras_cas_generation --> vid_ras, vid_cas_ac/bd
--                                     | vid_ras_n
--                                     v
--      taps, border ---------> video_address_generation --> a0..a6
--
-- Pure wiring: no logic of its own. vid_c3_n and vid_ras_n are internal
-- (s_vid_c3_n, s_vid_ras_n). Unused outputs left open: vid_cas_pulse (no
-- consumer, cpu_memory_access takes vid_cas_ac / vid_cas_bd) and ae_n.
--
-- a0 is an out here although the A0 pin is inout at the top level: this
-- subsystem only drives it, io_port_decode_0xfe is the one that reads it.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity ula_video_fetch is
    port (
        clk_14  : in    std_logic; -- 14 MHz crystal: clocks the synchronous strobes
        clk_7   : in    std_logic; -- 7 MHz (half-pixel phase bit for the strobes)
        clk_7_n : in    std_logic; -- /clk7

        -- horizontal counter taps
        c0   : in    std_logic;
        c1   : in    std_logic;
        c2   : in    std_logic;
        c3   : in    std_logic;
        c4   : in    std_logic;
        c5   : in    std_logic;
        c6   : in    std_logic;
        c7   : in    std_logic;
        c0_n : in    std_logic;
        c1_n : in    std_logic;
        c2_n : in    std_logic;
        c3_n : in    std_logic;

        -- vertical counter taps
        v0 : in    std_logic;
        v1 : in    std_logic;
        v2 : in    std_logic;
        v3 : in    std_logic;
        v4 : in    std_logic;
        v5 : in    std_logic;
        v6 : in    std_logic;
        v7 : in    std_logic;

        border   : in    std_logic; -- '1' in the border (no fetches)
        border_n : in    std_logic; -- '0' in the border

        -- DRAM address pins (the ULA drives them only during a video fetch)
        a0 : out   std_logic;
        a1 : out   std_logic;
        a2 : out   std_logic;
        a3 : out   std_logic;
        a4 : out   std_logic;
        a5 : out   std_logic;
        a6 : out   std_logic;

        -- video DRAM strobes, merged with the CPU's in cpu_memory_access
        vid_ras    : out   std_logic;
        vid_cas_ac : out   std_logic;
        vid_cas_bd : out   std_logic;

        -- to the colour datapath
        clk_7_pixel         : out   std_logic; -- pixel clock for the shift register
        pixel_data_latch_n  : out   std_logic;
        attr_data_latch_n   : out   std_logic;
        attr_output_latch_n : out   std_logic;
        sload               : out   std_logic;
        video_en            : out   std_logic
    );
end entity ula_video_fetch;

architecture structural of ula_video_fetch is

    signal s_vid_c3_n  : std_logic;
    signal s_vid_ras_n : std_logic;

begin

    latch_shift_clks : entity work.latch_and_shift_reg_control_clks (synchronous)
        port map (
            clk_14              => clk_14,
            clk_7               => clk_7,
            clk_7_n             => clk_7_n,
            c0_n                => c0_n,
            c0                  => c0,
            c2                  => c2,
            c3_n                => c3_n,
            c1                  => c1,
            c1_n                => c1_n,
            c2_n                => c2_n,
            border_n            => border_n,
            vid_c3_n            => s_vid_c3_n,
            clk_7_pixel         => clk_7_pixel,
            vid_cas_pulse       => open,
            pixel_data_latch_n  => pixel_data_latch_n,
            attr_data_latch_n   => attr_data_latch_n,
            video_en            => video_en,
            sload               => sload,
            attr_output_latch_n => attr_output_latch_n
        );

    strobe_generation : entity work.ras_cas_generation(synchronous)
        port map (
            clk_14     => clk_14,
            clk_7      => clk_7,
            c0         => c0,
            c1         => c1,
            vid_c3_n   => s_vid_c3_n,
            vid_ras    => vid_ras,
            vid_cas_ac => vid_cas_ac,
            vid_cas_bd => vid_cas_bd,
            vid_ras_n  => s_vid_ras_n
        );

    video_addressing : entity work.video_address_generation(structural)
        port map (
            vid_ras_n => s_vid_ras_n,
            c0_n      => c0_n,
            c1        => c1,
            c1_n      => c1_n,
            c2        => c2,
            c2_n      => c2_n,
            c3        => c3,
            c4        => c4,
            c5        => c5,
            c6        => c6,
            c7        => c7,
            v0        => v0,
            v1        => v1,
            v2        => v2,
            v3        => v3,
            v4        => v4,
            v5        => v5,
            v6        => v6,
            v7        => v7,
            border    => border,
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
