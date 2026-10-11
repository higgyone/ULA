----------------------------------------------------------------------------------
-- border_reg_tb — self-checking TB for the border colour register.
--
-- What it proves:
--   1. POWER-ON: before any write the border is black (000), from
--      data_latch_1_bit's seed.
--   2. ALL 8 COLOURS: an OUT to the ULA port with each colour 0..7 sets
--      b2 b1 b0 to it, in the right bit order (b0 blue, b1 red, b2 green).
--   3. HOLD: after the write, the data bus carries every other pattern (as
--      it does all the time: DRAM data, other I/O) and the border does not
--      move.
--   4. TRANSPARENT DURING THE WRITE: while port_wr_n is low the outputs
--      follow the bus. That is the book's latch, not an edge flip-flop.
--   5. THE VALUE AT THE END OF THE WRITE STICKS: if the bus changes part-way
--      through a write, the value present when port_wr_n rises is kept.
--   6. Z80 TIMING: the data is put on the bus before the write strobe falls
--      and removed after it rises, as the Z80 does in an OUT; the colour
--      written is the colour held.
--
-- Any mismatch is fatal; a clean run prints "ALL TESTS PASSED".
----------------------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

library std;
    use std.env.all;

entity border_reg_tb is
end entity border_reg_tb;

architecture behavioral of border_reg_tb is

    constant settle : time := 10 ns;  -- > the latch's after-tg chain
    constant t_data : time := 50 ns;  -- Z80: data before WR falls, and after it rises
    constant t_wr   : time := 400 ns; -- write strobe low

    type colour_names_t is array (0 to 7) of string(1 to 7);

    constant colour_name : colour_names_t :=
    (
        "black  ",
        "blue   ",
        "red    ",
        "magenta",
        "green  ",
        "cyan   ",
        "yellow ",
        "white  "
    );

    signal di        : std_logic_vector(2 downto 0) := "000"; -- data bits 2..0
    signal port_wr_n : std_logic                    := '1';

    signal b : std_logic_vector(2 downto 0); -- b2 b1 b0 = green red blue

    signal checks : integer := 0;

    function bits_of (
        n : integer
    ) return std_logic_vector is

        variable v : std_logic_vector(2 downto 0);

    begin

        for i in 0 to 2 loop

            if ((n / (2 ** i)) mod 2 = 1) then
                v(i) := '1';
            else
                v(i) := '0';
            end if;

        end loop;

        return v;

    end function bits_of;

begin

    dut : entity work.border_reg(structural)
        port map (
            di_0      => di(0),
            di_1      => di(1),
            di_2      => di(2),
            port_wr_n => port_wr_n,
            b0        => b(0),
            b1        => b(1),
            b2        => b(2)
        );

    stim : process is

        variable checks_v : integer := 0;

        procedure expect (
            want : in std_logic_vector(2 downto 0);
            what : in string
        ) is
        begin

            assert b = want
                report "FAIL " & what & ": border (green red blue) expected "
                       & to_string(want) & " got " & to_string(b)
                severity failure;

            checks_v := checks_v + 1;

        end procedure expect;

        -- an OUT to the ULA port with Z80 timing: data first, then the strobe,
        -- data held a little after the strobe ends, then the bus moves on

        procedure out_port (
            colour : in integer
        ) is
        begin

            di        <= bits_of(colour);
            wait for t_data;
            port_wr_n <= '0';
            wait for t_wr;
            port_wr_n <= '1';
            wait for t_data;
            di        <= not bits_of(colour);  -- bus moves on to other traffic
            wait for settle;

        end procedure out_port;

    begin

        --------------------------------------------------------------
        -- 1) POWER-ON: black before any write
        --------------------------------------------------------------
        -- bus busy, but no write
        di <= "111";
        wait for settle;
        expect("000", "power-on, before any write");

        report "PASS: border is black at power-on"
            severity note;

        --------------------------------------------------------------
        -- 2) + 3) + 6) every colour, written then held while the bus
        --    carries every other pattern
        --------------------------------------------------------------
        for colour in 0 to 7 loop

            out_port(colour);
            expect(bits_of(colour), "after OUT " & colour_name(colour));

            for other in 0 to 7 loop

                di <= bits_of(other);
                wait for settle;
                expect(bits_of(colour), "holding " & colour_name(colour)
                       & " with bus = " & integer'image(other));

            end loop;

        end loop;

        report "PASS: all 8 colours written with Z80 timing and held while the bus moves"
            severity note;

        --------------------------------------------------------------
        -- 4) transparent while port_wr_n is low
        --------------------------------------------------------------
        port_wr_n <= '0';

        for colour in 0 to 7 loop

            di <= bits_of(colour);
            wait for settle;
            expect(bits_of(colour), "transparent during write, bus = "
                   & colour_name(colour));

        end loop;

        report "PASS: outputs follow the bus while the write strobe is low (latch)"
            severity note;

        --------------------------------------------------------------
        -- 5) the value present when port_wr_n rises is the one kept
        --------------------------------------------------------------
        -- blue at the start of the write, yellow by the end of it
        di        <= bits_of(1);
        wait for settle;
        di        <= bits_of(6);
        wait for settle;
        port_wr_n <= '1';
        wait for settle;
        di        <= bits_of(1);
        wait for settle;
        expect(bits_of(6), "value at the end of the write (yellow) kept");

        report "PASS: the value on the bus when the write ends is the one held"
            severity note;

        checks <= checks_v;
        wait for 1 ns;

        report "ALL TESTS PASSED (" & integer'image(checks_v) & " checks)"
            severity note;
        finish;

    end process stim;

end architecture behavioral;
