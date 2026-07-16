----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 29.06.2020 14:01:39
-- Design Name:
-- Module Name: master_horiz_counter_tb - Behavioral
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
    use ieee.numeric_std.all;

entity master_horiz_counter_tb is
--  Port ( );
end entity master_horiz_counter_tb;

architecture behavioral of master_horiz_counter_tb is

    -- Clock period. Use the REAL 7 MHz pixel period (143 ns). The FF
    -- library now carries `after TG` gate delays, and at a 64-count
    -- boundary the worst-case settle path (lower gated-ripple ->
    -- clk_hc6 -> T_Structure C6-C8 after-TG) stacks to ~15-20 ns. A
    -- 10 ns clock is SHORTER than that, so the count can't settle
    -- before the next sample and the self-check reads mid-ripple
    -- garbage at the boundaries. 143 ns gives T/2 = 71 ns >> settle,
    -- so every falling-edge sample is clean. (Do not drop below ~50 ns.)
    constant t       : time      := 143 ns; -- 7 MHz real pixel clock
    signal   clk_7   : std_logic;
    signal   tclk_a  : std_logic := '0';
    signal   reset   : std_logic;
    signal   c0      : std_logic;
    signal   c1      : std_logic;
    signal   c2      : std_logic;
    signal   c3      : std_logic;
    signal   c4      : std_logic;
    signal   c5      : std_logic;
    signal   c6      : std_logic;
    signal   c7      : std_logic;
    signal   c8      : std_logic;
    signal   clk_hc6 : std_logic;
    signal   hc_rst  : std_logic;

begin

    mhc : entity work.master_horiz_counter(Behavioral)
        port map (
            clk7    => clk_7,
            reset   => reset,
            tclk_a  => tclk_a,
            c0      => c0,
            c1      => c1,
            c2      => c2,
            c3      => c3,
            c4      => c4,
            c5      => c5,
            c6      => c6,
            c7      => c7,
            c8      => c8,
            clk_hc6 => clk_hc6,
            hc_rst  => hc_rst
        );

    -- *****************************************************************
    -- clock
    -- *****************************************************************
    -- 20 ns clock running forever
    process is
    begin

        clk_7 <= '0';
        wait for t / 2;
        clk_7 <= '1';
        wait for t / 2;

    end process;

    process is
    begin

        reset <= '1';
        wait for 5 * t;    -- hold reset several clock cycles
        reset <= '0';
        wait for t * 100;

        wait;

    end process;

    -- *****************************************************************
    -- Self-check: full count increments by 1 each clk7, wraps at 448
    -- *****************************************************************
    -- The full line count is the 9-bit tap concatenation c8..c0
    -- (= c_upper*64 + c_lower), which runs 0..447 (64 x 7). Rather than
    -- predict the absolute start phase (tricky with the gated clocks,
    -- synchronous reset and after-TG gate delays), we LOCK onto the
    -- actual count after reset and then assert it advances by exactly 1
    -- (mod 448) every clk7. This catches any skip, stuck bit, or wrong
    -- wrap without depending on the start phase.
    --
    -- Sampled on the FALLING edge of clk7 (mid-period), by which point
    -- the ripple chain and the T_Structure C6-C8 stage have settled.
    check_proc : process (clk_7) is

        variable taps    : std_logic_vector(8 downto 0);
        variable act     : integer range 0 to 511;
        variable expnext : integer range 0 to 447;
        variable locked  : boolean := false;

    begin

        if falling_edge(clk_7) then
            if (reset = '1') then
                locked := false;                 -- re-lock after every reset
            else
                taps := c8 & c7 & c6 & c5 & c4 & c3 & c2 & c1 & c0;
                if (not is_x(taps)) then
                    act := to_integer(unsigned(taps));
                    if (locked) then
                        assert act = expnext
                            report "MHC count mismatch: taps=" & integer'image(act) &
                                   " expected=" & integer'image(expnext)
                            severity error;
                        if (expnext = 447) then
                            report "MHC: line complete -- 448 counts verified (0..447)."
                                severity note;
                        end if;
                    end if;
                    -- predict next count and lock on
                    if (act = 447) then
                        expnext := 0;
                    else
                        expnext := act + 1;
                    end if;
                    locked := true;
                end if;
            end if;
        end if;

    end process check_proc;

end architecture behavioral;
