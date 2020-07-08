----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 07.07.2020 13:33:46
-- Design Name: 
-- Module Name: b3_tb - Behavioral
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
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity b3_tb is
--  Port ( );
end b3_tb;

architecture Behavioral of b3_tb is
    constant T    : time    := 10 ns; -- clk period
    signal clk   : std_logic;
    signal reset  : std_logic;
    signal output : std_logic_vector (2 downto 0);
    signal overflow: std_logic;
begin
b3c: entity work.bit3_counter(Behavioral)
port map(
      clk => clk,        
      reset => reset,
      output => output,
      overflow => overflow
   );
   
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
       wait for 50ns;
      reset <= '0';
      wait for 50ns;
      reset <= '1';
       wait for 50ns;
      reset <= '0';
      wait for T * 100;
      
      wait;
   end process;

end Behavioral;
