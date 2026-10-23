----------------------------------------------------------------------------------
-- ula_build_pkg (SIMULATION version) — which model the storage primitives use
--
-- There are two files that both declare package ula_build_pkg:
--   ula_build_pkg_sim.vhd   FPGA_BUILD = false   used in SIMULATION only
--   ula_build_pkg_fpga.vhd  FPGA_BUILD = true    used in SYNTHESIS only
-- Vivado's per-file "used in" setting picks one for each flow, so the same
-- sources simulate the book's gates and synthesise to FPGA flip-flops/latches.
--
-- The storage primitives (d_ff_nor, data_latch_1_bit, single_bit_shift_register,
-- the hold latch in contention_handler_3) contain cross-coupled NOR gates. On
-- an FPGA those become LUTs feeding back into themselves: combinational loops
-- with routing-dependent timing that Vivado cannot analyse. So each primitive
-- has two generate branches:
--   FPGA_BUILD = false  the book's NOR gates, with `after tg` (gate-accurate)
--   FPGA_BUILD = true   the FPGA's own flip-flop / latch, same behaviour
-- Everything above the primitives is identical in both builds.
--
-- To simulate the FPGA version (e.g. ula_tb against the synthesised
-- behaviour), compile ula_build_pkg_fpga.vhd instead of this file.
----------------------------------------------------------------------------------

package ula_build_pkg is

    constant fpga_build : boolean := false;

end package ula_build_pkg;
