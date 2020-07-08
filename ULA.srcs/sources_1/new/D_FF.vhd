library IEEE;
use IEEE.STD_LOGIC_1164.ALL;


entity d_ff is
    Port ( clk : in std_logic;
           d : in std_logic ;
           q : out std_logic;
           q_bar : out std_logic);
end d_ff;

architecture Behavourial of d_ff is
signal d_sig : std_logic := '0';
begin
    process(clk)
    begin
        if falling_edge(clk) then
            d_sig <= d;
        end if;
        q <= d_sig;
        q <= not d_sig;
    end process;
end Behavourial;
