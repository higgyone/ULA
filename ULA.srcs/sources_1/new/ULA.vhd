----------------------------------------------------------------------------------
-- ula — the ZX Spectrum 48K ULA (Ferranti 6C001E-7), top level
--
-- Gate-accurate recreation of the Spectrum's custom chip, following Chris
-- Smith's "The ZX Spectrum ULA". This file only WIRES six subsystems and the
-- interrupt block together; its only logic is gathering the data bus into
-- s_d and releasing D7. One port per pin of the 40-pin package; see
-- docs/pinout.md for every pin's cell, pad type and board circuit.
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
-- ── Subsystems (instance : entity, and the blocks inside) ────────────
--   timing_subsystem       ula_timing        clk_14 inverter, clk_div_2,
--                                            video_sync, test_modes
--   video_fetch_subsystem  ula_video_fetch   latch_and_shift_reg_control_clks,
--                                            ras_cas_generation,
--                                            video_address_generation
--   colour_subsystem       ula_colour        flash_clock,
--                                            attr_output_latch_border_select_mux,
--                                            yuv_video
--   memory_cpu_subsystem   ula_memory_cpu    cpu_memory_access,
--                                            contention_handler_3
--   io_port_subsystem      ula_io_port       io_port_decode_0xfe,
--                                            keyboard_input, border_reg
--   sound_subsystem        ula_sound         cassette_speaker_out, sound_io,
--                                            cassette_input
--   interrupts             interrupt         /INT (a single block)
--   Each subsystem is pure wiring with its own header. Nets used by only one
--   subsystem live inside it (vid_c3_n, vid_ras_n, flash_clk, mic, speaker,
--   ear, tclk_a); this file carries only the nets that cross between them.
--
--   Data flow:
--     timing --clocks, counter taps, border, sync--> everything else
--     video_fetch --fetch strobes, pixel clock--> colour
--     video_fetch --vid_ras / vid_cas--> memory_cpu --ioreqtw3_n--> io_port
--     io_port --port_rd_n / port_wr_n--> sound;  --border_colour--> colour
--
-- ── Clocks ───────────────────────────────────────────────────────────
--   clk_14 (pin 39) --NOT (common-emitter stage)--> clk_div_2 (in ula_timing)
--         Q      = s_clk_7    -> ras_cas_generation (half-pixel phase)
--         NOT Q  = s_clk_7_n  -> the book's /clk7: all the video timing
--   latch_and_shift_reg_control_clks (in ula_video_fetch): NOT /clk7 =
--     s_clk_7_pixel (the book's clk7 pixel) -> the pixel shift register.
--   The fetch strobes are registered on clk_14 (architecture synchronous).
--   The inversion before the divider puts clk_7's edges just after clk_14's
--   rising edge, which ras_cas_generation relies on (no resync; see
--   CLAUDE.md). The divider has no reset, as in the book.
--
-- ── Pins and pad models ──────────────────────────────────────────────
--   Simulation models each pad (docs/pinout.md):
--     open collector + pull-up : D0..D4, D6 (do_N), K0, /INT -> '0' / 'H'
--     inverting open collector : /phicpu (pin 32)            -> '0' / 'Z'
--     tri-state totem pole     : /RAS, A0..A6                -> '0' / '1' / 'Z'
--     inputs                   : D5 (input only), K1..K4, CPU control, A14/A15
--     analogue (mV)            : /Y, U, V, SOUND out; tape_mv in
--   A0 and K0 are inout: one subsystem drives the pin, another reads it
--   (A0: video_fetch drives, io_port reads; K0: timing's test_modes drives,
--   io_port's keyboard reads).
--   D7 is inout but nothing in the ULA drives it, so it is released to 'H'
--   here: an inout port with no driver would put its default 'U' on the bus.
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
--   net, one name. The exceptions now sit inside the subsystems:
--   sync_n => sync_6c_n (the 6C001's composite sync, in ula_colour) and
--   pixel_data / attr_data => d (both fetch latches see the whole bus, the
--   strobes pick which byte each takes).
--   A subsystem output that is also read inside its own subsystem goes
--   through an internal s_ signal and a copy line (VHDL-93 can't read an
--   out port): clk_7_n, v8_n, red/green/blue/hl, port_rd_n / port_wr_n.
--
-- ── Nets kept for the testbench ──────────────────────────────────────
--   ula_tb reads s_red, s_green, s_blue, s_hl, s_clk_7_pixel, s_vid_ras,
--   s_c0..s_c8 and s_v0..s_v8 through VHDL-2008 external names
--   (.ula_tb.dut.s_xxx). They must stay as signals in this file. s_v8 has no
--   other reader; RGB + BRIGHT are also the natural FPGA VGA output.
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
    signal s_clk_7       : std_logic;
    signal s_clk_7_n     : std_logic;
    signal s_clk_7_pixel : std_logic;

    -- test clocks
    signal s_tclk_b : std_logic;

    -- control clocks
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
    signal s_c5   : std_logic;
    signal s_c6   : std_logic;
    signal s_c7   : std_logic;
    signal s_c7_n : std_logic;
    signal s_c8   : std_logic;
    signal s_c8_n : std_logic;

    signal s_v0   : std_logic;
    signal s_v1   : std_logic;
    signal s_v2   : std_logic;
    signal s_v3   : std_logic;
    signal s_v4   : std_logic;
    signal s_v5   : std_logic;
    signal s_v6   : std_logic;
    signal s_v7   : std_logic;
    signal s_v8   : std_logic;
    signal s_v8_n : std_logic;

    -- DRAM
    signal s_vid_ras    : std_logic;
    signal s_vid_cas_ac : std_logic;
    signal s_vid_cas_bd : std_logic;

    -- colours
    signal s_border_colour : std_logic_vector(2 downto 0);
    signal s_red           : std_logic;
    signal s_green         : std_logic;
    signal s_blue          : std_logic;
    signal s_hl            : std_logic;

    -- cpu
    signal s_ioreqtw3_n : std_logic;
    signal s_port_rd_n  : std_logic;
    signal s_port_wr_n  : std_logic;

begin

    s_d <= d7 & d6 & d5 & d4 & d3 & d2 & d1 & d0; -- the data bus as one byte, for the two video fetch latches (read only)

    d7 <= 'H'; -- D7's open-collector output never pulls low: released to the weak on-chip pull-up

    timing_subsystem : entity work.ula_timing(structural)
        port map (
            clk_14    => clk_14,
            reset     => reset,
            rd_n      => rd_n,
            wr_n      => wr_n,
            mreq_n    => mreq_n,
            ioreq_n   => ioreq_n,
            k0        => k0,
            clk_7     => s_clk_7,
            clk_7_n   => s_clk_7_n,
            tclk_b    => s_tclk_b,
            hblank_n  => s_hblank_n,
            vsync     => s_vsync,
            border    => s_border,
            border_n  => s_border_n,
            sync_6c_n => s_sync_6c_n,
            c0        => s_c0,
            c0_n      => s_c0_n,
            c1        => s_c1,
            c1_n      => s_c1_n,
            c2        => s_c2,
            c2_n      => s_c2_n,
            c3        => s_c3,
            c3_n      => s_c3_n,
            c4        => s_c4,
            c5        => s_c5,
            c6        => s_c6,
            c7        => s_c7,
            c7_n      => s_c7_n,
            c8        => s_c8,
            c8_n      => s_c8_n,
            v0        => s_v0,
            v1        => s_v1,
            v2        => s_v2,
            v3        => s_v3,
            v4        => s_v4,
            v5        => s_v5,
            v6        => s_v6,
            v7        => s_v7,
            v8        => s_v8,
            v8_n      => s_v8_n
        );

    video_fetch_subsystem : entity work.ula_video_fetch(structural)
        port map (
            clk_14              => clk_14,
            clk_7               => s_clk_7,
            clk_7_n             => s_clk_7_n,
            c0                  => s_c0,
            c1                  => s_c1,
            c2                  => s_c2,
            c3                  => s_c3,
            c4                  => s_c4,
            c5                  => s_c5,
            c6                  => s_c6,
            c7                  => s_c7,
            c0_n                => s_c0_n,
            c1_n                => s_c1_n,
            c2_n                => s_c2_n,
            c3_n                => s_c3_n,
            v0                  => s_v0,
            v1                  => s_v1,
            v2                  => s_v2,
            v3                  => s_v3,
            v4                  => s_v4,
            v5                  => s_v5,
            v6                  => s_v6,
            v7                  => s_v7,
            border              => s_border,
            border_n            => s_border_n,
            a0                  => a0,
            a1                  => a1,
            a2                  => a2,
            a3                  => a3,
            a4                  => a4,
            a5                  => a5,
            a6                  => a6,
            vid_ras             => s_vid_ras,
            vid_cas_ac          => s_vid_cas_ac,
            vid_cas_bd          => s_vid_cas_bd,
            clk_7_pixel         => s_clk_7_pixel,
            pixel_data_latch_n  => s_pixel_data_latch_n,
            attr_data_latch_n   => s_attr_data_latch_n,
            attr_output_latch_n => s_attr_output_latch_n,
            sload               => s_sload,
            video_en            => s_video_en
        );

    colour_subsystem : entity work.ula_colour(structural)
        port map (
            clk_7_pixel         => s_clk_7_pixel,
            tclk_b              => s_tclk_b,
            v8_n                => s_v8_n,
            pixel_data_latch_n  => s_pixel_data_latch_n,
            attr_data_latch_n   => s_attr_data_latch_n,
            attr_output_latch_n => s_attr_output_latch_n,
            sload               => s_sload,
            video_en            => s_video_en,
            d                   => s_d,
            border_colour       => s_border_colour,
            vsync               => s_vsync,
            hblank_n            => s_hblank_n,
            sync_6c_n           => s_sync_6c_n,
            c4                  => s_c4,
            c5                  => s_c5,
            c6                  => s_c6,
            c7_n                => s_c7_n,
            c8_n                => s_c8_n,
            v0                  => s_v0,
            red                 => s_red,
            green               => s_green,
            blue                => s_blue,
            hl                  => s_hl,
            y_n                 => y_n,
            u                   => u,
            v                   => v
        );

    memory_cpu_subsystem : entity work.ula_memory_cpu(structural)
        port map (
            a14        => a14,
            a15        => a15,
            mreq_n     => mreq_n,
            ioreq_n    => ioreq_n,
            rd_n       => rd_n,
            wr_n       => wr_n,
            vid_ras    => s_vid_ras,
            vid_cas_ac => s_vid_cas_ac,
            vid_cas_bd => s_vid_cas_bd,
            c0_n       => s_c0_n,
            c2         => s_c2,
            c3         => s_c3,
            border     => s_border,
            border_n   => s_border_n,
            ras_n      => ras_n,
            cas_n      => cas_n,
            we_n       => we_n,
            rom_cs_n   => rom_cs_n,
            phicpu_n   => phicpu_n,
            ioreqtw3_n => s_ioreqtw3_n
        );

    io_port_subsystem : entity work.ula_io_port(structural)
        port map (
            a0            => a0,
            ioreq_n       => ioreq_n,
            ioreqtw3_n    => s_ioreqtw3_n,
            rd_n          => rd_n,
            wr_n          => wr_n,
            k0            => k0,
            k1            => k1,
            k2            => k2,
            k3            => k3,
            k4            => k4,
            d0            => d0,
            d1            => d1,
            d2            => d2,
            d3            => d3,
            d4            => d4,
            port_rd_n     => s_port_rd_n,
            port_wr_n     => s_port_wr_n,
            border_colour => s_border_colour
        );

    sound_subsystem : entity work.ula_sound(structural)
        port map (
            port_rd_n => s_port_rd_n,
            port_wr_n => s_port_wr_n,
            d3        => d3,
            d4        => d4,
            tape_mv   => tape_mv,
            d6        => d6,
            sound     => sound
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
