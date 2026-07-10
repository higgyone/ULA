----------------------------------------------------------------------
-- pixel_serialiser — video data latch + pixel shift register block
--
-- The front of the ULA video data path (Chris Smith, "The ZX Spectrum
-- ULA"): the display-RAM byte is captured in the 8-bit data latch, then
-- parallel-loaded into the 8-bit shift register and serialised MSB-first
-- at the pixel clock (one ink/paper-select bit per pixel). Pure structure
-- — no logic of its own, just the two cells wired together.
--
--   data (7:0)  --> data_latch_8_bit --(data_out_n, active-low)--> shift8.data_n --> serial_data
--
-- Key wiring note: the latch's ACTIVE-LOW output bus (data_out_n) feeds
-- the shift register's ACTIVE-LOW load bus (data_n). The two active-low
-- conventions cancel, so the register loads the TRUE pixel byte. (Do NOT
-- wire the latch's true data_out here — that would load inverted pixels.)
-- The latch's true output is left `open` for now; it heads to the
-- attribute/colour path in a later block.
--
-- Control lines (driven from the counter phases in a later timing block;
-- exposed as ports for now so the TB can drive them):
--   data_latch_n — ACTIVE-LOW latch enable (= not datalatch): '0'
--                  transparent, '1' hold. Rising edge captures the byte.
--   SLoad        — '1' parallel-load the latched byte, '0' shift left.
--
-- Sin: the shift register's active-low serial-in (LSB end) is tied to
-- SLoad, per the book's schematic. It is a don't-care for the 8 valid
-- pixels of a serialisation (never reaches the MSB output within 8
-- shifts); the tie mirrors the gate-level drawing rather than inventing a
-- constant, keeping this recreation schematic-faithful.
----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity pixel_serialiser is
    Port ( clk          : in  STD_LOGIC;                     -- pixel clock (falling-edge commit in shift8)
           SLoad        : in  STD_LOGIC;                     -- '1' load latched byte, '0' shift left
           data_latch_n : in  STD_LOGIC;                     -- active-low latch enable (= not datalatch)
           data         : in  STD_LOGIC_VECTOR (7 downto 0); -- byte in (from display RAM)
           serial_data  : out STD_LOGIC                      -- serial pixel stream, MSB first
           );
end pixel_serialiser;

architecture Structural of pixel_serialiser is
    -- latch's active-low output bus -> shift register's active-low load bus
    signal latch_data_out_n : STD_LOGIC_VECTOR (7 downto 0);

begin

data_latch_8: entity work.data_latch_8_bit
    port map (
                enable      => data_latch_n,
                data        => data,
                data_out    => open,               -- true byte -> attribute/colour path (later)
                data_out_n  => latch_data_out_n
                );

shift_8: entity work.shift8
    port map (
                clk     => clk,
                SLoad   => SLoad,
                Sin     => SLoad,                  -- serial-in tied to SLoad per book schematic (don't-care for the 8 valid pixels)
                data_n  => latch_data_out_n,
                q       => serial_data,
                q_bar   => open
                );

end Structural;
