----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date: 18.09.2026 12:41:26
-- Design Name:
-- Module Name: yuv - Behavioural
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

package yuv_levels_pkg is

    -- Top of range: 5.0 V rail - 0.7 V Vbe, no current sinks conducting.
    constant v_top : integer := 4300;

    -- All video voltages in this design are integer MILLIVOLTS,
    -- measured at the output transistor's emitter.

    subtype millivolts_t is integer range 0 to V_TOP;

end package yuv_levels_pkg;

library ieee;
    use ieee.std_logic_1164.all;
    use work.yuv_levels_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
-- use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
-- library UNISIM;
-- use UNISIM.VComponents.all;

entity yuv is
    port (
        -- Y_n group
        hl_n    : in    std_logic;
        red_i   : in    std_logic;
        green_i : in    std_logic;
        blue_i  : in    std_logic;
        sync_n  : in    std_logic;
        y_n     : out   millivolts_t; -- millivolts

        -- U group
        red_ii_n   : in    std_logic;
        green_ii_n : in    std_logic;
        blue_ii    : in    std_logic;
        burst_ii_n : in    std_logic;
        u          : out   millivolts_t; -- millivolts

        -- V group
        red_star     : in    std_logic;
        green_star_n : in    std_logic;
        blue_star_n  : in    std_logic;
        burst_star   : in    std_logic;
        burst_star_n : in    std_logic;
        v            : out   millivolts_t -- millivolts
    );
end entity yuv;

architecture behavioural of yuv is

    -- Y Channel
    -- ── Voltage contributions, in millivolts ────────────────────────
    -- Output transistor saturates: it can drop at most 4.041 V across R2,
    -- so y_n cannot fall below 4.300 - 4.041 = 0.259 V. Only bright white
    -- (sum 4359 mV) exceeds this; every other combination is below the limit.
    constant v_min_y : integer := 259;

    -- Sync
    constant v_sync_y : integer := 1851; -- 0.597 mA x 3.1k = 1850.7 mV

    -- Blue
    constant v_blue_y    : integer := 285; -- 0.092 mA x 3.1k =  285.2 mV
    constant v_blue_br_y : integer := 366; -- 0.118 mA x 3.1k =  365.8 mV

    -- Red
    constant v_red_y    : integer := 552; -- 0.178 mA x 3.1k =  551.8 mV
    constant v_red_br_y : integer := 725; -- 0.234 mA x 3.1k =  725.4 mV

    -- Green
    constant v_green_y    : integer := 1079; -- 0.348 mA x 3.1k =  1078.8 mV
    constant v_green_br_y : integer := 1417; -- 0.457 mA x 3.1k =  1416.7 mV

    -- Unclamped sum. MUST allow negative values
    -- bright white reaches -59 mV before clamping, so this cannot be millivolts_t.
    signal y_raw_y : integer range -100 to V_TOP;
    -- ── Per-signal contributions selected by the colour inputs ──────
    signal v_sync_c_y  : millivolts_t;
    signal v_red_c_y   : millivolts_t;
    signal v_green_c_y : millivolts_t;
    signal v_blue_c_y  : millivolts_t;

    -- U channel
    constant v_black_u : integer := 364;  -- 0.235 mA x 1.55k =  364.3 mV  (always on)
    constant v_red_u   : integer := 335;  -- 0.216 mA x 1.55k =  334.8 mV
    constant v_green_u : integer := 668;  -- 0.431 mA x 1.55k =  668.1 mV
    constant v_blue_u  : integer := 1011; -- 0.652 mA x 1.55k = 1010.6 mV
    constant v_burst_u : integer := 910;  -- 0.587 mA x 1.55k =  909.9 mV

    signal v_red_c_u   : millivolts_t;
    signal v_green_c_u : millivolts_t;
    signal v_blue_c_u  : millivolts_t;
    signal v_burst_c_u : millivolts_t;

    -- V channel

    constant v_red_v     : integer := 1417; -- 0.457 mA x 3.1k = 1416.7 mV
    constant v_green_v   : integer := 1187; -- 0.383 mA x 3.1k = 1187.3 mV
    constant v_blue_v    : integer := 242;  -- 0.078 mA x 3.1k =  241.8 mV
    constant v_burst_v   : integer := 958;  -- 0.309 mA x 3.1k =  957.9 mV (burst_star sink)
    constant v_burst_n_v : integer := 958;  -- 0.309 mA x 3.1k =  957.9 mV (burst_star_n sink)

    signal v_red_c_v     : millivolts_t;
    signal v_green_c_v   : millivolts_t;
    signal v_blue_c_v    : millivolts_t;
    signal v_burst_c_v   : millivolts_t;
    signal v_burst_n_c_v : millivolts_t;

begin

    -- Y channel
    v_blue_c_y <= 0 when blue_i = '0' else
                  v_blue_br_y when hl_n = '0' else
                  v_blue_y;

    v_red_c_y <= 0 when red_i = '0' else
                 v_red_br_y when hl_n = '0' else
                 v_red_y;

    v_green_c_y <= 0 when green_i = '0' else
                   v_green_br_y when hl_n = '0' else
                   v_green_y;

    v_sync_c_y <= 0 when sync_n = '0' else
                  v_sync_y;

    y_raw_y <= V_TOP - v_sync_c_y - v_blue_c_y - v_red_c_y - v_green_c_y;
    y_n     <= v_min_y when y_raw_y < v_min_y else
               y_raw_y; -- clamp the bright white output above 0 volts

    -- U channel
    v_red_c_u   <= v_red_u when red_ii_n = '1' else
                   0;
    v_green_c_u <= v_green_u when green_ii_n = '1' else
                   0;
    v_blue_c_u  <= v_blue_u when blue_ii = '1' else
                   0;
    v_burst_c_u <= v_burst_u when burst_ii_n = '1' else
                   0;

    u <= V_TOP - v_red_c_u - v_green_c_u - v_blue_c_u - v_burst_c_u - v_black_u;

    -- V channel
    v_red_c_v     <= v_red_v when red_star = '1' else
                     0;
    v_green_c_v   <= v_green_v when green_star_n = '1' else
                     0;
    v_blue_c_v    <= v_blue_v when blue_star_n = '1' else
                     0;
    v_burst_c_v   <= v_burst_v when burst_star = '1' else
                     0;
    v_burst_n_c_v <= v_burst_n_v when burst_star_n = '1' else
                     0;

    v <= V_TOP - v_red_c_v - v_green_c_v - v_blue_c_v - v_burst_c_v - v_burst_n_c_v;

end architecture behavioural;
