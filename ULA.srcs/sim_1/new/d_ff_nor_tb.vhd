----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.06.2020 15:48:36
-- Design Name: 
-- Module Name: trce_ff_tb - Behavioral
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

entity d_ff_nor_tb is
--  Port ( );
end d_ff_nor_tb;

architecture Behavioral of d_ff_nor_tb is
    constant T    : time    := 10 ns; -- clk period
    signal clk    : std_logic;
    signal d      : std_logic;
    signal q      : std_logic;
    signal qbar   : std_logic;
begin
d_ffnor: entity work.d_ff_nor(Behavioral)
    Port map( 
        clk => clk,
        d => d,
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
        d <= '0';
        wait for 50ns;
        d <= '1';
        wait for 50ns;
        d <= '0';
        wait for 50ns;
        d <= '1';
        wait for 50ns;

        --wait for T * 100;
        wait;
   end process;
end Behavioral;
