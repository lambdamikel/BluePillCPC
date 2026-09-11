#!/usr/bin/env python3
"""Build tracker.asm (CPC) from the TRS-80 tracker7.asm.

The port is deliberately a transcription, not a rewrite: the shadow video
buffer sits at #3C00, the TRS-80's own video address, so every screen
address in TRACKER is correct as written and the vast majority of the
source crosses over untouched. What this script does is
  (1) a mechanical zmac -> rasm syntax pass, and
  (2) a set of named region replacements, one per thing that is genuinely
      machine specific: keyboard, disc, timing base, external clock,
      video refresh, and the exit path.
Everything else - the editor, the song mode, the MIDI clock generator,
the note scheduler - is the TRS-80's code.
"""
import re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))

# The TRS-80 source this is generated from. A copy ships next to this
# script so the tree builds standalone; the working copy in the MIDI-80
# repo wins when it is present, so a fix there flows straight through.
SRC = os.path.join(HERE, 'tracker7.asm')
for cand in (os.path.expanduser('~/claude/midi80/MIDI-80/trs-80/zmac/tracker7.asm'),):
    if os.path.exists(cand):
        SRC = cand
        break
DST = os.path.join(HERE, 'tracker.asm')

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from zmac2rasm import convert

lines = convert(open(SRC).read()).split('\n')
orig = list(lines)

def find_in(seq, label, start=0):
    pat = re.compile(r'\s*' + re.escape(label.rstrip(':')) + r'(?![A-Za-z0-9_])')
    for i in range(start, len(seq)):
        if pat.match(seq[i]):
            return i
    raise SystemExit('anchor not found: ' + label)

def find(label, start=0):
    pat = re.compile(r'\s*' + re.escape(label.rstrip(':')) + r'(?![A-Za-z0-9_])')
    for i in range(start, len(lines)):
        if pat.match(lines[i]):
            return i
    raise SystemExit('anchor not found: ' + label)

edits = []          # (start_label, end_label_or_None, replacement_text)
def R(a, b, text):
    edits.append((a, b, text))

# ===================================================================== #
R(None, 'main:', r'''
;; ===================================================================
;; TRACKER/CPC  -  TRACKER V2.00 for the Ultimate MIDI Card, ported
;; from the TRS-80 MIDI/80 version to the Amstrad CPC 6128
;; (C)2026 LAMBDAMIKEL + CLAUDE.  Assembles with rasm.
;;
;; This is the TRS-80 source. The editor, the song mode, the note
;; scheduler and the MIDI clock generator are unchanged; what is
;; replaced is the six things that are actually machine specific.
;;
;;   video     TRACKER writes characters to #3C00 + row*64 + col. The CPC
;;             has no text mode, so #3C00 is a 64x16 shadow buffer laid
;;             out exactly like TRS-80 video RAM, and a renderer turns it
;;             into mode 2 pixels. Not one screen address had to change.
;;   keyboard  the matrix is behind the PSG rather than memory mapped;
;;             the whole thing is sampled once per main loop pass.
;;   MIDI      "out (8),a" becomes "call midiout" (BC is live across
;;             several of TRACKER's sends, so the wrappers preserve it).
;;   disc      AMSDOS moves a whole file in one call, so the TRS-80's 88
;;             iteration loop and its ERN arithmetic are gone.
;;   clock     the external step pulse arrives as MIDI #F8 instead of on
;;             the printer port, which on a CPC is write only.
;;   time      see the timing block below.
;;
;; MEMORY MAP
;;   #0800..#0FFF  font, eight page aligned scanline tables
;;   #1000..#3BFF  code
;;   #3C00..#3FFF  VRAM, the shadow video buffer (TRS-80 geometry)
;;   #4000..#9874  the data segment, 22645 bytes - byte for byte the
;;                 TRS-80's, so DUMP files interchange between machines
;;   #9880..#9C7F  SHADOW, what is currently on screen
;;   #9E00..#A5FF  AMSDOS's 2K buffer
;;
;; Interrupts stay off throughout, and are enabled only around AMSDOS
;; calls. Nothing else here touches the firmware, and with interrupts off
;; the gate array's whole-microsecond instruction timing makes the step
;; period exactly deterministic - which is what lets the BPM readout be
;; computed rather than calibrated. See the timing block below.
;; ===================================================================

VRAM    equ #3C00               ; the TRS-80's video address, kept
SHADOW  equ #9880               ; what the screen currently shows
dsk_buffer equ #9E00            ; AMSDOS scratch; unused in disc mode

DISPMIDINOTEOFFSET equ #61      ; 0 -> 'a'

;; The position marker, used for the song editor's cursor and for the play
;; cursor on the ruler. On a TRS-80 #AA is a graphics block that reads as a
;; cursor; the CPC has a completely different set there and it comes out as
;; a 3/4 fraction. #8F is the CPC's only solid block - and is what its own
;; BASIC cursor looks like, so it is the idiomatic choice here.
POSMARKSYM equ  #8F
SETSYM  equ     #8f
CURSYM  equ     'X'

ENTER   equ #0d

KCURLEFT        equ 8
KCURRIGHT       equ 9
KCURUP          equ 91
KCURDOWN        equ 10

CPC_PRINTER     equ #EF00       ; Centronics data, for the clock box

;; ---- MIDI clock / MMC output ----------------------------------------
;; MIDI beat clock is 24 ppqn. One TRACKER step is a 16th note, so a
;; quarter note is 4 steps and 6 MIDI clocks are due per step.
MIDICLKPERSTEP  equ     6

;; ---- timing ---------------------------------------------------------
;; The TRS-80 has to ESTIMATE elapsed time, because it cannot know its
;; own loop costs: video wait states, DRAM refresh and a variable ROM
;; keyboard call all move under it. That estimate is what made its BPM
;; readout read low, and it needed measuring on real hardware to fix.
;;
;; The CPC needs none of that. The gate array stretches every instruction
;; to a whole number of microseconds, so with interrupts off each region
;; of the loop costs exactly what it costs, every time. The accumulator
;; below is therefore not an estimate but an account, and steptarget is
;; the period the machine actually plays - which is why the BPM readout
;; here is simply 3750000/steptarget with no calibration constant.
;;
;; Time is accumulated in units of USCALE microseconds. A whole step is
;; up to 225 ms, which would overflow the 16 bit accumulator undivided.
USCALE          equ     4       ; microseconds per accounting unit

;; Step period, matched to the TRS-80's measured 30963 + 763*tempo us so
;; that a song plays at the speed it does on the machine it came from:
;;      steptarget = 7741 + 191*tempo   in 4 us units
;; 30963/4 = 7740.75 and 763/4 = 190.75, so the two agree to 0.1% over
;; the whole tempo range. tempo #2A gives 63.1 ms, tempo #FF 225.8 ms.
TEMPOBASE       equ     7741
TEMPOSLOPE      equ     191

;; Region costs, in USCALE units. Unlike the TRS-80's, these are exact:
;; each is the measured cost of a deterministic block.
PASSDIV         equ     1       ; charge every main loop pass
SHORTDIV        equ     1       ; ... and every short_delay
;; Measured under MAME by tapping the PPI write that starts each keyboard
;; scan, which happens exactly once per pass:
;;      full pass          1606 us     (deterministic to the microsecond
;;                                      except when the cursor blinks)
;;      step boundary      ~10000 us   on top of a pass
;; and 24 short_delay calls fall inside that boundary. The credits below
;; are those measurements, so the account balances whatever the tempo and
;; however many passes a step turns out to hold. Measured step period at
;; BOOGIE's tempo: 107364 us target, within 0.1%.
;;
;; NOTE these are calibrated against the code as it stands. Change what a
;; pass does and PASS_U has to be re-measured, or the tempo drifts.
PASS_U          equ     407     ; one main loop pass: keyboard scan, one
                                ; sixteenth of the dirty scan, and the rest
SHORTDLY_U      equ     20      ; one short_delay (28 us + overhead)
WHLSLICES       equ     4       ; slices the per step delay is broken into
WHLNORM         equ     100     ; iterations per slice, 7 us each
WHLSYNC         equ     WHLNORM ; the TRS-80 shortened the step delay while
                                ; the clock ran, to give back what the clock
                                ; cost. Here the generator charges itself
                                ; per call instead (SYNCCALL_U), which is
                                ; exact, so no such give-back is needed.
WHLSLICE_U      equ     185     ; one slice
NEXTNOTE_U      equ     60      ; nextnote bookkeeping
CURSOR_U        equ     300     ; showplaycursor: two rows plus two cells
PLAYNOTES_U     equ     381     ; playnotes / stoptracks, the fixed part
NOTEEVENT_U     equ     256     ; ... plus this for every note actually sent.
                                ; A note event is three bytes through midiout
                                ; plus two short_delays; at 320 us a byte that
                                ; is 990 us measured, and it dominates a busy
                                ; step. Kept a power of two so the multiply
                                ; stays shifts: 256 units = 1024 us.
CURBLINK_U      equ     150     ; one edit cursor blink (two cells)
CELLCOST_U      equ     64      ; one cell redrawn by the dirty scan (256 us;
                                ; measured 250). A pattern switch dirties
                                ; ~140 of them, so this is 35 ms that has to
                                ; come out of the step's idle delay rather
                                ; than be added to the step.
;; The page copy and screen rebuild at a pattern switch - two ~800 byte
;; LDIRs, 9.7 us measured - is deliberately NOT charged, and the reason is
;; worth writing down because it is not obvious.
;;
;; A charge only helps when the work happens DURING the step's delay, as
;; the dirty scan's does: the account advances, the remaining delay
;; shrinks, and the step still lands on time. Boundary work is different.
;; It runs after the delay is already exhausted, so charging it cannot
;; shorten the step it belongs to - it shortens the NEXT one. Measured:
;; charging 13 ms turned one 115 ms step into a 115 then 95 ms pair, a
;; 20 ms swing, where leaving it alone gives a single 6.4 ms blip.
;;
;; So one-off boundary work is left as a small unavoidable blip. The
;; per-step boundary work (NEXTNOTE_U, CURSOR_U, PLAYNOTES_U) IS charged,
;; because it happens every step and is therefore uniform - the average
;; period stays right and no step is out of line with its neighbours.

SYNCCOST_U      equ     500     ; six clock bytes out of the card, per step:
                                ; at 320 us a byte that is 2 ms, not the 130 us
                                ; it was before the wire pacing went in
SYNCCALL_U      equ     28      ; the clock generator's own cost, per call.
                                ; It runs a Bresenham step on every one of
                                ; the ~93 accounting points in a step, which
                                ; is real time and has to be charged or the
                                ; tempo drops 8% the moment sync is on.

MIDI_CLOCK      equ     #f8
MIDI_START      equ     #fa
MIDI_CONTINUE   equ     #fb
MIDI_STOP       equ     #fc
MIDI_SPP        equ     #f2
MMC_STOP        equ     #01
MMC_PLAY        equ     #02
MMC_RECSTROBE   equ     #06
MMC_PAUSE       equ     #09
midisyncs:      equ     'M'

stoppeds:  equ  'H'
playings:  equ  'P'
songs:     equ  'S'
records:   equ  '*'
playbacks: equ  ' '
extclocks: equ  "'"

frees:    equ   'F'
trackeds: equ   'T'

;; ---- the binary ------------------------------------------------------
    org #0800
    include "font.asm"

    org #1000
    run #1000                   ; AMSDOS entry point
    jp main                     ; ... which stays at #1000 whatever follows

    include "midi.asm"
    include "fileio.asm"
    include "render.asm"
    include "kbdcpc.asm"

DSK_START equ datastart
DSK_LEN   equ datalength

errorm: defb   '***** DISK ERROR! DISK FULL / PROTECTED / NO DUMP? ANY KEY *****'

line:   defb   'SONG EDITOR:  USE LEFT/RIGHT, ENTER, A-Z=PATTERN, .=STOP, *=LOOP'

quitm:  defb   '***** QUIT TRACKER - REALLY QUIT? SAVED YOUR WORK? Y/N: _  *****'

clearm: defb   '***** CLEAR PATTERN - ARE YOU SURE? REALLY CLEAR? Y/N: _   *****'

savem:  defb   '**** SAVE STATE - OVERWRITE EXISTING CORE DUMP FILE? Y/N: _ ****'

loadm:  defb   '***** LOAD STATE - LOAD CORE DUMP FILE INTO MEMORY? Y/N: _ *****'

@@SCREENS@@
''')

# --- the title block, the ruler and the help page are copied verbatim
#     from the TRS-80 source by the region walk below (title: .. helpt end)

R('main:', 'main2:', r'''
main:
    call setscreen              ; mode 2, black paper, bright yellow text
    di                          ; and nothing touches the firmware again
                                ; until a disc call

    ld hl,rowsplit              ; the sequencer's screen layout
    call setrows

    ld  hl,waitt
    ld  de,VRAM
    ld  bc,1024
    ldir
    call renderall              ; show the splash while initmem runs

    call initmem

''')

R('loop:', 'loopnoclk:', r'''
loop:
    call kbdraw                 ; one matrix sample serves the whole pass
    call renderslice            ; a sixteenth of the screen, ~0.9 ms clean

    ld a,(rendered)             ; ... but far more when cells actually
    or a                        ; changed, so charge what it drew
    jr z, loopnorend
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                   ; * CELLCOST_U (64)
    ex de,hl
    call midiclkadd
loopnorend:

    ld hl, passdivc             ; account for elapsed loop passes
    dec (hl)
    jr nz, loopnoclk
    ld (hl), PASSDIV
    ld de, PASS_U
    call midiclkadd
''')

R('listenextclock:', 'advanceclock:', r'''
listenextclock:

    ;; The TRS-80 takes its external clock off the printer port. The CPC's
    ;; Centronics is write only, so the step pulse comes in over MIDI
    ;; instead: an #F8 timing clock from the card advances one step. That
    ;; is the better fit anyway - the card is already there, and every
    ;; sequencer and drum machine in the world sends #F8.

    call midipoll
    or a
    jr z, lec1
    ld hl, midi_registered      ; a recorded note arrived in the same poll
    ld (hl), 1
lec1:
    ld hl, extclktick
    ld a, (hl)
    or a
    jp z, nostep
    ld (hl), 0
    jp nextstep

''')

R('advanceclock:', 'nextstep:', r'''
advanceclock:

    ;; Step when the time accounted for this step reaches the target.
    ;;
    ;; Here the CPC can do something the TRS-80 could not. On that machine
    ;; the step could only ever fall on a main loop pass boundary, so it
    ;; landed up to a whole pass late and the carry in steplatch had to
    ;; make the average come out right - which is where most of its 680 us
    ;; of jitter came from. The gate array quantises every instruction to a
    ;; whole microsecond, so here, once the target is less than one pass
    ;; away, the exact remainder can be burned off: a "djnz" taken costs
    ;; 13 T rounded up to 16, which is 4 us, which is one accounting unit.
    ;; The step then lands on the microsecond it is due.

    ld hl,(steptarget)
    ld de,(steptime)
    or a
    sbc hl,de
    jr c, nextstep              ; already past: step now and let steplatch
    jr z, nextstep              ; carry the overshoot, as before
    ld de,PASS_U
    push hl
    or a
    sbc hl,de
    pop hl
    jp nc, nostep               ; a whole pass still fits: keep looping

    ex de,hl                    ; de = units still to go
    push de
    call midiclkadd             ; account for them, and send any clock due
    pop hl

    ld a,h
    or a
    jr z, acfine1
acfine0:
    ld b,0                      ; 256 units
acfine0a:
    djnz acfine0a               ; exactly 4 us an iteration
    dec h
    jr nz, acfine0
acfine1:
    ld a,l
    or a
    jr z, nextstep
    ld b,l
acfine1a:
    djnz acfine1a

''')

R('nextstep:', 'nextstep1:', r'''
nextstep:

    call steplatch

    ;; step pulse on the Centronics data lines, for the clock box
    ld hl, extclockout
    inc (hl)
    ld a, (hl)
    ld bc, CPC_PRINTER
    out (c), a

''')

R('nostep:', 'cur0:', r'''
nostep:

    ;; Sample the keys that may be queued during playback. The TRS-80 read
    ;; three matrix rows here; the CPC's whole matrix was already sampled
    ;; at the top of the pass, so these are free.

    ld a,(kbdmap+KROW_SPACE)
    and KBIT_SPACE
    jr nz,nostep_scan1
    ld hl, space_registered
    ld (hl), 1

nostep_scan1:

    ld a,(kbdmap+KROW_CLR)
    and KBIT_CLR
    jr nz,nostep_scan2
    ld hl, clear_registered
    ld (hl), 1

nostep_scan2:

    ;; ENTER is never dispatched by its ASCII code - TRACKER samples the
    ;; key straight from the matrix, so that it still registers while a
    ;; pattern is playing and notes can be punched in live. COPY sets a
    ;; note too, so it is sampled in exactly the same place.
    ld a,(kbdmap+KROW_RET)
    and KBIT_RET
    jr z,nostep_ent
    ld a,(kbdmap+KROW_COPY)
    and KBIT_COPY
    jr nz,nostep_scan3
nostep_ent:
    ld hl, enter_registered
    ld (hl), 1

nostep_scan3:

    ;; sample MIDI and queue if in RECORD mode only

    ld a,(record)
    or a
    jr z, cur0

    call midipoll
    or a
    jr z, cur0

    ld hl, midi_registered
    ld (hl), 1

''')

R('midiin:', 'help:', r'''
midipoll:

    call midistat
    ret z

    ;;  byte available

    call midiin

    cp #f8
    jr c, midipoll1             ; not a system real time byte
    jr nz, midipollrt           ; #F9..#FF: handled below, and either way
                                ; the running status parser is left alone,
                                ; which is what a real time byte may do

    ;; #F8, the MIDI beat clock. It runs at 24 ppqn and a TRACKER step is
    ;; a 16th note, so six of them make one step - which is also exactly
    ;; what TRACKER sends when IT is the master.
    ld hl,extclkdiv
    dec (hl)
    jr nz, midipollz
    ld (hl),MIDICLKPERSTEP
    ld a,1
    ld (extclktick),a
    jr midipollz

midipollrt:
    cp #fa                      ; #FA start: line the divider up with the
    jr nz, midipollz            ; master, so the phase is right from bar 1
    ld a,MIDICLKPERSTEP
    ld (extclkdiv),a

midipollz:
    xor a
    ret

midipoll1:
    bit 7,a
    jr nz, midicommand

    ld b, a
    ;; MIDI data byte
    ld a, (midicount)
    or a
    ret z

    ;; note byte?
    cp 1
    jr nz, velcheck

    ld a, b
    ld (curnote), a
    ld a, 2
    ld (midicount), a

    xor a

    ret

velcheck:
    ; use velocity from settings instead of MIDI message!

    call gettrackvelocity
    ld (curvelocity), a

    ; signal message complete -> note / vel available
    ld a, 1

    ret

midicommand:

    ld b, a
    xor a
    ld (midicount), a

    ld a, b
    ;; note on?
    cp #90
    jr z, midinoteon

    xor a
    ret

midinoteon:

    ;;  note on!
    ld a, 1
    ld (midicount), a

    xor a

    ret

''')

R('help:', 'midiflush:', r'''
help:
    call putpat

    ld  hl,VRAM
    ld  de,VRAM+1
    ld  bc,1024-1
    ld  (hl),' '
    ldir

    ld  hl,helpt
    ld  de,VRAM
    ld  bc,1024
    ldir

    ld hl,rowflat               ; 16 solid lines of text want no gaps
    call setrows
    call renderall              ; and waitkey blocks, so the incremental
                                ; scan would never get a turn to show it
    call waitkey

    ld  hl,title
    ld  de,VRAM
    ld  bc,1024
    ldir

    call long_delay
    call long_delay
    call long_delay

    jp main2

''')

R('quit:', 'nextbar:', r'''
quit:
    call putpat

    ld hl, quitm
    call yesnoprompt
    jp nz, cont

    ;; TRACKER is loaded over BASIC's program and variable area, so there
    ;; is nothing left to return to: reset back to a clean BASIC.
    ei
    jp 0

''')

R('settarget:', 'sendrt:', r'''
settarget:
    ;; steptarget = TEMPOBASE + tempo*191   (191 = 192 - 1)
    ld a,(tempo)
    ld l,a
    ld h,0
    ld d,h
    ld e,l                      ; de = tempo
    add hl,hl                   ; 2t
    add hl,hl                   ; 4t
    add hl,hl                   ; 8t
    add hl,hl                   ; 16t
    add hl,hl                   ; 32t
    add hl,hl                   ; 64t
    ld b,h
    ld c,l                      ; bc = 64t
    add hl,hl                   ; 128t
    add hl,bc                   ; 192t
    or a
    sbc hl,de                   ; 191t
    ld de,TEMPOBASE
    add hl,de
    ld (steptarget),hl
    ret

''')

R('showplaycursor:', 'screenupdate:', r'''
showplaycursor:

    ;; Both ruler rows are rewritten from the title image and the marker
    ;; put back, exactly as on the TRS-80 - but only two cells can have
    ;; changed, so only two are pushed to the screen. 424 us, which is
    ;; 0.4% of a step; letting the incremental scan find them would have
    ;; left the play cursor up to 26 ms late.

    ld  hl,title+2*64
    ld  de,VRAM+2*64
    ld  bc,64
    ldir

    ld  hl,title+9*64
    ld  de,VRAM+9*64
    ld  bc,64
    ldir

    ld hl,(lastplaypos)         ; repaint whatever the old marker covered
    call rendercellc

    ld a,(qtrackpos)

    ld hl,VRAM+2*64
    ld e,a
    ld d,0
    add hl,de

    bit 6,a
    jr nz,showcurtrack2

showcurtrack1:
    ld (hl),POSMARKSYM
    ld (lastplaypos),hl
    call rendercellc
    ret

showcurtrack2:
    ld de,6*64
    add hl,de
    jr showcurtrack1

''')

R('showcursor:', 'byte2ascii:', r'''
showcursor:

    ld hl,(lastcurpos)
    ld a,(lastcur)
    ld (hl),a
    call rendercellc            ; put back what the cursor was covering
    call cursor
    ld (lastcurpos),hl
    ld a,(hl)
    ld (lastcur),a

    ld a,(blink)
    cp 127
    ret c                       ; dark half of the blink: the cell already
                                ; shows its own character
    ld (hl), CURSYM
    call rendercellc
    ret

;; one blink transition, charged to the clock like every other region
curblink:
    call showcursor
    ld de,CURBLINK_U
    jp midiclkadd

''')

R('dly.01:', 'clearextclockr:', '')

R('clearextclockr:', 'nextnote:', r'''
clearextclockr:

    xor a
    ld (extclktick), a
    ld a,MIDICLKPERSTEP
    ld (extclkdiv), a
    ret

''')

R('calcbpm:', 'calcbpm0:', r'''
calcbpm:
    ld a,(tempo)
    ld hl,bpmtempo
    cp (hl)
    ret z                       ; unchanged: digits are still valid
    ld (hl),a

    call settarget              ; steplatch only runs while playing, so
                                ; keep the period in step with tempo here

    ld hl,bpmk
    ld de,dvnd
    ld bc,4
    ldir

    ;; On the CPC the period the machine plays IS steptarget - the
    ;; accounting is exact - so the readout divides by it directly and
    ;; needs no measured calibration constant of its own.
    ld hl,(steptarget)
    ld (bpmdiv),hl

    srl h                       ; round to nearest instead of truncating:
    rr l                        ; bias the dividend by half the divisor
    ld de,(dvnd)
    add hl,de
    ld (dvnd),hl
    jr nc,calcbpm0
    ld hl,(dvnd+2)
    inc hl
    ld (dvnd+2),hl
''')

R('bpmk3:', 'gettracknr:', r'''
;; BPM = 60e6 / (4 steps * steptarget * USCALE) = 3750000 / steptarget
bpmk:   defb #70,#38,#39,#00    ; 3750000, little endian

''')

R('long_delay:', 'kbdscan:', r'''
long_delay:
    ld de,#0800                 ; ~14 ms
delloop1:
    dec de
    ld a,d
    or e
    jp nz,delloop1
    ret

;; Byte pacing is midiout's job now - see the long comment there. This is
;; kept for the clock accounting hook it carries and for the small part it
;; plays in equalising a busy step against an empty one.
short_delay:
    ld de,4                     ; 28 us. The wire pacing that used to live
                                ; here is now inside midiout, where the bare
                                ; OUTs get it too; what is left is the clock
                                ; accounting hook and a little of the work
                                ; that equalises a busy step against an
                                ; empty one.
delloop:
    dec de
    ld a,d
    or e
    jp nz,delloop
    ld hl,shortdivc
    dec (hl)
    jr nz,shortnoclk
    ld (hl),SHORTDIV
    ld de,SHORTDLY_U
    call midiclkadd
shortnoclk:
    ret

''')

R('kbdscan:', 'loaddisk:', '')

R('loaddisk:', 'yesnoprompt:', r'''
;; ---------------------------------------------------------------
;; Disc. AMSDOS moves a whole file in one call, so the TRS-80's 88
;; iteration @read loop, its 256 byte staging buffer and its ERN fixup
;; are all gone. dsk_save / dsk_load are in fileio.asm, and they put the
;; disc jumpblock back first - RUN" leaves the CASSETTE vectors in place,
;; which is the trap that cost a day.
;; ---------------------------------------------------------------

loaddisk:
    call discio_begin
    call dsk_load
    push af
    call discio_end
    pop af
    ret c
    jr diskerror

savedisk:
    call discio_begin
    call dsk_save
    push af
    call discio_end
    pop af
    ret c
    jr diskerror

;; AMSDOS wants interrupts, and on an error it prints over our screen, so
;; the mode is re-established and the whole display repainted either way.
discio_begin:
    ei
    ret

discio_end:
    call setscreen              ; AMSDOS may have printed over us, and
    di                          ; SCR SET MODE resets the palette
    call renderall
    ret

diskerror:
    ld  hl,errorm
    ld  de,VRAM+64
    ld  bc,64
    ldir
    ld  hl,VRAM+64
    ld  bc,64
    call renderrun
    call waitkey
    call restorestatus
    ld  hl,VRAM+64
    ld  bc,2*64
    call renderrun
    ret

''')

R('yesnoprompt:', 'org #8000', r'''
yesnoprompt:
    push hl
    call savestatus
    pop hl
    ld  de,VRAM+64
    ld  bc,64
    ldir
    ld  hl,VRAM+64
    ld  bc,64
    call renderrun              ; waitkey blocks, so show it now
    call waitkey
    cp 'Y'
    call restorestatus

    push af
    ld  hl,VRAM+64
    ld  bc,2*64
    call renderrun
    ;; ensure enter doesn't register...
    call long_delay
    call long_delay
    call long_delay
    pop af

    ret

;; ---------------------------------------------------------------
;; wHL - burn HL iterations. George Phillips' T-state juggling is not
;; needed here: the gate array quantises every instruction to a whole
;; microsecond, so this plain loop costs exactly 7 us an iteration and
;; the delay is deterministic.
;;      dec hl (2) + ld a,h (1) + or l (1) + jr nz (3) = 7 us
;; ---------------------------------------------------------------
wHL:
    ld a,h
    or l
    ret z
wHL1:
    dec hl
    ld a,h
    or l
    jr nz,wHL1
    ret

;;
;; data region
;;

''')

R('org #8000', 'datastart', r'''
;; State that is NOT part of a DUMP. On the TRS-80 this sat just below
;; datastart; here it can live anywhere, so it lives in the code.

usemidisync     defb 0          ; 0 off, 1 clock, 2 clock+MMC, 3 MMC only
midiclkacc      defw 0          ; Bresenham accumulator
steptime        defw 0          ; time accumulated so far this step
laststeptime    defw 0          ; previous step total
steptarget      defw 0          ; the step period, from tempo
bpmtempo        defb #ff        ; tempo the BPM digits were computed for
bpmdigits       defb '-','-','-'
dvnd            defs 4          ; scratch dividend for the BPM division
midiclkbusy     defb 0          ; re-entrancy guard while sending a message
passdivc        defb 1          ; main loop call divider
shortdivc       defb 1          ; short_delay call divider
bpmdiv          defw 0          ; the divisor behind the BPM readout
whlslicecur     defw WHLNORM    ; active step delay slice
extclktick      defb 0          ; an #F8 arrived from the card
noteevents      defb 0          ; MIDI note events sent this step
extclkdiv       defb MIDICLKPERSTEP  ; 24 ppqn in, one 16th note out
lastplaypos     defw VRAM+2*64  ; where the play marker was last drawn

    org #4000
''')

R('end main', None, '''
;; The data segment is byte for byte the TRS-80's, so a DUMP written on
;; one machine loads on the other.
    assert datalength == 22645

    save "TRACKER.BIN", #0800, dataend-#0800, AMSDOS, main
''')

# ===================================================================== #
# apply, from the bottom up so earlier indices stay valid
spans = []
for a, b, text in edits:
    i = 0 if a is None else find(a)
    j = len(lines) if b is None else find(b, i + 1)
    spans.append((i, j, text))
spans.sort(key=lambda s: -s[0])
for i, j, text in spans:
    lines[i:j] = text.split('\n')

out = '\n'.join(lines)

# The card is a MIDI/80 only on the TRS-80. Here it is Michael's Ultimate
# MIDI Card, so the banner says so. The line is exactly 64 columns and has
# to stay that way - it is a screen image, LDIRed straight into the buffer,
# so a byte more or less would shift everything after it.
TRSTITLE = "***** MIDI/80 TRACKER V2.00 - (C)2026 LAMBDAMIKEL + CLAUDE *****"
CPCTITLE = "**** ULT.MIDI CARD TRACKER V2.00 (C)2026 LAMBDAMIKEL+CLAUDE ****"
assert len(CPCTITLE) == len(TRSTITLE) == 64

# TRACKER's own screen images: the banner, the status line, the two rulers
# and the help page. Copied across as they stand - every key the help page
# names exists on a CPC keyboard in the same shift relation it had on a
# TRS-80, so not a line of it needed changing.
screens = '\n'.join(orig[find_in(orig, 'waitt:'):find_in(orig, 'macro keydown')])
assert screens.count(TRSTITLE) == 2      # the splash and the live title
screens = screens.replace(TRSTITLE, CPCTITLE)
out = out.replace('@@SCREENS@@', screens)

# rasm wants "name equ value", never "name: equ value"
out = re.sub(r'^(\w+)\s*:(\s+)equ\b', r'\1\2equ', out, flags=re.M | re.I)

# The blink redraw costs real time on the pass it happens; charge it,
# or it shows up as an unmodelled spike in the step period. Also drops
# the original's reliance on A surviving a call.
out = out.replace("""\tor a
\tjp nz, cur1
\tcall showcursor

cur1:
\tcp 127
\tjp nz, scan
\tcall showcursor

scan:""", """\tor a
\tcall z, curblink

\tld a,(blink)
\tcp 127
\tcall z, curblink

scan:""")

out = out.replace("""curblink_MARKER""", "")

# --- charge the MIDI clock generator its own running cost ------------
# The charge has to go into DE, not straight into steptime: the clock's
# own Bresenham accumulates 6*DE and relies on the DEs summing to exactly
# one steptarget per step. Adding to steptime alone breaks that invariant
# and the clock drops to 5.5 per step instead of 6.
old = """midiclkadd:"""
new = """midiclkadd:

\t;; From "ret z; mode 0" on, this routine does real work on every one of
\t;; the ~93 accounting points in a step, and that is real time. Charge it
\t;; here, into DE, so that both the step clock and the MIDI clock see it
\t;; and the tempo does not drop 8% the moment sync is switched on.
\tld a,(usemidisync)
\tor a
\tjr z,mcanocost
\tcp 3
\tjr z,mcanocost
\tpush hl
\tld hl,SYNCCALL_U
\tadd hl,de
\tex de,hl
\tpop hl
mcanocost:"""
assert out.count(old) == 1
out = out.replace(old, new)

# --- per note accounting ---------------------------------------------
# The TRS-80 charged playnotes a flat rate and paid for it in jitter: a
# step where six tracks fire costs real time that a step of rests does
# not. Its answer was two "waste some time" short_delays in the rest
# branch, which only approximates it. Here each note event that actually
# goes out is counted and charged, so the step period stops depending on
# how busy the pattern is.
out = out.replace("""playnotes:
\tld a,(qtrackpos)""", """playnotes:
\txor a
\tld (noteevents),a
\tld a,(qtrackpos)""")

for lab in ("playnote1:", "stopnote1:"):
    old = "\n" + lab + "\n"
    assert old in out, lab
    out = out.replace(old, "\n" + lab + "\n\n\tpush hl\t\t\t; one more MIDI note event this step\n"
                            "\tld hl,noteevents\n\tinc (hl)\n\tpop hl\n", 1)

old = """\tcall playnotes
\tld de, PLAYNOTES_U
\tcall midiclkadd"""
assert old in out
out = out.replace(old, """\tcall playnotes
\tld a,(noteevents)\t; charge the notes that actually went out
\tld l,a
\tld h,0
\tadd hl,hl
\tadd hl,hl
\tadd hl,hl
\tadd hl,hl
\tadd hl,hl
\tadd hl,hl
\tadd hl,hl
\tadd hl,hl\t\t; * NOTEEVENT_U (256)
\tld de,PLAYNOTES_U
\tadd hl,de
\tex de,hl
\tcall midiclkadd""")

# main2 is where everything comes back to, so it re-establishes the
# sequencer's screen layout - which is what puts the help page's own
# layout back afterwards.
out = out.replace("""main2:

\tld\thl,title+2*64""", """main2:

\tld hl,rowsplit
\tcall setrows

\tld\thl,title+2*64""")

# deliberately NOT charged - see the SWITCH_U note in the constants

# --- CPC-native keys -------------------------------------------------
# The arrow keys move the edit cursor, which is what anyone sitting at a
# CPC expects them to do. On the TRS-80 they carried the bar position
# (up/down) and the drum number (left/right); the bar position is already
# on A and D, so nothing is lost there, and the drum number moves to
# SHIFT with the two arrows.
#
# This changes the MEANING in the dispatch rather than the key table, so
# the song editor - which has its own dispatch and moves its cursor on
# these same two codes - is untouched.
old = """\tcp KCURLEFT
\tjp z,drumnodown

\tcp KCURRIGHT
\tjp z,drumnoup"""
assert old in out
out = out.replace(old, """\tcp KCURLEFT\t\t; the arrows move the cursor on a CPC ...
\tjp z,left

\tcp KCURRIGHT
\tjp z,right

\tcp KDRUMDOWN\t\t; ... and SHIFT with them is the drum number
\tjp z,drumnodown

\tcp KDRUMUP
\tjp z,drumnoup""")

old = """\tcp KCURUP
\tjp z,nextbar

\tcp KCURDOWN
\tjp z,prevbar"""
assert old in out
out = out.replace(old, """\tcp KCURUP\t\t; bar position is on A and D, so these are
\tjp z,up\t\t\t; free to be what they look like

\tcp KCURDOWN
\tjp z,down""")

# --- help page, for the keys that differ from the TRS-80 --------------
HELP = [
 ("CURSOR MOVEMENT, FINE CONTROL        : A D W X, Z C             ",
  "CURSOR MOVEMENT, FINE CONTROL        : ARROWS, A D W X, Z C     "),
 ("SET GRID, SOUND, CLEAR               : SPACE, ENTER, CLEAR      ",
  "SET GRID, SOUND, CLEAR               : SPACE, ENTER/COPY, CLR   "),
 ("PAGE CHANGE CUR TRACK DRUM, LAST MIDI: ARROW-LEFT ARROW-RIGHT, @",
  "PAGE CHG CUR TRACK DRUM, LAST MIDI   : SHIFT-ARROW L/R, @       "),
 ("NEXT / PREV GRID POS, CHANGE GRID    : ARROW-UP ARROW-DOWN, G   ",
  "NEXT / PREV GRID POS, CHANGE GRID    : A D, G                   "),
]
for a, b in HELP:
    assert len(a) == len(b) == 64, (len(a), len(b))
    assert a in out, a
    out = out.replace(a, b)

# --- refresh points -------------------------------------------------
# The main loop repaints a sixteenth of the screen per pass, so anything
# it reaches is correct within ~26 ms without being told. These are the
# three places that write the buffer and then do NOT come back to the
# main loop, so they have to push their own pixels.

# startup: establish both the screen and the shadow copy in one go
out = out.replace("""\tcall screenupdate
\tcall showcursor""", """\tcall screenupdate
\tcall renderall\t\t; establish the screen, and the shadow copy of it
\tcall showcursor""")

# the pattern-copy prompt blocks in waitkey
out = out.replace("""\tld (hl), 63

\tcall waitkey""", """\tld (hl), 63

\tld hl,VRAM+64+5\t\t; blocks in waitkey, so show it now
\tld bc,4
\tcall renderrun

\tcall waitkey""")

# the song editor is a loop of its own and never passes through "loop:"
out = out.replace("""keyscan2:

\tcall kbdscan""", """keyscan2:

\tcall kbdraw
\tcall renderslice\t; the song editor never passes through "loop:"
\tcall kbdkey""")

# the main loop already sampled the matrix at the top of the pass
out = out.replace("""keyscan:

\tcall kbdscan""", """keyscan:

\tcall kbdkey\t\t; kbdraw already ran at the top of the pass""")

# the one macro-local label in the source; rasm spells those with @
out = re.sub(r'\bplaynoteon\b', '@playnoteon', out)

# labels that collide with rasm directives
out = re.sub(r'^load:', 'doload:', out, flags=re.M)
out = re.sub(r'^save:', 'dosave:', out, flags=re.M)
out = re.sub(r'\bjp z,load\b', 'jp z,doload', out)
out = re.sub(r'\bjp z,save\b', 'jp z,dosave', out)

# the stray "ld (hl),'A'" at initmem writes through whatever HL the
# preceding LDIR happened to leave; initmem1 sets curpat properly anyway
out = out.replace("initmem:\n\n\tld (hl), 'A'\n", "initmem:\n")

# these three now live in kbdcpc.asm
for v in ('lastkey', 'kbdsettlec', 'kbdshift'):
    out = re.sub(r'^' + v + r'\s+defb.*\n', '', out, flags=re.M)

open(DST, 'w').write(out)
print('wrote %s, %d lines' % (DST, out.count('\n') + 1))
