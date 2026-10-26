----------------------------------------------------------------------------------
-- ula_build_pkg (FPGA version) — which model the storage primitives use
--
-- Same package as ula_build_pkg_sim.vhd, with FPGA_BUILD = true. Used in
-- SYNTHESIS only: the storage primitives then use the FPGA's own flip-flops
-- and latches instead of cross-coupled NOR gates. See ula_build_pkg_sim.vhd
-- for the full explanation.
----------------------------------------------------------------------------------

package ula_build_pkg is

    constant fpga_build : boolean := true;

end package ula_build_pkg;
