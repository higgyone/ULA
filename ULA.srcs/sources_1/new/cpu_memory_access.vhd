----------------------------------------------------------------------------------
-- cpu_memory_access — CPU side of the lower-16K DRAM interface
--
-- Decodes the Z80's memory requests into the lower 16K (0x4000..0x7FFF, the
-- 4116 DRAM the ULA shares with the CPU), gives the ROM chip select, and merges
-- the CPU strobes with the video strobes onto the DRAM's RAS, CAS and WE.
--
-- ── Decode ───────────────────────────────────────────────────────────
--   ram_16     = MREQ AND a14 AND NOT a15          lower-16K memory request
--                Exported: the CPU-clock contention logic needs it.
--   rom_cs_n   = a14 OR a15                        low for 0x0000..0x3FFF
--                (as in the book: not qualified by MREQ)
--   we_n       = NOT(ram_16 AND write)             lower-16K writes only
--   mux_select = ram_16 AND (read OR write)        the CPU-CAS condition
--
--   mux_select is INTERNAL ONLY, despite its name. The external 74LS157
--   address multiplexers are switched by ras_n itself, because the ULA has no
--   pin for a mux select. mux_select only decides when the CPU gets a CAS: on
--   a read or write, but NOT on a refresh cycle (MREQ with neither RD nor WR).
--
-- ── The Z80 cycles this produces ─────────────────────────────────────
--   READ     MREQ and RD fall together -> RAS, then CAS.
--   WRITE    MREQ falls -> RAS only. WR falls ~285 ns later (Z80 timing, not a
--            ULA delay) -> WE, then CAS. WE leads CAS: an "early write", so
--            the 4116 latches the data at CAS.
--   REFRESH  MREQ alone. With I = 0x40..0x7F the refresh address lands in the
--            lower 16K -> RAS WITHOUT CAS, a RAS-only refresh. This is the
--            cycle behind the Spectrum's "snow" effect. With I = 0x3F (the
--            ROM default) nothing happens.
--
-- ── Merge with the video strobes ─────────────────────────────────────
--   ras_n     = NOR(ram_16, vid_ras)
--   com_cas_n = NOR(mux_select, vid_cas_ac, vid_cas_bd)
--   cas_n     = com_cas_n through a 2-inverter output buffer
--   All inputs here are ACTIVE HIGH. These are the same three gates as the
--   book's page-127 n_ras / d_out / n_cas (see the reference block in
--   ras_cas_generation); the book draws them in both places. The merge is
--   done ONCE, here (option B): ras_cas_generation makes the video strobes
--   only and hands vid_ras / vid_cas_ac / vid_cas_bd to this block.
--
-- ── The delay chains (book form, ~10 ns per gate) ────────────────────
--   mreq_n -> ras_n      2 gates   ~20 ns
--   ras_n  -> cas_n      8 gates   ~80 ns  (3-inverter ram_16_n chain,
--                                           mux_select NOR, 2-inverter chain,
--                                           com_cas NOR, 2-inverter buffer)
--   ram_16 -> cas_n      9 gates   ~90 ns
--
--   Only RAS -> CAS matters, and only with a real DRAM: when ras_n falls the
--   '157s switch from row to column, and the column address must get through
--   them and settle before CAS falls (about 30-45 ns minimum; 80 ns gives
--   margin). mreq_n -> ras_n is plain gate delay: the Z80's row address is
--   valid long before MREQ.
--
--   The chains are kept in book form for traceability, but they are 0 ns in
--   simulation (no `after` clauses) and synthesis optimises them away. If the
--   FPGA ever drives a real DRAM, the RAS -> CAS spacing must come from clock
--   edges instead: RAS on one clk_14 edge, CAS on the next = 71 ns, the same
--   spacing ras_cas_generation already uses for the video side.
--
-- ── Ports ────────────────────────────────────────────────────────────
--   a14, a15     Z80 address bits 14 and 15
--   mreq_n       Z80 /MREQ: memory request (read, write or refresh), active low
--   wr_n         Z80 /WR, active low
--   rd_n         Z80 /RD, active low
--   vid_ras      video RAS, active HIGH
--   vid_cas_ac   video CAS, first byte of each pair (A, C), active HIGH
--   vid_cas_bd   video CAS, second byte of each pair (B, D), active HIGH
--   ram_16       lower-16K memory request, active HIGH (for contention)
--   rom_cs_n     ROM chip select, active low
--   ras_n        DRAM RAS, active low (also switches the external '157s)
--   cas_n        DRAM CAS, active low
--   we_n         DRAM write enable, active low
--
-- Verified by cpu_memory_access_tb.
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity cpu_memory_access is
    port (
        a14        : in    std_logic; -- address bit 14
        a15        : in    std_logic; -- address bit 15
        mreq_n     : in    std_logic; -- memory request: read, write or refresh
        wr_n       : in    std_logic; -- Z80 write strobe
        rd_n       : in    std_logic; -- Z80 read strobe
        vid_ras    : in    std_logic; -- video RAS, active high
        vid_cas_ac : in    std_logic; -- video CAS, bytes A and C, active high
        vid_cas_bd : in    std_logic; -- video CAS, bytes B and D, active high
        ram_16     : out   std_logic; -- lower-16K memory request, active high
        rom_cs_n   : out   std_logic; -- ROM chip select
        ras_n      : out   std_logic; -- DRAM RAS (also selects the '157 muxes)
        cas_n      : out   std_logic; -- DRAM CAS
        we_n       : out   std_logic  -- DRAM write enable
    );
end entity cpu_memory_access;

architecture structural of cpu_memory_access is

    signal s_ram_16   : std_logic;
    signal ram_16_n   : std_logic;
    signal a14_n      : std_logic;
    signal rom_cs     : std_logic;
    signal we         : std_logic;
    signal wr         : std_logic;
    signal rd         : std_logic;
    signal a_out      : std_logic;
    signal mux_select : std_logic;
    signal com_cas_n  : std_logic;

begin

    -- ROM: 0x0000..0x3FFF
    rom_cs   <= not(a14 or a15);
    rom_cs_n <= not(rom_cs);

    -- lower-16K memory request: a15 = '0', a14 = '1', MREQ asserted
    a14_n    <= not(a14);
    s_ram_16 <= not(a15 or a14_n or mreq_n);
    ram_16   <= s_ram_16;

    -- 3-inverter chain: an inverted, delayed ram_16 (part of RAS -> CAS)
    ram_16_n <= not(not(not(s_ram_16)));

    -- write enable: lower-16K write
    we   <= not(ram_16_n or wr_n);
    we_n <= not(we);

    -- CPU-CAS condition: lower-16K read or write, NOT refresh
    wr         <= not(wr_n);
    rd         <= not(rd_n);
    a_out      <= not(wr or rd);
    mux_select <= not(a_out or ram_16_n);

    -- merge with video. The 2-inverter chain on mux_select and the
    -- 2-inverter output buffer are book delays (part of RAS -> CAS).
    ras_n     <= not(s_ram_16 or vid_ras);
    com_cas_n <= not(not(not(mux_select)) or vid_cas_ac or vid_cas_bd);
    cas_n     <= not(not(com_cas_n));

end architecture structural;
