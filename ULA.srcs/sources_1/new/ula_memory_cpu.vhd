----------------------------------------------------------------------------------
-- ula_memory_cpu — memory and CPU clock subsystem
--
-- One of the ULA.vhd subsystems: the ULA's side of the Z80 memory bus.
--
--   cpu_memory_access   lower-16K / ROM decode and the DRAM strobes: merges
--                       the CPU's access with the video fetch strobes onto
--                       ras_n / cas_n / we_n, drives rom_cs_n, and releases
--                       RAS ('Z') in border ROM-area cycles (6C001 rasen_n)
--   contention_handler_3
--                       the 3.5 MHz CPU clock from c0, held (stretched) when
--                       the CPU touches 0x4000..0x7FFF or the ULA port while
--                       the ULA is fetching; drives pin 32 phicpu_n (open
--                       collector) and ioreqtw3_n for the port decode
--
--      a14, a15, mreq_n, rd_n, wr_n, vid_ras/cas --> cpu_memory_access
--                                                    --> ras_n, cas_n, we_n, rom_cs_n
--      c0_n, c2, c3, border, a14, a15, mreq_n, ioreq_n --> contention_handler_3
--                                                    --> phicpu_n, ioreqtw3_n
--
-- Pure wiring: the two blocks don't talk to each other, so there are no
-- internal signals. Unused outputs left open: ram_16, cpuclk.
--
-- Pad types pass through unchanged: ras_n is a tri-state ('Z' when
-- released), phicpu_n is open collector ('0' / 'Z', the 1k pull-up is on the
-- PCB). std_logic carries both through the out ports.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity ula_memory_cpu is
    port (
        -- CPU bus
        a14     : in    std_logic;
        a15     : in    std_logic;
        mreq_n  : in    std_logic;
        ioreq_n : in    std_logic;
        rd_n    : in    std_logic;
        wr_n    : in    std_logic;

        -- video DRAM strobes, from ula_video_fetch
        vid_ras    : in    std_logic;
        vid_cas_ac : in    std_logic;
        vid_cas_bd : in    std_logic;

        -- timing, from ula_timing
        c0_n     : in    std_logic; -- CPU clock source (3.5 MHz)
        c2       : in    std_logic; -- contention window
        c3       : in    std_logic;
        border   : in    std_logic; -- no contention in the border
        border_n : in    std_logic; -- RAS released in border ROM-area cycles

        -- DRAM / ROM pins
        ras_n    : out   std_logic; -- tri-state
        cas_n    : out   std_logic;
        we_n     : out   std_logic;
        rom_cs_n : out   std_logic;

        phicpu_n   : out   std_logic; -- CPU clock pin 32, open collector
        ioreqtw3_n : out   std_logic  -- to io_port_decode_0xfe
    );
end entity ula_memory_cpu;

architecture structural of ula_memory_cpu is

begin

    mem_access : entity work.cpu_memory_access(structural)
        port map (
            a14        => a14,
            a15        => a15,
            mreq_n     => mreq_n,
            wr_n       => wr_n,
            rd_n       => rd_n,
            vid_ras    => vid_ras,
            vid_cas_ac => vid_cas_ac,
            vid_cas_bd => vid_cas_bd,
            border_n   => border_n,
            ram_16     => open,
            rom_cs_n   => rom_cs_n,
            ras_n      => ras_n,
            cas_n      => cas_n,
            we_n       => we_n
        );

    cpu_contention : entity work.contention_handler_3(structural)
        port map (
            c0_n       => c0_n,
            a14        => a14,
            ioreq_n    => ioreq_n,
            a15        => a15,
            c2         => c2,
            c3         => c3,
            border     => border,
            mreq_n     => mreq_n,
            cpuclk     => open,
            phicpu_n   => phicpu_n,
            ioreqtw3_n => ioreqtw3_n
        );

end architecture structural;
