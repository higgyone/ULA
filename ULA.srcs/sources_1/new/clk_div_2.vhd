----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.06.2020 10:57:19
-- Design Name: 
-- Module Name: clk_div_2 - Behavioral
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

entity clk_div_2 is
    port (
            reset : in std_logic;
            clk_in : in std_logic;
            clk_out : out std_logic;
            clk_out_n : out std_logic
          );
end clk_div_2;

architecture Behavioral of clk_div_2 is
signal clk_state : std_logic;
    begin
        process (clk_in,reset)
        begin
             if reset = '1' then
                clk_state <= '0';
             elsif falling_edge(clk_in) then
                clk_state <= not clk_state;
             end if;
        end process;
    clk_out <= clk_state;
    clk_out_n <= not clk_state;
end Behavioral;
