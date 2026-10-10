----------------------------------------------------------------------------------
-- Module Name: pixel_flash_tb - Behavioral
-- Description: Self-checking testbench for pixel_flash.
--
--   pixel_flash conditionally inverts the serialised pixel select bit to
--   produce the FLASH effect. It is pure combinational with three inputs
--   (fl, flash_clk, serial_data), so the TB is EXHAUSTIVE: it drives all
--   eight input combinations, waits SETTLE, and checks data_select_n
--   against the reference equation.
--
--   Reference model:
--     b_o           = fl AND (NOT flash_clk)
--     data_select_n = NOT( serial_data XOR b_o )          (= XNOR)
--
--   Key cases covered by the sweep:
--     - fl='0'  : data_select_n = NOT serial_data (pass-through), for
--                 both flash_clk values (flash_clk is a don't-care here).
--     - fl='1', flash_clk='1' : still pass-through (wrong half-period).
--     - fl='1', flash_clk='0' : INVERTED  -> data_select_n = serial_data.
--
--   Any mismatch is a fatal error; reaching the end prints
--   "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity pixel_flash_tb is
--  Port ( );
end entity pixel_flash_tb;

architecture behavioral of pixel_flash_tb is

    constant settle : time := 10 ns; -- > worst-case gate path (5*TG = 5 ns) with margin

    signal fl            : std_logic := '0';
    signal flash_clk     : std_logic := '0';
    signal serial_data   : std_logic := '0';
    signal data_select_n : std_logic;

    -- Reference model: the expected active-low select for given inputs.

    function expected_select_n (
        f,
        fc,
        s : std_logic
    ) return std_logic is

        variable b : std_logic;

    begin

        b := f and (not fc);  -- flash-gate: swap this half?
        return not (s xor b); -- XNOR(b, serial_data)

    end function expected_select_n;

    -- Apply one input combination, let it settle, and check the output.

    procedure check (
        signal fl_s : out std_logic;
        signal fc_s : out std_logic;
        signal sd_s : out std_logic;
        signal dsn  : in  std_logic;
        f,
        fc,
        s           : in  std_logic
    ) is

        variable exp : std_logic;

    begin

        fl_s <= f;
        fc_s <= fc;
        sd_s <= s;
        wait for SETTLE;
        exp  := expected_select_n(f, fc, s);
        assert dsn = exp
            report "FAIL: fl=" & std_logic'image(f)
                   & " flash_clk=" & std_logic'image(fc)
                   & " serial_data=" & std_logic'image(s)
                   & " - expected data_select_n=" & std_logic'image(exp)
                   & " got " & std_logic'image(dsn)
            severity failure;
        report "PASS: fl=" & std_logic'image(f)
               & " flash_clk=" & std_logic'image(fc)
               & " serial_data=" & std_logic'image(s)
               & " -> data_select_n=" & std_logic'image(dsn)
            severity note;

    end procedure check;

begin

    dut : entity work.pixel_flash(Structural)
        port map (
            fl            => fl,
            flash_clk     => flash_clk,
            serial_data   => serial_data,
            data_select_n => data_select_n
        );

    -- *****************************************************************
    -- exhaustive stimulus + self-check (pure combinational)
    -- *****************************************************************
    process is
    begin

        -- fl='0' : pass-through, flash_clk is a don't-care
        check(fl, flash_clk, serial_data, data_select_n, '0', '0', '0');
        check(fl, flash_clk, serial_data, data_select_n, '0', '0', '1');
        check(fl, flash_clk, serial_data, data_select_n, '0', '1', '0');
        check(fl, flash_clk, serial_data, data_select_n, '0', '1', '1');

        -- fl='1', flash_clk='1' : wrong half -> still pass-through
        check(fl, flash_clk, serial_data, data_select_n, '1', '1', '0');
        check(fl, flash_clk, serial_data, data_select_n, '1', '1', '1');

        -- fl='1', flash_clk='0' : swap half -> inverted select
        check(fl, flash_clk, serial_data, data_select_n, '1', '0', '0');
        check(fl, flash_clk, serial_data, data_select_n, '1', '0', '1');

        report "ALL TESTS PASSED"
            severity note;
        wait;

    end process;

end architecture behavioral;
