----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 29.06.2020 09:55:58
-- Design Name: 
-- Module Name: D_FF_tb - Behavioral
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

entity D_FF_tb is
--  Port ( );
end D_FF_tb;

architecture arch of D_FF_tb is
    constant T  : time    := 10 ns; -- clk period
    signal clk  : std_logic;
    signal d    : std_logic :='0';
    signal q    : std_logic;
    signal q_bar : std_logic;
    signal qb_out :std_logic;
begin
    dFlipFlop: entity work.d_ff(Behavourial)
        port map(
            clk => clk,
            d => d,
            q => q,
            q_bar => q_bar
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
       
        d <= q_bar;
        wait;
   end process;
   --process 
--   begin 
----        d <= '1';
----        wait for 50ns;
        
----        wait for 100ns;
--        if rising_edge(clk) then
--            d <= q_bar;
--        end if;
--    end process;
    --wait for 100ns;
    --d <= qb_out;
--   d <= '1';
--   wait for 50ns;
--   qb_out <= q_bar;
--   d <= qb_out;
       --d <= q_bar;
       --wait for 50ns;
--       d <= '1';
--       wait for 50ns;
       
--      d <= '0';
--      wait for 50ns;
--      d <= '1';
--       wait for 50ns;
       
--      d <= '0';
--      wait for 50ns;
--      d <= q_bar;

end arch;
