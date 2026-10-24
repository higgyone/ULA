----------------------------------------------------------------------
-- data_latch_1_bit — one bit of the ULA video data latch
--
-- Gate-accurate single bit of the 8-bit latch that captures a byte
-- returned from display RAM before it is fanned out to the pixel shift
-- register (bitmap) and the attribute path. Built from four NOR gates:
-- a feed-forward input stage gated by the enable, plus a two-NOR
-- cross-coupled SR latch. Topology mirrors the discrete NOR-gate
-- drawing in Chris Smith's "The ZX Spectrum ULA".
--
-- This is a transparent D LATCH, not an edge-triggered flip-flop: it
-- has a single gated SR latch (half the network of d_ff_nor's
-- master-slave). While the enable holds it transparent, q tracks d;
-- when the enable deasserts, q freezes the last sampled value.
--
--   Enable polarity: e is ACTIVE-LOW.
--     e='0' -> transparent (q follows d)
--     e='1' -> hold / latched (q frozen, d ignored)
--   i.e. the RISING edge of e captures the data bit. In the ULA the port
--   is driven by e = NOT datalatch, so the upstream (active-high)
--   'datalatch' strobe is transparent-high / hold-low as expected; the
--   active-low sense here is that inverter absorbed into the interface.
--
-- Topology:
--
--   input stage (feed-forward, gated by e):
--      s_b_out = NOR(e, d)        -- = not d when e='0'; forced 0 when e='1'
--      s_a_out = NOR(e, s_b_out)      -- =     d when e='0'; forced 0 when e='1'
--
--   SR latch (2 cross-coupled NORs):
--      s_c_out = NOR(s_a_out, s_d_out)
--      s_d_out = NOR(s_b_out, s_c_out)
--
--      q     = s_d_out
--      q_n = s_c_out
--
--   With e='1' both s_a_out and s_b_out are 0, so the SR latch sees no set/reset
--   and holds. With e='0', s_a_out=d and s_b_out=not d drive it to q=d.
--
-- Characteristic table:
--
--   e    d   |  q(next)   q_n(next)
--   ---  --  |  -------   -----------
--    0   0   |    0           1       transparent: q = d
--    0   1   |    1           0
--    1   X   |    q         not q     hold (latched)
--
-- Output use: q_n is the active-low tap that feeds the pixel shift
-- register's data_n load input — the two active-low conventions cancel,
-- so the shift register loads the TRUE pixel value. q (true polarity)
-- heads toward the attribute / colour path. Both are brought out.
--
-- Gate delay `TG` and init values (simulation only). The s_c_out/s_d_out pair is
-- cross-coupled, so like d_ff_nor / single_bit_shift_register every NOR
-- carries an `after TG` inertial delay; without it the loop re-evaluates
-- within one simulation instant and xsim/GHDL delta-spin to their
-- iteration guard (a t=0 hang). The four internal signals are seeded to
-- the "transparent, holding 0" resting state (e='0', d='0', q='0') so the
-- network starts defined instead of 'U'. Both are simulation-only: the
-- gate model is not synthesised at all (see below).
--
-- ── Two models: gate_model (simulation) / fpga_datalatch (FPGA) ─────
--   Two generate branches, picked by fpga_build from ula_build_pkg
--   (ula_build_pkg_sim.vhd = false in simulation, ula_build_pkg_fpga.vhd
--   = true in synthesis), the same scheme as d_ff_nor:
--
--   fpga_build = false  the four NOR gates above, with `after TG`.
--                       Gate-accurate; every testbench uses this.
--   fpga_build = true   a real FPGA latch (LDCE): a process that assigns
--                       s_q <= d only while e = '0', with no else, so s_q
--                       must remember its value when e = '1'. Same
--                       characteristic table.
--
--   Why: on an FPGA the cross-coupled NORs become a LUT feeding back into
--   itself (a combinational loop) that Vivado cannot time. 19 instances
--   use this cell (the pixel, attribute and attribute-output latches, the
--   border and MIC / speaker registers, video_en, the row-A0 latch, the
--   burst parity latch, and contention_handler_3's two latches, whose CPU
--   clock hold feeds back through them).
--
--   Latch, not flip-flop: there is no clock edge. The process must be
--   sensitive to d as well as e, because q follows d continuously while
--   transparent; with only e in the list, simulation would update q only
--   when e changes while the hardware latch follows d (a sim/hardware
--   mismatch). Vivado reports "inferring latch" for this cell: in most
--   designs that warning means a forgotten else, here it is intended.
--
--   s_q := '0' is the power-up value on the FPGA (the bitstream loads it),
--   matching the gate model's seed. It matters: some of these latches stay
--   closed long after power-up (border_reg until the first OUT to 0xFE).
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;
    use work.ula_build_pkg.all;

entity data_latch_1_bit is
    port (
        e   : in    std_logic; -- active-low enable (= not datalatch): '0' transparent, '1' hold
        d   : in    std_logic; -- data bit in (from display RAM byte)
        q   : out   std_logic; -- latched data (true)
        q_n : out   std_logic  -- latched data (active-low) -> shift-reg data_n
    );
end entity data_latch_1_bit;

architecture structural of data_latch_1_bit is

    -- Seeded to the "transparent, holding 0" state (e='0', d='0', q='0'):
    --   s_b_out = NOR(e, d)    = NOR(0,0) = 1
    --   s_a_out = NOR(e, s_b_out)  = NOR(0,1) = 0
    --   s_c_out = NOR(s_a_out,s_d_out) = NOR(0,0) = 1   => q_n = 1
    --   s_d_out = NOR(s_b_out,s_c_out) = NOR(1,1) = 0   => q     = 0
    signal s_a_out : std_logic := '0';
    signal s_b_out : std_logic := '1';
    signal s_c_out : std_logic := '1';
    signal s_d_out : std_logic := '0';
    -- (the four above exist only in the gate model; synthesis removes them)

    -- fpga_datalatch branch: the stored bit. '0' is the FPGA power-up value.
    signal s_q : std_logic := '0';

    constant tg : time := 1 ns;   -- modelled NOR propagation delay (sim only)

begin

    gate_model : if not FPGA_BUILD generate
        -- input stage (gated by active-low enable e)
        s_b_out <= not (e or d)       after tg;
        s_a_out <= not (e or s_b_out)     after tg;

        -- cross-coupled SR latch
        s_c_out <= not (s_a_out or s_d_out)   after tg;
        s_d_out <= not (s_b_out or s_c_out)   after tg;

        q_n <= s_c_out;
        q   <= s_d_out;
    else generate

        fpga_datalatch : process (e, d) is
        begin

            if (e = '0') then
                s_q <= d;
            end if;

        end process fpga_datalatch;

        q   <= s_q;
        q_n <= not(s_q);
    end generate gate_model;

end architecture structural;
