----------------------------------------------------------------------------------
-- Module Name: attr_data_latch_paper_border_mux_tb - Behavioral
--
-- Self-checking testbench for attr_data_latch_paper_border_mux (the
-- attribute latch + paper/border colour multiplexer).
--
-- What it proves, in plain words:
--   Load an attribute byte into the latch, then check the four colour
--   outputs in BOTH regions:
--     * vid_en='1' (display): paper_border = PAPER (attr bits 5:3),
--       bright/flash pass through (attr bits 6/7), ink = attr bits 2:0.
--     * vid_en='0' (border):  paper_border = BORDER colour, bright/flash
--       forced to 0. (ink is a don't-care off-screen, so not checked.)
--   It also proves the latch HOLDS: after latching a byte, the attr_data
--   input is scribbled with garbage and the outputs must not move.
--
-- Attribute byte layout under test (see the DUT header):
--   bit7 FLASH | bit6 BRIGHT | bits5:3 PAPER (GRB) | bits2:0 INK (GRB)
--
-- Expected values are taken as SLICES of the stimulus constants
-- (e.g. paper = ATTR(5 downto 3)) so the TB never hand-computes a colour
-- and can't drift from the DUT's bit map.
--
-- No clock: the latch is level-sensitive and the mux is combinational, so
-- the TB drives inputs, waits SETTLE for the modelled gate delays, then
-- checks. Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity attr_data_latch_paper_border_mux_tb is
--  Port ( );
end attr_data_latch_paper_border_mux_tb;

architecture Behavioral of attr_data_latch_paper_border_mux_tb is
    constant SETTLE : time := 6 ns;    -- > worst-case gate path (latch TG + mux NORs)

    --                                   7 6 543 210
    --                                   F B PPP III
    constant ATTR1   : std_logic_vector(7 downto 0) := "10111010"; -- flash=1 bright=0 paper=111 ink=010
    constant ATTR2   : std_logic_vector(7 downto 0) := "01000101"; -- flash=0 bright=1 paper=000 ink=101
    constant BORDER1 : std_logic_vector(2 downto 0) := "100";      -- green
    constant BORDER2 : std_logic_vector(2 downto 0) := "011";      -- red+blue (magenta)

    signal attr_data     : std_logic_vector(7 downto 0) := (others => '0');
    signal attr_latch_n  : std_logic := '0';                       -- active-low: start transparent
    signal border_colour : std_logic_vector(2 downto 0) := (others => '0');
    signal vid_en        : std_logic := '1';                       -- start in display area
    signal ink           : std_logic_vector(2 downto 0);
    signal paper_border  : std_logic_vector(2 downto 0);
    signal al6_hl        : std_logic;
    signal al7_fl        : std_logic;

    procedure check_slv(signal v : in std_logic_vector(2 downto 0);
                        expected  : in std_logic_vector(2 downto 0);
                        msg       : in string) is
    begin
        assert v = expected
            report "FAIL: " & msg severity failure;
        report "PASS: " & msg severity note;
    end procedure;

    procedure check_sl(signal s : in std_logic;
                       expected  : in std_logic;
                       msg       : in string) is
    begin
        assert s = expected
            report "FAIL: " & msg & " - expected " & std_logic'image(expected)
                 & " got " & std_logic'image(s)
            severity failure;
        report "PASS: " & msg severity note;
    end procedure;

begin

    dut: entity work.attr_data_latch_paper_border_mux(Structural)
        port map (
            attr_data     => attr_data,
            attr_latch_n  => attr_latch_n,
            border_colour => border_colour,
            vid_en        => vid_en,
            ink           => ink,
            paper_border  => paper_border,
            al6_hl        => al6_hl,
            al7_fl        => al7_fl
        );

    process
    begin
        --------------------------------------------------------------
        -- ATTR1, transparent latch. Display area first.
        --------------------------------------------------------------
        attr_data     <= ATTR1;
        border_colour <= BORDER1;
        attr_latch_n  <= '0';              -- transparent: latch follows attr_data
        vid_en        <= '1';              -- display area
        wait for SETTLE;
        check_slv(ink,          ATTR1(2 downto 0), "ATTR1 display: ink = attr(2:0)");
        check_slv(paper_border, ATTR1(5 downto 3), "ATTR1 display: paper_border = PAPER (attr 5:3)");
        check_sl (al6_hl,       ATTR1(6),          "ATTR1 display: bright = attr(6)");
        check_sl (al7_fl,       ATTR1(7),          "ATTR1 display: flash = attr(7)");

        -- same byte, now the border region
        vid_en <= '0';
        wait for SETTLE;
        check_slv(paper_border, BORDER1, "ATTR1 border: paper_border = BORDER colour");
        check_sl (al6_hl,       '0',     "ATTR1 border: bright forced 0");
        check_sl (al7_fl,       '0',     "ATTR1 border: flash forced 0");
        check_slv(ink,          ATTR1(2 downto 0), "ATTR1 border: ink unchanged (ungated)");

        --------------------------------------------------------------
        -- Latch HOLD: freeze ATTR1, scribble garbage on attr_data, and
        -- confirm the display outputs still reflect the held byte.
        --------------------------------------------------------------
        attr_latch_n <= '1';               -- hold
        wait for SETTLE;
        attr_data    <= (others => '1');    -- garbage under the held latch
        vid_en       <= '1';               -- back to display area
        wait for SETTLE;
        check_slv(ink,          ATTR1(2 downto 0), "hold: ink still ATTR1 despite garbage in");
        check_slv(paper_border, ATTR1(5 downto 3), "hold: paper still ATTR1 despite garbage in");
        check_sl (al6_hl,       ATTR1(6),          "hold: bright still ATTR1");
        check_sl (al7_fl,       ATTR1(7),          "hold: flash still ATTR1");

        --------------------------------------------------------------
        -- ATTR2, transparent again, different border. Both regions.
        --------------------------------------------------------------
        attr_latch_n  <= '0';              -- transparent
        attr_data     <= ATTR2;
        border_colour <= BORDER2;
        vid_en        <= '1';
        wait for SETTLE;
        check_slv(ink,          ATTR2(2 downto 0), "ATTR2 display: ink = attr(2:0)");
        check_slv(paper_border, ATTR2(5 downto 3), "ATTR2 display: paper_border = PAPER (attr 5:3)");
        check_sl (al6_hl,       ATTR2(6),          "ATTR2 display: bright = attr(6)");
        check_sl (al7_fl,       ATTR2(7),          "ATTR2 display: flash = attr(7)");

        vid_en <= '0';
        wait for SETTLE;
        check_slv(paper_border, BORDER2, "ATTR2 border: paper_border = BORDER colour");
        check_sl (al6_hl,       '0',     "ATTR2 border: bright forced 0");
        check_sl (al7_fl,       '0',     "ATTR2 border: flash forced 0");

        report "ALL TESTS PASSED" severity note;
        wait;
    end process;

end Behavioral;
