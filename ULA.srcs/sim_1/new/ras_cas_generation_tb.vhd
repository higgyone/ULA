----------------------------------------------------------------------------------
-- ras_cas_generation_tb — self-checking TB for the synchronous video RAS/CAS
-- generator, and for its merge with the CPU side in cpu_memory_access.
--
-- ras_cas_generation makes the VIDEO strobes only (active high: vid_ras,
-- vid_cas_ac, vid_cas_bd, plus the active-low n_vid_ras tap). The merge with the
-- CPU onto the DRAM pins is done once, in cpu_memory_access (option B). This TB
-- wires the two together, as the top level will, so it also proves the DRAM pins
-- come out exactly as before the merge moved.
--
-- What it proves:
--   1. Waveform — walking the tick index {c1, c0, phase} = 0..7 through one
--      4-pixel DRAM cycle (fetch window active, CPU idle) produces the registered
--      pattern from the block's header table on all four outputs: one RAS
--      spanning the cycle, the FIRST CAS on vid_cas_ac, the SECOND on vid_cas_bd,
--      a precharge gap between them, and RAS releasing one tick before the last
--      CAS. n_vid_ras is the complement of vid_ras at every tick.
--   2. The two CAS legs never overlap, and together give exactly TWO separate
--      CAS pulses per cycle, so a full c3-high burst (two cycles) fetches the
--      four bytes A/B/C/D.
--   3. DRAM pins via cpu_memory_access — ras_n / cas_n at every tick match the
--      original merged waveform (RAS 0 0 0 0 0 0 1 1, CAS 1 0 0 1 0 0 0 1).
--   4. DRAM AC minimums — the tick positions give RAS→CAS, CAS-high gap, CAS-low
--      width and RAS-hold that clear the datasheet limits.
--   5. Fetch-window gating — with n_vid_c3 = '1' all video strobes stay
--      de-asserted at every tick (border/blank, and the c3-low CPU gap).
--   6. CPU through the merge — with video idle, a Z80 read of 0x4000 pulls the
--      DRAM ras_n / cas_n low, while n_vid_ras stays high (video tap only).
--
-- The DUT registers its strobes on clk_14, so the drive pattern is: set the tick
-- on a FALLING clk_14 edge (clean setup), let the next RISING edge capture it,
-- then sample. Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library std;
    use std.env.all;

entity ras_cas_generation_tb is
end entity ras_cas_generation_tb;

architecture behavioral of ras_cas_generation_tb is

    constant t : time := 72 ns; -- clk_14 period (~14 MHz, half a pixel)

    signal clk_14   : std_logic := '0';
    signal clk_7    : std_logic := '0';
    signal c0       : std_logic := '0';
    signal c1       : std_logic := '0';
    signal n_vid_c3 : std_logic := '1';

    signal vid_ras    : std_logic;
    signal vid_cas_ac : std_logic;
    signal vid_cas_bd : std_logic;
    signal n_vid_ras  : std_logic;

    -- CPU side of cpu_memory_access (idle unless a test drives it)
    signal a14    : std_logic := '0';
    signal a15    : std_logic := '0';
    signal mreq_n : std_logic := '1';
    signal wr_n   : std_logic := '1';
    signal rd_n   : std_logic := '1';

    -- DRAM pins, from the merge in cpu_memory_access
    signal ram_16   : std_logic;
    signal rom_cs_n : std_logic;
    signal ras_n    : std_logic;
    signal cas_n    : std_logic;
    signal we_n     : std_logic;

    -- expected registered strobes per tick (fetch window active, CPU idle)
    --                          tick:   0    1    2    3    4    5    6    7

    type slv8 is array (0 to 7) of std_logic;

    constant exp_ras    : slv8 := ('1', '1', '1', '1', '1', '1', '0', '0');
    constant exp_cas_ac : slv8 := ('0', '1', '1', '0', '0', '0', '0', '0');
    constant exp_cas_bd : slv8 := ('0', '0', '0', '0', '1', '1', '1', '0');

    -- the DRAM pins as they were before the merge moved (active low)
    constant exp_ras_n : slv8 := ('0', '0', '0', '0', '0', '0', '1', '1');
    constant exp_cas_n : slv8 := ('1', '0', '0', '1', '0', '0', '0', '1');

begin

    dut : entity work.ras_cas_generation(synchronous)
        port map (
            clk_14     => clk_14,
            clk_7      => clk_7,
            c0         => c0,
            c1         => c1,
            n_vid_c3   => n_vid_c3,
            vid_ras    => vid_ras,
            vid_cas_ac => vid_cas_ac,
            vid_cas_bd => vid_cas_bd,
            n_vid_ras  => n_vid_ras
        );

    merge : entity work.cpu_memory_access(structural)
        port map (
            a14        => a14,
            a15        => a15,
            mreq_n     => mreq_n,
            wr_n       => wr_n,
            rd_n       => rd_n,
            vid_ras    => vid_ras,
            vid_cas_ac => vid_cas_ac,
            vid_cas_bd => vid_cas_bd,
            ram_16     => ram_16,
            rom_cs_n   => rom_cs_n,
            ras_n      => ras_n,
            cas_n      => cas_n,
            we_n       => we_n
        );

    clk_gen : process is
    begin

        clk_14 <= '0';
        wait for t / 2;
        clk_14 <= '1';
        wait for t / 2;

    end process clk_gen;

    stim : process is

        variable checks   : integer := 0;
        variable cas_lows : integer := 0;
        variable cas_k    : std_logic;
        variable cas_km1  : std_logic;

        -- drive the tick index onto {c1, c0, phase} (called on a falling edge)

        procedure set_tick (
            k : in integer
        ) is

            variable kv : std_logic_vector(2 downto 0);

        begin

            kv    := std_logic_vector(to_unsigned(k, 3));
            c1    <= kv(2);
            c0    <= kv(1);
            clk_7 <= kv(0);

        end procedure set_tick;

        -- set a tick, let the register capture it, then let the outputs settle

        procedure step (
            k : in integer
        ) is
        begin

            wait until falling_edge(clk_14);
            set_tick(k);
            wait until rising_edge(clk_14);
            wait for t / 4;

        end procedure step;

    begin

        ------------------------------------------------------------------
        -- 1) + 3) one full 4-pixel DRAM cycle, fetch active, CPU idle:
        --    the video strobes AND the merged DRAM pins at every tick
        ------------------------------------------------------------------
        n_vid_c3 <= '0';

        for k in 0 to 7 loop

            step(k);

            assert vid_ras = exp_ras(k)
                report "FAIL tick " & integer'image(k) & ": vid_ras expected "
                       & std_logic'image(exp_ras(k)) & " got " & std_logic'image(vid_ras)
                severity failure;

            assert vid_cas_ac = exp_cas_ac(k)
                report "FAIL tick " & integer'image(k) & ": vid_cas_ac expected "
                       & std_logic'image(exp_cas_ac(k)) & " got " & std_logic'image(vid_cas_ac)
                severity failure;

            assert vid_cas_bd = exp_cas_bd(k)
                report "FAIL tick " & integer'image(k) & ": vid_cas_bd expected "
                       & std_logic'image(exp_cas_bd(k)) & " got " & std_logic'image(vid_cas_bd)
                severity failure;

            assert n_vid_ras = not exp_ras(k)
                report "FAIL tick " & integer'image(k) & ": n_vid_ras expected "
                       & std_logic'image(not exp_ras(k)) & " got " & std_logic'image(n_vid_ras)
                severity failure;

            assert ras_n = exp_ras_n(k)
                report "FAIL tick " & integer'image(k) & ": DRAM ras_n expected "
                       & std_logic'image(exp_ras_n(k)) & " got " & std_logic'image(ras_n)
                severity failure;

            assert cas_n = exp_cas_n(k)
                report "FAIL tick " & integer'image(k) & ": DRAM cas_n expected "
                       & std_logic'image(exp_cas_n(k)) & " got " & std_logic'image(cas_n)
                severity failure;

            checks := checks + 6;

        end loop;

        report "PASS: video waveform on all four outputs, and the merged DRAM pins "
               & "match the original"
            severity note;

        ------------------------------------------------------------------
        -- 2) the two CAS legs never overlap, and give exactly TWO separate
        --    CAS pulses per cycle (the byte pair under one RAS)
        ------------------------------------------------------------------
        cas_lows := 0;

        for k in 0 to 7 loop

            assert not (exp_cas_ac(k) = '1' and exp_cas_bd(k) = '1')
                report "FAIL tick " & integer'image(k) & ": both CAS legs asserted"
                severity failure;
            checks := checks + 1;

            cas_k := exp_cas_ac(k) or exp_cas_bd(k);

            if (k = 0) then
                cas_km1 := '0';
            else
                cas_km1 := exp_cas_ac(k - 1) or exp_cas_bd(k - 1);
            end if;

            if (cas_k = '1' and cas_km1 = '0') then
                cas_lows := cas_lows + 1;
            end if;

        end loop;

        assert cas_lows = 2
            report "FAIL expected 2 CAS pulses per RAS cycle, found "
                   & integer'image(cas_lows)
            severity failure;
        checks := checks + 1;

        ------------------------------------------------------------------
        -- 4) DRAM AC minimums, expressed in ticks (1 tick = 71.4 ns)
        --    RAS↓ tick 0, first CAS↓ tick 1  -> RAS→CAS  = 71 ns  (min 20)
        --    CAS↑ tick 3, next CAS↓ tick 4   -> gap      = 71 ns  (min 60)
        --    each CAS low for 2+ ticks       -> width    = 143 ns (min 100)
        --    last CAS↓ tick 4, RAS↑ tick 6   -> RAS hold = 143 ns (min 100)
        ------------------------------------------------------------------
        assert exp_ras_n(0) = '0' and exp_cas_n(0) = '1' and exp_cas_n(1) = '0'
            report "FAIL RAS-to-CAS setup: first CAS must trail RAS by one tick"
            severity failure;

        assert exp_cas_n(3) = '1'
            report "FAIL CAS precharge gap missing between the byte pair"
            severity failure;

        assert exp_ras_n(4) = '0' and exp_ras_n(5) = '0'
            report "FAIL RAS must stay low through the second CAS access"
            severity failure;

        assert exp_ras_n(6) = '1' and exp_cas_n(6) = '0'
            report "FAIL RAS must release one tick before the last CAS ends"
            severity failure;
        checks := checks + 4;

        ------------------------------------------------------------------
        -- 5) fetch-window gating: n_vid_c3 = '1' holds all strobes off
        --    (border/blank, and the c3-low CPU contention gap)
        ------------------------------------------------------------------
        n_vid_c3 <= '1';

        for k in 0 to 7 loop

            step(k);

            assert vid_ras = '0' and vid_cas_ac = '0' and vid_cas_bd = '0'
                   and n_vid_ras = '1' and ras_n = '1' and cas_n = '1'
                report "FAIL gating tick " & integer'image(k) & ": a strobe is asserted ("
                       & std_logic'image(vid_ras) & std_logic'image(vid_cas_ac)
                       & std_logic'image(vid_cas_bd) & std_logic'image(n_vid_ras)
                       & std_logic'image(ras_n) & std_logic'image(cas_n) & ")"
                severity failure;
            checks := checks + 1;

        end loop;

        report "PASS: CAS legs never overlap, two CAS per RAS, AC minimums, and "
               & "fetch-window gating"
            severity note;

        ------------------------------------------------------------------
        -- 6) CPU through the merge: with video idle, a Z80 read of 0x4000
        --    pulls the DRAM ras_n / cas_n low; n_vid_ras stays high
        ------------------------------------------------------------------
        wait until falling_edge(clk_14);
        a15    <= '0';
        a14    <= '1';
        mreq_n <= '0';
        rd_n   <= '0';
        wait until rising_edge(clk_14);
        wait for t / 4;

        assert (ras_n = '0' and cas_n = '0')
            report "FAIL cpu merge: ras_n/cas_n not pulled low by a CPU read ("
                   & std_logic'image(ras_n) & std_logic'image(cas_n) & ")"
            severity failure;

        assert n_vid_ras = '1'
            report "FAIL cpu merge: n_vid_ras disturbed by CPU ("
                   & std_logic'image(n_vid_ras) & ")"
            severity failure;
        checks := checks + 2;

        mreq_n <= '1';
        rd_n   <= '1';

        report "PASS: CPU read reaches the DRAM pins through the merge"
            severity note;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
