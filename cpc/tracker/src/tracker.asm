
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

POSMARKSYM equ  #aa
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
midisyncs      equ     'M'

stoppeds  equ  'H'
playings  equ  'P'
songs     equ  'S'
records   equ  '*'
playbacks equ  ' '
extclocks equ  "'"

frees    equ   'F'
trackeds equ   'T'

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

waitt:	defb   '**** ULT.MIDI CARD TRACKER V2.00 (C)2026 LAMBDAMIKEL+CLAUDE ****'
	defb   'PAT:A SF | TRACK:1 BPM:---  | B:8 S:04 | C:0 I:01 N:24 V:7F G:04'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	defb	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'

title:	defb   '**** ULT.MIDI CARD TRACKER V2.00 (C)2026 LAMBDAMIKEL+CLAUDE ****'
	defb   'PAT:A SF | TRACK:1 BPM:---  | B:8 S:04 | C:0 I:01 N:24 V:7F G:04'
	defb	'1===-===+===-===2===-===+===-===3===-===+===-===4===-===+===-==='
data:	defb   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	defb   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	defb   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	defb   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	defb   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	defb   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	defb	'5===-===+===-===6===-===+===-===7===-===+===-===8===-===+===-==='
	defb   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	defb   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	defb   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	defb   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	defb   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	defb   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'

helpt:	defb   '************************** HELP PAGE ***************************'
	defb   'CURSOR MOVEMENT, FINE CONTROL        : ARROWS, A D W X, Z C     '
	defb   'CHANGE BAR COUNT, JUMP TO BAR POS    : B, 1 2 3 4 5 6 7 8       '
	defb   'NEXT / PREV GRID POS, CHANGE GRID    : A D, G                   '
	defb   'SET GRID, SOUND, CLEAR               : SPACE, ENTER/COPY, CLR   '
	defb   "PAT/SONG PLAY, EXTCLK, MIDISYNC C/B/M: P !, ', R                "
	defb   'ALL NOTES OFF (MIDI PANIC)           : 0                        '
	defb   'TOGGLE RECORD, TOGGLE TRACKING       : #, T                     '
	defb   'PAT +/-, PAT CLEAR, COPY, SONG EDITOR: / ?, =, ", &             '
	defb   'HELP, QUIT, LOAD & SAVE              : H Q L S                  '
	defb   'GLOBAL CHANGE CUR TRACK MIDI INSTR.  : U I                      '
	defb   'PAGE CHANGE PLAYBACK SPEED           : N M , .                  '
	defb   'PAGE CHANGE CUR TRACK MIDI CHANNEL   : + -                      '
	defb   'PAGE CHANGE CUR TRACK MIDI VELOCITY  : J K                      '
	defb   'PAGE CHG CUR TRACK DRUM, LAST MIDI   : SHIFT-ARROW L/R, @       '
	defb   'PAGE CHANGE CUR TRACK GATE LENGTH    : *                        '



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


main2:

	ld hl,rowsplit
	call setrows

	ld	hl,title+2*64
	ld	de,#3c00+2*64
	ld	bc,1024-2*64
	ldir

	call settarget

	call screenupdate
	call renderall		; establish the screen, and the shadow copy of it
	call showcursor
	call showplaycursor
	call showtempo

	ld hl, 	#3c00; glitch out last cusor pos
	ld (hl), 42


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

loopnoclk:

	ld a, (status); stopped ? 
	or a
	jp z, nostep

running:

;; use external clock?
	ld hl, useextclock
	ld a, (hl)
	or a
	jr z, advanceclock


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



nextstep:

    call steplatch

    ;; step pulse on the Centronics data lines, for the clock box
    ld hl, extclockout
    inc (hl)
    ld a, (hl)
    ld bc, CPC_PRINTER
    out (c), a


nextstep1:
;;  inc note pointer
	call nextnote
	ld de, NEXTNOTE_U
	call midiclkadd
	call showplaycursor
	ld de, CURSOR_U
	call midiclkadd
	call playnotes
	ld a,(noteevents)	; charge the notes that actually went out
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl		; * NOTEEVENT_U (256)
	ld de,PLAYNOTES_U
	add hl,de
	ex de,hl
	call midiclkadd

	ld a,0
	ld (delayc),a

	ld a,(track)
	or a
	jp z, nostep

tracking_enabled:

;; tracked - set screen cursor x to playcursor x

	ld a,(trackpos)
	bit 6,a
	jr nz,trackcury; >= 64 inc y

	res 6,a
	ld (cursorx),a
	ld (memcursorx),a

	ld a,(cursory)
	cp 10
	jr c, showtrackcur

	sub 7
	ld (cursory), a
	ld a,(memcursory)
	sub 6
	ld (memcursory),a

	jr showtrackcur

trackcury:

	res 6,a

	ld (cursorx),a
	ld (memcursorx),a

	ld a,(cursory)
	cp 10
	jr nc,showtrackcur

	add a,7
	ld (cursory),a
	ld a,(memcursory)
	add a,6
	ld (memcursory),a

showtrackcur:

	ld hl, blink
	ld (hl), 127

	call showcursor

;; cursor updates complete, now scan the keyboard

	jr scan


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


cur0:

	ld a,(blink)
	inc a
	ld (blink), a

	or a
	call z, curblink

	ld a,(blink)
	cp 127
	call z, curblink

scan:

	ld a, (status)
	or a
	jr nz, keyscan

;; not in play mode; tracker is stopped: 
;; here we only react to MIDI and keyboard input if stopped! 
;; else we react in "nextnote" 

        ld hl, midi_registered
	ld a, (hl)
	ld (hl), 0
	or a
	jp nz,setgridandsoundmidi

        ld hl, clear_registered
	ld a, (hl)
	ld (hl), 0
	or a
	jp nz,erasegrid

        ld hl, enter_registered
	ld a, (hl)
	ld (hl), 0
	or a
	jp nz,setgridandsoundkey

        ld hl, space_registered
	ld a, (hl)
	ld (hl), 0
	or a
	jp nz,setgridkey

keyscan:

	call kbdkey		; kbdraw already ran at the top of the pass
	or a
	jp z,loop

	cp 'Z'
	jp z,left
	cp 'Y'
	jp z,left
	cp 'A'
	jp z,prevbar
	cp 'C'
	jp z,right
	cp 'D'
	jp z,nextbar
	cp 'W'
	jp z,up
	cp 'X'
	jp z,down

	cp 44
	jp z,faster
	cp 46
	jp z,slower
	cp 'N'
	jp z,faster1
	cp 'M'
	jp z,slower1

	cp 'P'
	jp z,startstop

	cp 33
	jp z,startstopsong

	cp 35
	jp z,recordstatus

	cp 39
	jp z,extclockstatus

	cp 'R'
	jp z,midisyncstatus

	cp 'T'
	jp z,trackstatus

	cp KCURLEFT		; the arrows move the cursor on a CPC ...
	jp z,left

	cp KCURRIGHT
	jp z,right

	cp KDRUMDOWN		; ... and SHIFT with them is the drum number
	jp z,drumnodown

	cp KDRUMUP
	jp z,drumnoup

	cp 64
	jp z,drumnocurrent

	cp 43
	jp z,channelup

	cp 45
	jp z,channeldown

	cp 'U'
	jp z,instrumentdown

	cp 'I'
	jp z,instrumentup

	cp 'J'
	jp z,velocitydown

	cp 'K'
	jp z,velocityup

	cp KCURUP		; bar position is on A and D, so these are
	jp z,up			; free to be what they look like

	cp KCURDOWN
	jp z,down

	cp '1'
	jp z,bar1

	cp '2'
	jp z,bar2

	cp '3'
	jp z,bar3

	cp '4'
	jp z,bar4

	cp '5'
	jp z,bar5

	cp '6'
	jp z,bar6

	cp '7'
	jp z,bar7

	cp '8'
	jp z,bar8

	cp 'Q'
	jp z,quit

	cp 'H'
	jp z,help

	cp 'L'
	jp z,doload

	cp 'S'
	jp z,dosave

	cp 'G'
	jp z,chgridres

	cp 'B'
	jp z,chgnumbars

	cp '0'
	jp z,midiflushpanic

	cp 42
	jp z,chggatelength

	cp 47
	jp z,uppat

	cp 63
	jp z,downpat

	cp 61
	call z,clrpat

	cp 34
	jp z,copypat

	cp 38
	jp z,songpage

	jp loop

;;  do a screen update after keypress and continue 
cont:
	call screenupdate
	call showtrack
	call showtrackdrum
	call showtrackchannel
	call showtrackinstrument
	call showtrackvelocity
	call showgridres
	call showbars
	call showgate
	call showpat
	call showtempo

	jp loop


uppat:
	ld a,(curpat)
	cp 'Z'
	jp z,cont

	call putpat

	ld a,(curpat)
	inc a
	ld (curpat), a

	call getpat

	jp cont

downpat:
	ld a,(curpat)
	cp 'A'
	jp z,cont

	call putpat

	ld a,(curpat)
	dec a
	ld (curpat), a

	call getpat

	jp cont

getpatadr:
	ld a,(curpat)
getpatadr1:
	sub 'A'-1
	ld b, a
	ld de, pagelen
	ld hl, pages-pagelen
getpatadr2:
	add hl, de
	djnz getpatadr2

	ret

putpat:
	call getpatadr
	push hl
	pop de
	ld	hl,pagestart
	ld	bc,pagelen
	ldir
	ret

getpat:
	call getpatadr
	ld	de,pagestart
	ld	bc,pagelen
	ldir

	call screenupdate
	call showtrack
	call showtrackdrum
	call showtrackchannel
	call showtrackinstrument
	call showtrackvelocity
	call showgridres
	call showbars
	call showgate
	call showpat

	ret

getpat0:
	call getpatadr
	ld	de,pagestart
	ld	bc,pagelen
	ldir

	ret

initmem:

initmem1:
	ld hl, curpat

	call clrpat1
	call putpat

	ld hl, curpat
	ld a, (hl)
	inc a
	ld (hl), a
	cp 'Z'+1

	jr nz, initmem1

	ld hl, curpat
	ld (hl), 'A'

	ret

clrpat:

	ld hl, clearm
	call yesnoprompt
	ret nz

	ld	hl,data
	ld	de,tracks1
	ld	bc,6*64
	ldir

	ld	hl,data
	ld	de,tracksoff1
	ld	bc,6*64
	ldir

	ld	hl,data
	ld	de,tracks2
	ld	bc,6*64
	ldir

	ld	hl,data
	ld	de,tracksoff2
	ld	bc,6*64
	ldir

	call midipanicr
	call long_delay

	call setmiditrackinstruments
	call screenupdate


clrpat1:
	ld	hl,data
	ld	de,tracks1
	ld	bc,6*64
	ldir

	ld	hl,data
	ld	de,tracks2
	ld	bc,6*64
	ldir

	ret

copypat:
	call savestatus
	call putpat

	ld hl, curpat
	ld a, (hl)
	ld hl, topat
	ld (hl), a

copypat1:

	ld hl,#3c00+64+5
	ld (hl), 60
	inc hl
	ld (hl), 45
	inc hl
	ld de, topat
	ld a, (de)
	ld (hl), a
	inc hl
	ld (hl), 63

	ld hl,VRAM+64+5		; blocks in waitkey, so show it now
	ld bc,4
	call renderrun

	call waitkey
	cp ENTER
	jp z, copypat2

	ld hl, topat
	ld (hl), a

	jr copypat1

copypat2:

	call long_delay
	ld hl, topat
	ld a, (hl)
	cp 'A'
	jr c, copypat1
	cp 'Z'+1
	jr nc, copypat1

	ld b, a
	ld a, (curpat)
	cp b
	jr z, copycleanup

	ld a, (topat)
	call getpatadr1
	push hl
	pop de
	ld	hl,pagestart
	ld	bc,pagelen
	ldir

copycleanup:
	call restorestatus
	call long_delay
	call long_delay
	call long_delay

	jp main2

songpage:

;;  call stopallplayr
	call putpat

	call savestatus

	ld	hl,songdata
	ld	de,#3c00+64
	ld	bc,64
	ldir

	ld	hl,line
	ld	de,#3c00+128
	ld	bc,64
	ldir

	ld hl, songcur
	ld (hl), 0

keyscan2:

	call kbdraw
	call renderslice	; the song editor never passes through "loop:"
	call kbdkey

	or a
	jp z,noscansonged

scancont2:

	cp KCURLEFT
	jp z,songcurleft

	cp KCURRIGHT
	jp z,songcurright

	cp ENTER
	jr z,quitsongeditor

	cp 42; loop song 
	jr z, acceptmarker

	cp 46; empty 
	jr z, acceptmarker

	cp 'A'
	jr c, keyscan2
	cp 'Z'+1
	jr nc, keyscan2

	ld (curpat), a
	call getpat

	ld	hl,songdata
	ld	de,#3c00+64
	ld	bc,64
	ldir

acceptmarker:
	push af
	ld hl, #3c00+64
	ld a, (songcur)
	ld d, 0
	ld e, a
	add hl, de
	ld (hl), a

	pop af
	ld hl, songdata
	add hl, de
	ld (hl), a

	jp keyscan2

noscansonged:
	ld a,(blink)
	inc a
	ld (blink), a

	ld hl, #3c00+64
	ld a, (songcur)
	ld d, 0
	ld e, a
	add hl, de

	ld a,(blink)
	cp 127
	jr c,cur3
	ld (hl), POSMARKSYM

	jp keyscan2

cur3:
	push hl
	ld hl, songdata
	ld a, (songcur)
	ld d, 0
	ld e, a
	add hl, de
	ld a, (hl)
	pop hl
	ld (hl), a

	jp keyscan2


quitsongeditor:
	call restorestatus
	call long_delay
	call long_delay
	call long_delay
	jp cont

songcurleft:
	ld a, (songcur)
	or a
	jp z, keyscan2
	dec a
	ld (songcur), a

	ld	hl,songdata
	ld	de,#3c00+64
	ld	bc,64
	ldir

	jp keyscan2

songcurright:
	ld a, (songcur)
	cp 63
	jp nc, keyscan2
	inc a
	ld (songcur), a

	ld	hl,songdata
	ld	de,#3c00+64
	ld	bc,64
	ldir

	jp keyscan2

restorestatus:
	ld	de, #3c00+64
	ld 	hl, statusbuffer
	ld 	bc, 2*64
	ldir
	ret

savestatus:
	ld	hl, #3c00+64
	ld 	de, statusbuffer
	ld 	bc, 2*64
	ldir
	ret

chggatelength:
	call gettrackgate
	sla a
	and #1f
	jr nz,chggatelength1
	ld a,1

chggatelength1:
	ld (hl), a
	jp cont

chgridres:
	ld a,(gridres)
	sla a
	and #1f
	jr nz,chgridres1
	ld a,1

chgridres1:
	ld (gridres),a

	cp 1
	jr nz, gridres2
	ld a,%11111111
	ld (quantpat), a
	jp cont

gridres2:
	cp 2
	jr nz, gridres4
	ld a,%11111110
	ld (quantpat), a
	jp cont

gridres4:
	cp 4
	jr nz, gridres8
	ld a,%11111100
	ld (quantpat), a
	jp cont

gridres8:
	cp 8
	jr nz, gridres16
	ld a,%11111000
	ld (quantpat), a
	jp cont

gridres16:
	cp 16
	jr nz, gridres32
	ld a,%11110000
	ld (quantpat), a
	jp cont

gridres32:
	cp 32
	jp nz, cont
	ld a,%11100000
	ld (quantpat), a
	jp cont


chgnumbars:
	ld a,(numbars)
	cp 8
	jr nz, chgnumbars1
	ld a, 0
chgnumbars1:
	inc a
	ld (numbars),a

	ld b,a
	ld a,0

countticks:
	add a,16
	djnz countticks

	ld (numticks),a
	jp cont


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


midiflush:

	ret
	call midistat
	or a
	ret z

;;  byte available

	call midiin
	bit 7,a
	ret z

	jr midiflush

doload:
	call putpat

	ld hl, loadm
	call yesnoprompt
	jp nz, cont
	call loaddisk
	jp cont

dosave:
	call putpat

	ld hl, savem
	call yesnoprompt
	jp nz, cont
	call savedisk
	jp cont


quit:
    call putpat

    ld hl, quitm
    call yesnoprompt
    jp nz, cont

    ;; TRACKER is loaded over BASIC's program and variable area, so there
    ;; is nothing left to return to: reset back to a clean BASIC.
    ei
    jp 0


nextbar:
	ld a,(cursorx)
	ld hl,gridres
	ld b,(hl)
	add a,b
	cp 64
	jp nc, cont
	ld (cursorx),a
	ld hl,memcursorx
	ld (hl),a
	jp cont

prevbar:
	ld a,(cursorx)
	ld hl,gridres
	ld b,(hl)
	sub b
	jp c, cont
	ld (cursorx),a
	ld hl,memcursorx
	ld (hl),a
	jp cont

macro setbar1x
	ld (cursorx), a
	ld hl,memcursorx
	ld (hl),a

	ld a, (cursory)
	cp 9
	jp c,cont
; else change y cursor 
	sub 7
	ld (cursory),a

	ld a,(memcursory)
	sub 6
	ld (memcursory),a

	jp cont
mend


macro setbar2x
	ld (cursorx), a
	ld hl,memcursorx
	ld (hl),a

	ld a, (cursory)
	cp 10
	jp nc,cont
; else change y cursor 
	add a,7
	ld (cursory),a

	ld a,(memcursory)
	add a,6
	ld (memcursory),a

	jp cont
mend

bar1:

	ld a,(status)
	cp 1; pattern play mode?
	jr nz, bar1a

;; else, change the current pattern to A after current bar
	ld a, 'A'
	ld (nextpat), a
	jp cont

bar1a:

	ld a,0
	setbar1x

bar2:

	ld a,(status)
	cp 1; pattern play mode?
	jr nz, bar2a

;; else, change the current pattern to B after current bar
	ld a, 'B'
	ld (nextpat), a
	jp cont

bar2a:
	ld a,16
	setbar1x

bar3:
	ld a,(status)
	cp 1; pattern play mode?
	jr nz, bar3a

;; else, change the current pattern to B after current bar
	ld a, 'C'
	ld (nextpat), a
	jp cont

bar3a:
	ld a,32
	setbar1x

bar4:
	ld a,(status)
	cp 1; pattern play mode?
	jr nz, bar4a

;; else, change the current pattern to B after current bar
	ld a, 'C'
	ld (nextpat), a
	jp cont


bar4a:
	ld a,48
	setbar1x

bar5:
	ld a,(status)
	cp 1; pattern play mode?
	jr nz, bar5a

;; else, change the current pattern to B after current bar
	ld a, 'D'
	ld (nextpat), a
	jp cont


bar5a:
	ld a,0
	setbar2x

bar6:

	ld a,(status)
	cp 1; pattern play mode?
	jr nz, bar6a

;; else, change the current pattern to B after current bar
	ld a, 'E'
	ld (nextpat), a
	jp cont

bar6a:
	ld a,16
	setbar2x

bar7:
	ld a,(status)
	cp 1; pattern play mode?
	jr nz, bar7a

;; else, change the current pattern to B after current bar
	ld a, 'F'
	ld (nextpat), a
	jp cont

bar7a:
	ld a,32
	setbar2x

bar8:

	ld a,(status)
	cp 1; pattern play mode?
	jr nz, bar8a

;; else, change the current pattern to B after current bar
	ld a, 'G'
	ld (nextpat), a
	jp cont

bar8a:
	ld a,48
	setbar2x

faster:
	ld a,(tempo)
	cp 1
	jp z,cont

	dec a
	ld c,a
	ld (tempo),a
	ld a,0
	ld hl,delayc
	ld (hl),0
	call showtempo
	jp cont

faster1:
	ld a,(tempo)
	cp #11
	jp c,cont

	sub #10
	ld c,a
	ld (tempo),a
	ld a,0
	ld hl,delayc
	ld (hl),0
	call showtempo
	jp cont

slower:
	ld a,(tempo)
	cp 255
	jp z,cont

	inc a
	ld c,a
	ld (tempo),a
	ld a,0
	ld hl,delayc
	ld (hl),0

	call showtempo
	jp cont

slower1:
	ld a,(tempo)
	cp #f0
	jp nc,cont

	add a,#10
	ld c,a
	ld (tempo),a
	ld a,0
	ld hl,delayc
	ld (hl),0

	call showtempo
	jp cont

macro testsoundx

;; first, turn of previously played note
;; ONLY if in record mode!

	call gettrackchannel
	ld b, a

	ld a,(record)
	or a
	jr z, @playnoteon

;; turn off currently held note

	ld a, b
	add a,#80
	call midiout

	call short_delay
	ld a,(lastcurnote)
	call midiout

	call short_delay
	ld a,(lastcurvelocity)
	call midiout

	call short_delay
	call short_delay

@playnoteon:

	ld a, b
	add a,#90
	call midiout

	call short_delay
	ld a,(curnote)
	call midiout
	ld (lastcurnote), a

	call short_delay
	ld a,(curvelocity)
	call midiout
	ld (lastcurvelocity), a

mend

;; ---------------------------------------------------------------
;; Time weighted MIDI clock generator.
;;
;; Measurement showed a step is NOT a uniform run of loop passes:
;; ~55% is 41 short passes (~1646 T each) and ~45% is ONE contiguous
;; work block (wHL delay + short_delay MIDI pacing + nextnote). Spreading
;; clocks evenly across *passes* therefore bunched 5 clocks into 6.1 ms
;; gaps and stretched the 6th to 34.9 ms.
;;
;; So instead of counting passes we accumulate elapsed T-states, and
;; instrument the work block from the inside (short_delay accounts for
;; itself, and the step delay is sliced). A clock is due whenever
;;     acc*6 >= (length of the previous step)
;; which yields exactly 6 clocks per step regardless of how wrong the
;; individual cost constants are -- they only affect the spacing.
;;
;; Entry: de = T-states elapsed in the region that just executed.
;; Preserves all registers.
;; ---------------------------------------------------------------

midiclkadd:

	;; From "ret z; mode 0" on, this routine does real work on every one of
	;; the ~93 accounting points in a step, and that is real time. Charge it
	;; here, into DE, so that both the step clock and the MIDI clock see it
	;; and the tempo does not drop 8% the moment sync is switched on.
	ld a,(usemidisync)
	or a
	jr z,mcanocost
	cp 3
	jr z,mcanocost
	push hl
	ld hl,SYNCCALL_U
	add hl,de
	ex de,hl
	pop hl
mcanocost:

;; The elapsed time accounting now runs UNCONDITIONALLY: it is the
;; tempo time base, not just the MIDI clock's. A and DE are already
;; clobbered by short_delay, so only BC and HL need saving.
	push hl
	ld hl,(steptime); steptime += de
	add hl,de
	ld (steptime),hl
	pop hl

	ld a,(usemidisync)
	or a
	ret z; mode 0: off
	cp 3
	ret z; mode 3: MMC only, no timing clock
	ld a,(status)
	or a
	ret z; only clock while playing
	ld a,(midiclkbusy)
	or a
	ret nz; inside a message: do not interleave

	push bc
	push hl

	ld hl,(steptarget); the clock period is the INTENDED step
	ld a,h; length, so it no longer lags a step behind
	or l
	jr z,midiclkadd4
	ld b,h
	ld c,l

	ld h,d; hl = 6*de
	ld l,e
	add hl,hl; 2de
	ld d,h
	ld e,l
	add hl,hl; 4de
	add hl,de; 6de
	ex de,hl

	ld hl,(midiclkacc); acc += 6*de
	add hl,de

midiclkadd1:
	or a
	sbc hl,bc
	jr c,midiclkadd3; acc < period: nothing due

	ld a,MIDI_CLOCK
	call midiout; one bare OUT, no pacing needed
	jr midiclkadd1; more than one due? (very low tempo)

midiclkadd3:
	add hl,bc; undo the overshoot
	ld (midiclkacc),hl

midiclkadd4:
	pop hl
	pop bc
	ret

;; Latch the step length at each step boundary and start a new one.

steplatch:
	ld a,(usemidisync); charge the clock generator's own cost,
	or a; but only in the modes that run the clock
	jr z,steplatch0
	cp 3
	jr z,steplatch0
	ld hl,(steptime)
	ld de,SYNCCOST_U
	add hl,de
	ld (steptime),hl
steplatch0:
;; Carry the overshoot into the next step rather than zeroing, so
;; the average period stays exact despite the granularity of the
;; accounting points.
	ld hl,(steptime)
	ld (laststeptime),hl
	ld de,(steptarget)
	or a
	sbc hl,de
	jr nc,steplatch1
	ld hl,0; underflow guard
steplatch1:
	ld (steptime),hl
;; fall through: tempo is page specific, so recompute every step


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


sendrt:
	ld b,a
	ld a,(usemidisync)
	or a
	ret z; off
	cp 3
	ret z; MMC only: FA/FC are meaningless to a
; receiver that is getting no clock from us
	ld a,b
	call midiout
	ret

;; set/clear the guard so short_delay does not emit a clock mid message
midiclkupd:
	ld hl,WHLNORM
	ld a,(usemidisync)
	or a
	jr z,midiclkupd1; off
	cp 3
	jr z,midiclkupd1; MMC only: no clock overhead to compensate
	ld hl,WHLSYNC
midiclkupd1:
	ld (whlslicecur),hl
	ret

midibusyon:
	ld a,1
	ld (midiclkbusy),a
	ret
midibusyoff:
	xor a
	ld (midiclkbusy),a
	ret

;; ---------------------------------------------------------------
;; Send an MMC command in a as  F0 7F 7F 06 <cmd> F7.
;; Device id 7F is the all-call / broadcast id.
;; These are six back to back bytes, so they DO need short_delay
;; pacing -- but they only fire on transport changes, never per step.
;; ---------------------------------------------------------------

sendmmc:
	ld c,a; c = command, survives short_delay
	ld a,(usemidisync)
	cp 2; MMC goes out in mode 2 (both) and 3 (MMC)
	ret c
	call midibusyon

	ld a,#f0
	call midiout
	call short_delay
	ld a,#7f; universal real time sysex
	call midiout
	call short_delay
	ld a,#7f; device id: all call
	call midiout
	call short_delay
	ld a,#06; MMC command
	call midiout
	call short_delay
	ld a,c
	call midiout
	call short_delay
	ld a,#f7; end of sysex
	call midiout
	call short_delay
	call midibusyoff
	ret

;; Transport helpers -----------------------------------------------

midisyncstartr:
	ld a,(usemidisync)
	or a
	ret z
	ld hl,0; restart the clock phase cleanly
	ld (midiclkacc),hl
	ld (steptime),hl
	ld (laststeptime),hl
	ld a,MIDI_START
	call sendrt
	call short_delay
	ld a,MMC_PLAY
	call sendmmc
	ret

midisyncstopr:
	ld a,(usemidisync)
	or a
	ret z
	ld a,MIDI_STOP
	call sendrt
	call short_delay
	ld a,MMC_STOP
	call sendmmc
	ret

;; Toggle, bound to the R key -------------------------------------

;; R cycles through four modes rather than a plain on/off, because the
;; two things it sends are not equally harmless. MMC is ignored by gear
;; that does not speak it, but a timing clock is not: anything set to
;; external sync will start following this machine's tempo the moment
;; the clock appears. So "MMC only" is a real and useful setting when
;; something else is the timing master and you just want the P key to
;; roll the other device's transport.
;;
;;   0  ' '  off
;;   1  'C'  clock + FA/FC transport
;;   2  'B'  both: clock + FA/FC + MMC
;;   3  'M'  MMC transport only, no timing clock

midisyncstatus:
	ld a,(usemidisync)
	inc a
	and 3
	ld (usemidisync), a
	call midiclkupd

	ld a,(usemidisync)
	or a
	jr nz, showmidisyncstatus

;; leaving sync entirely: stop the downstream gear too
	ld a,MIDI_STOP
	call midiout

showmidisyncstatus:
	ld hl,midisyncchars
	ld a,(usemidisync)
	ld e,a
	ld d,0
	add hl,de
	ld a,(hl)
	ld hl,#3c00 + 64 + 10
	ld (hl), a

	jp cont

midisyncchars:	defb ' ','C','B','M'

midiflushpanic:

	call midipanicr
	call midiflush

	jp cont

midipanicr:

	ld b, #10

channeloffr:

	ld a, b
	dec a
	add a,#b0
	call midiout; MIDI CC for Channel in a 
	call short_delay

	ld a,123
	call midiout; MIDI NOTE OFF 
	call short_delay

	ld a,0
	call midiout; Don't Care 
	call short_delay

;;  repeat for all 16 Channels 
	djnz channeloffr

	ret

drumnocurrent:
	call gettrackdrum
	ld a, (curnote)
	and #7f
	ld (hl), a
	jp cont

drumnoup:
	call gettrackdrum
	inc a
	and #7f
	ld (hl), a
	jp cont

drumnodown:
	call gettrackdrum
	dec a
	and #7f
	ld (hl), a
	jp cont

channelup:
	call gettrackchannel
	inc a
	and #0f
	ld (hl), a

	call gettracknr
	dec a
	call setinstrument

	jp cont

channeldown:
	call gettrackchannel
	dec a
	and #0f
	ld (hl), a

	call gettracknr
	dec a
	call setinstrument

	jp cont

instrumentup:
	call gettrackinstrument
	inc a
	and #7f
	ld (hl), a

	call gettracknr
	dec a
	call setinstrument

	jp cont

instrumentdown:
	call gettrackinstrument
	dec a
	and #7f
	ld (hl), a

	call gettracknr
	dec a
	call setinstrument

	jp cont

velocityup:
	call gettrackvelocity
	inc a
	and #7f
	ld (hl), a

	call gettracknr
	dec a
	call setinstrument

	jp cont

velocitydown:
	call gettrackvelocity
	dec a
	and #7f
	ld (hl), a

	call gettracknr
	dec a
	call setinstrument

	jp cont

macro restorecellx
	ld a,(memcursorx)

	ld hl,data
	ld d,0
	ld e,a
	add hl,de
	ld a,(hl)
mend

macro setgridx
	call memcursor
; ld (hl),SETSYM
	ld a, (curnote)
	add a,DISPMIDINOTEOFFSET

	ld (hl), a
	ld hl,lastcur
; ld (hl),SETSYM
	ld (hl), a
mend

macro erasegridx
	call memcursor
	ld a, (hl)
;;  erase
	push hl
	restorecellx
	pop hl
	ld (hl),a
	ld hl,lastcur
	ld (hl),a
mend

macro gettrackdrumx
	call gettracknr
	dec a
	ld hl,drumnostracks
	ld d,0
	ld e,a
	add hl, de
	ld a,(hl)
mend

macro gettrackchannelx
	call gettracknr
	dec a
	ld hl,channeltracks
	ld d,0
	ld e,a
	add hl, de
	ld a,(hl)
mend

macro gettrackinstrumentx
	call gettracknr
	dec a
	ld hl,instrumenttracks
	ld d,0
	ld e,a
	add hl, de
	ld a,(hl)
mend

macro gettrackgatex
	call gettracknr
	dec a
	ld hl,gatetracks
	ld d,0
	ld e,a
	add hl, de
	ld a,(hl)
mend

macro gettrackvelocityx
	call gettracknr
	dec a
	ld hl,velocitytracks
	ld d,0
	ld e,a
	add hl, de
	ld a,(hl)
mend

setgridandsoundmidi:

	testsoundx
	setgridx

	jp cont

setgridandsoundkey:

	call gettrackdrum
	ld (curnote), a

	call gettrackvelocity
	ld (curvelocity), a

	testsoundx
	setgridx

	jp cont

setgridandsoundr:

	testsoundx
	setgridx

	ret

setgridandsoundkeyr:

	call gettrackdrum
	ld (curnote), a

	call gettrackvelocity
	ld (curvelocity), a

	testsoundx
	setgridx

	ret

setgrid:

	setgridx
	jp cont

setgridkey:

	call gettrackdrum
	ld (curnote), a

	call gettrackvelocity
	ld (curvelocity), a

	setgridx
	jp cont

setgridr:

	setgridx
	ret

setgridkeyr:

	call gettrackdrum
	ld (curnote), a

	call gettrackvelocity
	ld (curvelocity), a

	setgridx
	ret

erasegrid:

	erasegridx
	jp cont

erasegridr:

	erasegridx
	ret

stopallplayr:
	ld a, 0
	ld (status), a
	ret

startstop:
	ld a,(status)
	xor 1
	and 1
	ld (status), a
	or a
	jr nz, showplay

showstartstop:
	call midisyncstopr
	call midipanicr; stopping must silence whatever is still sounding
	ld hl,#3c00 + 64 + 6
	ld a,stoppeds
	ld (hl), a
	jp cont

showplay:

;; store current pattern in case user modified it before switching
	call putpat

	ld hl, qtrackpos
	ld (hl), 0

	ld hl,0
	ld (steptime),hl
	call settarget

	call midibusyon; no clocks during the reset pre-roll:
	call midipanicr; they would precede the FA start byte
	call long_delay

	call setmiditrackinstruments
	call long_delay
	call midibusyoff

	ld hl,#3c00 + 64 + 6
	ld a, playings
	ld (hl), a

	call midisyncstartr

	call playnotes
	call clearextclockr

	jp cont


startstopsong:
	ld a,(status)
	xor 2
	and 2
	ld (status), a
	or a
	jr nz, showplaysong
	jr showstartstop

getsongpat:

	ld hl, songdata; load song pattern at song index pos 
	ld a, (songpos)
	ld d, 0
	ld e, a
	add hl, de
	ld a, (hl); a has pattern

	cp 46; empty? stop
	jr z, stopsong

	cp 42; repeat?
	jr z, repeatsong

	cp 'A'
	ret c
	cp 'Z'+1
	ret nc

;; load next patter from song 
	ld hl, curpat
	ld (hl), a

	call getpat0

	ret

repeatsong:
	ld hl, songpos
	ld (hl), 0
	jr getsongpat

stopsong:

	ld hl, status
	ld (hl), 0
	call midisyncstopr
	call midipanicr; stopping must silence whatever is still sounding
	ld hl,#3c00 + 64 + 6
	ld a,stoppeds
	ld (hl), a

	ret

contsong:


showplaysong:

;; store current pattern in case user modified it before switching
	call putpat

	ld hl, songpos
	ld (hl), 0
	call getsongpat

	ld hl, qtrackpos
	ld (hl), 0

	ld hl,0
	ld (steptime),hl
	call settarget

	call midibusyon; no clocks during the reset pre-roll
	call midipanicr
	call long_delay

	call setmiditrackinstruments
	call long_delay

	call midibusyoff

	ld hl,#3c00 + 64 + 6
	ld a, songs
	ld (hl), a

	call midisyncstartr

	call playnotes
	call clearextclockr

	jp cont


recordstatus:
	ld a,(record)
	xor 1
	ld (record), a
	or a
	jr nz, showrecordstatus

	ld hl,#3c00 + 64 + 8
	ld a, playbacks
	ld (hl), a

	jp cont

showrecordstatus:
	ld hl,#3c00 + 64 + 8
	ld a, records
	ld (hl), a

	jp cont


extclockstatus:
	ld a,(useextclock)
	xor 1
	ld (useextclock), a
	or a
	jr nz, showextclockstatus

	ld hl,#3c00 + 64 + 9
	ld a, 124
	ld (hl), a

	jp cont

showextclockstatus:
	ld hl,#3c00 + 64 + 9
	ld a, extclocks
	ld (hl), a

	jp cont


trackstatus:
	ld a,(track)
	xor 1
	ld (track), a
	or a
	jr nz, showtrackstatus

	ld hl,#3c00 + 64 + 7
	ld a, frees
	ld (hl), a

	jp cont

showtrackstatus:
	ld hl,#3c00 + 64 + 7
	ld a, trackeds
	ld (hl), a

	jp cont


left:
	ld a,(cursorx)
	or a
	jp z, cont
	dec a
	ld (cursorx),a
	ld hl,memcursorx
	ld (hl),a
	jp cont
right:
	ld a,(cursorx)
	cp 63
	jp z, cont
	inc a
	ld (cursorx),a
	ld hl,memcursorx
	ld (hl),a
	jp cont
up:
	ld a,(cursory)
	cp 3
	jp z, cont
	cp 10
	jr nz,up1
	ld a,8
	jr up2
up1:
	dec a

up2:
	ld (cursory),a

	ld hl,memcursory
	ld a,(hl)
	dec a
	ld (hl),a

;; call setinstrument

	jp cont

down:
	ld a,(cursory)
	cp 15
	jp z, cont
	cp 8
	jr nz,down1
	ld a,10
	jr down2
down1:
	inc a
down2:
	ld (cursory),a

	ld hl,memcursory
	ld a,(hl)
	inc a
	ld (hl),a

;; call setinstrument

	jp cont


cursor:
;;ld a,(blink)
;;inc a
;;ld (blink),a
	ld hl,#3c00
	ld a,(cursorx)
	or a
	jr z, moveyup
	ld b,a
movex:
	inc hl
	djnz movex
moveyup:
	ld a,(cursory)
	or a
	ret z
	ld b,a
	ld de,64
movey:
	add hl,de
	djnz movey
	ret

memcursor:
	ld hl,tracks1
	ld a,(memcursorx)
	or a
	jr z, mmoveyup
	ld b,a
mmovex:
	inc hl
	djnz mmovex
mmoveyup:
	ld a,(memcursory)
	or a
	ret z
	ld b,a
	ld de,64
mmovey:
	add hl,de
	djnz mmovey
	ret




clearextclockr:

    xor a
    ld (extclktick), a
    ld a,MIDICLKPERSTEP
    ld (extclkdiv), a
    ret


nextnote:

	ld a,(qtrackpos)
	inc a
	ld b,a

	ld a,(numticks)
	cp b
	ld a,b

	jr nz,nextnotew

;; page end - 
;; check if song mode?

	ld a, (status)
	cp 2

	jr nz, nosongmode

;;  in song mode, load next patter from song

;; store current pattern in case user modified it before switching

	ld a, (record)
	or a

	call nz, putpat; only store if recording active (optimization to prevent lag during playback)

	ld hl, songpos
	inc (hl)
	call getsongpat

	call screenupdate
	call showpat
	call showtempo
	call showgridres
	call showbars

;;call showtrack
;;call showtrackdrum
;;call showtrackchannel
;;call showtrackinstrument
;;call showtrackvelocity 
;;call showgridres
;;call showbars
;;call showgate

nosongmode:

;; max tick number reached, set to 0

	ld a, 0
	jr nextnote0

nextnotew:

;; no song-based page switch, check for requested page switch
	ld b, a
	ld a, (nextpat)
	or a
	ld a, b
	jr z, nextnotecontpat; no requested pattern switch

;; else, switch to requested pattern at end of current bar

	ld a, (qtrackpos)
	inc a
	and %00001111
	or a
	jr nz, nextnotecontpat

;; else, switch in requested next pattern

	ld hl, curpat
	ld a, (nextpat)
	ld (hl), a
	call getpat0
	call screenupdate
	call showpat
	call showtempo
	call showgridres
	call showbars

	ld a, 0
	ld (nextpat), a

	jr nextnote0


nextnotecontpat:

;; next note, no page switch
	ld a, (qtrackpos)
	inc a

	push af
	ld b,WHLSLICES; slices of the per step calibrated delay
nextnotewait:
	push bc
	ld hl,(whlslicecur)
	call wHL
	ld de, WHLSLICE_U
	call midiclkadd
	pop bc
	djnz nextnotewait
	pop af

nextnote0:

;; update cursors, quantize tracking cursor

	ld (qtrackpos),a

	ld b, a
	ld a, (quantpat)
	and b
	ld (trackpos),a


nextnote_continue:

	ld a, (qtrackpos)
	ld b, a
	ld a, (trackpos)

	cp b
	jr nz, nextnote2

	ld a, (record); don't sample if not in record mode 
	or a
	jr z, nextnote2

;; check registered keypresses and
;; take action when (qtrackpos) = (trackpos) 


nextnote_check_registered:

        ld hl, clear_registered
	ld a, (hl)
	ld (hl), 0
	or a
	call nz,erasegridr

        ld hl, enter_registered
	ld a, (hl)
	ld (hl), 0
	or a
	call nz,setgridandsoundkeyr

        ld hl, space_registered
	ld a, (hl)
	ld (hl), 0
	or a
	call nz,setgridkeyr

        ld hl, midi_registered
	ld a, (hl)
	ld (hl), 0
	or a
	call nz,setgridandsoundr


nextnote2:

	ret


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


screenupdate:

;;  swap in track 1 
	ld	hl,tracks1
	ld	de,#3c00+3*64
	ld	bc,6*64
	ldir

;;  swap in track 1 
	ld	hl,tracks2
	ld	de,#3c00+10*64
	ld	bc,6*64
	ldir

	ret


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


byte2ascii:; input c, output de ASCII 
   ld a, c
   rra
   rra
   rra
   rra
   call convnibble
   ld d, a
   ld  a,c
convnibble:
   and  #0F
   add a,#90
   daa
   adc a,#40
   daa
   ld e, a
   ret

;; ---------------------------------------------------------------
;; Real BPM readout.
;;
;; Now that tempo names an actual period this is a genuine tempo and
;; not an opaque delay count. A step is a 16th note, so a quarter is
;; four steps and
;;      BPM = 60 * F / (4 * period * TSCALE)
;;
;; The period here is NOT steptarget. steptarget is the intended step, and
;; the accumulator that chases it over-counts idle loop passes, so the real
;; step falls short of it by a margin that grows with tempo. bpmdiv holds
;; the measured period instead -- see the BPMBASE block at the top -- which
;; makes the readout honest to within 0.3% on both machines:
;;          BPM = 1900800 / bpmdiv    (Model III / 4 at 2.02752 MHz)
;;          BPM = 1646800 / bpmdiv    (Model I, incl. its ~1% longer step)
;;
;; The MIDI clock divisor in midiclkadd deliberately still uses steptarget:
;; the step boundary and the clock both run off the same biased time base,
;; so the bias cancels and exactly 6 clocks land per step whatever the
;; calibration says. That one must not be "fixed".
;;
;; Recomputed only when tempo actually changes, so the 32/16 division
;; never lands in the playback path.
;; ---------------------------------------------------------------

showtempo:
	call calcbpm
	ld hl,#3c00+64+23
	ld de,bpmdigits
	ld b,3
showtempo1:
	ld a,(de)
	ld (hl),a
	inc hl
	inc de
	djnz showtempo1
	ret


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

calcbpm0:

	ld hl,0; remainder
	ld b,32
calcbpm2:
	or a; shift dvnd left, carry out of the top
	ld a,(dvnd)
	rla
	ld (dvnd),a
	ld a,(dvnd+1)
	rla
	ld (dvnd+1),a
	ld a,(dvnd+2)
	rla
	ld (dvnd+2),a
	ld a,(dvnd+3)
	rla
	ld (dvnd+3),a

	adc hl,hl; bring that bit into the remainder
	ld de,(bpmdiv)
	or a
	sbc hl,de
	jr nc,calcbpm3
	add hl,de; did not fit: restore
	jr calcbpm4
calcbpm3:
	ld a,(dvnd); it fit: set the quotient bit
	or 1
	ld (dvnd),a
calcbpm4:
	djnz calcbpm2

	ld hl,(dvnd); quotient -> three ASCII digits
	ld de,bpmdigits
	ld bc,-100
	call bpmdigit
	ld bc,-10
	call bpmdigit
	ld a,l
	add a,'0'
	ld (de),a

	ld a,(bpmdigits); blank a leading zero
	cp '0'
	ret nz
	ld a,' '
	ld (bpmdigits),a
	ret

bpmdigit:
	ld a,'0'-1
bpmdigit1:
	inc a
	add hl,bc
	jr c,bpmdigit1
	sbc hl,bc; one too far: add it back
	ld (de),a
	inc de
	ret


;; BPM = 60e6 / (4 steps * steptarget * USCALE) = 3750000 / steptarget
bpmk:   defb #70,#38,#39,#00    ; 3750000, little endian


gettracknr:
	ld a,(memcursory)
	add a,1
	cp 7
	ret c
	sub 6
	ret



gettrackdrum:
	gettrackdrumx
	ret

gettrackchannel:
	gettrackchannelx
	ret

gettrackinstrument:
	gettrackinstrumentx
	ret

gettrackgate:
	gettrackgatex
	ret

gettrackvelocity:
	gettrackvelocityx
	ret

gettrackdrumreg:; input: e register, starting at 0
	ld hl,drumnostracks
	ld d,0
	add hl, de
	ld b,(hl)
	ret

gettrackchannelreg:; input: e register, starting at 0
	ld hl,channeltracks
	ld d,0
	add hl, de
	ld b,(hl)
	ret

showtrackdrum:
	call gettrackdrum
	ld c, a
	ld hl,#3c00+64+52
	call byte2ascii
	ld (hl),d
	inc hl
	ld (hl),e
	ret

showtrackchannel:
	call gettrackchannel
	ld c, a
	ld hl,#3c00+64+43
	call convnibble
	ld (hl),e
	ret

showtrackinstrument:
	call gettrackinstrument
	ld c, a
	ld hl,#3c00+64+47
	call byte2ascii
	ld (hl),d
	inc hl
	ld (hl),e
	ret

showtrackvelocity:
	call gettrackvelocity
	ld c, a
	ld hl,#3c00+64+57
	call byte2ascii
	ld (hl),d
	inc hl
	ld (hl),e
	ret

showtrack:
	call gettracknr
	ld c,a
	ld hl,#3c00+64+17
	call convnibble
	ld (hl),e
	ret

setinstrument:; a has track number 

	push af
	ld ix,channeltracks; retrieve MIDI channel for track a
	ld c,a
	ld b,0
	add ix,bc
	ld a,(ix+0); MIDI channel for track a is now in a 

	ld b,#c0; add $c0 for change instrument for MIDI channel in a 
	add a,b
	call midiout; change instrument for channel in a 
	call short_delay

	pop af
	ld ix,instrumenttracks; retrieve instrument for track a 
	ld c,a
	ld b,0
	add ix,bc
	ld a,(ix+0); MIDI instrument for track a is now in a 

	call midiout; change MIDI instrument to a 
	call short_delay

	ret

setmiditrackinstruments:

	ld a, 5
	call setinstrument

	ld a, 4
	call setinstrument

	ld a, 3
	call setinstrument

	ld a, 2
	call setinstrument

	ld a, 1
	call setinstrument

	ld a, 0
	call setinstrument

	ret

playnotes:
	xor a
	ld (noteevents),a
	ld a,(qtrackpos)

	bit 6,a
	jr nz,playhightracks; >= 64  

playlowtracks:

	ld hl,tracksoff1
	call stoptracks

	ld a,(qtrackpos)
	ld hl,tracks1

	ld ix,tracksoff1
	ld iy,tracksoff2

	call playtracks

	ret

playhightracks:

	ld hl,tracksoff2
	call stoptracks

	ld a,(qtrackpos)
	ld hl,tracks2

	ld ix,tracksoff1
	ld iy,tracksoff2

	call playtracks

	ret


stoptracks:
; add track index
; clear bit 6
	res 6,a
	ld e,a
	ld d,0
	add hl,de
	ld bc,64

	push hl
	push bc

	ld c,(hl); -> c is note off
	ld d,0
	ld e,0; e is track number 
	call stopnote

	pop bc
	pop hl

	add hl,bc

	push hl
	push bc

	ld c,(hl)
	ld d,0
	ld e,1
	call stopnote

	pop bc
	pop hl

	add hl,bc

	push hl
	push bc

	ld c,(hl)
	ld d,0
	ld e,2
	call stopnote

	pop bc
	pop hl

	add hl,bc

	push hl
	push bc

	ld c,(hl)
	ld d,0
	ld e,3
	call stopnote

	pop bc
	pop hl

	add hl,bc

	push hl
	push bc

	ld c,(hl)
	ld d,0
	ld e,4
	call stopnote

	pop bc
	pop hl

	add hl,bc

	push hl
	push bc

	ld c,(hl)
	ld d,0
	ld e,5
	call stopnote

	pop bc
	pop hl

	ret

playtracks:

	push hl
	push ix
	push iy

	ld d,0
	ld e,0; e is track number 
	call playnote

	pop iy
	pop ix
	pop hl

	ld bc,64
	add hl,bc
	add ix,bc
	add iy,bc

	push hl
	push ix
	push iy

	ld d,0
	ld e,1
	call playnote

	pop iy
	pop ix
	pop hl

	ld bc,64
	add hl,bc
	add ix,bc
	add iy,bc

	push hl
	push ix
	push iy

	ld d,0
	ld e,2
	call playnote

	pop iy
	pop ix
	pop hl

	ld bc,64
	add hl,bc
	add ix,bc
	add iy,bc

	push hl
	push ix
	push iy

	ld d,0
	ld e,3
	call playnote

	pop iy
	pop ix
	pop hl

	ld bc,64
	add hl,bc
	add ix,bc
	add iy,bc

	push hl
	push ix
	push iy

	ld d,0
	ld e,4
	call playnote

	pop iy
	pop ix
	pop hl

	ld bc,64
	add hl,bc
	add ix,bc
	add iy,bc

	push hl
	push ix
	push iy

	ld d,0
	ld e,5
	call playnote

	pop iy
	pop ix
	pop hl

	ret


playnote:; input note on in c; track number 0..5 in e; hl track start, ix note of track start 

	ld a, (qtrackpos); add note index offset
	res 6, a; reset high tracks bit 

	ld b, a; save note index to b 

	push de; save track number in e 
	ld d, 0; compute note pointer 
	ld e, a
	add hl, de
	pop de

        ld a, (hl); get note; note on, <> 0? no -> return 
	cp DISPMIDINOTEOFFSET+1
	jr nc, playnote1

;; else, waste some time!

	call short_delay
	call short_delay

	ret

playnote1:

	push hl			; one more MIDI note event this step
	ld hl,noteevents
	inc (hl)
	pop hl

; note index in b, note to play in a,
; e track number, hl note pointer,
; ix start of note off low  tracks
; iy start of note off high tracks

	push	af; save note in a	

	ld hl,channeltracks; determine MIDI channel for track in e 
	add hl, de
	ld a,(hl); MIDI channel for track  

	add a,#90; MIDI NOTE ON for MIDI channel in a 
	call midiout

	push de; protect track number in e 
	call short_delay
	pop de

	pop af; output note number
	push af
	sub DISPMIDINOTEOFFSET
	call midiout

	push de; protect track number in e 
	call short_delay
	pop de

	ld hl,velocitytracks; determine MIDI velocity for track in e  
	add hl, de
	ld a,(hl); MIDI velocity for track in e 
	call midiout

;; compute and set note off in noteoff tracks 

	ld hl,gatetracks
	add hl, de; gate duration index 
	ld c, (hl); gate duration for track 	

	ld a, (qtrackpos); load note index, with bit 6 set if >= 64
	add a,c; add gate duration 

	ld hl, numticks
	ld c, (hl)
	cp c; a > numticks? wrap around! use iy as basis 
	jr c, nowrap

; else, we need to wrap around, sub 64; c has note position + gate duration offset
; a has numticks 

	sub c

nowrap:; a has note position + gate duration offset, wrapped around - check if high or low tracks 

	bit 6,a
	jr nz, storenoteoffhigh; >= 64, high off tracks

	bit 7,a
	jr nz, storenoteoffhigh2; >= 128, low off tracks

storenoteofflow:

	push ix; low off tracks 
	pop hl

	jr storenoteoff

storenoteoffhigh:

	res 6,a; -> low tracks 

	push iy; high off tracks 
	pop hl

	jr storenoteoff

storenoteoffhigh2:

	res 7,a; -> low tracks (wrap around at end track 6, > 127!) 

	push ix; low off tracks 
	pop hl

	jr storenoteoff

storenoteoff:

	ld d, 0
	ld e, a
	add hl, de; hl has high or low note pos in off tracks 

	pop af; restore note to play / turn off
	ld (hl), a; store note in note off grid

	ret


stopnote:; input note off in c; track number 0..5 in e 

        ld a, c; note on <> 0? no; return
	or a
	jr nz, stopnote1

;; else, waste some time!

	call short_delay
	call short_delay

	ret

stopnote1:

	push hl			; one more MIDI note event this step
	ld hl,noteevents
	inc (hl)
	pop hl

	ld (hl), 0; hl = note pointer; erase note for now, will be rescheduled when played again!	

	push bc

	ld hl,channeltracks; determine MIDI channel for track in e 
;; ld d,0
;; ld e,e 
	add hl, de
	ld a,(hl); MIDI channel for track in e

	add a,#80; MIDI NOTE OFF for MIDI channel in a 
	call midiout

	push de
	call short_delay
	pop de

	ld a,c; c has the note number -> MIDI out 
	sub DISPMIDINOTEOFFSET
	call midiout

	push de
	call short_delay
	pop de

	pop bc

	ld hl,velocitytracks; determine MIDI velocity for track in e  
;; ld d,0
;; ld e,e 
	add hl, de
	ld a,(hl); MIDI velocity for track in e 
	call midiout

cost1   equ     t($)-t(stopnote1)

	ret

showgridres:
	ld a,(gridres)
	ld c, a
	ld hl,#3c00+64+36
	call byte2ascii
	ld (hl),d
	inc hl
	ld (hl),e
	ret

showpat:
	ld a,(curpat)
	ld hl,#3c00+64+4
	ld (hl),a
	ret


showgate:
	call gettrackgate
	ld c, a
	ld hl,#3c00+64+62
	call byte2ascii
	ld (hl),d
	inc hl
	ld (hl),e
	ret

showbars:
	ld a,(numbars)
	ld c, a
	ld hl,#3c00+64+32
	call convnibble
	ld (hl),e
	ret


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

datastart

startmarker 	defb 'START-OF-FILE-MARKER'

statusbuffer		defs	2*64

instrumenttracks 	defb 1, 2, 3, 4, 5, 1

lastcur	     defb	'.'
lastcurpos   defw 	#3c00+3*64

memcursorx defb 	0
memcursory defb 	0

cursorx	defb 	0
cursory	defb 	3
blink   defb    0
status  defb    0
track	defb    0
record  defb    0

trackpos   defb  0
qtrackpos  defb  0

useextclock   defb	 0

midicount         defb  0
curnote           defb  0
curvelocity       defb  0
lastcurnote       defb  0
lastcurvelocity   defb  0

extclockout      defb	 0
lastextclockin1  defb	 0
lastextclockin2  defb	 0


clear_registered defb 0
space_registered defb 0
enter_registered defb 0
midi_registered  defb 0

tracksoff1 	defs    6*64
tracksoff2 	defs    6*64

; there is some bug in the code from tracksoff that messes with the songdata! double check at some point... for now, put a hack in here to protect song data:

buffer 	defs    64

songdata	defb	'A...............................................................'
songcur		defb 	0
songpos		defb 	0

curpat		defb   'A'
topat		defb   'A'
nextpat		defb	 0

;; page-specific variables


pagestart

delayc 	defb	0
tempo   defb	#2a
numbars defb	8
numticks defb	8*16
gridres defb  	4
quantpat   defb  %11111100

drumnostracks		defb 36, 38, 40, 51, 44, 46
channeltracks 		defb 0, 1, 2, 3, 4, 9
;; these will be global; too much overhead to change instruments with each page
;; instrumenttracks 	byte 1, 2, 3, 4, 5, 1 
velocitytracks	 	defb 127, 127, 127, 127, 127, 127
gatetracks	 	defb 8,8,8,8,8,8

tracks1 	defs    6*64
tracks2 	defs    6*64

pagelen 	equ $-pagestart

pages		defs 26*pagelen; pages A-Z

endmarker 	defb 'END-OF-FILE-MARKER'

dataend 	equ $
datalength 	equ $-datastart



;; The data segment is byte for byte the TRS-80's, so a DUMP written on
;; one machine loads on the other.
    assert datalength == 22645

    save "TRACKER.BIN", #0800, dataend-#0800, AMSDOS, main
