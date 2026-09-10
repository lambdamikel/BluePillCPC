# TRACKER for the Ultimate MIDI Card

A six track MIDI step sequencer for the CPC 6128, driving the Ultimate
MIDI Card. Ported from the TRS-80 MIDI/80 version of TRACKER 2.00.

![TRACKER on a CPC 6128](../../pics/tracker-boogie.png)

## Just run it

`dsk/` and `hfe/` each hold three ready to run discs, one per demo song.
Put one in the drive and type

    RUN"TRACKER

then `L` and `Y` to load the song, and `P` to play it. `!` plays the whole
arrangement instead of the one pattern. `H` is the help page.

| song | | |
|---|---|---|
| 12 bar blues shuffle, 140 BPM | `dsk/tracker-boogie.dsk` | `hfe/tracker-boogie.hfe` |
| Berlin school 16th note sequence, 120 BPM | `dsk/tracker-sequence.dsk` | `hfe/tracker-sequence.hfe` |
| six voice drum machine, 125 BPM | `dsk/tracker-drums.dsk` | `hfe/tracker-drums.hfe` |

`Q` quits by resetting the machine - TRACKER loads over BASIC's program
area, so there is nothing left to return to.

## Keys

| | |
|---|---|
| `A` `D` `W` `X`, `Z` `C`, **arrow keys** | move the edit cursor |
| SPACE | set the grid step |
| ENTER, **COPY** | set the step and sound it |
| CLR / DEL | clear the step |
| `P` / `!` | play pattern / play song |
| `0` | all notes off (MIDI panic) |
| `/` `?` | next / previous pattern |
| `1`-`8` | jump to bar - **or, while a pattern is playing, queue that pattern** |
| `+` `-` | MIDI channel for this track |
| `U` `I` | GM instrument for this track |
| `J` `K` | velocity for this track |
| SHIFT + left/right arrow | drum note for this track |
| `*` | gate length |
| `,` `.` `N` `M` | tempo |
| `B`, `G` | bar count, grid resolution |
| `#`, `T` | record, cursor tracking |
| `R`, `'` | MIDI clock out, external clock in |
| `&` | song editor |
| `L` `S` `Q` | load, save, quit |

The arrow keys and `COPY` are CPC additions; everything else is as it is
on the TRS-80.

## Building

Needs [rasm](https://github.com/EdouardBERGE/rasm) and
[iDSK](https://github.com/cpcsdk/idsk):

    cd src
    python3 mktracker.py          # tracker7.asm -> tracker.asm
    rasm tracker.asm              # -> TRACKER.BIN, with an AMSDOS header

then put it on a disc together with a song:

    iDSK out.dsk -n
    iDSK out.dsk -i TRACKER.BIN -t 2 -f
    iDSK out.dsk -i DUMP -t 1 -c 4000 -e 4000 -f

`-t 2` matters: `TRACKER.BIN` already carries its own AMSDOS header, so it
must go in raw. For an HFE, `hxcfe -finput:out.dsk -foutput:out.hfe
-conv:HXC_HFE`.

`tracker.asm` is checked in, so `rasm tracker.asm` alone is enough if you
do not want to run the generator.

## How the port works

**`tracker.asm` is generated, not forked.** `mktracker.py` takes the
TRS-80 source (`tracker7.asm`, also here) and applies a mechanical
zmac-to-rasm syntax pass plus a set of named region replacements, one per
thing that is genuinely machine specific. About 600 of the 4000 lines are
new; the editor, the song mode, the note scheduler and the MIDI clock
generator are the TRS-80's own code, running unchanged. Re-running the
script pulls fixes across from the original.

**The trick the whole thing rests on:** TRACKER writes characters straight
into TRS-80 video RAM, computing addresses like `#3C00 + 14*64 + 35`. So
the port puts a 64x16 shadow buffer *at #3C00*, the TRS-80's own video
address, and points that code at it. Every address calculation is then
correct as written, and a renderer turns the buffer into mode 2 pixels.
Not one screen address had to change.

The 64x16 grid is spread over 20 of the CPC's 25 rows rather than packed
into 16. Packed it fills 80% of the width but only 64% of the height and
reads as stretched, because a CPC character cell is 8x8 where a TRS-80's
is 8x12.

**Timing.** The TRS-80 has to *estimate* elapsed time - video wait states,
DRAM refresh and a variable ROM keyboard call all move under it - and that
estimate is what made its BPM readout read low. The CPC needs none of it:
the gate array stretches every instruction to a whole number of
microseconds, so with interrupts off each region of the loop costs exactly
what it costs. The step period is computed, not calibrated:

    steptarget = 7741 + 191 * tempo      in 4 us units
    BPM        = 3750000 / steptarget

which matches the TRS-80's measured `30963 + 763*tempo` us to within 0.1%,
so a song plays at the speed it does on the machine it came from. Measured
over 420 steps with the step boundary tapped directly: **107453 us against
a 107364 target, +0.08%, jitter sd 244 us**.

**MIDI byte pacing.** MIDI is 31250 baud, so a byte occupies the wire for
320 us and nothing can go out faster, whatever the card's buffer does. The
wait lives inside `midiout` rather than at the call sites, so the clock
bytes and the panic messages - which are bare `OUT`s - get it too. This
matters more than it sounds: an earlier version paced at 98 us, and on
real hardware whole chords and program changes went missing, because a
step where five tracks sound is 15 bytes that need 4.8 ms.

**Files**

| | |
|---|---|
| `src/mktracker.py`, `src/zmac2rasm.py` | the port itself; they generate `tracker.asm` |
| `src/tracker7.asm` | the TRS-80 original it is generated from |
| `src/tracker.asm` | generated - do not edit |
| `src/render.asm` | the display layer and the two row maps |
| `src/kbdcpc.asm` | the PSG keyboard scan and the key tables |
| `src/midi.asm` | MIDI send/receive, including the byte pacing |
| `src/fileio.asm` | AMSDOS save/load |
| `src/font.asm` | generated from `OS_6128.ROM` at &3900 |

## Notes for anyone doing something similar

- **`RUN"` leaves the CASSETTE jumpblock in place.** At the BASIC prompt
  `&BC77` reads `DF 8B A8` (disc); inside a running binary it reads
  `CF E5 A4` (tape). A machine code program that wants disc must restore
  the 13 disc vectors itself - one LDIR of 13x3 bytes of `DF 8B A8`. And
  because AMSDOS identifies which call was made from the stacked return
  address plus `&10D2`, that pattern may only live in genuine jumpblock
  slots.
- **Do not use `TXT GET MATRIX` (&BBA5) for the font.** It returns a
  lower-ROM address that is paged out once the call returns, so it reads
  RAM and yields zeros. Extract from the OS ROM at `&3900` instead.
- **`SCR SET MODE` resets the palette**, so the mode and the inks have to
  be set together every time the screen is re-established.
- `&FBEE` sits close to the floppy controller at `&FB7E/&FB7F`, which is
  only partially decoded and shares A10=0. No trouble seen, but worth
  knowing.

## Status

Written and verified under MAME, then tested on real hardware. Load,
playback, the editor, song mode, MIDI clock out and external sync all
work. Saving with `S` writes correct bytes to the floppy controller but
has had less testing than the rest.

Songs interchange with the TRS-80 version: the data segment is byte for
byte the same, so a `DUMP` written on one machine loads on the other.
