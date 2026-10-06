----------------------------------------------------------------------------------
-- contention_handler_3_tb — self-checking TB for the CPU clock and contention.
--
-- A small Z80 bus model runs real memory and I/O cycles against the clock the
-- DUT produces, and the TB measures how long each cycle takes. The ULA's
-- horizontal counter (c0, c2, c3) is driven by a free-running 16-pixel counter.
--
-- ── Timing units ─────────────────────────────────────────────────────
--   1 pixel = 143 ns, 1 T-state = 2 pixels = 286 ns, 8 T-states = 16 pixels.
--   A Z80 T-state's position in the ULA cycle is idx = c3c2c1 at its start
--   (0..7). The contention window is c2 OR c3: idx 2..7, 6 T-states of 8.
--
-- ── Expected results ─────────────────────────────────────────────────
--   MEMORY: an access to 0x4000..0x7FFF whose T1 starts at idx is delayed by
--       d(idx) = 0, 6, 5, 4, 3, 2, 1, 0      (idx = 0..7)
--   which is the documented 48K pattern 6,5,4,3,2,1,0,0 starting at idx 1.
--   Accesses to the ROM or the upper 32K, and any access in the border, are
--   never delayed. Only T1 is checked: mreqt23 masks T2 and T3, so a cycle
--   whose T3 lands inside the window is not held a second time.
--
--   I/O: the documented 48K rules, written as an emulator would apply them
--   ("C:n" = apply d(idx) at the current T-state, then advance n T-states;
--   "N:n" = advance n with no check), using the same d table:
--     high byte 0x40..0x7F, even port   C:1, C:3
--     high byte 0x40..0x7F, odd port    C:1, C:1, C:1, C:1
--     other high byte,      even port   N:1, C:3
--     other high byte,      odd port    N:4
--   The TB computes each expected cycle length from these rules and compares
--   it with what the gates actually do.
--
-- ── Two things the book does not pin down (generics) ─────────────────
--   g_z80_inverted  TRUE: the Z80 is clocked from NOT cpuclk (one net inversion
--                   between cpuclk and the Z80). FALSE (the real circuit): from
--                   cpuclk, through two inverting transistors that cancel.
--   g_c0_delay_ns / when c0 and c2/c3 change at the SAME pixel boundary, which
--   g_c23_delay_ns  reaches the DUT first. Only the edges at pixels 4 and 16
--                   (window opening / closing) care, but there it decides
--                   whether the first contended T-state gets the full 6.
--
--   All four combinations were run (2026-10-06). Only the DEFAULTS reproduce
--   every documented pattern:
--     g_z80_inverted = FALSE, c2/c3 reach the DUT 5 ns BEFORE c0   ALL PASS
--     g_z80_inverted = FALSE, c0 first (plain ripple order)
--         the first contended position loses its delay entirely (idx 1
--         gives 0 instead of 6), and the I/O patterns go wrong with it
--     g_z80_inverted = TRUE (either order)
--         memory is fine, but the ULA-port I/O contention (the C:3 after T2)
--         NEVER happens: IORQ falls in T2's first half, which in this
--         polarity is when the ioreqtw3 latch is open, so it masks itself
--         straight away. Even ports are never delayed.
--   (1) is CONFIRMED by the circuit: cpuclk passes through TWO inverting
--   transistors before the Z80, which cancel:
--     cpuclk -> ULA output transistor -> pin 32 (phicpu_n)
--            -> PCB transistor        -> Z80 clock = cpuclk
--   So the Z80 runs on cpuclk (= c0 while running) and is held HIGH with it,
--   which is what g_z80_inverted = FALSE models.
--   (2) still stands: the real ULA must let c2/c3 settle before c0's edge
--   reaches this block (with all three changing at the same instant, the window
--   opening gives a 1 ns runt pulse on the CPU clock). The documented "6"
--   shows the real chip resolves it that way; the FPGA must guarantee it by
--   design.
--
-- Also checked throughout: the Z80 clock never has a runt pulse (every high or
-- low phase lasts at least most of a pixel).
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity contention_handler_3_tb is
    generic (
        g_z80_inverted : boolean := false;
        g_c0_delay_ns  : natural := 5;
        g_c23_delay_ns : natural := 0
    );
end entity contention_handler_3_tb;

architecture behavioral of contention_handler_3_tb is

    constant t_pix   : time := 143 ns;
    constant t_state : time := 2 * t_pix;
    constant t_addr  : time := 10 ns;  -- Z80: address after the T1 rising edge
    constant t_ctrl  : time := 20 ns;  -- Z80: MREQ / IORQ after their edges
    constant t_runt  : time := 100 ns; -- shortest legal clock phase here

    type d_table_t is array (0 to 7) of integer;

    -- expected memory delay by T1 position (see header)
    constant d_tab : d_table_t := (0, 6, 5, 4, 3, 2, 1, 0);

    -- DUT inputs
    signal c0_n    : std_logic := '1';
    signal c2      : std_logic := '0';
    signal c3      : std_logic := '0';
    signal a14     : std_logic := '0';
    signal a15     : std_logic := '0';
    signal a0      : std_logic := '1';
    signal mreq_n  : std_logic := '1';
    signal iorq_n  : std_logic := '1';
    signal ioreq_n : std_logic;
    signal border  : std_logic := '0';

    -- DUT outputs
    signal cpuclk     : std_logic;
    signal phicpu_n   : std_logic;
    signal ioreqtw3_n : std_logic;

    -- the Z80's clock (pin 32 through the PCB transistor) and the pixel count
    signal zclk : std_logic;
    signal pix  : integer range 0 to 15 := 0;

    signal clock_checks : integer := 0;

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

    -- one emulator step: C:n applies d at the current position, then advances

    procedure contend (
        pos   : inout integer;
        total : inout integer;
        n     : in    integer;
        check : in    boolean
    ) is
    begin

        if (check) then
            total := total + d_tab(pos mod 8);
            pos   := pos + d_tab(pos mod 8);
        end if;

        total := total + n;
        pos   := pos + n;

    end procedure contend;

begin

    -- the ULA-port decode the book puts outside this block
    ioreq_n <= a0 or iorq_n;

    dut : entity work.contention_handler_3(structural)
        port map (
            c0_n       => c0_n,
            a14        => a14,
            ioreq_n    => ioreq_n,
            a15        => a15,
            c2         => c2,
            c3         => c3,
            border     => border,
            mreq_n     => mreq_n,
            cpuclk     => cpuclk,
            phicpu_n   => phicpu_n,
            ioreqtw3_n => ioreqtw3_n
        );

    -- The PCB transistor inverts pin 32 (phicpu_n) back for the Z80, so by
    -- default the Z80 runs on cpuclk. TRUE leaves the pin uninverted (one net
    -- inversion), kept to show what would break.
    zclk <= phicpu_n when g_z80_inverted else
            not phicpu_n;

    -- the pin is the complement of the internal clock, one tg later
    pin_check : process is
    begin

        wait on cpuclk;
        wait for 2 ns;

        assert phicpu_n = not cpuclk
            report "FAIL pin 32: phicpu_n is not the complement of cpuclk at "
                   & time'image(now)
            severity failure;

    end process pin_check;

    ------------------------------------------------------------------
    -- free-running 16-pixel horizontal counter (c0, c2, c3)
    ------------------------------------------------------------------
    counter : process is

        variable p : integer := 0;

    begin

        loop

            pix  <= p;
            c0_n <= not bit_of(p, 0) after g_c0_delay_ns * 1 ns;
            c2   <= bit_of(p, 2) after g_c23_delay_ns * 1 ns;
            c3   <= bit_of(p, 3) after g_c23_delay_ns * 1 ns;
            wait for t_pix;
            p    := (p + 1) mod 16;

        end loop;

    end process counter;

    ------------------------------------------------------------------
    -- no runt pulses on the Z80 clock
    ------------------------------------------------------------------
    runt_watch : process is

        variable last : time    := 0 ns;
        variable n    : integer := 0;

    begin

        wait until zclk'event;
        last := now;

        loop

            wait until zclk'event;

            assert now - last >= t_runt
                report "FAIL runt pulse on the Z80 clock: phase of "
                       & time'image(now - last) & " ending at " & time'image(now)
                severity failure;

            n            := n + 1;
            clock_checks <= n;
            last         := now;

        end loop;

    end process runt_watch;

    ------------------------------------------------------------------
    -- the Z80
    ------------------------------------------------------------------
    z80 : process is

        variable checks : integer := 0;
        variable len    : integer;

        -- wait for Z80 clock rising edges until one starts T-state idx

        procedure goto_t1 (
            idx : in integer
        ) is
        begin

            loop

                wait until rising_edge(zclk);
                exit when pix / 2 = idx;

            end loop;

        end procedure goto_t1;

        -- park the bus: ROM address, odd port bit, no requests

        procedure park is
        begin

            a15    <= '0';
            a14    <= '0';
            a0     <= '1';
            mreq_n <= '1';
            iorq_n <= '1';

        end procedure park;

        -- length in T-states from the current rising edge (T1) to the
        -- rising edge that starts the next T1

        impure function t_states (
            t_start : time
        ) return integer is
        begin

            return (now - t_start + t_state / 2) / t_state;

        end function t_states;

        -- a memory read: T1, T2, T3. Call at the T1 rising edge.

        procedure mem_read (
            hi15 : in    std_logic;
            hi14 : in    std_logic;
            n    : out   integer
        ) is

            variable t0 : time;

        begin

            t0     := now;
            wait for t_addr;
            a15    <= hi15;
            a14    <= hi14;
            wait until falling_edge(zclk); -- T1, second half
            wait for t_ctrl;
            mreq_n <= '0';
            wait until rising_edge(zclk);  -- T2
            wait until rising_edge(zclk);  -- T3
            wait until falling_edge(zclk);
            wait for t_ctrl;
            mreq_n <= '1';
            wait until rising_edge(zclk);  -- next T1
            n      := t_states(t0);
            park;

        end procedure mem_read;

        -- an I/O cycle: T1, T2, TW, T3. Call at the T1 rising edge.

        procedure io_cycle (
            hi15 : in    std_logic;
            hi14 : in    std_logic;
            lo0  : in    std_logic;
            n    : out   integer
        ) is

            variable t0 : time;

        begin

            t0     := now;
            wait for t_addr;
            a15    <= hi15;
            a14    <= hi14;
            a0     <= lo0;
            wait until rising_edge(zclk);  -- T2
            wait for t_ctrl;
            iorq_n <= '0';
            wait until rising_edge(zclk);  -- TW
            wait until rising_edge(zclk);  -- T3
            wait until falling_edge(zclk);
            wait for t_ctrl;
            iorq_n <= '1';
            wait until rising_edge(zclk);  -- next T1
            n      := t_states(t0);
            park;

        end procedure io_cycle;

        procedure expect (
            got  : in integer;
            want : in integer;
            what : in string
        ) is
        begin

            assert got = want
                report "FAIL " & what & ": " & integer'image(got)
                       & " T-states, expected " & integer'image(want)
                severity failure;

            checks := checks + 1;

        end procedure expect;

        -- expected I/O cycle length from the emulator rules

        impure function io_expected (
            idx       : integer;
            contended : boolean;
            even      : boolean
        ) return integer is

            variable p : integer;
            variable t : integer;

        begin

            p := idx;
            t := 0;

            if (contended and even) then
                contend(p, t, 1, true);
                contend(p, t, 3, true);
            elsif (contended) then
                contend(p, t, 1, true);
                contend(p, t, 1, true);
                contend(p, t, 1, true);
                contend(p, t, 1, true);
            elsif (even) then
                contend(p, t, 1, false);
                contend(p, t, 3, true);
            else
                contend(p, t, 4, false);
            end if;

            return t;

        end function io_expected;

    begin

        park;
        wait for 10 * t_state;                     -- let the latches settle

        --------------------------------------------------------------
        -- 1) MEMORY: delay by T1 position, contended address
        --------------------------------------------------------------
        for idx in 0 to 7 loop

            goto_t1(idx);
            mem_read('0', '1', len);
            expect(len, 3 + d_tab(idx), "memory read 0x4000, T1 at idx "
                   & integer'image(idx));

        end loop;

        report "PASS: memory contention 0x4000 by T1 position = 0,6,5,4,3,2,1,0"
            severity note;

        --------------------------------------------------------------
        -- 2) MEMORY: ROM and upper 32K never delayed
        --------------------------------------------------------------
        for idx in 0 to 7 loop

            goto_t1(idx);
            mem_read('0', '0', len);
            expect(len, 3, "memory read 0x0000 (ROM), T1 at idx " & integer'image(idx));

            goto_t1(idx);
            mem_read('1', '0', len);
            expect(len, 3, "memory read 0x8000, T1 at idx " & integer'image(idx));

        end loop;

        report "PASS: ROM and upper-32K reads are never delayed"
            severity note;

        --------------------------------------------------------------
        -- 3) BORDER: no contention at any position
        --------------------------------------------------------------
        border <= '1';

        for idx in 0 to 7 loop

            goto_t1(idx);
            mem_read('0', '1', len);
            expect(len, 3, "memory read 0x4000 in the border, T1 at idx "
                   & integer'image(idx));

        end loop;

        border <= '0';

        report "PASS: no contention in the border"
            severity note;

        --------------------------------------------------------------
        -- 4) I/O: the four documented 48K patterns at every position
        --------------------------------------------------------------
        for idx in 0 to 7 loop

            goto_t1(idx);
            io_cycle('0', '1', '0', len);
            expect(len, io_expected(idx, true, true),
                   "I/O 0x40xx even (C:1, C:3), T1 at idx " & integer'image(idx));

            goto_t1(idx);
            io_cycle('0', '1', '1', len);
            expect(len, io_expected(idx, true, false),
                   "I/O 0x40xx odd (C:1 x4), T1 at idx " & integer'image(idx));

            goto_t1(idx);
            io_cycle('0', '0', '0', len);
            expect(len, io_expected(idx, false, true),
                   "I/O 0x00xx even (N:1, C:3), T1 at idx " & integer'image(idx));

            goto_t1(idx);
            io_cycle('0', '0', '1', len);
            expect(len, io_expected(idx, false, false),
                   "I/O 0x00xx odd (N:4), T1 at idx " & integer'image(idx));

        end loop;

        report "PASS: all four I/O contention patterns at every T1 position"
            severity note;

        report "ALL TESTS PASSED (" & integer'image(checks) & " cycle checks, "
               & integer'image(clock_checks) & " clock phases checked for runts)"
            severity note;
        finish;

    end process z80;

end architecture behavioral;
