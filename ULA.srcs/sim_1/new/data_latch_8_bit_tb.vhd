----------------------------------------------------------------------------------
-- Module Name: data_latch_8_bit_tb - Behavioral
--
-- Self-checking testbench for data_latch_8_bit (the full 8-bit ULA video
-- data latch built from eight data_latch_1_bit cells).
--
-- What it proves, in plain words:
--   The whole byte behaves like the single cell, in parallel across all 8
--   bits, with one shared ACTIVE-LOW enable:
--     * enable='0' : transparent -> data_out follows data
--     * enable='1' : hold        -> data_out frozen, data ignored
--   and the two output buses stay opposite at all times:
--     * data_out   = the latched byte (TRUE polarity)
--     * data_out_n = its bitwise inverse (ACTIVE-LOW) -> feeds shift8 data_n
--
--   There is no clock (the latch is level-sensitive), so the TB drives
--   enable/data directly, waits SETTLE for the modelled TG gate delays inside
--   each cell to settle, then checks both buses. Coverage:
--     - transparent follow of a whole byte (and a second, different byte)
--     - latch a byte, then change EVERY data bit underneath -> must hold
--     - re-open transparent -> follows the new byte again
--     - a mid-scale pattern to catch any bit that is stuck or cross-wired
--   data_out_n is asserted to be the exact complement of data_out at every
--   check (a real consumer, shift8's active-low data_n load bus, depends on
--   it). Any mismatch is a fatal error; reaching the end prints
--   "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity data_latch_8_bit_tb is
--  Port ( );
end data_latch_8_bit_tb;

architecture Behavioral of data_latch_8_bit_tb is
    constant SETTLE : time := 5 ns;   -- > worst-case gate path inside a cell (~4*TG)

    signal enable     : std_logic := '0';                              -- active-low enable: start transparent
    signal data       : std_logic_vector(7 downto 0) := (others => '0');
    signal data_out   : std_logic_vector(7 downto 0);
    signal data_out_n : std_logic_vector(7 downto 0);

    -- Check the true bus equals the expected byte AND the inverted bus is its
    -- exact complement, after the last stimulus has settled.
    procedure check(signal outv  : in std_logic_vector(7 downto 0);
                    signal outnv : in std_logic_vector(7 downto 0);
                    expected     : in std_logic_vector(7 downto 0);
                    msg          : in string) is
    begin
        assert outv = expected
            report "FAIL: " & msg & " - expected data_out=" & integer'image(to_integer(unsigned(expected)))
                 & " got " & integer'image(to_integer(unsigned(outv)))
            severity failure;
        assert outnv = not outv
            report "FAIL: " & msg & " - data_out_n not the complement of data_out"
            severity failure;
        report "PASS: " & msg severity note;
    end procedure;

begin

    dut: entity work.data_latch_8_bit(Structural)
        port map (
            enable     => enable,
            data       => data,
            data_out   => data_out,
            data_out_n => data_out_n
        );

    --*****************************************************************
    -- stimulus + self-check (level-sensitive, no clock)
    --*****************************************************************
    process
    begin
        -- transparent (enable='0'), data=0x00 from init
        wait for SETTLE;
        check(data_out, data_out_n, x"00", "transparent: follow 0x00");

        -- transparent follow of a whole byte
        data <= x"B4";                          -- 10110100
        wait for SETTLE;
        check(data_out, data_out_n, x"B4", "transparent: follow 0xB4");

        -- latch it: enable='1' freezes the byte
        enable <= '1';
        wait for SETTLE;
        check(data_out, data_out_n, x"B4", "latch 0xB4");

        -- while latched, flip EVERY bit underneath -> must still hold 0xB4
        data <= x"4B";                          -- inverse-ish pattern; not(0xB4)=0x4B
        wait for SETTLE;
        check(data_out, data_out_n, x"B4", "hold 0xB4 while data=0x4B");

        -- re-open transparent -> now follows the new byte
        enable <= '0';
        wait for SETTLE;
        check(data_out, data_out_n, x"4B", "re-open transparent: follow 0x4B");

        -- latch the new byte
        enable <= '1';
        wait for SETTLE;
        check(data_out, data_out_n, x"4B", "latch 0x4B");

        -- while latched, drive all-ones underneath -> must hold 0x4B
        data <= x"FF";
        wait for SETTLE;
        check(data_out, data_out_n, x"4B", "hold 0x4B while data=0xFF");

        -- re-open transparent -> follows 0xFF (all bits high)
        enable <= '0';
        wait for SETTLE;
        check(data_out, data_out_n, x"FF", "re-open transparent: follow 0xFF");

        -- and back to all-zeros transparently (all bits low)
        data <= x"00";
        wait for SETTLE;
        check(data_out, data_out_n, x"00", "transparent: follow 0x00 again");

        report "ALL TESTS PASSED" severity note;
        wait;
    end process;

end Behavioral;
