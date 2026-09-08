# Naughty Boy — Porting spec (Basys 3)

Status: scripted through `create_prj`/`clk_wiz`/`patch`, verified with a
read-only Vivado smoke test. Not yet synthesized.

## 0. Deviations from the sf-darfpga project convention (confirmed with user)

This port does not follow the `sf-darfpga/<Machine>-by-Dar/` layout or the
SourceForge-archive setup convention documented in the root `AGENTS.md` /
`PORTING_SPEC.md`. Confirmed decisions (mirrors `vhdl_congo_bongo`'s §0,
same situation):

- **Location**: ported in place inside `vhdl_naughty_boy/`, not as a new
  `sf-darfpga/Naughty-Boy-by-Dar/` directory. `vhdl_naughty_boy/` itself
  plays the role every other machine's `<Machine>-by-Dar/` directory plays.
- **Source acquisition**: `vhdl_naughty_boy/` is its own git checkout of
  `https://github.com/darfpga/vhdl_naughty_boy` (pinned at commit `5679b89`,
  "Add sound, Fix slow down"), not a SourceForge zip. There is no
  archive-fetch / SHA-256-verification step. `setup_naughty_boy.sh` skips
  the fetch entirely and starts from the `rtl_dar/`/`rtl_T80/` trees already
  present in this directory's own git history.
- No synthesis/behavior-fix patches to the pristine core are currently known
  to be needed (see §3, §5) — unlike `vhdl_congo_bongo`, which required a
  video-timing-exposure patch. If Vivado synthesis turns up a width-mismatch
  or similar defect (the `hflip`-class bug found in several sibling ports),
  it will be recorded as a `.patch` under `contrib/code/`, applied
  idempotently with `patch -p1 --forward`, per the project convention.

## 1. Reference model

- Source: `vhdl_naughty_boy/` (this directory), pinned pristine reference —
  see §0.
- Baseline top-level: `rtl_dar/naughty_boy_de10_lite.vhd` (confirmed with
  user over `naughty_boy_de1_soc.vhd`, whose audio path is fully
  disconnected and which does not wire `flip_screen` — treated as
  incomplete/buggy, not ported).
- Top entity (new): `naughty_boy_basys3` (target file
  `sources_1/new/naughty_boy_basys3.vhd`), replacing the pristine
  `naughty_boy_de10_lite.vhd` top.
- Part: `xc7a35tcpg236-1`, VHDL target language — matches every other
  sf-darfpga-convention port.
- Reference cores used unchanged: `naughty_boy.vhd` (main core, includes
  `naughty_boy_video.vhd`'s H/V counters, `naughty_boy_effect1..4.vhd`
  discrete sound-effect emulation, `naughty_boy_noise.vhd`, `tms3615.vhd`
  melody synth, `gen_ram.vhd`), `line_doubler.vhd`, `io_ps2_keyboard.vhd`,
  `kbd_joystick.vhd`, `rtl_T80/` (T80 CPU — `T80se`/`T80`/`T80_ALU`/
  `T80_MCode`/`T80_Pack`/`T80_Reg`; the rest of `rtl_T80/` is unused
  boilerplate from the generic T80 distribution).

## 2. Clocking

- Single core clock: **12 MHz** (`clock_12`), derived on DE10-lite from
  50 MHz by `max10_pll_12M`. On Basys 3, `clk_wiz_0` derives it from the
  100 MHz board oscillator instead (same shape as every sibling port) — no
  second clock domain needed.
- The core's `clock_50` port exists but is not referenced anywhere in
  `naughty_boy.vhd`'s architecture body (confirmed by inspection) —
  vestigial. Tied to `clock_12` in the Basys3 wrapper (any stable signal
  works; avoids introducing an extra unconstrained clock net from the raw
  100 MHz pin).
- Reset polarity: DE10-lite uses active-low `key(0)` (`reset <= not
  reset_n`); Basys 3 uses active-high `btnC`. Standard project pattern:
  ```vhdl
  reset <= btnC or not mmcm_locked;
  clk_wiz_0 port map( ..., reset => btnC, locked => mmcm_locked );
  ```

## 3. Video — no defect to fix, unlike vhdl_congo_bongo

Unlike `congo_bongo`/`zaxxon` (whose cores declared dead `video_hs`/
`video_vs` ports), `naughty_boy.vhd`'s `video_hs`/`video_vs` ports are
genuinely driven by `naughty_boy_video.vhd`'s counter logic — confirmed by
the pristine DE10-lite top wiring them straight into `vga_hs`/`vga_vs` (in
31 kHz mode) with no exposure patch. **No synthesis-fix patch needed for
video.**

The pristine top also already contains its own `line_doubler.vhd` (15 kHz →
31 kHz), instantiated at top level (since commit `937bee5`) and selected by
`tv15kHz_mode` (`sw(9)` on DE10-lite) — this is the "internal line doubler,
no external scandoubler" case (per the `xpr-dependency-closure` skill's
video-path classification). **No MiST/DECA scandoubler import needed.**

Plan: carry the pristine top's video section over verbatim, just renaming
the output ports to Basys3's `vgaRed`/`vgaGreen`/`vgaBlue`/`vgaHsync`/
`vgaVsync` and keeping the `sw(9)` = `tv15kHz_mode` switch-selectable 15 kHz
composite fallback vs. 31 kHz VGA:

- Core video output: `video_r(1:0)`, `video_g(1:0)`, `video_b(1:0)` — native
  2-bit/channel (6-bit total, via two palette PROMs — low/high intensity).
  Basys3 VGA is 4-4-4; the pristine top already pads by placing the 2 core
  bits in the two MSBs and zeroing the two LSBs (`r & "00"`), not MSB
  replication — carried over unchanged, no new padding scheme invented.
- 15 kHz mode (`sw(9) = '1'`): `vgaHsync <= csync`, `vgaVsync <= '1'`,
  color = raw `r`/`g`/`b` — TV/composite, matches pristine.
- 31 kHz mode (`sw(9) = '0'`, default): `vgaHsync <= hsync_31kHz`,
  `vgaVsync <= vsync` (real, undoubled — the line doubler only doubles the
  horizontal rate, matching the pristine top exactly), color = line-doubled
  `video_31kHz`.

## 4. Audio (mono PWM on PmodAMP2)

- `naughty_boy_de10_lite.vhd` already has a complete, working 13-bit PWM
  accumulator DAC (`pwm_accumulator`, clocked every `clock_12` edge, no
  divider gate) driving `pwm_audio_out_l`/`_r` — both tied to the same
  accumulator bit (mono duplicated to stereo at the DE10-lite GPIO level).
  Reused verbatim for the Basys3 wrapper's `O_PMODAMP2_AIN`.
- `sw(15)` → AMP gain, `sw(14)` → AMP shutdown (standard project
  convention; not present in the pristine top, added in the Basys3
  wrapper like every sibling port).
- Sound sources mixed inside the core (`naughty_boy.vhd`): `tms3615`
  (12-voice additive melody synth), 4 discrete RC-model sound-effect
  blocks (`naughty_boy_effect1..4.vhd`), fed by a shared LFSR noise
  source (`naughty_boy_noise.vhd`) — reused unmodified, no wrapper-level
  changes beyond the top-level port map.

## 5. Keyboard clock — already above the known threshold

Several sibling ports (`vhdl_congo_bongo`, `Arcade_Zaxxon`) hit a bug where
the Basys 3's onboard USB-HID (PS/2) host port needs the keyboard clock at
≥6 MHz; their pristine cores clocked the keyboard at 4 MHz via a shared
divider and needed a dedicated ≥6 MHz divider added.

`naughty_boy_de10_lite.vhd` already clocks `io_ps2_keyboard`/`kbd_joystick`
directly at `clk12` (12 MHz — the same clock the whole core runs on, no
divider at all). 12 MHz already exceeds the 6 MHz threshold every other
port had to engineer toward. **Plan: carry this over unchanged — no
dedicated keyboard-clock divider needed.** Not yet confirmed on real
hardware (no other port has exercised the onboard USB-HID port at exactly
12 MHz before); flagged as a hardware-bring-up verification item (§10),
not assumed safe purely by extrapolation from the ≥6 MHz threshold.

## 6. Inputs

- Core has **one coin input** (`coin`, active-low: `coin <= not
  JoyPCFRLDU(7)` in the pristine top) and **two start inputs** (`starts`,
  active-high, no genuine second coin) — same shape as `Arcade_Zaxxon`
  (single coin), not `vhdl_congo_bongo` (two real coins). Per the
  constrained-ports rule (only declare ports the shared XDC actually
  constrains), **no `btnD`** is declared in the top-level entity — unlike
  `vhdl_congo_bongo`'s dual-coin port list.
- Basys3 button plan: `btnU` = coin, `btnL` = start 1 (P1), `btnR` =
  start 2 (P2), `btnC` = reset — each OR-merged with the keyboard-decoded
  `JoyPCFRLDU` bits (F3/coin, F2/start2, F1/start1), same OR-merge pattern
  as every sibling port. Because the core's `coin` port is active-low
  (unlike `starts`, which is active-high), the merge is inverted:
  `coin <= not (JoyPCFRLDU(7) or btnU);` — `starts`/`player*_btns` OR
  directly (`starts(0) <= JoyPCFRLDU(5) or btnL;`, etc.), matching the
  pristine top's own (non-inverted) polarity for those two.
- PS/2 keyboard + `kbd_joystick`, ported unchanged onto the Basys 3's
  onboard USB-HID host port (`ps2_clk`/`ps2_dat` on `C17`/`B17`) — default
  per project convention, not the JB1/JB3 Pmod breakout.
- JA joystick (5-pin, active-low, invert to active-high) OR-merged into
  movement + fire only, same pin convention as every other machine: JA1 =
  Right, JA2 = Left, JA3 = Down, JA4 = Up, JA7 = Fire.
- `player1_btns` and `player2_btns` are tied to the same merged `buttons`
  signal in the pristine top (no genuine second control set) — carried
  through unchanged, same as every sibling port.
- Requires uncommenting `btnU`/`btnL`/`btnR` (not `btnD` — see above) in
  this port's own copy of `Basys-3-Master.xdc`.
- DIP switches: pristine `sw(7 downto 0)` = game options (lives/extra/
  credits/difficulty/cabinet, see the header comment table in
  `naughty_boy_de10_lite.vhd`), `sw(8)` = flip_screen, `sw(9)` =
  tv15kHz_mode — carried over at the same bit positions, leaving `sw(14)`/
  `sw(15)` free for the audio gain/shutdown convention (§4).

## 7. LEDs / 7-segment display

- `ledr(8 downto 0)` is hardwired to a constant (`"101010101"`, debug
  pattern) in the pristine top — not meaningful game state, not ported (no
  Basys3 LED mapping needed), matching every other machine's convention of
  skipping the DE10-lite debug LED/7-segment chain.
- `hex0`–`hex5` (`decodeur_7_seg` debug display) are commented out /
  unused in the pristine top — not ported.

## 8. ROM generation

`make_naughty_boy_proms.bat` (18 source files → 7 generated PROM VHDL
files) is the reference conversion list:

| Source ROM(s) | Generated VHDL |
|---|---|
| `15.44`+`16.43` (concat) | `prom_graphx_1_bit0.vhd` |
| `13.46`+`14.45` (concat) | `prom_graphx_1_bit1.vhd` |
| `11.48`+`12.47` (concat) | `prom_graphx_2_bit0.vhd` |
| `9.50`+`10.49` (concat) | `prom_graphx_2_bit1.vhd` |
| `1.30`+`2.29`+`3.28`+`4.27`+`5.26`+`6.25`+`7.24`+`8.23` (concat) | `prom_prog.vhd` |
| `6301-1.63` | `prom_palette_1.vhd` |
| `6301-1.64` | `prom_palette_2.vhd` |

`prep_roms.sh` follows the standard `.bat`→`.sh` conversion rules from the
`port-dar-machine` skill, compiling `tools/tools_prom_src/src/make_vhdl_prom.c`
(the identical, generic Dar tool already committed in `vhdl_congo_bongo/`
and several other trees in this repo — reused as-is, not machine-specific)
on the host.

### Romset — resolved, no translation needed

`~/roms/naughtyb.zip` (MAME canonical short name for this hardware, 18
files) confirmed present. Its 18 filenames match `make_naughty_boy_proms.bat`'s
expected inputs **byte-for-byte** (`1.30`, `2.29`, ..., `6301-1.63`,
`6301-1.64`) — unlike `vhdl_congo_bongo`/Pooyan, **no `DAR_TO_CANON`
filename-translation table is needed**; `prep_roms.sh` unzips `$ROMZIP`
directly and runs the converted script unmodified. `ROMZIP` defaults to
`~/roms/naughtyb.zip`.

## 9. Directory / script layout (in-place, per §0)

Mirrors every other machine's `contrib/` layout, rooted at
`vhdl_naughty_boy/` instead of `sf-darfpga/<Machine>-by-Dar/`:

- `contrib/tools/` — `setup_naughty_boy.sh` (no archive fetch, no fix
  patches known needed yet — see §0), `prep_roms.sh`.
- `contrib/basys3/code/` — reserved for a future top-level rewrite patch
  record (`naughty_boy_de10_lite_to_basys3.patch`, generated).
- `contrib/basys3/vivado/` — `naughty_boy_basys3.xpr`, `Basys-3-Master.xdc`,
  `make_clk_wiz_0.sh`.
- `contrib/basys3/tools/` — `make_de10_lite_to_basys3_patch.sh`,
  `make_naughty_boy_basys3_bitstream.sh`.
- `tools/tools_prom_src/` — copy of the shared `make_vhdl_prom.c` tool
  (from `vhdl_congo_bongo/tools/tools_prom_src/`), compiled at `make setup`
  time.
- `tools/roms/` (gitignored) — unzipped romset + generated PROM VHDL,
  staged by `prep_roms.sh` under the existing pristine `tools/` directory
  (which already holds `make_naughty_boy_proms.bat`/`.exe` in this
  upstream repo, unlike `vhdl_congo_bongo`'s pristine `tools/congo_unzip/`
  — no new `<game>_unzip`-named directory is introduced into the pristine
  tree, `tools/` is used directly).
- `Makefile` at `vhdl_naughty_boy/` root: `all / setup / create_prj /
  clk_wiz / patch / synth / bitstream / clean`, cloned from the
  `vhdl_congo_bongo` structure per the `port-dar-machine` skill.
- `README.md` at `vhdl_naughty_boy/` root, authored last.
- **Non-nested project layout**: `.xpr` directly at
  `basys3/naughty_boy_basys3.xpr`, sources at
  `basys3/naughty_boy_basys3.srcs/`.

Not a root-`Makefile` (`sf-darfpga/Makefile`) delegation target — this port
lives outside `sf-darfpga/`, so no root shorthand applies; build from
inside `vhdl_naughty_boy/` directly (`make <step>`).

## 10. Shared conventions & hard rules (carried over)

- **Vivado build scripts run from `/tmp`** so `vivado.log`/`vivado.jou` stay
  out of the repo. Never run `make synth`/`make bitstream` unless the user
  explicitly asks for a synthesis/bitstream build in that message.
- **Tool/path resolution**: `ENV_VAR → project default → interactive
  prompt`. Vivado: `VIVADO` → `/tools/Xilinx/Vivado/2020.2/bin/vivado`.
  Roms: `ROMZIP` → `~/roms/naughtyb.zip`.
- **Roms and generated PROM VHDL are copyrighted content** — never commit or
  distribute them.
- No Vivado synthesis has been run against this core yet; any
  synthesis-fix patches (width mismatches, etc., in the style of
  `congo_bongo_hflip_xor_width.patch`) are unknown until `make create_prj`
  / `make synth` is first attempted.

## 11. Next steps

1. ~~Scaffold `contrib/{tools,basys3/{code,tools,vivado}}/`,
   `tools/tools_prom_src/`, `Makefile`, `README.md`, `.gitignore` per §9.~~
   Done.
2. ~~Run `make setup` (`ROMZIP` default `~/roms/naughtyb.zip`) and confirm
   all 7 expected PROM VHDL files generate, non-empty.~~ Done — verified
   clean, no missing/empty inputs or outputs.
3. ~~`make create_prj clk_wiz patch` — read-only Vivado smoke test (open
   project, confirm all `get_files` resolve, no runs launched).~~ Done —
   `make create_prj clk_wiz patch` ran cleanly end to end; a read-only
   Vivado smoke test (`open_project`, no runs launched) confirmed 29/29
   source and constraint files resolve (0 missing) and the top entity
   resolves to `naughty_boy_basys3`.
4. **Not yet run** (requires explicit user request): `make synth` — first
   real signal on whether any width-mismatch-class synthesis-fix patch is
   needed (§0, §10).
5. **Not yet run** (requires explicit user request): `make bitstream` +
   hardware bring-up — verify video (both `sw(9)` modes), audio, JA
   joystick, coin/start buttons, and — the one open item not covered by any
   sibling port's precedent — the onboard USB-HID keyboard at the core's
   native 12 MHz rate (§5).
