----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 09.07.2020 15:00:16
-- Design Name:
-- Module Name: horiz_timing_tb - Behavioral
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

entity horiz_timing_tb is
--  Port ( );
end entity horiz_timing_tb;

architecture behavioral of horiz_timing_tb is

    constant t       : time      := 143 ns; -- clk period
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

    signal hsync_5c : std_logic;
    signal hsync_6c : std_logic;
    signal nhblank  : std_logic;

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

    ht : entity work.horiz_timing(Behavioral)
        port map (
            clk      => clk_7,
            reset    => reset,
            hsync_5c => hsync_5c,
            hsync_6c => hsync_6c,
            nhblank  => nhblank
        );

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
        wait for 50 ns;
        reset <= '0';
        wait for t * 100;

        wait;

    end process;

end architecture behavioral;
