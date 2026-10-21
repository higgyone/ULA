----------------------------------------------------------------------------------
-- test_modes — wafer-test clock modes (fast video frame and flash counter)
--
-- A frame takes 20 ms and a FLASH period 0.64 s, far too slow to test
-- every chip on the wafer. Two test modes let the wafer probe clock the slow
-- counters directly from a CPU strobe pin, at up to 20 MHz.
--
-- ── Entering a test mode ─────────────────────────────────────────────
--   Both modes need MREQ and IORQ low TOGETHER. A real Z80 never does that,
--   so the chip can never enter a test mode in a Spectrum. The level of the
--   other strobe picks the mode, and the strobe left free is the test clock:
--
--     mode  held       clock  output                   drives
--     ----  ---------  -----  -----------------------  ----------------------
--      A    WR high    rd_n   tclk_a = NOT rd_n       master_horiz_counter
--                                                      tclk_a (C6..C8, hc6)
--      B    RD high    wr_n   tclk_b = NOT wr_n       flash_clock tclk_b
--
--   Outside its test mode each output is '0'. That matters: both feed a NOR
--   that must see '0' in normal operation, so that it passes c5 / v8 through:
--     master_horiz_counter  clk_hc6  = NOR(tclk_a, c5_n)
--     flash_clock           clock_in = NOR(v8_n, tclk_b)
--   In test mode the strobe takes over only while the other NOR input is
--   '0' (c5 = 1 for A, v8 = 1 for B).
--
-- ── The gates ────────────────────────────────────────────────────────
--   tclk_a   = NOR(ioreq_n, mreq_n, rd_n, s_wr)      s_wr = NOT wr_n
--   s_tclk_b = NOR(s_rd, wr_n, ioreq_n, mreq_n)      s_rd = NOT rd_n
--   tclk_b   = s_tclk_b
--   s_k0_n    = NOR(v8_n, s_tclk_b_n)                    s_tclk_b_n = NOT s_tclk_b
--   k0        = '0' when s_k0_n = '1', else 'H'       (open-collector pad)
--   Each decode takes its clock strobe directly and the other strobe
--   inverted, as the "held high" condition.
--
-- ── Speed-up ─────────────────────────────────────────────────────────
--   A: rd_n clocks C6..C8 (divide by 7), whose wrap clocks the line counter:
--      20 MHz / 7 = 2.86 MHz line rate instead of 15.625 kHz.
--   B: wr_n clocks the flash counter (divide by 32):
--      20 MHz / 32 = 625 kHz instead of 50 Hz / 32 = 1.5625 Hz.
--
-- ── K0: the v8 monitor ───────────────────────────────────────────────
--   In test mode B the K0 pin carries v8_n (while wr_n is low), so the probe
--   can see when v8_n is low, which is when wr_n can clock the flash counter.
--
--   K0 is also a keyboard column input (keyboard_input). Its pad has the
--   usual emitter-follower input buffer and WEAK on-chip pull-up of the
--   keyboard pins, plus an open-collector output that only K0 has. The
--   book's gate is k0_n = NOR(v8_n, tclkb): the complement of the pin. When
--   k0_n = '1' the output transistor pulls K0 low; otherwise it lets go and
--   the weak pull-up holds the pin high, so:
--
--                     s_tclk_b_n  s_k0_n  K0 pin
--     normal             1       0     'H'  released: keyboard works
--     test B, wr_n low   0       v8    v8_n ('0' while v8 is high)
--
--   Outside test mode B the pin is always released, so a key on column 0
--   can pull it low with no clash. Modelled as '0' / 'H', like int_n and the
--   D pins.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   v8_n      line counter bit 8, complement
--   rd_n      Z80 /RD: test A clock
--   ioreq_n   ULA /IORQ pin
--   mreq_n    Z80 /MREQ
--   wr_n      Z80 /WR: test B clock
--   k0        K0 pin, open collector: v8_n in test B, else released ('H')
--   tclk_b   test clock B to flash_clock ('0' outside test B)
--   tclk_a   test clock A to master_horiz_counter ('0' outside test A)
--
-- Verified by test_modes_tb.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity test_modes is
    port (
        v8_n    : in    std_logic;
        rd_n    : in    std_logic;
        ioreq_n : in    std_logic;
        mreq_n  : in    std_logic;
        wr_n    : in    std_logic;
        k0      : out   std_logic;
        tclk_b  : out   std_logic;
        tclk_a  : out   std_logic
    );
end entity test_modes;

architecture structural of test_modes is

    signal s_rd       : std_logic;
    signal s_wr       : std_logic;
    signal s_tclk_b_n : std_logic;
    signal s_tclk_b   : std_logic;
    signal s_k0_n     : std_logic;

begin

    s_rd <= not(rd_n);
    s_wr <= not(wr_n);

    -- Test mode B: MREQ and IORQ held low together (never happens on a real
    -- Z80) with RD high. tclk_b then follows wr_n (inverted), so the tester
    -- can use wr_n directly as a clock. Outside test mode B it is '0'.
    -- tclk_b drives the tclk_b input of flash_clock, where
    -- clock_in = NOR(v8_n, tclk_b): wr_n overrides v8 as the flash
    -- counter's clock. The counter divides by 32, so with wr_n
    -- toggled at 20 MHz the flash signal runs at 20 MHz / 32 = 625 kHz
    -- instead of the normal 50 Hz / 32 = 1.5625 Hz, which speeds up testing.
    s_tclk_b   <= not(s_rd or wr_n or ioreq_n or mreq_n);
    s_tclk_b_n <= not(s_tclk_b);
    tclk_b     <= s_tclk_b;

    -- Test mode B monitor: v8_n is output on the K0 pin so the wafer probe
    -- can see when v8_n is low. Only then can tclk_b take control of the
    -- flash counter's clock, since clock_in = NOR(v8_n, tclk_b) is held at
    -- '0' while v8_n is high. s_k0_n is the book's k0_n, the complement of
    -- the pin.
    s_k0_n <= not(v8_n or s_tclk_b_n);

    -- open-collector output: pull K0 low, otherwise release it to the weak
    -- on-chip pull-up so the keyboard matrix can drive it
    k0 <= '0' when s_k0_n = '1' else
          'H';

    -- Test mode A: MREQ and IORQ held low together (never happens on a real
    -- Z80) with WR high. tclk_a then follows rd_n (inverted), so the tester
    -- can use rd_n directly as a clock. tclk_a drives the tclk_a input of
    -- master_horiz_counter, where clk_hc6 = NOR(tclk_a, c5_n): rd_n clocks
    -- C6..C8 directly (hc6), skipping C0..C5. C6..C8 divide by 7, and their
    -- wrap clocks the line counter, so with rd_n toggled at 20 MHz the video
    -- frame advances at 20 MHz / 7 = 2.86 MHz instead of the normal
    -- 15.625 kHz line rate, which speeds up testing a whole frame.
    tclk_a <= not(ioreq_n or mreq_n or rd_n or s_wr);

end architecture structural;
