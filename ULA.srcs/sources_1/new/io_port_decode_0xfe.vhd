----------------------------------------------------------------------------------
-- io_port_decode_0xfe — ULA port read / write strobes
--
-- Makes the two strobes every I/O block keys off:
--   port_rd_n  low during an IN from the ULA port  -> keyboard_input (do_0..do_4)
--                                                     and cassette_input (do_6)
--                                                     drive the bus
--   port_wr_n  low during an OUT to the ULA port   -> border_reg (di_0..di_2) and
--                                                     cassette_speaker_out
--                                                     (di_3, di_4) latch the bus
-- The ULA answers on any EVEN I/O address (A0 = '0'); 0xFE is the one the ROM
-- uses.
--
-- ── Logic ────────────────────────────────────────────────────────────
--   s_port_rd = NOR(a0, ioreq_n, ioreqtw3_n, rd_n)    port_rd_n = NOT s_port_rd
--   s_port_wr = NOR(a0, ioreq_n, ioreqtw3_n, wr_n)    port_wr_n = NOT s_port_wr
--   A NOR gives '1' only when EVERY input is '0', so each strobe needs:
--     a0         = '0'  even address
--     ioreq_n    = '0'  I/O request to the ULA port
--     ioreqtw3_n = '0'  the access has reached T2 / TW / T3 (see below)
--     rd_n / wr_n = '0' the Z80 is reading / writing
--   A0 goes in UNINVERTED. The schematic shows a buffer there (no output
--   bubble), not an inverter; inverting it would decode the ODD ports.
--
-- ── Where the inputs come from ───────────────────────────────────────
--   a0          the ULA's A0 pin -- the MULTIPLEXED DRAM ADDRESS pin, the same
--               pin video_address_generation drives as its a0 output during a
--               video fetch (enabled by ae_n). Otherwise the PCB's '157
--               multiplexer drives it, selected by ras_n: ras_n HIGH passes
--               the B input = CPU A0 (row address), ras_n LOW passes the A
--               input = CPU A7 (column address). An I/O cycle has no /MREQ, so
--               no RAS: ras_n stays high and the pin carries CPU A0 for the
--               whole port access. The ULA is not driving the pin then --
--               contention keeps port accesses out of the fetch slots.
--   ioreq_n     a ULA pin, made OFF-CHIP on the PCB as Z80 /IORQ OR A0. It
--               already contains A0, so -- with the pin carrying A0 as above --
--               the a0 term is logically redundant; kept because the book
--               draws it.
--   ioreqtw3_n  from contention_handler_3: a latched copy of ioreq_n that goes
--               low from T2 onwards, once the contention hold has had its
--               chance. Gating with it means the ULA only drives the bus, or
--               opens its port latches, after contention has settled. The
--               live ioreq_n term ends the strobe as soon as /IORQ rises,
--               rather than when the latch releases.
--   rd_n, wr_n  Z80 /RD and /WR.
--
-- ── Interrupt acknowledge ────────────────────────────────────────────
--   The Z80 also pulls /IORQ low (with /M1) to acknowledge an interrupt, and A0
--   may be '0' then. Neither /RD nor /WR goes low in that cycle, so neither
--   strobe fires: the ULA does not drive the keyboard onto the bus while it is
--   carrying the interrupt vector.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity io_port_decode_0xfe is
    port (
        a0         : in    std_logic;
        ioreq_n    : in    std_logic;
        ioreqtw3_n : in    std_logic;
        rd_n       : in    std_logic;
        wr_n       : in    std_logic;
        port_rd_n  : out   std_logic;
        port_wr_n  : out   std_logic
    );
end entity io_port_decode_0xfe;

architecture structural of io_port_decode_0xfe is

    signal s_port_rd : std_logic;
    signal s_port_wr : std_logic;

begin

    -- port read: even address, ULA I/O request, past T2, Z80 reading
    s_port_rd <= not(a0 or ioreq_n or ioreqtw3_n or rd_n);
    port_rd_n <= not(s_port_rd);

    -- port write: the same, Z80 writing
    s_port_wr <= not(a0 or ioreq_n or ioreqtw3_n or wr_n);
    port_wr_n <= not(s_port_wr);

end architecture structural;
