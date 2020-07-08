----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 01.07.2020 14:23:53
-- Design Name: 
-- Module Name: tce_ff_tb - Behavioral
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


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity tce_ff_tb is
--  Port ( );
end tce_ff_tb;

architecture Behavioral of tce_ff_tb is
    constant T    : time    := 10 ns; -- clk period
    signal clk    : std_logic;
    signal enable : std_logic;
    signal carry  : std_logic;
    signal q      : std_logic;
    signal qbar   : std_logic;
begin
tce: entity work.tce_ff(Behavioral)
    Port map( 
        enable  => enable,
        clk => clk,
        carry => carry,
        q => q,
        qbar => qbar
        );
        
           --*****************************************************************
   -- clock
   --*****************************************************************
   -- 20 ns clock running forever
   process
   begin
      clk <= '0';
      wait for T / 2;
      clk <= '1';
      wait for T / 2;
   end process;

    process
    begin
        enable <= '0';
        wait for 50ns;
        enable <= '1'; 
        wait for 100ns;
        enable <= '0';
        wait for 50ns;
        enable <= '1';
        wait for 10ns;
        enable <= '0';
        wait for 50ns;
        enable <= '1';
        wait;
    end process;
end Behavioral;
