----------------------------------------------------------------------------------
-- cpu_memory_access_tb — self-checking TB for the CPU side of the DRAM interface.
--
-- ── Reference model (what each signal MEANS) ─────────────────────────
--   ram_16   = MREQ asserted AND address in 0x4000..0x7FFF (a15='0', a14='1')
--              (also an OUTPUT, for the contention logic)
--              -> the lower 16K, the DRAM the ULA shares with the CPU
--   rom_cs_n = a14 OR a15              -> low for 0x0000..0x3FFF (book: not
--                                         qualified by MREQ)
--   ras_n    = NOT(ram_16 OR vid_ras)  -> CPU and video RAS merged
--   we_n     = NOT(ram_16 AND write)   -> write enable, lower 16K writes only
--   mux_sel  = ram_16 AND (read OR write)
--                                      -> excludes the refresh cycle, which has
--                                         MREQ but neither RD nor WR
--   cas_n    = NOT(mux_sel OR vid_cas_ac OR vid_cas_bd)
--                                      -> CPU and video CAS merged
--
-- ── What it proves ───────────────────────────────────────────────────
--   1. EXHAUSTIVE: all 2**8 = 256 combinations of a15, a14, mreq_n, wr_n,
--      rd_n, vid_ras, vid_cas_ac, vid_cas_bd, all five outputs against the
--      model (1280 checks).
--   2. Z80 CYCLES at 3.5 MHz (T = 282 ns), stepped through in time:
--      - READ of the lower 16K: MREQ and RD fall together, so RAS and CAS
--        both assert; WE stays high.
--      - WRITE of the lower 16K: MREQ falls -> RAS only. WR follows 285 ns
--        later -> WE and CAS assert TOGETHER (WE no later than CAS, an
--        "early write": the 4116 latches the data at CAS). Checked both
--        before and after WR falls.
--      - REFRESH with I = 0x40..0x7F (address in the lower 16K): MREQ with no
--        RD/WR -> RAS WITHOUT CAS, a RAS-only refresh. This is the cycle
--        behind the Spectrum's famous "snow" effect.
--      - REFRESH with I = 0x3F (the ROM default): no RAS, no CAS.
--      - ROM read and upper-32K read: no RAS, no CAS, no WE; rom_cs_n low
--        only for the ROM.
--      - I/O read (MREQ high, RD low): no DRAM strobes.
--      - Video strobes pass straight through while the CPU is idle.
--
-- The block has no modelled delays, so `settle` only covers the delta chain.
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity cpu_memory_access_tb is
end entity cpu_memory_access_tb;

architecture behavioral of cpu_memory_access_tb is

    constant settle   : time := 5 ns;   -- >> the delta chain
    constant t_state  : time := 282 ns; -- Z80 at 3.5469 MHz
    constant wr_delay : time := 285 ns; -- WR falls ~1 T after MREQ in a write

    signal vid_ras    : std_logic := '0';
    signal a14        : std_logic := '0';
    signal a15        : std_logic := '0';
    signal mreq_n     : std_logic := '1';
    signal wr_n       : std_logic := '1';
    signal rd_n       : std_logic := '1';
    signal vid_cas_ac : std_logic := '0';
    signal vid_cas_bd : std_logic := '0';

    signal ram_16   : std_logic;
    signal rom_cs_n : std_logic;
    signal ras_n    : std_logic;
    signal we_n     : std_logic;
    signal cas_n    : std_logic;

    signal checks : integer := 0;

    -- bit k of n as std_logic

    function bit_of (
        n : integer;
        k : integer
    ) return std_logic is
    begin

        if ((n / (2 ** k)) mod 2 = 1) then
            return '1';
        end if;

        return '0';

    end function bit_of;

begin

    dut : entity work.cpu_memory_access(structural)
        port map (
            vid_ras    => vid_ras,
            a14        => a14,
            a15        => a15,
            mreq_n     => mreq_n,
            wr_n       => wr_n,
            rd_n       => rd_n,
            vid_cas_ac => vid_cas_ac,
            vid_cas_bd => vid_cas_bd,
            ram_16     => ram_16,
            rom_cs_n   => rom_cs_n,
            ras_n      => ras_n,
            we_n       => we_n,
            cas_n      => cas_n
        );

    stim : process is

        variable checks_v : integer := 0;

        -- check all five outputs against the reference model

        procedure check_all (
            msg : in string
        ) is

            variable ram16 : std_logic;
            variable mux   : std_logic;
            variable e_rom : std_logic;
            variable e_ras : std_logic;
            variable e_we  : std_logic;
            variable e_cas : std_logic;

        begin

            ram16 := a14 and not a15 and not mreq_n;
            mux   := ram16 and (not wr_n or not rd_n);
            e_rom := a14 or a15;
            e_ras := not (ram16 or vid_ras);
            e_we  := not (ram16 and not wr_n);
            e_cas := not (mux or vid_cas_ac or vid_cas_bd);

            assert ram_16 = ram16
                report "FAIL " & msg & ": ram_16 expected " & std_logic'image(ram16)
                       & " got " & std_logic'image(ram_16)
                severity failure;

            assert rom_cs_n = e_rom
                report "FAIL " & msg & ": rom_cs_n expected " & std_logic'image(e_rom)
                       & " got " & std_logic'image(rom_cs_n)
                severity failure;

            assert ras_n = e_ras
                report "FAIL " & msg & ": ras_n expected " & std_logic'image(e_ras)
                       & " got " & std_logic'image(ras_n)
                severity failure;

            assert we_n = e_we
                report "FAIL " & msg & ": we_n expected " & std_logic'image(e_we)
                       & " got " & std_logic'image(we_n)
                severity failure;

            assert cas_n = e_cas
                report "FAIL " & msg & ": cas_n expected " & std_logic'image(e_cas)
                       & " got " & std_logic'image(cas_n)
                severity failure;

            checks_v := checks_v + 5;

        end procedure check_all;

        -- assert the three DRAM strobes have the given levels

        procedure expect (
            e_ras : in std_logic;
            e_cas : in std_logic;
            e_we  : in std_logic;
            msg   : in string
        ) is
        begin

            assert ras_n = e_ras and cas_n = e_cas and we_n = e_we
                report "FAIL " & msg & ": expected ras_n/cas_n/we_n = "
                       & std_logic'image(e_ras) & std_logic'image(e_cas)
                       & std_logic'image(e_we) & ", got "
                       & std_logic'image(ras_n) & std_logic'image(cas_n)
                       & std_logic'image(we_n)
                severity failure;

            checks_v := checks_v + 1;

        end procedure expect;

        -- return the bus to idle between cycles

        procedure idle is
        begin

            mreq_n <= '1';
            rd_n   <= '1';
            wr_n   <= '1';
            wait for t_state;

        end procedure idle;

    begin

        --------------------------------------------------------------
        -- 1) EXHAUSTIVE: all 256 input combinations
        --    bit 7 a15, 6 a14, 5 mreq_n, 4 wr_n, 3 rd_n,
        --    2 vid_ras, 1 vid_cas_ac, 0 vid_cas_bd
        --------------------------------------------------------------
        for n in 0 to 255 loop

            a15        <= bit_of(n, 7);
            a14        <= bit_of(n, 6);
            mreq_n     <= bit_of(n, 5);
            wr_n       <= bit_of(n, 4);
            rd_n       <= bit_of(n, 3);
            vid_ras    <= bit_of(n, 2);
            vid_cas_ac <= bit_of(n, 1);
            vid_cas_bd <= bit_of(n, 0);
            wait for settle;

            check_all("combination " & integer'image(n));

        end loop;

        report "PASS: exhaustive sweep of all 256 input combinations"
            severity note;

        vid_ras    <= '0';
        vid_cas_ac <= '0';
        vid_cas_bd <= '0';
        idle;

        --------------------------------------------------------------
        -- 2) Z80 CYCLES
        --------------------------------------------------------------

        -- READ of the lower 16K (0x4000..0x7FFF): MREQ and RD together
        a15    <= '0';
        a14    <= '1';
        wait for t_state;
        mreq_n <= '0';
        rd_n   <= '0';
        wait for settle;
        expect('0', '0', '1', "read 0x4000: RAS and CAS low, WE high");
        idle;
        expect('1', '1', '1', "after read: all strobes released");

        report "PASS: read of the lower 16K -> RAS and CAS, no WE"
            severity note;

        -- WRITE of the lower 16K: MREQ first, WR ~285 ns later
        mreq_n <= '0';
        wait for settle;
        expect('0', '1', '1', "write 0x4000, before WR: RAS only");
        wait for wr_delay - settle;
        wr_n   <= '0';
        wait for settle;
        expect('0', '0', '0', "write 0x4000, after WR: WE and CAS low together");
        idle;

        report "PASS: write of the lower 16K -> RAS, then WE with CAS 285 ns later"
            severity note;

        -- REFRESH, I = 0x40..0x7F: MREQ with no RD/WR, address in the lower 16K
        mreq_n <= '0';
        wait for settle;
        expect('0', '1', '1', "refresh, I in 0x40..0x7F: RAS-only, no CAS");
        idle;

        report "PASS: refresh with I in 0x40..0x7F -> RAS without CAS (the 'snow' cycle)"
            severity note;

        -- REFRESH, I = 0x3F: address 0x3Fxx is ROM space
        a14      <= '0';
        mreq_n   <= '0';
        wait for settle;
        expect('1', '1', '1', "refresh, I = 0x3F: no DRAM strobes");
        assert rom_cs_n = '0'
            report "FAIL refresh I = 0x3F: rom_cs_n should be low (book: not MREQ-qualified)"
            severity failure;
        checks_v := checks_v + 1;
        idle;

        -- ROM read (0x0000..0x3FFF)
        a15      <= '0';
        a14      <= '0';
        mreq_n   <= '0';
        rd_n     <= '0';
        wait for settle;
        expect('1', '1', '1', "ROM read: no DRAM strobes");
        assert rom_cs_n = '0'
            report "FAIL ROM read: rom_cs_n should be low"
            severity failure;
        checks_v := checks_v + 1;
        idle;

        -- upper-32K read (0x8000..0xFFFF): not this block's DRAM
        a15      <= '1';
        a14      <= '0';
        mreq_n   <= '0';
        rd_n     <= '0';
        wait for settle;
        expect('1', '1', '1', "upper-32K read: no DRAM strobes");
        assert rom_cs_n = '1'
            report "FAIL upper-32K read: rom_cs_n should be high"
            severity failure;
        checks_v := checks_v + 1;
        idle;

        -- I/O read: RD without MREQ, even with a lower-16K address on the bus
        a15  <= '0';
        a14  <= '1';
        rd_n <= '0';
        wait for settle;
        expect('1', '1', '1', "I/O read: no DRAM strobes");
        idle;

        report "PASS: refresh I = 0x3F, ROM, upper 32K and I/O -> no DRAM strobes"
            severity note;

        -- video strobes pass straight through with the CPU idle
        vid_ras    <= '1';
        wait for settle;
        expect('0', '1', '1', "video RAS through");
        vid_cas_ac <= '1';
        wait for settle;
        expect('0', '0', '1', "video CAS (A/C) through");
        vid_cas_ac <= '0';
        vid_cas_bd <= '1';
        wait for settle;
        expect('0', '0', '1', "video CAS (B/D) through");
        vid_cas_bd <= '0';
        vid_ras    <= '0';
        wait for settle;
        expect('1', '1', '1', "video idle");

        report "PASS: video RAS and both video CAS legs pass through"
            severity note;

        checks <= checks_v;
        wait for 1 ns;

        report "ALL TESTS PASSED (" & integer'image(checks_v) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
