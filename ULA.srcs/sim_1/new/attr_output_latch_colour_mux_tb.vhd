----------------------------------------------------------------------------------
-- Module Name: attr_output_latch_colour_mux_tb - behavioral
--
-- Self-checking testbench for attr_output_latch_colour_mux (the attribute
-- OUTPUT latch + ink/paper colour mux + final blanking mux).
--
-- What it proves, in plain words:
--   1. LATCH: with a_o_latch_n='0' (transparent) an attribute cell is
--      captured; with a_o_latch_n='1' (hold) the colour outputs must not
--      move even when every latched input is scribbled with the opposite
--      value. Releasing the latch lets the new (scribbled) cell through —
--      proving transparency resumes.
--   2. COLOUR MUX: the per-pixel select data_select_n picks between the
--      latched INK and PAPER colours:
--        data_select_n='0' -> colour = INK      ('0' selects ink)
--        data_select_n='1' -> colour = PAPER
--      data_select_n is NOT latched (it changes every pixel), so it is
--      swept while the latch holds and the mux must still track it.
--   3. BLANKING: v_sync='1' OR h_blank='1' (h_blank_n='0') forces the
--      colour output to black (0,0,0), regardless of the mux result.
--   4. BRIGHT / FLASH pass-through: hl = latched al6_hl, fl = latched
--      al7_fl (both taken straight off the latch, ungated).
--
-- Bit packing under test (matches the DUT's latch_data_in mapping):
--   latch bit : 0    1    2    3    4    5    6    7
--   signal    : i0_b pb0_b i1_r pb1_r i2_g pb2_g al6_hl al7_fl
--   i.e. ink and paper are INTERLEAVED per colour (blue, red, green), so
--   colour output blue=mux(q0,q1), red=mux(q2,q3), green=mux(q4,q5).
--
-- Stimulus is built from named per-bit constants (ink_*, pap_*, a_bright,
-- a_flash) and the expected colours are the SAME constants, so the TB can
-- never drift from the DUT's bit map. The "scribbled" hold-test values are
-- the bitwise complements, chosen so a leaking latch would flip an output.
--
-- No clock: the latch is level-sensitive and the mux/blank logic is
-- combinational. The TB drives inputs, waits SETTLE for the modelled gate
-- delays, then checks. Any mismatch is fatal; a clean run ends with
-- "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity attr_output_latch_colour_mux_tb is
--  Port ( );
end entity attr_output_latch_colour_mux_tb;

architecture behavioral of attr_output_latch_colour_mux_tb is

    constant settle : time := 8 ns; -- > worst-case gate path (latch ~4*TG + mux NORs)

    -- Attribute cell #1 (the value we latch and expect back).
    -- INK   = green   (b=0 r=0 g=1)
    -- PAPER = magenta (b=1 r=1 g=0)
    constant ink_b    : std_logic := '0';
    constant ink_r    : std_logic := '0';
    constant ink_g    : std_logic := '1';
    constant pap_b    : std_logic := '1';
    constant pap_r    : std_logic := '1';
    constant pap_g    : std_logic := '0';
    constant a_bright : std_logic := '1';
    constant a_flash  : std_logic := '1';

    -- DUT inputs
    signal v_sync        : std_logic := '0'; -- '1' = blank (colour forced black)
    signal h_blank_n     : std_logic := '1'; -- active-low blank: '0' = blank
    signal data_select_n : std_logic := '0'; -- per-pixel select: '0'=ink, '1'=paper
    signal i0_b          : std_logic := '0';
    signal pb0_b         : std_logic := '0';
    signal i1_r          : std_logic := '0';
    signal pb1_r         : std_logic := '0';
    signal i2_g          : std_logic := '0';
    signal pb2_g         : std_logic := '0';
    signal al6_hl        : std_logic := '0';
    signal al7_fl        : std_logic := '0';
    signal a_o_latch_n   : std_logic := '0'; -- active-low latch enable: '0' transparent, '1' hold

    -- DUT outputs
    signal blue  : std_logic;
    signal red   : std_logic;
    signal green : std_logic;
    signal hl    : std_logic;
    signal fl    : std_logic;

    -- Check the three colour bits against an expected (b,r,g) triple.

    procedure check_colour (
        signal b : in std_logic;
        signal r : in std_logic;
        signal g : in std_logic;
        eb,
        er,
        eg       : in std_logic;
        msg      : in string
    ) is
    begin

        assert (b = eb) and (r = er) and (g = eg)
            report "FAIL: " & msg
                   & " - expected (b,r,g)=" & std_logic'image(eb)
                   & std_logic'image(er) & std_logic'image(eg)
                   & " got " & std_logic'image(b)
                   & std_logic'image(r) & std_logic'image(g)
            severity failure;
        report "PASS: " & msg
            severity note;

    end procedure check_colour;

    -- Check a single-bit output (bright / flash).

    procedure check_sl (
        signal s : in std_logic;
        expected : in std_logic;
        msg      : in string
    ) is
    begin

        assert s = expected
            report "FAIL: " & msg & " - expected " & std_logic'image(expected)
                   & " got " & std_logic'image(s)
            severity failure;
        report "PASS: " & msg
            severity note;

    end procedure check_sl;

begin

    dut : entity work.attr_output_latch_colour_mux(Structural)
        port map (
            v_sync        => v_sync,
            h_blank_n     => h_blank_n,
            data_select_n => data_select_n,
            i0_b          => i0_b,
            pb0_b         => pb0_b,
            i1_r          => i1_r,
            pb1_r         => pb1_r,
            i2_g          => i2_g,
            pb2_g         => pb2_g,
            al6_hl        => al6_hl,
            al7_fl        => al7_fl,
            a_o_latch_n   => a_o_latch_n,
            blue          => blue,
            red           => red,
            green         => green,
            hl            => hl,
            fl            => fl
        );

    process is
    begin

        --------------------------------------------------------------
        -- Load attribute cell #1 (transparent), no blanking, select INK.
        --------------------------------------------------------------
        a_o_latch_n   <= '0';                                                                                   -- transparent: latch follows inputs
        v_sync        <= '0';                                                                                   -- not blanking
        h_blank_n     <= '1';                                                                                   -- not blanking
        data_select_n <= '0';                                                                                   -- select INK
        i0_b          <= ink_b;
        pb0_b         <= pap_b;
        i1_r          <= ink_r;
        pb1_r         <= pap_r;
        i2_g          <= ink_g;
        pb2_g         <= pap_g;
        al6_hl        <= a_bright;
        al7_fl        <= a_flash;
        wait for settle;
        check_colour(blue, red, green, ink_b, ink_r, ink_g, "cell1 display: select ink -> colour = INK");
        check_sl(hl, a_bright, "cell1: bright = al6_hl");
        check_sl(fl, a_flash,  "cell1: flash  = al7_fl");

        -- flip the per-pixel select -> PAPER (nothing else changes)
        data_select_n <= '1';
        wait for settle;
        check_colour(blue, red, green, pap_b, pap_r, pap_g, "cell1 display: select paper -> colour = PAPER");

        --------------------------------------------------------------
        -- Blanking overrides the mux -> black, either source.
        --------------------------------------------------------------
        v_sync <= '1';                                                                                          -- vertical sync blanks
        wait for settle;
        check_colour(blue, red, green, '0', '0', '0', "v_sync: colour forced black");

        v_sync    <= '0';
        h_blank_n <= '0';                                                                                       -- horizontal blank blanks
        wait for settle;
        check_colour(blue, red, green, '0', '0', '0', "h_blank: colour forced black");

        h_blank_n <= '1';                                                                                       -- back to visible
        wait for settle;

        --------------------------------------------------------------
        -- LATCH HOLD: freeze cell #1, scribble every latched input with
        -- its complement. The colour must still reflect the HELD cell,
        -- and the (unlatched) select must still switch ink<->paper.
        --------------------------------------------------------------
        data_select_n <= '0';                                                                                   -- select INK again
        a_o_latch_n   <= '1';                                                                                   -- HOLD
        wait for settle;
        i0_b          <= not ink_b;
        pb0_b         <= not pap_b;                                                                             -- garbage under the held latch
        i1_r          <= not ink_r;
        pb1_r         <= not pap_r;
        i2_g          <= not ink_g;
        pb2_g         <= not pap_g;
        al6_hl        <= not a_bright;
        al7_fl        <= not a_flash;
        wait for settle;
        check_colour(blue, red, green, ink_b, ink_r, ink_g, "hold: colour still cell1 INK despite garbage in");
        check_sl(hl, a_bright, "hold: bright still cell1");
        check_sl(fl, a_flash,  "hold: flash  still cell1");

        -- select still works on the held cell
        data_select_n <= '1';
        wait for settle;
        check_colour(blue, red, green, pap_b, pap_r, pap_g, "hold: select paper -> held cell1 PAPER");

        --------------------------------------------------------------
        -- Release latch: the scribbled cell (#1 complemented) flows
        -- through, proving transparency resumed. New INK/PAPER are the
        -- complements of cell #1.
        --------------------------------------------------------------
        a_o_latch_n   <= '0';                                                                                   -- transparent again
        data_select_n <= '0';                                                                                   -- select INK
        wait for settle;
        check_colour(blue, red, green, not ink_b, not ink_r, not ink_g, "release: new INK flows through");
        check_sl(hl, not a_bright, "release: bright follows new cell");
        check_sl(fl, not a_flash,  "release: flash  follows new cell");

        report "ALL TESTS PASSED"
            severity note;
        wait;

    end process;

end architecture behavioral;
