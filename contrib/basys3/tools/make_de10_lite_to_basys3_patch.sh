#!/bin/bash
# Generate the patch that adapts the upstream DE10-lite top level
# (rtl_dar/naughty_boy_de10_lite.vhd) into the Basys3 top level
# (naughty_boy_basys3.vhd).
#
# The target naughty_boy_basys3.vhd is authored here (it is a full rewrite of
# the top-level wrapper). The script:
#   1. Writes the target VHDL to a scratch dir.
#   2. Diffs it against the pristine upstream source to produce the git-style
#      patch at contrib/basys3/code/naughty_boy_de10_lite_to_basys3.patch.
#   3. Places the target where naughty_boy_basys3.xpr expects it
#      (basys3/naughty_boy_basys3.srcs/sources_1/new/naughty_boy_basys3.vhd).
#
# Requires `make setup` to have run first (no fix patches to the pristine
# core are currently known needed -- see contrib/basys3/PORTING_SPEC.md §0).
# Per project rules this script runs from /tmp so scratch stays outside the repo.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ROOT/rtl_dar/naughty_boy_de10_lite.vhd"
PROJ_DIR="$ROOT/basys3"
TARGET_SRC="$PROJ_DIR/naughty_boy_basys3.srcs/sources_1/new"
PATCH="$ROOT/contrib/basys3/code/naughty_boy_de10_lite_to_basys3.patch"

WORK=/tmp/naughty_boy_de10_to_basys3
TARGET="$WORK/naughty_boy_basys3.vhd"

if [ ! -f "$SRC" ]; then
    echo "error: pristine source not found: $SRC" >&2
    exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK"

cat > "$TARGET" <<'EOF'
---------------------------------------------------------------------------------
-- Basys3 Top level for Naughty Boy by Dar (darfpga@aol.fr)
-- http://darfpga.blogspot.fr
--
-- Basys3 port by Red~Bote.
--
-- Ported from naughty_boy_de10_lite.vhd:
--  - 100 MHz board oscillator, clk_wiz_0 MMCM derives 12 MHz (clock_12) --
--    the core's only clock domain (same shape as every sibling port). The
--    core's clock_50 port is not referenced anywhere in naughty_boy.vhd's
--    architecture body (confirmed by inspection) -- tied to clock_12 here
--    rather than the raw, otherwise-unconstrained 100 MHz pin.
--  - Video: the pristine core genuinely drives video_hs/video_vs (unlike
--    congo_bongo/zaxxon's dead ports) and already contains its own
--    line_doubler (15 kHz -> 31 kHz), carried over unchanged. No
--    video-timing-exposure patch and no external scandoubler needed --
--    see PORTING_SPEC.md §3. sw(9) selects 15 kHz TV/composite (native
--    rate) vs 31 kHz VGA (line-doubled), same bit position as the pristine
--    top. Native 2-bit/channel core color is padded to Basys3's 4-bit VGA
--    DAC by zeroing the two LSBs (r & "00"), the same padding the pristine
--    top already uses -- not MSB replication.
--  - Joystick on JA (movement + fire), OR-merged with a USB keyboard and,
--    for coin/start, dedicated buttons: btnU = coin, btnL = P1 start,
--    btnR = P2 start. This core has a single coin input (unlike
--    congo_bongo's two) -- no btnD is declared, matching the
--    constrained-ports rule (only declare ports the shared XDC actually
--    constrains). The core's coin input is active-low (starts is
--    active-high) -- carried over from the pristine top's own polarity for
--    each; see PORTING_SPEC.md §6.
--  - Keyboard input is the Basys 3's onboard USB-A "USB HID" host port
--    (C17/B17), presenting a plugged-in USB keyboard to the fabric over the
--    same PS/2 protocol/pins io_ps2_keyboard.vhd/kbd_joystick.vhd already
--    expect -- a pin remap in Basys-3-Master.xdc, not a logic change, same
--    as every sibling port's default. The pristine top already clocks the
--    keyboard at clock_12 (12 MHz) directly, no divider -- already above
--    the >=6 MHz rate other ports needed a dedicated divider to reach for
--    this port (see PORTING_SPEC.md §5); carried over unchanged. Not yet
--    hardware-verified at this specific rate on the onboard USB-HID port.
--  - Mono (duplicated to stereo at the pristine top's GPIO level, now
--    single-channel) PWM audio on PmodAMP2 (JC); sw14 = shutdown, sw15 =
--    gain select (project convention, not present in the pristine top).
--    Reuses the pristine top's exact 13-bit accumulator, clocked every
--    clock_12 edge with no divider gate (unlike congo_bongo's gated
--    accumulator).
--  - btnC = reset (also resets the MMCM; core held in reset until MMCM lock)
--  - No led port: the pristine top's ledr(8 downto 0) is hardwired to a
--    debug constant, not meaningful game state -- not ported, matching
--    every other machine's convention.
--  - DE10-lite's 7-segment debug hex display is commented out in the
--    pristine top and not ported.
---------------------------------------------------------------------------------
-- Educational use only
-- Do not redistribute synthetized file with roms
-- Do not redistribute roms whatever the form
-- Use at your own risk
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity naughty_boy_basys3 is
port(
 clk             : in  std_logic;
 sw              : in  std_logic_vector(15 downto 0);
 btnC            : in  std_logic;  -- reset
 btnU            : in  std_logic;  -- coin
 btnL            : in  std_logic;  -- P1 start
 btnR            : in  std_logic;  -- P2 start

 JA              : in  std_logic_vector(4 downto 0);  -- joystick (movement + fire)
 ps2_dat         : in  std_logic;
 ps2_clk         : in  std_logic;

 O_PMODAMP2_AIN  : out std_logic;
 O_PMODAMP2_GAIN : out std_logic;
 O_PMODAMP2_SHUTD: out std_logic;

 vgaRed   : out std_logic_vector(3 downto 0);
 vgaGreen : out std_logic_vector(3 downto 0);
 vgaBlue  : out std_logic_vector(3 downto 0);
 vgaHsync : out std_logic;
 vgaVsync : out std_logic
);
end naughty_boy_basys3;

architecture struct of naughty_boy_basys3 is

 signal clock_12    : std_logic;
 signal mmcm_locked : std_logic;
 signal reset       : std_logic;

 signal r, g, b : std_logic_vector(1 downto 0);
 signal csync   : std_logic;
 signal hsync   : std_logic;
 signal vsync   : std_logic;
 signal ce_pix  : std_logic;

 signal video_15kHz  : std_logic_vector(5 downto 0);
 signal video_31kHz  : std_logic_vector(5 downto 0);
 signal hsync_31kHz  : std_logic;
 signal tv15kHz_mode : std_logic;

 signal audio           : std_logic_vector(11 downto 0);
 signal pwm_accumulator : std_logic_vector(12 downto 0);

 signal kbd_intr     : std_logic;
 signal kbd_scancode : std_logic_vector(7 downto 0);
 signal JoyPCFRLDU   : std_logic_vector(7 downto 0);

 signal coin    : std_logic;
 signal starts  : std_logic_vector(1 downto 0);
 signal buttons : std_logic_vector(4 downto 0);

begin

 -- btnC is active-high: it resets the MMCM and, together with !locked,
 -- holds the core in reset until the clock is stable.
 reset <= btnC or not mmcm_locked;
 tv15kHz_mode <= sw(9);

 clocks : entity work.clk_wiz_0
 port map(
  clk_in1  => clk,
  clk_out1 => clock_12,
  reset    => btnC,
  locked   => mmcm_locked
 );

 naughty_boy_inst : entity work.naughty_boy
 port map(
  clock_50     => clock_12,  -- unused inside naughty_boy.vhd, see header
  clock_12     => clock_12,
  reset        => reset,
  dip_switch   => sw(7 downto 0),
  flip_screen  => sw(8),
  coin         => coin,
  starts       => starts,
  player1_btns => buttons,
  player2_btns => buttons,
  video_r      => r,
  video_g      => g,
  video_b      => b,
  video_csync  => csync,
  video_hs     => hsync,
  video_vs     => vsync,
  video_hblank => open,
  video_vblank => open,
  ce_pix       => ce_pix,
  audio        => audio
 );

 -- line doubler (already part of the pristine top, carried over unchanged)
 video_15kHz <= r & g & b;

 doubler : entity work.line_doubler
 port map(
   clock   => clock_12,
   ena_pix => ce_pix,
   video_i => video_15kHz,
   hsync_i => hsync,
   video_o => video_31kHz,
   hsync_o => hsync_31kHz
 );

 -- Adapt video to Basys3's 4-bit/channel VGA DAC: native 2-bit core color
 -- placed in the two MSBs, LSBs zeroed -- the same padding the pristine
 -- top already uses, not MSB replication.
 vgaRed   <= r & "00" when tv15kHz_mode = '1' else video_31kHz(5 downto 4) & "00";
 vgaGreen <= g & "00" when tv15kHz_mode = '1' else video_31kHz(3 downto 2) & "00";
 vgaBlue  <= b & "00" when tv15kHz_mode = '1' else video_31kHz(1 downto 0) & "00";

 vgaHsync <= csync when tv15kHz_mode = '1' else hsync_31kHz;
 vgaVsync <= '1'   when tv15kHz_mode = '1' else vsync;

 -- get scancode from keyboard (12 MHz -- see header note on the keyboard
 -- clock rate)
 keyboard : entity work.io_ps2_keyboard
 port map (
   clk       => clock_12,
   kbd_clk   => ps2_clk,
   kbd_dat   => ps2_dat,
   interrupt => kbd_intr,
   scancode  => kbd_scancode
 );

 -- translate scancode to joystick / function keys
 joystick : entity work.kbd_joystick
 port map (
   clk         => clock_12,
   kbdint      => kbd_intr,
   kbdscancode => std_logic_vector(kbd_scancode),
   JoyPCFRLDU  => JoyPCFRLDU
 );

 -- OR-merge the joystick on JA with the PS/2 keyboard joystick. JA physical
 -- map: JA1=right, JA2=left, JA3=down, JA4=up, JA7=fire, i.e. JA(0)=right,
 -- JA(1)=left, JA(2)=down, JA(3)=up, JA(4)=fire -- same pin convention as
 -- every other machine. JA is active-low (pressed shorts to ground);
 -- invert so a press reads active-high, matching the keyboard path.
 buttons(1) <= JoyPCFRLDU(0) or not JA(3);  -- up     (JA4)
 buttons(2) <= JoyPCFRLDU(1) or not JA(2);  -- down   (JA3)
 buttons(4) <= JoyPCFRLDU(2) or not JA(1);  -- left   (JA2)
 buttons(3) <= JoyPCFRLDU(3) or not JA(0);  -- right  (JA1)
 buttons(0) <= JoyPCFRLDU(4) or not JA(4);  -- fire   (JA7)

 -- Coin/start: keyboard OR-merged with dedicated buttons. Buttons are
 -- active-high (Basys3 board pull-down, same convention as btnC). The
 -- core's coin input is active-low (starts is active-high) -- carried over
 -- from the pristine top's own polarity for each, so only the coin merge
 -- is inverted.
 coin      <= not (JoyPCFRLDU(7) or btnU);  -- coin   = F3 or btnU (active-low)
 starts(0) <= JoyPCFRLDU(5) or btnL;        -- start1 = F1 or btnL
 starts(1) <= JoyPCFRLDU(6) or btnR;        -- start2 = F2 or btnR

 -- pwm sound output (reproduces the pristine top's exact accumulator,
 -- clocked every clock_12 edge, no divider gate)
 process(clock_12)
 begin
   if rising_edge(clock_12) then
     pwm_accumulator <= std_logic_vector(unsigned('0' & pwm_accumulator(11 downto 0)) + unsigned(audio & '0'));
   end if;
 end process;

 O_PMODAMP2_AIN   <= pwm_accumulator(12);
 O_PMODAMP2_SHUTD <= sw(14);  -- shutdown: 0 = off, 1 = on
 O_PMODAMP2_GAIN  <= sw(15);  -- gain: 0 = 12 dB, 1 = 6 dB

end struct;
EOF

# Emit git-style patch (matches the *_de10_lite_to_basys3.patch convention).
mkdir -p "$(dirname "$PATCH")"
{
  printf 'diff --git a/rtl_dar/naughty_boy_de10_lite.vhd b/rtl_dar/naughty_boy_de10_lite.vhd\n'
  diff -u --label "a/rtl_dar/naughty_boy_de10_lite.vhd" \
            --label "b/rtl_dar/naughty_boy_de10_lite.vhd" \
            "$SRC" "$TARGET" || [ $? -eq 1 ]   # diff returns 1 when files differ (expected)
} > "$PATCH"

mkdir -p "$TARGET_SRC"
cp -f "$TARGET" "$TARGET_SRC/naughty_boy_basys3.vhd"

rm -rf "$WORK"

echo "Generated patch:  $PATCH"
echo "Placed target:    $TARGET_SRC/naughty_boy_basys3.vhd"
echo "Verify with:      patch -p1 --dry-run < contrib/basys3/code/naughty_boy_de10_lite_to_basys3.patch"
