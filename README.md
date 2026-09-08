# Naughty Boy (Basys 3 port)

Naughty Boy (Jaleco, 1982) by Dar (`darfpga@aol.fr`,
http://darfpga.blogspot.fr, source: https://github.com/darfpga/vhdl_naughty_boy).
Basys 3 (Artix-7) port.

- Vivado 2020.2 project: `basys3/naughty_boy_basys3.xpr` (top entity
  `naughty_boy_basys3`)
- Core clock: 12 MHz (from the 100 MHz Basys 3 oscillator via `clk_wiz_0`)
- Video: 31 kHz progressive VGA via the core's own built-in line doubler;
  sw(9) switches to 15 kHz TV/composite mode. No external scandoubler
  import needed — see `contrib/basys3/PORTING_SPEC.md` §3.

This port deviates from the sf-darfpga project's usual layout and source
convention (in-place port, no SourceForge archive) — see
`contrib/basys3/PORTING_SPEC.md` §0 for why.

## Features supported

- **Video**: 31 kHz progressive VGA by default (`rtl_dar/line_doubler.vhd`,
  already part of the pristine core). sw(9) switches to 15 kHz TV/composite
  mode (native rate, composite sync on HS, VS held high).
- **Sound**: mono PWM audio on PmodAMP2. Sources: a 12-voice additive melody
  synth (`tms3615.vhd`), four discrete RC-model sound-effect blocks
  (`naughty_boy_effect1..4.vhd`), fed by a shared LFSR noise generator —
  reused unmodified.
- **Controls**: USB keyboard (via the Basys 3's onboard USB HID host port)
  + JA joystick (OR-merged); dedicated buttons for coin/start (btnU = coin,
  btnL = start 1, btnR = start 2), btnC = reset. This core has a single
  coin input (no `btnD`).

| Input | Keyboard |
|-------|----------|
| Move | Arrow keys |
| Fire | Space |
| Coin | F3 |
| Start 1 | F1 |
| Start 2 | F2 |

JA joystick (active-low, switch to GND):
- JA1 = Right, JA2 = Left, JA3 = Down, JA4 = Up, JA7 = Fire

Buttons (active-high, Basys3 board pull-down, same convention as btnC):
- btnU = coin (also F3), btnL = start 1 (also F1), btnR = start 2 (also F2),
  btnC = reset

## IO mapping

| Basys 3 resource | Wrapper port | Function |
|------------------|--------------|----------|
| clk (W5, 100 MHz) | `clk` | clock into `clk_wiz_0` MMCM |
| btnC | `btnC` | reset (active-high) |
| btnU | `btnU` | coin |
| btnL / btnR | `btnL` / `btnR` | start 1 / start 2 |
| sw(0-7) | `sw(7 downto 0)` | dip switches: lives/extra/credits/difficulty/cabinet (see `rtl_dar/naughty_boy_de10_lite.vhd` header) |
| sw(8) | `sw(8)` | flip screen |
| sw(9) | `sw(9)` | display mode: 0 = 31 kHz VGA, 1 = 15 kHz TV |
| sw(15) | `O_PMODAMP2_GAIN` | AMP gain: 0 = 12 dB, 1 = 6 dB |
| sw(14) | `O_PMODAMP2_SHUTD` | AMP shutdown: 0 = off, 1 = on |
| Onboard USB-A HID host (C17/B17) | `ps2_dat` / `ps2_clk` | USB keyboard, via Digilent's onboard USB-to-PS/2 translator |
| JA1-JA4, JA7 | `JA(0..4)` | joystick (active-low) |
| JC (PmodAMP2) | `O_PMODAMP2_AIN` | PWM audio (mono; JC1=AIN, JC2=GAIN, JC4=SHUTD) |
| VGA | `vgaRed/vgaGreen/vgaBlue(3:0)`, `vgaHsync`, `vgaVsync` | 4-4-4 RGB, 31 kHz VGA / 15 kHz TV |

## Scripted setup

Unlike every other sf-darfpga-convention machine, this port has no
SourceForge archive to fetch: this repository (`vhdl_naughty_boy/`) is
itself the pristine source, pinned via its own git history (a checkout of
https://github.com/darfpga/vhdl_naughty_boy). `contrib/tools/setup_naughty_boy.sh`
applies any fix patches idempotently (none known needed yet — see
`contrib/basys3/PORTING_SPEC.md` §0), then runs `contrib/tools/prep_roms.sh`
to compile `make_vhdl_prom`, convert `make_naughty_boy_proms.bat`, stage the
romset from `$ROMZIP` into `tools/roms/`, and generate the PROM VHDL there.
Run it via `make setup`.

`$ROMZIP` (default `~/roms/naughtyb.zip`) is used exactly as it ships — its
18 filenames already match `make_naughty_boy_proms.bat`'s expected inputs
byte-for-byte, so no filename translation is needed (unlike
`vhdl_congo_bongo`). `prep_roms.sh` still fails loudly with a clear message
if the staged romset is genuinely missing files.

The remaining steps are wrapped by the Makefile: `make create_prj` (copies
`naughty_boy_basys3.xpr` and `Basys-3-Master.xdc` into `basys3/`),
`make clk_wiz` (generates the `clk_wiz_0` MMCM IP wrappers), `make patch`
(regenerates `naughty_boy_de10_lite_to_basys3.patch` and places
`naughty_boy_basys3.vhd`), then `make synth` / `make bitstream` (Vivado
batch runs; logs stay outside the repo).

`make clean` removes only the generated `basys3/` Vivado project tree and
the staged `tools/roms/` (romset + generated PROM VHDL) — this port has no
separate extracted `vhdl_<machine>_rev_.../` tree to remove, since the
pristine source is this repository itself.

## ROM set required

Romset staged into `tools/roms/`:

```
$ROMZIP (default ~/roms/naughtyb.zip)   ->   tools/roms/
```

The tracked `make_naughty_boy_proms.bat` references filenames that already
match the MAME "naughtyb" romset exactly (`1.30`, `2.29`, ..., `6301-1.63`,
`6301-1.64`) — no translation table, renaming, or `ROMZIP` override needed.

Generated PROM VHDL: `prom_graphx_1_bit0.vhd`, `prom_graphx_1_bit1.vhd`,
`prom_graphx_2_bit0.vhd`, `prom_graphx_2_bit1.vhd`, `prom_prog.vhd`,
`prom_palette_1.vhd`, `prom_palette_2.vhd`.

machine ROMs are copyrighted — never commit or redistribute them.

## Build status

Scripted (`make setup create_prj clk_wiz patch`), verified with a read-only
Vivado smoke test (0 missing files, top entity resolves). Not yet
synthesized or bitstream-built.
