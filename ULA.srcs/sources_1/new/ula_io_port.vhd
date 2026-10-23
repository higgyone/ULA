----------------------------------------------------------------------------------
-- ula_io_port — I/O port subsystem: port 0xFE decode, keyboard, border
--
-- One of the ULA.vhd subsystems. The ULA answers any even I/O address
-- (A0 = 0), 0xFE by convention:
--
--   io_port_decode_0xfe the read and write strobes port_rd_n / port_wr_n
--                       (ioreq_n with a0 = 0, held off by ioreqtw3_n during
--                       contention)
--   keyboard_input      port READ: keyboard columns k0..k4 onto D0..D4
--                       (open collector '0' / 'H')
--   border_reg          port WRITE: D0..D2 latched as the border colour
--
--      a0, ioreq_n, ioreqtw3_n, rd_n, wr_n --> io_port_decode_0xfe
--                          | port_rd_n                | port_wr_n
--                          v                          v
--      k0..k4 --> keyboard_input --> d0..d4    d0..d2 --> border_reg --> border_colour
--
-- Pure wiring: no logic of its own.
--
-- port_rd_n / port_wr_n are exported (ula_sound uses them for EAR, MIC and
-- the speaker) and also read inside, so they are driven onto s_port_rd_n /
-- s_port_wr_n and copied to the ports (VHDL-93 can't read an out port).
--
-- d0..d2 are inout: keyboard_input drives them on a read and border_reg
-- reads them on a write. d3 / d4 are only driven here (ula_sound reads
-- them). k0 is an in here although the K0 pin is inout: test_modes in
-- ula_timing is what drives it.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity ula_io_port is
    port (
        a0         : in    std_logic; -- port address bit (even = ULA port)
        ioreq_n    : in    std_logic;
        ioreqtw3_n : in    std_logic; -- from ula_memory_cpu (contention)
        rd_n       : in    std_logic;
        wr_n       : in    std_logic;

        k1 : in    std_logic; -- keyboard columns, active low
        k2 : in    std_logic;
        k3 : in    std_logic;
        k4 : in    std_logic;
        k0 : in    std_logic; -- (the pin is inout: test B also drives it)

        d0 : inout std_logic; -- driven on a read (keys), read on a write (border)
        d1 : inout std_logic;
        d2 : inout std_logic;
        d3 : out   std_logic; -- keys only; MIC is read by ula_sound
        d4 : out   std_logic; -- keys only; speaker is read by ula_sound

        port_rd_n     : out   std_logic;                   -- port 0xFE read strobe, also to ula_sound
        port_wr_n     : out   std_logic;                   -- port 0xFE write strobe, also to ula_sound
        border_colour : out   std_logic_vector(2 downto 0) -- (0) blue, (1) red, (2) green
    );
end entity ula_io_port;

architecture structural of ula_io_port is

    signal s_port_rd_n : std_logic;
    signal s_port_wr_n : std_logic;

begin

    port_rd_n <= s_port_rd_n;
    port_wr_n <= s_port_wr_n;

    io_decode : entity work.io_port_decode_0xfe(structural)
        port map (
            a0         => a0,
            ioreq_n    => ioreq_n,
            ioreqtw3_n => ioreqtw3_n,
            rd_n       => rd_n,
            wr_n       => wr_n,
            port_rd_n  => s_port_rd_n,
            port_wr_n  => s_port_wr_n
        );

    keyboard : entity work.keyboard_input(structural)
        port map (
            k0        => k0,
            k1        => k1,
            k2        => k2,
            k3        => k3,
            k4        => k4,
            port_rd_n => s_port_rd_n,
            do_0      => d0,
            do_1      => d1,
            do_2      => d2,
            do_3      => d3,
            do_4      => d4
        );

    border : entity work.border_reg(structural)
        port map (
            di_0      => d0,
            di_1      => d1,
            di_2      => d2,
            port_wr_n => s_port_wr_n,
            b0        => border_colour(0),
            b1        => border_colour(1),
            b2        => border_colour(2)
        );

end architecture structural;
