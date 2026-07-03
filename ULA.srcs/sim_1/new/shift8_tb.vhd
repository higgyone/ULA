----------------------------------------------------------------------------------
-- Module Name: shift8_tb - Behavioral
--
-- Self-checking testbench for shift8 (the 8-bit parallel-load, serial-out,
-- shift-LEFT pixel register).
--
-- What it proves, in plain words:
--   Load a whole byte in one go (SLoad='1'), then flip to shift mode
--   (SLoad='0') and clock the register. The eight bits must come out of q one
--   per falling edge, MOST-SIGNIFICANT BIT FIRST — that is the order the ULA
--   paints pixels across the screen. It does this twice with two different
--   bytes, so the second load also proves the register re-loads correctly
--   (load overrides whatever was being shifted).
--
-- How the timing works (same idea as single_bit_shift_reg_tb):
--   * The falling edge of clk is the active edge; each cell commits there.
--   * Inputs are set just after a falling edge so they are stable through the
--     following clk-high sampling window and captured on the next falling edge.
--   * A short SETTLE wait after each edge lets the modelled `after TG` gate
--     delays finish before q is checked.
--   * Both data inputs of the register are ACTIVE-LOW, so the stimulus drives
--     `data_n <= not BYTE` to load the byte BYTE.
--
--   Any mismatch reports a fatal error and stops the run; a clean run prints
--   "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity shift8_tb is
--  Port ( );
end shift8_tb;

architecture Behavioral of shift8_tb is
    constant T      : time := 20 ns;   -- clk period
    constant SETTLE : time := 6 ns;    -- > worst-case gate settle after an edge

    -- Two test patterns. Each is shifted out of q MSB-first (bit7..bit0).
    constant BYTE1 : std_logic_vector(7 downto 0) := "10110100";  -- 0xB4
    constant BYTE2 : std_logic_vector(7 downto 0) := "00101101";  -- 0x2D

    signal clk    : std_logic := '0';
    signal SLoad  : std_logic := '1';                              -- start in LOAD mode
    signal Sin    : std_logic := '1';                              -- active-low serial-in: '1' feeds 0s into the LSB (don't-care here)
    signal data_n : std_logic_vector(7 downto 0) := (others => '1'); -- active-low load bus; all '1' = load 0x00
    signal q      : std_logic;
    signal q_bar  : std_logic;

    -- Check q (and that q_bar is its complement) after the falling edge just passed.
    procedure check(signal qv  : in std_logic;
                    signal qbv : in std_logic;
                    expected   : in std_logic;
                    msg        : in string) is
    begin
        assert qv = expected
            report "FAIL: " & msg & " - expected q=" & std_logic'image(expected)
                 & " got q=" & std_logic'image(qv)
            severity failure;
        assert qbv = not qv
            report "FAIL: " & msg & " - q_bar not complementary"
            severity failure;
        report "PASS: " & msg severity note;
    end procedure;

begin

    dut: entity work.shift8
        port map (
            clk    => clk,
            SLoad  => SLoad,
            Sin    => Sin,
            data_n => data_n,
            q      => q,
            q_bar  => q_bar
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
        -- BYTE1: parallel-load, then shift the 8 bits out MSB-first.
        --------------------------------------------------------------
        SLoad  <= '1';
        data_n <= not BYTE1;               -- active-low: drive the inverse of the byte
        wait until falling_edge(clk);      -- LOAD edge: all 8 cells grab BYTE1
        wait for SETTLE;
        check(q, q_bar, BYTE1(7), "BYTE1 load: q = bit7 (MSB)");

        SLoad <= '0';                      -- switch to SHIFT for every following edge
        for i in 6 downto 0 loop
            wait until falling_edge(clk);  -- one left-shift: next lower bit reaches the MSB
            wait for SETTLE;
            check(q, q_bar, BYTE1(i),
                  "BYTE1 shift: q = bit" & integer'image(i));
        end loop;

        --------------------------------------------------------------
        -- BYTE2: reload a different byte while running (proves re-load
        -- and that LOAD overrides SHIFT), then shift it out MSB-first.
        --------------------------------------------------------------
        SLoad  <= '1';
        data_n <= not BYTE2;
        wait until falling_edge(clk);      -- LOAD edge
        wait for SETTLE;
        check(q, q_bar, BYTE2(7), "BYTE2 load: q = bit7 (MSB)");

        SLoad <= '0';
        for i in 6 downto 0 loop
            wait until falling_edge(clk);
            wait for SETTLE;
            check(q, q_bar, BYTE2(i),
                  "BYTE2 shift: q = bit" & integer'image(i));
        end loop;

        report "ALL TESTS PASSED" severity note;
        wait;
    end process;

end Behavioral;
