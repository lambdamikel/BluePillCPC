# TRACKER/CPC

TRACKER 2.00 for the **Ultimate MIDI Card** (BluePillCPC), ported from
the TRS-80 MIDI/80 version to the Amstrad CPC 6128. Started 2026-09-08.

Target is the **6128**. A Revaldino RAM expansion gives a 464 full 6128
compatibility, so there is no reason to target the bare 464.

![TRACKER on a CPC 6128](../pics/tracker-cpc-boogie.png)

## Status

| layer | state |
|---|---|
| Display | works |
| Keyboard | works, every command key |
| MIDI out | works |
| MIDI in / realtime record | works |
| Disc load | works, byte exact against the TRS-80's own `DUMP` |
| Disc save | correct bytes reach the controller; see the caveat below |
| Timing | step period within **0.125%**, jitter 0.72% |
| MIDI clock out | 6 per step, within 1% of nominal |
| External sync in | works, as MIDI beat clock |
| Editor, song mode, help, quit | work |

Everything above is measured under MAME. 

## Running it

    RUN"TRACKER

on a disc that also carries a `DUMP`. `dsk/` has one disc per demo song.
`Q` quits by resetting the machine: TRACKER loads over BASIC's program and
variable area, so there is nothing left to return to.

## How the port is built

`tracker.asm` is **generated**, not hand written:

    python3 mktracker.py        # ../../midi80/MIDI-80/trs-80/zmac/tracker7.asm -> tracker.asm
    rasm tracker.asm            # -> TRACKER.BIN, with an AMSDOS header

`mktracker.py` does two things: a mechanical zmac-to-rasm syntax pass
(`zmac2rasm.py`), and a set of named region replacements, one per thing
that is genuinely machine specific. Everything else - the editor, song
mode, the note scheduler, the MIDI clock generator, the BPM division - is
the TRS-80's own code, unchanged.

Generating rather than forking means a fix on the TRS-80 side can be
re-applied here by re-running the script, and it makes the size of the
port honest: about 600 lines of the 4000 are new.

## The trick the whole port rests on

TRACKER writes characters straight into TRS-80 video RAM, computing
addresses like `#3C00 + 14*64 + 35`. So the port puts a **64x16 shadow
buffer at #3C00**, the TRS-80's own video address, and points that code at
it. Every address calculation is then correct as written -
`screenupdate`'s LDIR, `showplaycursor`'s two row copies, the lot. Not one
screen address had to change.

A renderer turns the buffer into mode 2 pixels: 640x200 in 2 colours = 80
bytes per scanline, so a character cell is one byte on each of its eight
scanlines, at `#C000 + scanline*#800 + row*80 + col`.

Measured on an emulated 6128:

| | cost |
|---|---|
| one cell, on demand | 212 us |
| dirty scan of 1/16th (64 cells) | ~900 us |
| everything | 84 ms |

The two cursors are rendered on demand, so they are instant. Everything
else is caught by an incremental scan that walks a sixteenth of the buffer
per main loop pass, comparing against a copy of what was last drawn: full
coverage every 16 passes, ~26 ms, and correct by construction - no caller
has to remember to mark anything dirty. Only the three places that write
the buffer and then *block* (the help page, the yes/no prompts, the
pattern-copy prompt) push their own pixels.

Two things make the inner loop fast: eight page aligned font tables, one
per scanline, so fetching a character's pixels is `ld l,c : ld a,(hl)`;
and SP as the text pointer, so `pop bc` fetches two characters in 3 us.
The latter needs interrupts off.

**Palette:** black paper and border, bright yellow text (firmware colours
0, 0 and 24). Mode 2 has only the two pens. Note that `SCR SET MODE` resets
the palette to the firmware default, so `setscreen` does the mode and the
inks together and is called from both places that establish the screen -
startup, and returning from an AMSDOS call, which can print over it.

**Font:** do NOT use `TXT GET MATRIX` (&BBA5). It returns an address in
the lower ROM, which is paged out once the firmware call returns, so it
reads RAM and yields zeros. `font.asm` is generated at build time from
`OS_6128.ROM` at **&3900**.

**Note glyphs need no translation.** TRACKER stores a note as
`chr(midi_note + 97)`, landing in #7C..#C1. Those are arbitrary marks on
the TRS-80 too, so the encoding ports verbatim.

## Screen layout: why 64x16 is spread over 25 rows

Packed into 16 consecutive rows the grid fills 80% of the width but only
64% of the height, and reads as horizontally stretched - a CPC character
cell is 8x8 where a TRS-80's is 8x12. Spread over 20 of the 25 rows it is
80% x 80%, the same shape it has on a TRS-80:

    title             -> 2
    status            -> 4
    ruler, bars 1-4   -> 6
    tracks 1-6        -> 7..12
    ruler, bars 5-8   -> 15
    tracks 1-6        -> 16..21

The help page is the opposite - 16 solid lines of text that want no gaps -
so there are two row maps and `setrows` swaps them, clearing the screen on
the way because the two use different rows.

## Keyboard

The TRS-80's matrix is memory mapped. The CPC's sits behind the PSG,
reached through the 8255 PPI: `#F4xx` port A (PSG data), `#F6xx` port C
(PSG control in bits 7,6; keyboard row in 0..3), `#F7xx` control. PSG
control bits are 00 inactive, 01 read, 10 write, 11 select register. A
pressed key reads as 0.

**323 us for a full ten row scan**, so the whole matrix is sampled once
per main loop pass and every later question - "is SPACE down?", "what was
typed?" - is answered from the copy for free. On the TRS-80 those were
separate memory reads; here one scan serves them all.

Every key TRACKER uses exists on a CPC in the same shift relation it had
on a TRS-80 - `!` is SHIFT-1, `"` SHIFT-2, `#` SHIFT-3, `&` SHIFT-6, `'`
SHIFT-7, `*` SHIFT-:, `+` SHIFT-;, `=` SHIFT--, `?` SHIFT-/ - so the
tables hand TRACKER the very same ASCII codes and almost none of its
comparisons needed changing. CLR and DEL both give the TRS-80's CLEAR.

### Two CPC-native additions

The CPC has keys the TRS-80 did not, and it is strange not to use them:

- **the arrow keys move the edit cursor.** On the TRS-80 they carried the
  bar position (up/down) and the drum number (left/right). The bar
  position is already on `A` and `D`, so nothing is lost there; the drum
  number moves to **SHIFT with the left and right arrows**.
- **COPY sets the note under the cursor and sounds it**, the same as
  ENTER.

The arrows still *send* `KCURLEFT`/`KCURRIGHT` and the meaning is changed
in TRACKER's key dispatch instead. That matters: the song editor has its
own dispatch and moves its cursor on those same two codes, so it goes on
working untouched.

COPY is sampled straight from the matrix next to RETURN, not dispatched by
its ASCII code - because that is how TRACKER reads ENTER, and it is what
lets a note be punched in while a pattern is playing.

## MIDI

BluePillCPC, the Ultimate MIDI Card:

| | TRS-80 MIDI/80 | BluePillCPC |
|---|---|---|
| send a MIDI byte | `out (8),a` | `ld bc,#FBEE : out (c),a` |
| byte waiting? | `in a,(9)` | `ld bc,#FBFE : in a,(c)` |
| read a MIDI byte | `in a,(8)` | `ld bc,#FBEE : in a,(c)` |

BC is live across several of TRACKER's sends (`playnote` holds the gate
duration in C), so the wrappers preserve everything.

### Byte pacing, and the bug that made it matter

MIDI runs at 31250 baud, 1 start + 8 data + 1 stop, so **a byte occupies
the wire for 320 us** and nothing can go out faster than that, whatever
the card's FIFO does.

The TRS-80 paced with `short_delay` between sends: 32 iterations of a 24 T
loop = 768 T = 379 us on a Model III, safely over one byte time. The first
CPC `short_delay` was tuned for step timing instead and came out at **98
us** - measured, **88% of every byte TRACKER sent was leaving faster than
the wire could carry it**. On real hardware Michael heard piano on track 2
of BOOGIE and no organ chords at all.

Two bursts do it:

| | bytes | time it got | time the wire needs |
|---|---|---|---|
| play-start: panic then 6 program changes | 48 + 12 | ~5.9 ms | 19.2 ms |
| a step where 5 tracks sound | 15 | ~3.0 ms | 4.8 ms |

A channel that loses its program change stays on program 0, Acoustic
Grand Piano - exactly the symptom.

**The wait now lives inside `midiout`, not at the call sites.** Every byte
pays it, including the clock bytes and the panic messages, which are bare
`OUT`s with no `short_delay` near them and which a call-site fix would
have missed. Measured after: minimum inter-byte gap **412 us, zero bytes
under the wire rate**, all six program changes intact, and the busiest
step spreads 15 bytes over 6.9 ms.

Cost is ~330 us a byte, up to 24 bytes in a step, so 7.4% of a 107 ms
step - and it comes out of the step delay, so the tempo is unchanged.
`NOTEEVENT_U` had to go from 32 to 256 units to charge it, or the step ran
1% long with three times the jitter.

Note `&FBEE` sits close to the floppy controller at `&FB7E/&FB7F`, which
is only partially decoded and shares A10=0. No trouble under emulation,
but worth remembering on real hardware.

Realtime recording is verified: with `#` (record) and `T` (tracking) on,
note-ons fed to the card land in the grid, quantised to the grid setting.
As on the TRS-80, only **channel 1** note-ons are recorded (the parser
tests for `#90` exactly).

### External sync arrives as MIDI clock

The TRS-80 takes its external step pulse off the printer port. On the CPC
it comes in over MIDI instead: `'` puts TRACKER in external clock mode and
it then steps on every sixth `#F8` timing clock - 24 ppqn in, one 16th
note out, which is exactly what TRACKER sends when *it* is the master.
`#FA` (start) lines the divider up so the phase is right from bar 1.

That is a good fit: the card is already there, and every sequencer and
drum machine in the world sends `#F8`.

**A correction, though.** MIDI clock was originally chosen because I
believed the CPC's Centronics was write only. That is true of the seven
data lines, but **the BUSY line is an input and it is readable**: PPI
port B, `&F5xx`, bit 6. Measured on an emulated 6128 - 2000 samples, and
port B reads `1E` with only bit 0 changing:

| bit | | |
|---|---|---|
| 0 | CRTC VSYNC | toggles, 57 of 2000 samples high |
| 1-3 | manufacturer | `111`, Amstrad |
| 4 | refresh rate | `1`, 50 Hz |
| 5 | cassette in | 0 |
| **6** | **printer BUSY** | **readable - Centronics pin 11** |
| 7 | expansion `/EXP` | 0 |

So a printer-port clock **is** possible on this machine, exactly as on the
TRS-80, and the same clock box could then drive both. Left as a **future
feature** - the MIDI clock path is what exists today.

Step pulse **output** is kept on the Centronics data lines (`&EF00`), so
the clock box still works in that direction.

## File I/O

AMSDOS is a better shape than LDOS here: `CAS IN DIRECT` and `CAS OUT
DIRECT` move a whole file in one call, so the TRS-80's 88 iteration loop,
its 256 byte staging buffer and its ERN arithmetic all go.

**The thing that cost a day.** When BASIC's `RUN"` hands control to a
binary, AMSDOS puts the *cassette* jumpblock back at &BC77..&BC9D:

    at the BASIC prompt    &BC77: DF 8B A8   RST &18 -> &A88B   disc
    inside a running prog  &BC77: CF E5 A4   RST 8   -> &A4E5   tape

Call them as they stand and you get "Press PLAY then any key". A machine
code program that wants disc must restore the disc vectors itself - which
is what TADITRANS does at &937A, and it is not optional. All 13 DOS
vectors take the same three bytes and are contiguous, so one LDIR does it.

AMSDOS tells the 13 calls apart by reading the stacked return address -
the RST leaves vector+3 - and adding &10D2. Hence: this pattern may
**only** be written into genuine jumpblock slots. Reached from anywhere
else the arithmetic is nonsense and the machine crashes.
("Das grosse Floppy-Buch zum CPC", section 2.1.14, p143.)

### Verification, and a correction

**Load is verified byte for byte.** TRACKER loads `BOOGIE.DUMP` off disc
and the working page in RAM comes back identical to pattern C in the file,
798 of 798 bytes; the 768 grid cells on screen match the data segment with
one difference, which is the cell the edit cursor is sitting on. The data
segment layout is byte for byte the TRS-80's, so **DUMP files interchange
between the two machines**.

**Save could not be verified the same way, and an earlier claim here that
it was is wrong.** That test saved `DUMP`, wiped memory and read it back -
but the disc already held a `DUMP` with exactly those bytes, so it would
have passed whether or not anything was written. It was a false positive.

What was actually established, by tapping writes to the floppy controller
data register at `&FB7F` during a save: TRACKER hands the FDC **the whole
data segment, correctly, including an edit made just before saving** - 42
of the 43 sector aligned windows match byte for byte, and the one that
does not is the page `putpat` rewrote after the reference snapshot was
taken. So the save path through AMSDOS is right.

What could not be shown is the bytes landing on the medium, because **MAME
0.264 does not commit CPC floppy writes at all**. Plain BASIC
`SAVE"X",b,&4000,1` followed by `LOAD"X",&4000` does not round trip
either, in `.dsk` or in MAME's own writable `.mfi`, and the host image is
byte identical after the run. So this is the harness, not TRACKER.

**`S` therefore needs one test on real hardware.**

## Timing

The TRS-80 has to *estimate* elapsed time, because it cannot know its own
loop costs: video wait states, DRAM refresh and a variable ROM keyboard
call all move under it. That estimate is what made its BPM readout read
low, and it took a stopwatch on real hardware to calibrate.

The CPC needs none of that. The gate array stretches every instruction to
a whole number of microseconds, so with interrupts off each region of the
loop costs exactly what it costs, every time. The accumulator is not an
estimate but an **account**, and `steptarget` is the period the machine
actually plays - which is why the BPM readout here is simply

    BPM = 3750000 / steptarget

with no calibration constant of its own.

Time is accumulated in units of 4 us, and the step period is matched to
the TRS-80's measured `30963 + 763*tempo` us so a song plays at the speed
it does on the machine it came from:

    steptarget = 7741 + 191*tempo      (4 us units)

30963/4 = 7740.75 and 763/4 = 190.75, so the two agree to 0.1% across the
whole tempo range.

**Measured**, by tapping the PPI write that starts each keyboard scan -
which happens exactly once per pass - and timing boundary to boundary at
BOOGIE's tempo:

| | |
|---|---|
| main loop pass | 1606 us, deterministic to the microsecond |
| step boundary | ~10 ms on top of a pass |
| step period | **107229 us** against a 107364 target, **-0.125%** |
| jitter | sd 776 us (0.72%); the TRS-80 measures 680 us (0.63%) |
| BPM | displays 140, plays 139.89 |

Three things the CPC can do here that the TRS-80 could not:

1. **The step lands on the microsecond it is due.** On the TRS-80 a step
   could only fall on a main loop pass boundary, so it landed up to a
   whole pass late and `steplatch` had to carry the overshoot to make the
   average come out. Here, once the target is less than one pass away, the
   exact remainder is burned off: a taken `djnz` costs 13 T rounded up to
   16, which is 4 us, which is one accounting unit.

2. **Each MIDI note event is charged individually.** A step where six
   tracks fire costs real time that a step of rests does not. The TRS-80
   approximated this with two "waste some time" `short_delay`s in the rest
   branch; here `playnotes` counts the events it actually sent and charges
   them, which took the jitter from 1090 us to 519 us. (An exact pad in
   the rest branch was tried and over-corrected - a rest ended up costing
   more than a note - so it was dropped.)

3. **The MIDI clock generator charges its own running cost.** It does a
   Bresenham step on every one of the ~93 accounting points in a step.
   Uncharged, switching sync on dropped the tempo 8%. The charge has to go
   into `DE`, not straight into `steptime`, because the clock's own
   accumulator relies on the DEs summing to exactly one `steptarget` per
   step; adding to `steptime` alone breaks that and the clock falls to 5.5
   per step instead of 6.

### Pattern switches, and which work is worth charging

A pattern switch was stalling the music by about 40 ms - Michael heard it
as "slight delay between pattern change". Two separate costs:

| | | |
|---|---|---|
| the screen redraw | ~140 of the 768 grid cells change, at 250 us a cell | **35 ms** |
| the page copy | `getpat0` + `screenupdate`, two ~800 byte LDIRs | **9.7 ms** |

Neither was charged to the step clock, so both were *added* to the step
instead of coming out of its idle delay.

**The redraw is now charged** - `renderslice` counts the cells it draws and
the main loop charges `rendered * CELLCOST_U`. That removed the 35 ms
entirely, because the redraw happens *during* the step's delay: the
account advances, the remaining delay shrinks, and the step still lands on
time.

**The page copy is deliberately NOT charged**, and this is the part worth
remembering. Boundary work runs *after* the delay is already exhausted, so
charging it cannot shorten the step it belongs to - it shortens the next
one. Measured: charging 13 ms turned one 115 ms step into a 115 then 95 ms
pair, a 20 ms swing, where leaving it alone gives a single 6.4 ms blip.
One-off boundary work is therefore left as a small blip.

The per-step boundary work (`NEXTNOTE_U`, `CURSOR_U`, `PLAYNOTES_U`) *is*
charged, because it happens every step and is uniform: the average period
stays right and no step is out of line with its neighbours.

Result, measured over 420 steps of BOOGIE in song mode with the step
boundary tapped directly at `qtrackpos`:

| | |
|---|---|
| step period | 107453 us against 107364 target, **+0.083%** |
| jitter | sd **244 us** |
| a pattern switch | a single **+6.5 ms** step, no compensating short one |

**These constants are calibrated against the code as it stands.** Change
what a main loop pass does and `PASS_U` has to be re-measured, or the
tempo drifts. Re-measure with `tk3.lua`.

## Memory map

    #0800..#0FFF  font, eight page aligned scanline tables
    #1000..#3BFF  code
    #3C00..#3FFF  VRAM, the shadow video buffer (TRS-80 geometry)
    #4000..#9874  the data segment, 22645 bytes, byte for byte the TRS-80's
    #9880..#9C7F  SHADOW, what is currently on screen
    #9E00..#A5FF  AMSDOS's 2K buffer

The binary is 36981 bytes, load #0800, entry #1000. Interrupts are off
throughout and enabled only around AMSDOS calls; nothing else here touches
the firmware.

## Files

| | |
|---|---|
| `mktracker.py`, `zmac2rasm.py` | the port itself: they generate `tracker.asm` |
| `tracker.asm` | generated, do not edit |
| `render.asm` | the display layer and the two row maps |
| `kbdcpc.asm` | the PSG keyboard scan and the key tables |
| `midi.asm` | MIDI send/receive wrappers |
| `fileio.asm` | AMSDOS save/load |
| `font.asm` | generated from `OS_6128.ROM` |
| `mame.sh` | headless MAME wrapper, xvfb so no window appears |
| `tk1..tk10.lua` | the harnesses each layer was verified with |
| `screen.asm`, `player.asm`, `*test.asm` | the earlier standalone layer tests |
| `TADI.BIN`, `TADI-disassembly.txt` | Michael's 1987 TADITRANS, the key reference |

Toolchain lives elsewhere:

    ~/claude/midi80/toolchain/rasm/rasm      CPC Z80 assembler (rasm 3.2.7)
    ~/claude/midi80/toolchain/idsk/iDSK      read/write CPC .dsk images
    ~/claude/cpc/mame-roms/                  cpc6128 + cpc464 romsets

rasm needed a stub for `tcp_send_receive()`: upstream calls it for the
"assemble straight to a real CPC over TCP" directive but ships no
definition, so it will not link. See `toolchain/rasm/tcp_stub.c`.

## Harness notes

MAME 0.264 from apt.

    ./mame.sh cpc6128 -flop1 disk.dsk -seconds_to_run 20 \
              -autoboot_delay 0 -autoboot_script script.lua

Traps, all of which cost runs:

1. **Taps and frame notifiers die when their handle is garbage collected.**
   Park them in globals. This one bit twice.
2. **`natkeyboard.in_use = true`** is required or typing silently does
   nothing.
3. **`post_coded` does not treat `\n` as RETURN.** Use `{ENTER}`.
4. **Results must outlive the program.** BASIC reclaims scratch areas the
   moment your program returns. End a test with `jr $` and read while it
   holds.
5. **MAME does not commit CPC floppy writes** - see the file I/O section.
   Verify writes at the controller instead.
6. **AMSDOS filenames are 8.3.** `RUN"OPENTEST2` gives "Bad command", not
   "file not found", and the program silently never runs.
7. An unpressed CPC keyboard row reads `#FF`, so **no byte can serve as a
   frame delimiter** in a captured stream - chunk by fixed length.
8. MAME exposes the CPC keyboard as `:kbrow.0` .. `:kbrow.9`, one port per
   hardware row, if `post_coded` is not enough.

## rasm and iDSK notes

- no `high()`; use `/256`
- a leading parenthesis parses as memory addressing, so `add a,(X>>8)`
  becomes an indirect load. Use `X/256`.
- labels are case insensitive, so `scrbase:` collides with `SCRBASE equ`,
  and `datastart:` with `DATASTART equ`. Prefix the port's equates.
- `name equ value`, never `name: equ value`
- strings are `defb "..."`, not zmac's `ascii`
- macros are `macro name args` / `mend`; macro-local labels start with `@`
- `save` is a directive, so it cannot also be a label
- rasm's expression parser chokes on some single character literals such
  as `'='`; `zmac2rasm.py` turns those into numbers - but **only on
  instruction operands**, because inside a `defb` list the same pattern
  matches the comma *between* two literals and silently eats them both.
  That bug put `' 44C44B44M'` where `' ','C','B','M'` belonged and showed
  up as a stray `4` on the status line.
- `run <addr>` sets the AMSDOS entry point that `save ...,AMSDOS` writes
- `iDSK -t 2` inserts a file that already has its own AMSDOS header

## Still to do

Test on real hardware - all of it, and `S` (save) in particular.

## Building the HFE images

`hxcfe` will not run as built - the loader cannot find `libhxcfe.so`, which
sits next to the binary rather than on the library path:

    export LD_LIBRARY_PATH=~/claude/midi80/toolchain/hxc/build
    ~/claude/midi80/toolchain/hxc/build/hxcfe \
        -finput:dsk/tracker-boogie.dsk \
        -foutput:hfe/tracker-boogie.hfe -conv:HXC_HFE

It picks the Amstrad CPC DSK loader and the CPC_DD floppy interface mode by
itself. Output is 42 tracks, single sided, 250 kbit/s MFM, 1054720 bytes.

All three were booted in MAME **from the HFE** and played, not just
converted and assumed good.
