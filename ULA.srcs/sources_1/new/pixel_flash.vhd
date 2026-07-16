----------------------------------------------------------------------
-- pixel_flash — flash control of the serialised pixel stream
--
-- Applies the ZX Spectrum FLASH effect to the ink/paper-select bit
-- coming out of the pixel shift register (pixel_serialiser.serial_data).
-- When an attribute has its FLASH bit set, ink and paper periodically
-- swap; the swap is a simple conditional inversion of the per-pixel
-- select bit, gated by the flash-enable and toggled by a slow flash
-- clock derived from the frame (V) counter.
--
-- Inputs:
--   fl          — flash ENABLE for this pixel = the attribute FLASH tap
--                 (attr bit 7 AND vid_en, i.e. al7_fl). '1' => this pixel
--                 may flash; '0' => never flashes.
--   flash_clk   — slow flash toggle (from the V counter). Selects which
--                 half of the flash period we are in. See polarity note.
--   serial_data — the raw pixel select bit from pixel_serialiser
--                 (MSB-first, '1' = ink chosen, '0' = paper chosen).
-- Output:
--   data_select_n — ACTIVE-LOW ink/paper select for the colour mux:
--                 '0' => select INK, '1' => select PAPER. (When fl='0'
--                 this is just NOT serial_data — a clean pass-through.)
--
-- Function (verified exhaustively):
--   b_o           = fl AND (NOT flash_clk)          -- "flash this half"
--   data_select_n = XNOR(b_o, serial_data)
--                 = NOT( serial_data XOR (fl AND NOT flash_clk) )
--   so the select is inverted only while fl='1' AND flash_clk='0',
--   otherwise the pixel bit passes straight through (active-low).
--
-- Topology: an inverter + a NOR (build the flash-gate b_o) feeding a
-- 4-NOR XNOR gate (c_o, d_o, e_o, data_select_n). No feedback loop, so
-- unlike the cross-coupled latches this cell needs no seed values to
-- simulate cleanly. Each gate still carries an `after TG` inertial delay
-- for consistency with the rest of the FF/gate library and to model the
-- XNOR's real propagation (and its transient static-hazard glitch); TG is
-- sim-only and ignored by synthesis. Worst-case path fl->...->out is 5*TG,
-- so downstream/TB sampling must allow > 5*TG to settle.
--
--   POLARITY NOTE: with fl inverted but flash_clk not, the swap occurs
--   on the flash_clk='0' half. Because FLASH is a symmetric 50/50
--   alternation, the absolute phase is not visible on screen — swapping
--   on '0' vs '1' only shifts which flash period starts swapped. Confirm
--   the V-counter flash_clk sense matches this when it is wired up.
----------------------------------------------------------------------

library ieee;
    use ieee.std_logic_1164.all;

entity pixel_flash is
    port (
        fl            : in    std_logic; -- flash enable (attr7 AND vid_en = al7_fl)
        flash_clk     : in    std_logic; -- slow flash toggle from the V counter
        serial_data   : in    std_logic; -- raw pixel select bit (from pixel_serialiser)
        data_select_n : out   std_logic  -- active-low ink/paper select: '0'=ink, '1'=paper
    );
end entity pixel_flash;

architecture structural of pixel_flash is

    signal a_o : std_logic; -- NOT fl
    signal b_o : std_logic; -- flash-gate: fl AND NOT flash_clk
    signal c_o : std_logic; -- XNOR internal
    signal d_o : std_logic; -- XNOR internal
    signal e_o : std_logic; -- XNOR internal

    constant tg : time := 1 ns; -- modelled gate propagation delay (sim only)

begin

    -- flash-gate: assert b_o only when flashing AND in the swap half-period
    a_o <= not(fl)              after tg;
    b_o <= not(a_o or flash_clk) after tg; -- = fl AND NOT flash_clk

    -- 4-NOR XNOR(b_o, serial_data): invert the pixel select when b_o='1'
    c_o           <= not(b_o or serial_data) after tg;
    d_o           <= not(b_o or c_o)      after tg;
    e_o           <= not(c_o or serial_data) after tg;
    data_select_n <= not(d_o or e_o) after tg; -- = XNOR(b_o, serial_data)

end architecture structural;
