library ieee;
    use ieee.std_logic_1164.all;

entity attr_output_latch_border_select_mux is
    port (
        clk_7              : in    std_logic;                            -- 7MHz clock
        s_load             : in    std_logic;                            -- serial pixel load
        pixel_data_latch_n : in    std_logic;                            -- latch pixel data
        pixel_data         : in    std_logic_vector(7 downto 0);         -- pixel data
        attr_data_latch    : in    std_logic;                            -- when to latch the attribute data
        attr_data          : in    std_logic_vector(7 downto 0);         -- D0-2 ink, D3-5 paper, D6 hl, D7 fl
        border_colour_bgr  : in    std_logic_vector(2 downto 0);         -- blue, green ed bits
        border_fl_hl       : in    std_logic_vector(1 downto 0) := "00"; -- always 0, border does not flash or highlight
        video_en           : in    std_logic;                            -- enable video; dont display on blank
        attr_output_latch  : in    std_logic;                            -- latch attr output data to rgb mux
        serial_pix_stream  : in    std_logic;                            -- generated
        blue               : out   std_logic;                            -- output blue bit
        green              : out   std_logic;                            -- output green bit
        red                : out   std_logic                             -- output red bit
    );
end entity attr_output_latch_border_select_mux;

architecture structural of attr_output_latch_border_select_mux is

    signal serial_pixel_stream : std_logic;

begin

    pix_serial : entity work.pixel_serialiser
        port map (
            clk          => clk_7,
            sload        => s_load,
            data_latch_n => pixel_data_latch_n,
            data         => pixel_data,
            serial_data  => serial_pix_stream
        );

    pix_flash : entity work.pixel_flash
        port map (
            fl             => open,
            flash_clk      => open,
            serial_data    => open,
            data_selelct_n => open
        );

end architecture structural;
