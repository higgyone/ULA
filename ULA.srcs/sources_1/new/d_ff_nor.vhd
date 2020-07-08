----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 01.07.2020 11:48:59
-- Design Name: 
-- Module Name: d_ff_nor - Behavioral
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

entity d_ff_nor is
    Port ( clk : in STD_LOGIC;
           d : in STD_LOGIC;
           q : out STD_LOGIC;
           qbar : out STD_LOGIC);
end d_ff_nor;

architecture Behavioral of d_ff_nor is
    signal a_o : std_logic;
    signal b_o : std_logic;
    signal c_o : std_logic;
    signal d_o : std_logic;
    signal e_o : std_logic;
    signal f_o : std_logic;
    
begin
    a_o <= not (d_o or b_o);
    b_o <= not(a_o or clk);
    c_o <= not(b_o or clk or d_o);
    d_o <= not(d or c_o);
    e_o <= not(b_o or f_o);
    f_o <= not(c_o or e_o);
    q <= e_o;
    qbar <= f_o; 

end Behavioral;
