----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 08.07.2020 11:47:09
-- Design Name: 
-- Module Name: Vert_Line_counter - Behavioral
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
use IEEE.NUMERIC_STD.ALL;

entity Vert_Line_counter is
    Port ( HCrst_Enable : in STD_LOGIC;
           Clk_HC6 : in STD_LOGIC;
           V0 : out STD_LOGIC;
           V1 : out STD_LOGIC;
           V2 : out STD_LOGIC;
           V3 : out STD_LOGIC;
           V4 : out STD_LOGIC;
           V5 : out STD_LOGIC;
           V6 : out STD_LOGIC;
           V7 : out STD_LOGIC;
           V8 : out STD_LOGIC);
end Vert_Line_counter;

architecture Behavioral of Vert_Line_counter is
constant v_max : unsigned( 8 downto 0 ) := "100110111"; -- 312 lines
signal output_cnt:  unsigned( 8 downto 0 ) := (others => '0');
begin
process (Clk_HC6, HCrst_Enable)
  begin
    if falling_edge(Clk_HC6) then  
      if HCrst_Enable = '1' then                  
        output_cnt <= output_cnt + 1;
        if output_cnt = v_max then
            output_cnt <= (others => '0');
         end if;       
      end if;
    end if;
  end process;

V0 <= output_cnt(0);
V1 <= output_cnt(1);
V2 <= output_cnt(2);
V3 <= output_cnt(3);
V4 <= output_cnt(4);
V5 <= output_cnt(5);
V6 <= output_cnt(6);
V7 <= output_cnt(7);
V8 <= output_cnt(8);
end Behavioral;
