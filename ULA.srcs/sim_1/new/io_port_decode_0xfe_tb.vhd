----------------------------------------------------------------------------------
-- io_port_decode_0xfe_tb — self-checking TB for the ULA port read/write strobes.
--
-- The DUT is pure combinational with FIVE inputs (a0, ioreq_n, ioreqtw3_n,
-- rd_n, wr_n), so the TB is EXHAUSTIVE: all 2**5 = 32 combinations, both
-- outputs checked against a reference model (64 checks). Some combinations
-- cannot occur in the real machine (ioreq_n low with a0 high, since the PCB
-- makes ioreq_n = /IORQ OR A0; /RD and /WR low together), but each is
-- electrically defined, so all are checked.
--
-- Then four Z80 cycles, driven as they really happen, to name what matters:
--   1. IN  from 0xFE  -> port_rd_n strobes, port_wr_n does not.
--   2. OUT to   0xFE  -> port_wr_n strobes, port_rd_n does not.
--   3. IN  from an ODD port -> no strobe. This is the case an inverted A0
--      would get wrong (it would decode the odd ports instead).
--   4. INTERRUPT ACKNOWLEDGE: /IORQ low with A0 = '0' but neither /RD nor /WR
--      -> no strobe, so the ULA never drives the bus while it carries the
--      interrupt vector.
-- In 1 and 2 the strobe must wait for ioreqtw3_n: /IORQ falling alone (T2,
-- before the contention latch) gives no strobe yet.
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity io_port_decode_0xfe_tb is
end entity io_port_decode_0xfe_tb;

architecture behavioral of io_port_decode_0xfe_tb is

    constant settle : time := 10 ns;

    signal a0         : std_logic := '0';
    signal ioreq_n    : std_logic := '1';
    signal ioreqtw3_n : std_logic := '1';
    signal rd_n       : std_logic := '1';
    signal wr_n       : std_logic := '1';

    signal port_rd_n : std_logic;
    signal port_wr_n : std_logic;

    -- reference model: a strobe is low only when every input to its NOR is low

    function strobe_n (
        a,
        ioreq,
        tw3,
        rw : std_logic
    ) return std_logic is
    begin

        if ((a = '0') and (ioreq = '0') and (tw3 = '0') and (rw = '0')) then
            return '0';
        else
            return '1';
        end if;

    end function strobe_n;

begin

    dut : entity work.io_port_decode_0xfe(structural)
        port map (
            a0         => a0,
            ioreq_n    => ioreq_n,
            ioreqtw3_n => ioreqtw3_n,
            rd_n       => rd_n,
            wr_n       => wr_n,
            port_rd_n  => port_rd_n,
            port_wr_n  => port_wr_n
        );

    stim : process is

        variable checks_v : integer := 0;

        procedure expect (
            want_rd : in std_logic;
            want_wr : in std_logic;
            what    : in string
        ) is
        begin

            assert (port_rd_n = want_rd) and (port_wr_n = want_wr)
                report "FAIL " & what & ": (port_rd_n, port_wr_n) expected "
                       & std_logic'image(want_rd) & std_logic'image(want_wr)
                       & " got " & std_logic'image(port_rd_n)
                       & std_logic'image(port_wr_n)
                severity failure;

            checks_v := checks_v + 2;

        end procedure expect;

        -- drive all five inputs, settle

        procedure drive (
            a,
            ioreq,
            tw3,
            r,
            w : in std_logic
        ) is
        begin

            a0         <= a;
            ioreq_n    <= ioreq;
            ioreqtw3_n <= tw3;
            rd_n       <= r;
            wr_n       <= w;
            wait for settle;

        end procedure drive;

        variable v : std_logic_vector(4 downto 0); -- a0 ioreq tw3 rd wr

    begin

        --------------------------------------------------------------
        -- EXHAUSTIVE: all 32 input combinations against the model
        --------------------------------------------------------------
        for n in 0 to 31 loop

            for i in 0 to 4 loop

                if ((n / (2 ** i)) mod 2 = 1) then
                    v(i) := '1';
                else
                    v(i) := '0';
                end if;

            end loop;

            drive(v(4), v(3), v(2), v(1), v(0));
            expect(strobe_n(v(4), v(3), v(2), v(1)),
                   strobe_n(v(4), v(3), v(2), v(0)),
                   "a0 ioreq_n ioreqtw3_n rd_n wr_n = " & to_string(v));

        end loop;

        report "PASS: all 32 input combinations match the model"
            severity note;

        --------------------------------------------------------------
        -- 1) IN from 0xFE: A0 = '0', ioreq_n follows /IORQ
        --------------------------------------------------------------
        drive('0', '1', '1', '1', '1');                                      -- T1: address out, nothing yet
        expect('1', '1', "IN 0xFE, T1");
        drive('0', '0', '1', '0', '1');                                      -- T2: /IORQ and /RD low, latch not yet
        expect('1', '1', "IN 0xFE, T2 before ioreqtw3_n");
        drive('0', '0', '0', '0', '1');                                      -- TW / T3: latch has caught up
        expect('0', '1', "IN 0xFE, TW/T3");
        drive('0', '1', '0', '1', '1');                                      -- end: /IORQ rises, latch still low
        expect('1', '1', "IN 0xFE, /IORQ released (live term ends it)");
        drive('0', '1', '1', '1', '1');
        report "PASS: IN from 0xFE strobes port_rd_n only, after ioreqtw3_n"
            severity note;

        --------------------------------------------------------------
        -- 2) OUT to 0xFE
        --------------------------------------------------------------
        drive('0', '0', '1', '1', '0');                                      -- T2
        expect('1', '1', "OUT 0xFE, T2 before ioreqtw3_n");
        drive('0', '0', '0', '1', '0');                                      -- TW / T3
        expect('1', '0', "OUT 0xFE, TW/T3");
        drive('0', '1', '1', '1', '1');
        expect('1', '1', "OUT 0xFE, after");
        report "PASS: OUT to 0xFE strobes port_wr_n only, after ioreqtw3_n"
            severity note;

        --------------------------------------------------------------
        -- 3) IN from an ODD port: A0 = '1', so the PCB holds ioreq_n high
        --------------------------------------------------------------
        drive('1', '1', '1', '0', '1');
        expect('1', '1', "IN from an odd port");
        drive('1', '1', '1', '1', '0');
        expect('1', '1', "OUT to an odd port");
        report "PASS: odd ports give no strobe (A0 is not inverted)"
            severity note;

        --------------------------------------------------------------
        -- 4) INTERRUPT ACKNOWLEDGE: /IORQ low, A0 may be '0', no /RD or /WR
        --------------------------------------------------------------
        drive('0', '0', '1', '1', '1');
        expect('1', '1', "interrupt acknowledge, early");
        drive('0', '0', '0', '1', '1');
        expect('1', '1', "interrupt acknowledge, latch caught up");
        report "PASS: interrupt acknowledge fires neither strobe"
            severity note;

        report "ALL TESTS PASSED (" & integer'image(checks_v) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
