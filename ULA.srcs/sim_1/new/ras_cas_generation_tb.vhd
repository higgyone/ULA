----------------------------------------------------------------------------------
-- ras_cas_generation_tb — self-checking TB for the synchronous RAS/CAS generator.
--
-- What it proves:
--   1. Waveform — walking the tick index {c1, c0, phase} = 0..7 through one
--      4-pixel DRAM cycle (fetch window active, CPU idle) produces the registered
--      RAS/CAS pattern from the block's header table: one RAS spanning the cycle
--      with TWO separate CAS pulses (the byte pair), a precharge gap between them,
--      and RAS releasing one tick before the last CAS.
--   2. Byte pair per RAS — exactly two CAS assertions per cycle, so a full
--      c3-high burst (two cycles) fetches the four bytes A/B/C/D.
--   3. Fetch-window gating — with n_vid_c3 = '1' the video strobes stay
--      de-asserted at every tick. This covers both the border/blank and the
--      c3-low CPU contention gap.
--   4. CPU merge — with the video side idle, driving cpu_ras / cpu_cas low pulls
--      n_ras / n_cas low (active-low merge), while the n_vid_ras tap is
--      unaffected by the CPU side.
--   5. DRAM AC minimums — the tick positions are checked to give RAS→CAS,
--      CAS-high gap, CAS-low width and RAS-hold that clear the datasheet limits.
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
    signal cpu_ras  : std_logic := '1';
    signal cpu_cas  : std_logic := '1';

    signal n_ras     : std_logic;
    signal n_cas     : std_logic;
    signal n_vid_ras : std_logic;

    -- expected registered strobes per tick (fetch window active, CPU idle)
    --                          tick:   0    1    2    3    4    5    6    7

    type slv8 is array (0 to 7) of std_logic;

    constant exp_ras : slv8 := ('0', '0', '0', '0', '0', '0', '1', '1');
    constant exp_cas : slv8 := ('1', '0', '0', '1', '0', '0', '0', '1');

begin

    dut : entity work.ras_cas_generation(synchronous)
        port map (
            clk_14    => clk_14,
            clk_7     => clk_7,
            c0        => c0,
            c1        => c1,
            n_vid_c3  => n_vid_c3,
            cpu_ras   => cpu_ras,
            cpu_cas   => cpu_cas,
            n_ras     => n_ras,
            n_cas     => n_cas,
            n_vid_ras => n_vid_ras
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

    begin

        ------------------------------------------------------------------
        -- 1) one full 4-pixel DRAM cycle, fetch active, CPU idle
        ------------------------------------------------------------------
        n_vid_c3 <= '0';
        cpu_ras  <= '1';
        cpu_cas  <= '1';

        for k in 0 to 7 loop

            wait until falling_edge(clk_14);
            set_tick(k);
            wait until rising_edge(clk_14);                                                 -- register captures this tick
            wait for t / 4;                                                                 -- let the registered outputs settle

            assert n_ras = exp_ras(k)
                report "FAIL tick " & integer'image(k) & ": n_ras expected "
                       & std_logic'image(exp_ras(k)) & " got " & std_logic'image(n_ras)
                severity failure;

            assert n_cas = exp_cas(k)
                report "FAIL tick " & integer'image(k) & ": n_cas expected "
                       & std_logic'image(exp_cas(k)) & " got " & std_logic'image(n_cas)
                severity failure;

            assert n_vid_ras = exp_ras(k)
                report "FAIL tick " & integer'image(k) & ": n_vid_ras expected "
                       & std_logic'image(exp_ras(k)) & " got " & std_logic'image(n_vid_ras)
                severity failure;

            checks := checks + 3;

        end loop;

        ------------------------------------------------------------------
        -- 2) the cycle must contain exactly TWO separate CAS pulses
        --    (the byte pair under one RAS), not one long strobe
        ------------------------------------------------------------------
        cas_lows := 0;

        for k in 0 to 7 loop

            if (exp_cas(k) = '0' and (k = 0 or exp_cas(k - 1) = '1')) then
                cas_lows := cas_lows + 1;
            end if;

        end loop;

        assert cas_lows = 2
            report "FAIL expected 2 CAS pulses per RAS cycle, found "
                   & integer'image(cas_lows)
            severity failure;
        checks := checks + 1;

        ------------------------------------------------------------------
        -- 3) DRAM AC minimums, expressed in ticks (1 tick = 71.4 ns)
        --    RAS↓ tick 0, first CAS↓ tick 1  -> RAS→CAS  = 71 ns  (min 20)
        --    CAS↑ tick 3, next CAS↓ tick 4   -> gap      = 71 ns  (min 60)
        --    each CAS low for 2 ticks        -> width    = 143 ns (min 100)
        --    last CAS↓ tick 4, RAS↑ tick 6   -> RAS hold = 143 ns (min 100)
        ------------------------------------------------------------------
        assert exp_ras(0) = '0' and exp_cas(0) = '1' and exp_cas(1) = '0'
            report "FAIL RAS-to-CAS setup: first CAS must trail RAS by one tick"
            severity failure;

        assert exp_cas(3) = '1'
            report "FAIL CAS precharge gap missing between the byte pair"
            severity failure;

        assert exp_ras(4) = '0' and exp_ras(5) = '0'
            report "FAIL RAS must stay low through the second CAS access"
            severity failure;

        assert exp_ras(6) = '1' and exp_cas(6) = '0'
            report "FAIL RAS must release one tick before the last CAS ends"
            severity failure;
        checks := checks + 4;

        ------------------------------------------------------------------
        -- 4) fetch-window gating: n_vid_c3 = '1' holds all strobes high
        --    (border/blank, and the c3-low CPU contention gap)
        ------------------------------------------------------------------
        n_vid_c3 <= '1';

        for k in 0 to 7 loop

            wait until falling_edge(clk_14);
            set_tick(k);
            wait until rising_edge(clk_14);
            wait for t / 4;

            assert (n_ras = '1' and n_cas = '1' and n_vid_ras = '1')
                report "FAIL gating tick " & integer'image(k) & ": strobes not all '1' ("
                       & std_logic'image(n_ras) & std_logic'image(n_cas)
                       & std_logic'image(n_vid_ras) & ")"
                severity failure;
            checks := checks + 1;

        end loop;

        ------------------------------------------------------------------
        -- 5) CPU merge: with video idle, the CPU strobes pull n_ras/n_cas
        --    low; n_vid_ras stays high (it is the video tap only)
        ------------------------------------------------------------------
        wait until falling_edge(clk_14);
        cpu_ras <= '0';
        cpu_cas <= '0';
        wait until rising_edge(clk_14);
        wait for t / 4;

        assert (n_ras = '0' and n_cas = '0')
            report "FAIL cpu merge: n_ras/n_cas not pulled low by CPU ("
                   & std_logic'image(n_ras) & std_logic'image(n_cas) & ")"
            severity failure;

        assert n_vid_ras = '1'
            report "FAIL cpu merge: n_vid_ras disturbed by CPU ("
                   & std_logic'image(n_vid_ras) & ")"
            severity failure;
        checks := checks + 3;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
