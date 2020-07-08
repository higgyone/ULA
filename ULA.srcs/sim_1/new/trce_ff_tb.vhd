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

entity trce_ff_tb is
--  Port ( );
end trce_ff_tb;

architecture Behavioral of trce_ff_tb is
    constant T    : time    := 10 ns; -- clk period
    signal clk    : std_logic;
    signal enable : std_logic;
    signal reset  : std_logic;
    signal carry  : std_logic;
    signal q      : std_logic;
    signal qbar   : std_logic;
begin
trce: entity work.trce_ff(Behavioral)
    Port map( 
        enable  => enable,
        clk => clk,
        reset => reset,
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
        reset <= '1';
        enable <= '0';
        wait for 50ns;
        reset <= '0';
        wait for 50ns;
        enable <= '1';
        wait for 50ns;
        enable <= '0';
        wait for 50ns;
        enable <= '1';
        wait for 50ns;
        reset <= '1';
        wait for 50ns;
        reset <= '0';
        wait for 40ns;
        enable <= '0';
        wait for 50ns;
        enable <= '1';
        wait;
   end process;
end Behavioral;
