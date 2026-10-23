----------------------------------------------------------------------------------
-- ula — the ZX Spectrum 48K ULA (Ferranti 6C001E-7), top level
--
-- Gate-accurate recreation of the Spectrum's custom chip, following Chris
-- Smith's "The ZX Spectrum ULA". This file only WIRES the verified blocks
-- together: it holds no logic of its own except the clock input inverter.
-- One port per pin of the 40-pin package; see docs/pinout.md for every pin's
-- cell, pad type and board circuit.
--
-- ── What the chip does ───────────────────────────────────────────────
--   * video timing: 448 pixels x 312 lines (PAL), border, sync, interrupt
--   * fetches the display and attribute bytes from the lower 16K DRAM and
--     turns them into pixels, colour, FLASH and the border colour
--   * analogue video out: inverted luminance /Y and the colour differences
--     U and V, with the PAL colour burst
--   * shares the lower 16K with the Z80: DRAM RAS / CAS / WE and address
--     A0..A6, ROM chip select, CPU clock contention
--   * I/O port 0xFE: keyboard and EAR in; border colour, MIC and speaker out
--   * wafer test modes (MREQ and IORQ low together)
--
-- ── Clocks ───────────────────────────────────────────────────────────
--   clk_14 (pin 39) --NOT (common-emitter stage)--> s_clk_14_n
--     --> clk_div_2 (toggles on clk_14's RISING edge)
--         Q      = s_clk_7    -> ras_cas_generation clk_7 (half-pixel phase)
--         NOT Q  = s_clk_7_n  -> the book's /clk7: all the video timing
--   latch_shift_clks: NOT /clk7 = s_clk_7_pixel (the book's clk7 pixel,
--     delay chain dropped) -> the pixel shift register
--   The inversion before the divider matters: it puts clk_7's edges just
--   after clk_14's rising edge, which ras_cas_generation relies on (no
--   resync; see CLAUDE.md). The divider has no reset, as in the book.
--
-- ── Pins and pad models ──────────────────────────────────────────────
--   Simulation models each pad (docs/pinout.md):
--     open collector + pull-up : D0..D4, D6 (do_N), K0, /INT -> '0' / 'H'
--     inverting open collector : /phicpu (pin 32)            -> '0' / 'Z'
--     tri-state totem pole     : /RAS, A0..A6                -> '0' / '1' / 'Z'
--     inputs                   : D5 (input only), K1..K4, CPU control, A14/A15
--     analogue (mV)            : /Y, U, V, SOUND out; tape_mv in
--   A0 and K0 are inout: one block drives the pin, another reads it.
--   Pin 28 (SOUND) is one analogue pin split into two ports: sound (what the
--   ULA drives) and tape_mv (what the board's EAR network adds).
--   Pull-ups are NOT modelled here (the K lines' 10k, the D bus's 8k2, pin
--   32's 1k): they belong to the board model / XDC. Weak 'H' does not
--   synthesise, so the FPGA needs 'Z' + PULLUP on those pins (Phase 7).
--
-- ── Not real pins ────────────────────────────────────────────────────
--   reset    simulation only: gives the counters a known start. The real
--            ULA has no reset; its counters power up anywhere and run.
--   tape_mv  the tape signal on pin 28, in mV (AC: can be negative).
--
-- ── Wiring conventions ───────────────────────────────────────────────
--   Every connection reads name => s_name (or name => name for a pin): one
--   net, one name. The deliberate exceptions:
--     sync_n      => s_sync_6c_n    the 6C001's composite sync (issue 6)
--     pixel_data  => s_d            both fetch latches see the whole bus,
--     attr_data   => s_d            the strobes pick which byte each takes
--   Unused outputs are open: hsync_5c/6c and sync_5c_n (inside the composite
--   sync), vid_cas_pulse, ram_16, cpuclk, ae_n and fl (used inside their
--   own blocks). Some exported counter taps have no reader; they are kept
--   for the waveform and trimmed by synthesis.
--
-- ── Blocks (instance : entity) ───────────────────────────────────────
--   master_clock      clk_div_2                            14 -> 7 MHz
--   test_clocks       test_modes                           wafer test modes, K0
--   video_timing      video_sync                           counters, border, sync
--   latch_shift_clks  latch_and_shift_reg_control_clks     fetch strobes, vid_c3_n
--   strobe_generation ras_cas_generation                   video RAS / CAS
--   mem_access        cpu_memory_access                    DRAM / ROM pins
--   video_addressing  video_address_generation             A0..A6
--   flash             flash_clock                          FLASH toggle
--   attr_select_mux   attr_output_latch_border_select_mux  pixels -> RGB
--   colour_output     yuv_video                            RGB -> /Y, U, V
--   cpu_contention    contention_handler_3                 /phicpu, contention
--   io_decode         io_port_decode_0xfe                  port read / write
--   keyboard          keyboard_input                       K0..K4 -> D0..D4
--   cassette_ip       cassette_input                       EAR -> D6
--   border            border_reg                           D0..D2 -> border colour
--   speaker_out       cassette_speaker_out                 D3, D4 -> MIC, speaker
--   sounds            sound_io                             pin 28
--   interrupts        interrupt                            /INT
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use work.yuv_levels_pkg.all;

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
        tape_mv : in    integer; -- split pin with sounds as FPGA cannot do both input and output that is not std_logic

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

        sound : out   millivolts_t; -- split pin with tape_mv as FPGA cannot do both input and output that is not std_logic

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

    flash : entity work.flash_clock(structural)
        port map (
            v8_n      => s_v8_n,
            tclk_b    => s_tclk_b,
            flash_clk => s_flash_clk
        );

    attr_select_mux : entity work.attr_output_latch_border_select_mux(structural)
        port map (
            clk_7_pixel         => s_clk_7_pixel,
            flash_clk           => s_flash_clk,
            sload               => s_sload,
            pixel_data_latch_n  => s_pixel_data_latch_n,
            pixel_data          => s_d,
            attr_data_latch_n   => s_attr_data_latch_n,
            attr_data           => s_d,
            border_colour       => s_border_colour,
            video_en            => s_video_en,
            attr_output_latch_n => s_attr_output_latch_n,
            vsync               => s_vsync,
            hblank_n            => s_hblank_n,
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
            sync_n => s_sync_6c_n,
            c4     => s_c4,
            c5     => s_c5,
            c6     => s_c6,
            c7_n   => s_c7_n,
            c8_n   => s_c8_n,
            v0     => s_v0,
            y_n    => y_n,
            u      => u,
            v      => v
        );

    cpu_contention : entity work.contention_handler_3(structural)
        port map (
            c0_n       => s_c0_n,
            a14        => a14,
            ioreq_n    => ioreq_n,
            a15        => a15,
            c2         => s_c2,
            c3         => s_c3,
            border     => s_border,
            mreq_n     => mreq_n,
            cpuclk     => open,
            phicpu_n   => phicpu_n,
            ioreqtw3_n => s_ioreqtw3_n
        );

    io_decode : entity work.io_port_decode_0xfe(structural)
        port map (
            a0         => a0,
            ioreq_n    => ioreq_n,
            ioreqtw3_n => s_ioreqtw3_n,
            rd_n       => rd_n,
            wr_n       => wr_n,
            port_rd_n  => s_port_rd_n,
            port_wr_n  => s_port_wr_n
        );

    keyboard : entity work.keyboard_input(structural)
        port map (
            k0        => k0,
            k1        => k1,
            k2        => k2,
            k3        => k3,
            k4        => k4,
            port_rd_n => s_port_rd_n,
            do_0      => d0,
            do_1      => d1,
            do_2      => d2,
            do_3      => d3,
            do_4      => d4
        );

    cassette_ip : entity work.cassette_input(structural)
        port map (
            port_rd_n => s_port_rd_n,
            ear       => s_ear,
            do_6      => d6
        );

    border : entity work.border_reg(structural)
        port map (
            di_0      => d0,
            di_1      => d1,
            di_2      => d2,
            port_wr_n => s_port_wr_n,
            b0        => s_border_colour(0),
            b1        => s_border_colour(1),
            b2        => s_border_colour(2)
        );

    speaker_out : entity work.cassette_speaker_out(structural)
        port map (
            di_3      => d3,
            di_4      => d4,
            port_wr_n => s_port_wr_n,
            mic       => s_mic,
            speaker   => s_speaker
        );

    sounds : entity work.sound_io(behavioral)
        port map (
            speaker => s_speaker,
            mic     => s_mic,
            tape_mv => tape_mv,
            sound   => sound,
            ear     => s_ear
        );

    interrupts : entity work.interrupt(structural)
        port map (
            v0    => s_v0,
            v1    => s_v1,
            v2    => s_v2,
            c6    => s_c6,
            c7    => s_c7,
            c8    => s_c8,
            vsync => s_vsync,
            int_n => int_n
        );

end architecture structural;
