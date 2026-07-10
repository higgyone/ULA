----------------------------------------------------------------------------------
-- Module Name: pixel_serialiser_tb - Behavioral
--
-- Self-checking testbench for pixel_serialiser (the video data latch +
-- shift8 pixel register wired together — the front of the ULA video path).
--
-- What it proves, in plain words:
--   Feed a byte in on `data`, capture it in the latch, load it into the
--   shift register, then shift: the eight bits must appear on `serial_data`
--   one per falling clk edge, MOST-SIGNIFICANT BIT FIRST — the order the
--   ULA paints pixels. Two bytes are run, and the SECOND one is exercised
--   through the full latch behaviour: the byte is latched, then the `data`
--   input is scribbled over with garbage BEFORE the load edge, proving the
--   register loads the HELD byte (from the latch) and not the live input.
--   That covers the whole path end-to-end: latch capture -> hold ->
--   parallel load -> serial shift.
--
-- Polarity sanity (why we just drive the true byte on `data`):
--   data -> data_latch_8_bit -> data_out_n (active-low) -> shift8.data_n
--   (active-low). The two active-low buses cancel inside the wrapper, so a
--   TRUE byte on `data` comes out as that same TRUE byte on serial_data.
--   The TB therefore drives plain BYTE values and expects plain bits back —
--   no inversion needed here (the wrapper hides it).
--
-- Timing (same scheme as shift8_tb):
--   * The falling edge of clk is the active (commit) edge for shift8.
--   * Latch controls (`data`, `data_latch_n`) are level-sensitive; we set
--     them and wait SETTLE for the modelled gate delays before the edge.
--   * A short SETTLE after each edge lets the `after TG` delays finish
--     before serial_data is checked.
--   Any mismatch is a fatal error; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity pixel_serialiser_tb is
--  Port ( );
end pixel_serialiser_tb;

architecture Behavioral of pixel_serialiser_tb is
    constant T      : time := 20 ns;   -- clk period
    constant SETTLE : time := 6 ns;    -- > worst-case gate settle after an edge

    -- Two test patterns. Each is shifted out of serial_data MSB-first (bit7..bit0).
    constant BYTE1 : std_logic_vector(7 downto 0) := "10110100";  -- 0xB4
    constant BYTE2 : std_logic_vector(7 downto 0) := "00101101";  -- 0x2D

    signal clk          : std_logic := '0';
    signal SLoad        : std_logic := '1';                              -- start in LOAD mode
    signal data_latch_n : std_logic := '0';                             -- active-low: start transparent
    signal data         : std_logic_vector(7 downto 0) := (others => '0');
    signal serial_data  : std_logic;

    -- Check serial_data after the falling edge / stimulus just settled.
    procedure check(signal sv : in std_logic;
                    expected  : in std_logic;
                    msg       : in string) is
    begin
        assert sv = expected
            report "FAIL: " & msg & " - expected serial_data=" & std_logic'image(expected)
                 & " got " & std_logic'image(sv)
            severity failure;
        report "PASS: " & msg severity note;
    end procedure;

begin

    dut: entity work.pixel_serialiser(Structural)
        port map (
            clk          => clk,
            SLoad        => SLoad,
            data_latch_n => data_latch_n,
            data         => data,
            serial_data  => serial_data
        );

    --*****************************************************************
    -- clock: free-running, falling edge is the active (commit) edge
    --*****************************************************************
    process
    begin
        clk <= '0';
        wait for T / 2;
        clk <= '1';
        wait for T / 2;
    end process;

    --*****************************************************************
    -- stimulus + self-check
    --*****************************************************************
    process
    begin
        --------------------------------------------------------------
        -- BYTE1: transparent latch path. Latch stays open (data_latch_n
        -- ='0'), so the byte flows straight through to the shift reg's
        -- load inputs; LOAD it, then shift the 8 bits out MSB-first.
        --------------------------------------------------------------
        data         <= BYTE1;
        data_latch_n <= '0';               -- transparent: latch follows data
        SLoad        <= '1';               -- load mode
        wait for SETTLE;                   -- let the latch pass the byte through

        wait until falling_edge(clk);      -- LOAD edge: shift reg grabs BYTE1
        wait for SETTLE;
        check(serial_data, BYTE1(7), "BYTE1 load: serial_data = bit7 (MSB)");

        SLoad <= '0';                      -- switch to SHIFT for every following edge
        for i in 6 downto 0 loop
            wait until falling_edge(clk);
            wait for SETTLE;
            check(serial_data, BYTE1(i),
                  "BYTE1 shift: serial_data = bit" & integer'image(i));
        end loop;

        --------------------------------------------------------------
        -- BYTE2: full latch behaviour. Capture BYTE2 while transparent,
        -- then HOLD it (data_latch_n='1') and overwrite `data` with
        -- garbage. The LOAD edge must still load BYTE2 (the held value),
        -- proving the latch isolates the shift reg from the live input.
        --------------------------------------------------------------
        data         <= BYTE2;
        data_latch_n <= '0';               -- transparent: capture BYTE2
        wait for SETTLE;

        data_latch_n <= '1';               -- hold BYTE2 in the latch
        wait for SETTLE;
        data         <= x"FF";             -- garbage under the held latch (must be ignored)
        wait for SETTLE;

        SLoad <= '1';                      -- load mode
        wait until falling_edge(clk);      -- LOAD edge: must grab the HELD BYTE2, not 0xFF
        wait for SETTLE;
        check(serial_data, BYTE2(7), "BYTE2 load (held): serial_data = bit7 (MSB)");

        SLoad <= '0';
        for i in 6 downto 0 loop
            wait until falling_edge(clk);
            wait for SETTLE;
            check(serial_data, BYTE2(i),
                  "BYTE2 shift: serial_data = bit" & integer'image(i));
        end loop;

        report "ALL TESTS PASSED" severity note;
        wait;
    end process;

end Behavioral;
