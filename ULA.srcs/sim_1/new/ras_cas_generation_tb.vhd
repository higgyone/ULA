----------------------------------------------------------------------------------
-- ras_cas_generation_tb — self-checking TB for the synchronous RAS/CAS generator.
--
-- What it proves:
--   1. Waveform: walking the pixel index c2c1c0 = 0..7 through one character cell
--      (display fetch active, CPU idle) produces the expected registered RAS/CAS
--      pattern from the block's header table.
--   2. Fetch-window gating: with n_vid_c3 = '1' the video strobes stay de-asserted
--      no matter what the pixel index does.
--   3. CPU merge: with the video side idle, driving cpu_ras / cpu_cas low pulls
--      n_ras / n_cas low (active-low OR-merge), while the n_vid_ras tap is
--      unaffected by the CPU side.
--
-- The DUT registers its strobes on clk_14, so the drive pattern is: set the pixel
-- index on a FALLING clk_14 edge (clean setup), let the next RISING edge capture
-- it, then sample the outputs. Any mismatch is fatal; a clean run prints
-- "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library std;
    use std.env.all;

entity ras_cas_generation_tb is
end entity ras_cas_generation_tb;

architecture behavioral of ras_cas_generation_tb is

    constant t : time := 72 ns; -- clk_14 period (~14 MHz)

    signal clk_14   : std_logic := '0';
    signal c0       : std_logic := '0';
    signal c1       : std_logic := '0';
    signal c2       : std_logic := '0';
    signal n_vid_c3 : std_logic := '1';
    signal cpu_ras  : std_logic := '1';
    signal cpu_cas  : std_logic := '1';

    signal n_ras     : std_logic;
    signal n_cas     : std_logic;
    signal n_vid_ras : std_logic;

    -- expected registered strobes per pixel index (display fetch, CPU idle)

    type slv8 is array (0 to 7) of std_logic;

    constant exp_ras  : slv8 := ('0', '0', '0', '0', '0', '1', '1', '1');
    constant exp_cas  : slv8 := ('1', '0', '1', '0', '0', '1', '1', '1');
    constant exp_vras : slv8 := ('0', '0', '0', '0', '0', '1', '1', '1');

    -- drive the pixel index onto c2/c1/c0 (called on a falling clk_14 edge)

    procedure set_pix (
        signal c2v : out std_logic;
        signal c1v : out std_logic;
        signal c0v : out std_logic;
        p          : in  integer
    ) is

        variable pv : std_logic_vector(2 downto 0);

    begin

        pv  := std_logic_vector(to_unsigned(p, 3));
        c2v <= pv(2);
        c1v <= pv(1);
        c0v <= pv(0);

    end procedure set_pix;

begin

    dut : entity work.ras_cas_generation(synchronous)
        port map (
            clk_14    => clk_14,
            c0        => c0,
            c1        => c1,
            c2        => c2,
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

        variable checks : integer := 0;

    begin

        --------------------------------------------------------------
        -- 1) waveform over one character cell (fetch active, CPU idle)
        --------------------------------------------------------------
        n_vid_c3 <= '0';
        cpu_ras  <= '1';
        cpu_cas  <= '1';

        for p in 0 to 7 loop

            wait until falling_edge(clk_14);
            set_pix(c2, c1, c0, p);
            wait until rising_edge(clk_14);                                                          -- register captures this pixel
            wait for t / 4;                                                                          -- let the registered outputs settle

            assert n_ras = exp_ras(p)
                report "FAIL pix " & integer'image(p) & ": n_ras expected "
                       & std_logic'image(exp_ras(p)) & " got " & std_logic'image(n_ras)
                severity failure;
            assert n_cas = exp_cas(p)
                report "FAIL pix " & integer'image(p) & ": n_cas expected "
                       & std_logic'image(exp_cas(p)) & " got " & std_logic'image(n_cas)
                severity failure;
            assert n_vid_ras = exp_vras(p)
                report "FAIL pix " & integer'image(p) & ": n_vid_ras expected "
                       & std_logic'image(exp_vras(p)) & " got " & std_logic'image(n_vid_ras)
                severity failure;
            checks := checks + 3;

        end loop;

        --------------------------------------------------------------
        -- 2) fetch-window gating: n_vid_c3 = '1' holds all strobes high
        --------------------------------------------------------------
        n_vid_c3 <= '1';

        for p in 0 to 7 loop

            wait until falling_edge(clk_14);
            set_pix(c2, c1, c0, p);
            wait until rising_edge(clk_14);
            wait for t / 4;

            assert (n_ras = '1' and n_cas = '1' and n_vid_ras = '1')
                report "FAIL gating pix " & integer'image(p) & ": strobes not all '1' ("
                       & std_logic'image(n_ras) & std_logic'image(n_cas)
                       & std_logic'image(n_vid_ras) & ")"
                severity failure;
            checks := checks + 1;

        end loop;

        --------------------------------------------------------------
        -- 3) CPU merge: with video idle (n_vid_c3='1'), the CPU strobes
        --    pull n_ras / n_cas low; n_vid_ras stays high (video tap)
        --------------------------------------------------------------
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
            report "FAIL cpu merge: n_vid_ras disturbed by CPU (" & std_logic'image(n_vid_ras) & ")"
            severity failure;
        checks := checks + 3;

        report "ALL TESTS PASSED (" & integer'image(checks) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
