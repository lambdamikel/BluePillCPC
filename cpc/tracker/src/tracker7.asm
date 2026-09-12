;; TRACKER Version 2.10
;; to do:
;; - mute tracks
;; - record NOTE OFF messages, too? (new mode with GATE = *)

	org $5400

DISPMIDINOTEOFFSET equ $61 ; 0 -> 'a' 

POSMARKSYM equ	$aa
SETSYM 	equ	$8f
CURSYM 	equ	'X'

;; Consecutive empty scans required before the same key may be reported
;; again. The direct scan runs about once a millisecond, fast enough to see
;; a bouncing contact re-close and report one press several times, which
;; makes command keys feel hair triggered. ~20 ms of quiet settles it and is
;; far below anything a player can type. Set to 1 to disable.
KBDSETTLE equ	24

;; ---- BPM readout ---------------------------------------------------
;; The BPM display must NOT be derived from steptarget. steptarget is what
;; advanceclock compares the step accumulator against, and the accumulator
;; over-counts idle main loop passes, so the real step is shorter than the
;; target by an amount that grows with tempo -- the readout used to be
;; honest around tempo 40 and ~10% slow at tempo 200.
;;
;; Measured in trs80gp by tracing the port 8 writes of a reference voice at
;; tempo 40/80/120/160/200, and confirmed on real hardware (32 bars of a
;; 140 BPM song timed at 55.0 s against 54.94 s predicted), the true step
;; period is linear in tempo. In the 16 T units used here:
;;
;;   step = BPMBASE + 97 * tempo      to within 0.3% over the whole range
;;
;; The Model I runs about 1% slower per step in T-states than the Model III
;; -- same code, slightly different per model branches -- which is absorbed
;; into bpmk1 rather than needing a second slope.
BPMBASE	  equ	3893
ENTER	equ	$0d ; @DSPLY with newline

KCURLEFT	equ 8
KCURRIGHT	equ 9
KCURUP		equ 91
KCURDOWN	equ 10

@DSPLY		equ	$4467
@EXIT		equ	$402d
@KBD    	equ 	$002b 
@KEY    	equ 	$0049 
@DSP    	equ 	$0033

M3_PRINTER_IO	equ	0xf8
M1_PRINTER_RAM	equ	0x37E8

;; ---- MIDI clock / MMC output ----------------------------------------
;; MIDI beat clock is 24 ppqn. One TRACKER step is a 16th note
;; (numticks = numbars*16), so a quarter note is 4 steps and
;; 24/4 = 6 MIDI clocks are due per step.
MIDICLKPERSTEP	equ	6
;; Measured T-state costs used to weight elapsed time (model independent:
;; T-states are T-states). Only the *evenness* depends on these being
;; right -- the clock COUNT is self-normalising at exactly 6 per step,
;; because the period is the previous step's own accumulated total.
;; Time is accumulated in units of TSCALE T-states. A whole step is
;; ~106700 T, which would overflow the 16 bit accumulator; dividing by
;; 16 keeps both steptime (~6670) and acc (~40000) comfortably in range.
;; ---- timing calibration -------------------------------------------
;; Time is accumulated in units of TSCALE T-states; a whole step is
;; ~107000 T, which would overflow the 16 bit accumulator undivided.
TSCALE		equ	16
CALLCOST	equ	250		; cost of one instrumented midiclkadd call
PASS_T		equ	1646		; one main loop pass (measured)
SHORTDLY_T	equ	768		; short_delay busy wait
;; Instrumenting every pass and every short_delay cost 73 calls per step
;; and slowed playback 18%. Throttle to roughly 35 calls instead.
PASSDIV		equ	2		; call midiclkadd every PASSDIV passes
SHORTDIV	equ	4		; ... and every SHORTDIV short_delays
WHLTOTAL	equ	16800		; the original per step calibrated delay
WHLSLICES	equ	4		; slices it is broken into
;; The remaining instrumentation cost is given back by shortening that
;; delay while sync is on, so the tempo is the same either way.
SYNCOVERHEAD	equ	9000
;; Step boundary work that is neither wHL nor short_delay: nextnote
;; bookkeeping, cursor redraw, playnotes dispatch. Lumping it into three
;; calls made the clock jump, so most is charged across the slices.
BOUNDARY_T	equ	17000

;; ---- time based tempo ---------------------------------------------
;; Until now "tempo" counted main loop passes, so the step period was
;; whatever the work happened to cost: it changed with note density,
;; with screen activity, and it moved every time the loop got faster.
;; Now tempo names an actual period, in TSCALE (16 T) units:
;;     steptarget = TEMPOBASE + tempo * 112
;; tempo $2A gives 8050 units = 128800 T = 63.5 ms on a Model III,
;; i.e. about where stock 1.98 sat, and the range spans roughly
;; 60 BPM (tempo $FF) to 550 BPM (tempo $01) counted in 16ths.
TEMPOBASE	equ	3346

WHLNORM		equ	WHLTOTAL/WHLSLICES
WHLSYNC		equ	(WHLTOTAL-SYNCOVERHEAD)/WHLSLICES

;; Credits below are MEASURED, by profiling one step by label in
;; trs80gp's bus trace (Model III, empty pattern, total 135559 T):
;;   keyscan 55836 | short_delay 19416 | showplaycursor 15930
;;   midiclkadd 11177 | wHL 7600 | rest ~5600
;; Each credit covers its region plus that region's share of the
;; instrumentation cost, so the bookkeeping tracks the wall clock.
;; Recalibrated after replacing @KBD: a loop pass no longer carries a
;; 1330 T ROM call, so PASS_U comes down sharply while short_delay --
;; now the single biggest cost at 22.6% -- goes up.
;; Scaled by 0.948: with sync off the step measured 60.25 ms against a
;; 63.53 ms target, i.e. the accounting was running 5% ahead of the wall
;; clock, so every credit comes down proportionally.
PASS_U		equ	137		; PASSDIV main loop passes
SHORTDLY_U	equ	219		; SHORTDIV short_delays
;; Recalibrated with video wait states OFF: showplaycursor dropped from
;; 16259 T to 2818 T, so wHL and nextnote are no longer compensating for
;; an under-credited cursor redraw and must come back down to their real
;; cost, or the clock fires too early right after the step boundary.
WHLSLICE_U	equ	138		; one slice + its share of nextnote
NEXTNOTE_U	equ	82		; nextnote bookkeeping (~1100 T)
CURSOR_U	equ	184		; showplaycursor redraw (~2818 T)
PLAYNOTES_U	equ	77		; playnotes / stoptracks dispatch
;; Emitting clocks costs real time that the per-call credits do not
;; see (the crossing test, the OUTs). Charge it once per step so the
;; period lands on target whether sync is on or off.
SYNCCOST_U	equ	345

MIDI_CLOCK	equ	$f8		; timing clock
MIDI_START	equ	$fa		; start from top
MIDI_CONTINUE	equ	$fb		; resume from current position
MIDI_STOP	equ	$fc		; stop
MIDI_SPP	equ	$f2		; song position pointer
;; MMC: F0 7F <dev> 06 <cmd> F7
MMC_STOP	equ	$01
MMC_PLAY	equ	$02
MMC_RECSTROBE	equ	$06
MMC_PAUSE	equ	$09
midisyncs:	equ	'M'		; status char when sync out is on

;; Model I/III addresses
@fspec  equ 441ch
@init   equ 4420h
@open   equ 4424h
@close  equ 4428h
@read   equ 4436h
@write  equ 4439h
@error  equ 4409h
@abort  equ 4030h       

stoppeds:  equ  'H'
playings:  equ  'P'
songs: 	   equ  'S'
records:   equ  '*'
playbacks: equ  ' '
extclocks: equ  "'"
	
frees: 	  equ   'F'
trackeds: equ   'T'

dcb:		defs 48			; 48 for Model III TRSDOS 1.3   
iobuf:		defs 256
lrlerr:		equ 42
filename:	ascii  "dump", 0


ernldos:	db 1


errorm:	ascii   '***** DISK ERROR! DISK FULL / PROTECTED / NO DUMP? ANY KEY *****'

line: 	ascii	'SONG EDITOR:  USE LEFT/RIGHT, ENTER, A-Z=PATTERN, .=STOP, *=LOOP'

quitm:  ascii	'***** QUIT TRACKER - REALLY QUIT? SAVED YOUR WORK? Y/N: _  *****'

clearm: ascii	'***** CLEAR PATTERN - ARE YOU SURE? REALLY CLEAR? Y/N: _   *****'

savem:  ascii	'**** SAVE STATE - OVERWRITE EXISTING CORE DUMP FILE? Y/N: _ ****'

loadm:  ascii	'***** LOAD STATE - LOAD CORE DUMP FILE INTO MEMORY? Y/N: _ *****'

waitt:	ascii   '***** MIDI/80 TRACKER V2.10 - (C)2026 LAMBDAMIKEL + CLAUDE *****'
	ascii   'PAT:A SF | TRACK:1 BPM:---  | B:8 S:04 | C:0 I:01 N:24 V:7F G:04'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	ascii	'WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT WAIT'
	
title:	ascii   '***** MIDI/80 TRACKER V2.10 - (C)2026 LAMBDAMIKEL + CLAUDE *****'
	ascii   'PAT:A SF | TRACK:1 BPM:---  | B:8 S:04 | C:0 I:01 N:24 V:7F G:04'
	ascii	'1===-===+===-===2===-===+===-===3===-===+===-===4===-===+===-===' 
data:	ascii   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	ascii   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	ascii   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	ascii   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	ascii   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	ascii   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	ascii	'5===-===+===-===6===-===+===-===7===-===+===-===8===-===+===-===' 
	ascii   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	ascii   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	ascii   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	ascii   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	ascii   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'
	ascii   '!...-...+...-...!...-...+...-...!...-...+...-...!...-...+...-...'

helpt:	ascii   '************************** HELP PAGE ***************************'
	ascii   'CURSOR MOVEMENT, FINE CONTROL        : A D W X, Z C             '
	ascii   'CHANGE BAR COUNT, JUMP TO BAR POS    : B, 1 2 3 4 5 6 7 8       '
	ascii   'NEXT / PREV GRID POS, CHANGE GRID    : ARROW-UP ARROW-DOWN, G   '
	ascii   'SET GRID, SOUND, CLEAR               : SPACE, ENTER, CLEAR      '
	ascii   "PAT/SONG PLAY, EXTCLK, MIDISYNC C/B/M: P !, ', R                "
	ascii   'ALL NOTES OFF (MIDI PANIC)           : 0                        '
	ascii   'TOGGLE RECORD, TOGGLE TRACKING       : #, T                     ' 
	ascii   'PAT +/-, PAT CLEAR, COPY, SONG EDITOR: / ?, =, ", &             '
	ascii   'HELP, QUIT, LOAD & SAVE              : H Q L S                  '
	ascii   'GLOBAL CHANGE CUR TRACK MIDI INSTR.  : U I                      '
	ascii   'PAGE CHANGE PLAYBACK SPEED           : N M , .                  '
	ascii   'PAGE CHANGE CUR TRACK MIDI CHANNEL   : + -                      '
	ascii   'PAGE CHANGE CUR TRACK MIDI VELOCITY  : J K                      '
	ascii   'PAGE CHANGE CUR TRACK DRUM, LAST MIDI: ARROW-LEFT ARROW-RIGHT, @' 
	ascii   'PAGE CHANGE CUR TRACK GATE LENGTH    : *                        '

keydown macro key
	ld	a,(key >> 8)
	and	key % $100
	endm 

k_@	equ	$380101
k_A	equ	$380102
k_B	equ	$380104
k_C	equ	$380108
k_D	equ	$380110
k_E	equ	$380120
k_F	equ	$380140
k_G	equ	$380180

k_H	equ	$380201
k_I	equ	$380202
k_J	equ	$380204
k_K	equ	$380208
k_L	equ	$380210
k_M	equ	$380220
k_N	equ	$380240
k_O	equ	$380280

k_P	equ	$380401
k_Q	equ	$380402
k_R	equ	$380404
k_S	equ	$380408
k_T	equ	$380410
k_U	equ	$380420
k_V	equ	$380440
k_W	equ	$380480

k_X	equ	$380801
k_Y	equ	$380802
k_Z	equ	$380804

k_0	equ	$381001
k_1	equ	$381002
k_2	equ	$381004
k_3	equ	$381008
k_4	equ	$381010
k_5	equ	$381020
k_6	equ	$381040
k_7	equ	$381080

k_8	equ	$382001
k_9	equ	$382002
k_colon	equ	$382004
k_semi	equ	$382008
k_comma	equ	$382010
k_dash	equ	$382020
k_dot	equ	$382040
k_slash	equ	$382080

k_enter	equ	$384001
k_clear	equ	$384002
k_break	equ	$384004
k_up	equ	$384008
k_down	equ	$384010
k_left	equ	$384020
k_right	equ	$384040
k_space	equ	$384080

k_shift	equ	$388001


main:

	ld	hl,waitt
	ld	de,$3c00
	ld	bc,1024
	ldir

	call initmem    

	call getmodel
	ld (trsversion), a
	;add 64
	;ld ($3c00), a
	;call @KEY
	;ret
	
	cp 1
	jr z, main2

	in  a,($ff)
	or  a,$10 		; enable IO on Model III 
	and a,~$20 		; disable video wait states M III 
	and a,~$40 		; slode mode M4 
	out ($ec),a

main2:

	ld	hl,title+2*64
	ld	de,$3c00+2*64
	ld	bc,1024-2*64 
	ldir

	call settarget

	call screenupdate
	call showcursor
	call showplaycursor
	call showtempo

	ld hl, 	$3c00 ; glitch out last cusor pos
	ld (hl), '*'

loop:
	ld hl, passdivc		; account for elapsed loop passes, but only
	dec (hl)		; every PASSDIV passes to keep the cost down
	jr nz, loopnoclk
	ld (hl), PASSDIV
	ld de, PASS_U
	call midiclkadd
loopnoclk:

	ld a, (status) ; stopped ? 
	or a
	jp z, nostep

running: 

	;; use external clock?
	ld hl, useextclock
	ld a, (hl)
	or a
	jr z, advanceclock 

listenextclock:

	ld a, (trsversion)
	cp 1 ; Model 1? 
	jr z, listenextclockm1 

	;; in a, (M3_PRINTER_IO)	; Model III Printer Input
	;; note that that the above does ONLY work on the Model III, not the 4!
	;; THIS works on both: 
	ld hl, M1_PRINTER_RAM	; MODEL 1 Printer Input 
	ld a, (hl)

	ld b, a
	ld hl, lastextclockin1	
	ld a, (hl)
	ld (hl), b 
	
	xor b 
	jr nz, nextstep
	jp nostep

listenextclockm1:

	ld hl, M1_PRINTER_RAM	; MODEL 1 Printer Input 
	ld a, (hl)
	ld b, a 
	ld hl, lastextclockin2
	ld a, (hl)
	ld (hl), b 
	
	xor b
	jr nz, nextstep
	jp nostep

advanceclock: 

	;; time based tempo: step when the accumulated elapsed time for
	;; this step reaches the target period derived from (tempo).
	;; Because the accounting includes the note output and the screen
	;; work, the period no longer varies with how busy the pattern is.
	ld hl,(steptime)
	ld de,(steptarget)
	or a
	sbc hl,de
	jp c, nostep

nextstep:

	call steplatch

	ld a, (trsversion)
	cp 1 ; Model 1? 
	jr z, outputextclockm1 

	;; output external clock, MODEL III
	ld hl, extclockout
	inc (hl) 
	ld a, (hl) 
	out (M3_PRINTER_IO), a
	jr nextstep1

 outputextclockm1:
 
	;; output external clock, MODEL I
	ld hl, extclockout
	inc (hl) 
	ld a, (hl) 
	ld (M1_PRINTER_RAM), a

nextstep1: 
	;;  inc note pointer
	call nextnote
	ld de, NEXTNOTE_U
	call midiclkadd
	call showplaycursor
	ld de, CURSOR_U
	call midiclkadd
	call playnotes
	ld de, PLAYNOTES_U
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
	jr nz,trackcury ; >= 64 inc y

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
	
	add 7	
	ld (cursory),a
	ld a,(memcursory)
	add 6 
	ld (memcursory),a

showtrackcur:

	ld hl, blink
	ld (hl), 127

	call showcursor

	;; cursor updates complete, now scan the keyboard
	
	jr scan 
	
nostep:
	
	;; sample keyboard during recording and MIDI

	keydown k_space 
	jr z,nostep_scan1

	ld hl, space_registered
	ld (hl), 1

nostep_scan1:

	;; sample keyboard CLEAR and queue 

	keydown k_clear
	jr z,nostep_scan2

	ld hl, clear_registered
	ld (hl), 1

nostep_scan2:

	keydown k_enter 
	jr z,nostep_scan3

	ld hl, enter_registered 
	ld (hl), 1

nostep_scan3:
	
	;; sample MIDI and queue if in RECORD mode only 

	ld a,(record)
	or a
	jr z, cur0

	call MIDIIN
	or a
	jr z, cur0

	;; MIDI available: 

	ld hl, midi_registered
	ld (hl), 1

cur0:

	ld a,(blink)
	inc a
	ld (blink), a

	or a
	jp nz, cur1
	call showcursor

cur1:	 
	cp 127
	jp nz, scan  
	call showcursor	
		
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

	call kbdscan
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

	cp ',' 
	jp z,faster	
	cp '.'
	jp z,slower 
	cp 'N' 
	jp z,faster1
	cp 'M' 
	jp z,slower1 
		
	cp 'P' 
	jp z,startstop

	cp '!' 
	jp z,startstopsong

	cp '#' 
	jp z,recordstatus

	cp "'" 
	jp z,extclockstatus

	cp 'R'
	jp z,midisyncstatus

	cp 'T'
	jp z,trackstatus
	
	cp KCURLEFT
	jp z,drumnodown

	cp KCURRIGHT
	jp z,drumnoup 

	cp '@'
	jp z,drumnocurrent 

	cp '+'
	jp z,channelup

	cp '-'
	jp z,channeldown

	cp 'U'
	jp z,instrumentdown

	cp 'I'
	jp z,instrumentup

	cp 'J'
	jp z,velocitydown

	cp 'K'
	jp z,velocityup

	cp KCURUP 
	jp z,nextbar

	cp KCURDOWN 
	jp z,prevbar

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
	jp z,load

	cp 'S'
	jp z,save

	cp 'G'
	jp z,chgridres

	cp 'B'
	jp z,chgnumbars 

	cp '0'
	jp z,midiflushpanic

	cp '*'
	jp z,chggatelength

	cp '/'
	jp z,uppat

	cp '?'
	jp z,downpat 

	cp '=' 
	call z,clrpat

	cp '"' 
	jp z,copypat

	cp '&'
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

	ld (hl), 'A'

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

	ld hl,$3c00+64+5
	ld (hl), '<'
	inc hl
	ld (hl), '-'
	inc hl
	ld de, topat
	ld a, (de) 
	ld (hl), a
	inc hl
	ld (hl), '?'

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
	ld	de,$3c00+64 
	ld	bc,64 
	ldir

	ld	hl,line 
	ld	de,$3c00+128
	ld	bc,64 
	ldir

	ld hl, songcur
	ld (hl), 0

keyscan2:	 

	call kbdscan

	or a
	jp z,noscansonged 

scancont2:

	cp KCURLEFT
	jp z,songcurleft

	cp KCURRIGHT
	jp z,songcurright

	cp ENTER
	jr z,quitsongeditor

	cp '*'	; loop song 
	jr z, acceptmarker

	cp '.'	; empty 
	jr z, acceptmarker

	cp 'A'
	jr c, keyscan2
	cp 'Z'+1
	jr nc, keyscan2

	ld (curpat), a
	call getpat

	ld	hl,songdata 
	ld	de,$3c00+64 
	ld	bc,64 
	ldir

acceptmarker: 
	push af 
	ld hl, $3c00+64
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

	ld hl, $3c00+64
	ld a, (songcur)
	ld d, 0
	ld e, a
	add hl, de
	
	ld a,(blink)
	cp a,127
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
	ld	de,$3c00+64 
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
	ld	de,$3c00+64 
	ld	bc,64 
	ldir

	jp keyscan2

restorestatus:
	ld	de, $3c00+64 
	ld 	hl, statusbuffer
	ld 	bc, 2*64
	ldir
	ret

savestatus:
	ld	hl, $3c00+64 
	ld 	de, statusbuffer
	ld 	bc, 2*64
	ldir
	ret 
	
chggatelength:
	call gettrackgate
	sla a 
	and $1f
	jr nz,chggatelength1
	ld a,1
	
chggatelength1:
	ld (hl), a
	jp cont
	
chgridres:
	ld a,(gridres)
	sla a 
	and $1f
	jr nz,chgridres1
	ld a,1
	
chgridres1: 
	ld (gridres),a
	
	cp a,1
	jr nz, gridres2
	ld a,11111111b
	ld (quantpat), a	
	jp cont
	
gridres2:
	cp a,2
	jr nz, gridres4
	ld a,11111110b
	ld (quantpat), a	
	jp cont

gridres4:
	cp a,4
	jr nz, gridres8
	ld a,11111100b
	ld (quantpat), a	
	jp cont

gridres8:
	cp a,8
	jr nz, gridres16
	ld a,11111000b
	ld (quantpat), a	
	jp cont

gridres16:
	cp a,16
	jr nz, gridres32
	ld a,11110000b
	ld (quantpat), a	
	jp cont

gridres32:
	cp a,32
	jp nz, cont 
	ld a,11100000b
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
	add 16 
	djnz countticks

	ld (numticks),a
	jp cont

midiin:

	in a,(9)
	or a
	ret z

	;;  byte available

	in a,(8)

	;; A system real time byte ($F8..$FF) may appear between the bytes of
	;; another message. It must leave the parser - and the running status -
	;; exactly as it found them, or a keyboard sending active sensing
	;; every 300 ms would cut a note in half.

	cp $f8
	jr nc, midirealtime

	bit 7,a
	jr nz, midicommand
	
	ld b, a 
	;; MIDI data byte
	ld a, (midicount)
	or a 
	ret z

	;; midicount is the parser state, and it also remembers which kind of
	;; message is being read, so that no new variable is needed - the data
	;; segment is the song file, and a byte added here would move every
	;; offset in it:
	;;
	;;   1  expecting the note of a NOTE ON     2  expecting its velocity
	;;   3  expecting the note of a NOTE OFF    4  expecting its velocity

	cp 2
	jr z, velcheck
	cp 4
	jr z, veloffcheck

	;; a note number: keep it and expect the velocity next

	ld a, b 
	ld (curnote), a
	ld a, (midicount)
	inc a			; 1 -> 2, 3 -> 4
	ld (midicount), a

	ld a, 0 

	ret

midirealtime:

	ld a, 0
	ret

velcheck:
	; ld a, b			
	; ld (curvelocity), a
	; use velocity from settings instead of MIDI message!

	;; Running status: after a complete message the next data byte begins
	;; another one of the same kind, so go back to expecting a note.

	ld a, 1
	ld (midicount), a

	;; Many keyboards send NOTE ON with velocity 0 in place of a NOTE OFF.
	;; Recording that as a note would put every key release in the grid.

	ld a, b
	or a
	jr z, midirelease

	call gettrackvelocity
	ld (curvelocity), a  

	; signal message complete -> note / vel available
	ld a, 1

	ret 

veloffcheck:

	ld a, 3			; running status, still NOTE OFF
	ld (midicount), a

midirelease:

	call releasenote

	ld a, 0
	ret

midicommand:	 

	ld b, a 
	ld a, 0 
	ld (midicount), a

	ld a, b
	;; note on? 
	cp $90 
	jr z, midinoteon

	;; note off? 
	cp $80
	jr z, midinoteoff

	ld a, 0
	ret 

midinoteoff:

	ld a, 3
	ld (midicount), a

	ld a, 0

	ret

midinoteon:	 

	;;  note on!
	ld a, 1
	ld (midicount), a

	ld a, 0
	
	ret	

releasenote:

	;; Let go of the note the recording echo is holding. Only while
	;; recording: midiin is the external clock listener too, and a stray
	;; NOTE OFF must not go out during playback.

	ld a,(record)
	or a
	ret z

	call gettrackchannel
	add $80 
	out (8),a

	call short_delay
	ld a,(curnote)
	out (8),a

	call short_delay
	ld a,0
	out (8),a

	call short_delay
	ret

help:
	call putpat

	ld	hl,$3c00
	ld	de,$3c00+1
	ld	bc,1024-1
	ld	(hl),' '
	ldir

	ld	hl,helpt
	ld	de,$3c00
	ld	bc,1024 
	ldir

	call waitkey

	ld a,'*'

	ld	hl,title
	ld	de,$3c00
	ld	bc,1024
	ldir

	call long_delay
	call long_delay
	call long_delay

	jp main2

midiflush:

	ret 
	in a,(9)
	or a
	ret z

	;;  byte available

	in a,(8)
	bit 7,a
	ret z 
	
	jr midiflush 

load:
	call putpat

	ld hl, loadm  
	call yesnoprompt
	jp nz, cont 
	call loaddisk
	jp cont 

save:
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
	call @EXIT	
	
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
	sub a,b
	jp c, cont
	ld (cursorx),a
	ld hl,memcursorx 
	ld (hl),a
	jp cont

setbar1x macro
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
	endm


setbar2x macro
	ld (cursorx), a
	ld hl,memcursorx 
	ld (hl),a

	ld a, (cursory)
	cp 10
	jp nc,cont
	; else change y cursor 
	add 7 
	ld (cursory),a
	
	ld a,(memcursory) 
	add 6
	ld (memcursory),a

	jp cont
	endm 

bar1:

	ld a,(status)
	cp 1 ; pattern play mode?
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
	cp 1 ; pattern play mode?
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
	cp 1 ; pattern play mode?
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
	cp 1 ; pattern play mode?
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
	cp 1 ; pattern play mode?
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
	cp 1 ; pattern play mode?
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
	cp 1 ; pattern play mode?
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
	cp 1 ; pattern play mode?
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
	cp $11
	jp c,cont
	
	sub $10
	ld c,a
	ld (tempo),a
	ld a,0
	ld hl,delayc
	ld (hl),0
	call showtempo
	jp cont
	
slower:
	ld a,(tempo)
	cp a,255
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
	cp a,$f0
	jp nc,cont
	
	add $10
	ld c,a
	ld (tempo),a
	ld a,0
	ld hl,delayc
	ld (hl),0

	call showtempo
	jp cont	

testsoundx macro 
        local playnoteon 
	;; first, turn of previously played note
	;; ONLY if in record mode!

	call gettrackchannel
	ld b, a

	ld a,(record)
	or a
	jr z, playnoteon

	;; turn off currently held note

	ld a, b
	add $80 
	out (8),a
  
	call short_delay
	ld a,(lastcurnote)
	out (8),a
  
	call short_delay
	ld a,(lastcurvelocity)
	out (8),a

	call short_delay
	call short_delay

playnoteon:

	ld a, b
	add $90 
	out (8),a
  
	call short_delay
	ld a,(curnote)
	out (8),a
	ld (lastcurnote), a
  
	call short_delay
	ld a,(curvelocity)
	out (8),a
	ld (lastcurvelocity), a

	endm 

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

	;; The elapsed time accounting now runs UNCONDITIONALLY: it is the
	;; tempo time base, not just the MIDI clock's. A and DE are already
	;; clobbered by short_delay, so only BC and HL need saving.
	push hl
	ld hl,(steptime)	; steptime += de
	add hl,de
	ld (steptime),hl
	pop hl

	ld a,(usemidisync)
	or a
	ret z			; mode 0: off
	cp 3
	ret z			; mode 3: MMC only, no timing clock
	ld a,(status)
	or a
	ret z			; only clock while playing
	ld a,(midiclkbusy)
	or a
	ret nz			; inside a message: do not interleave

	push bc
	push hl

	ld hl,(steptarget)	; the clock period is the INTENDED step
	ld a,h			; length, so it no longer lags a step behind
	or l
	jr z,midiclkadd4
	ld b,h
	ld c,l

	ld h,d			; hl = 6*de
	ld l,e
	add hl,hl		; 2de
	ld d,h
	ld e,l
	add hl,hl		; 4de
	add hl,de		; 6de
	ex de,hl

	ld hl,(midiclkacc)	; acc += 6*de
	add hl,de

midiclkadd1:
	or a
	sbc hl,bc
	jr c,midiclkadd3	; acc < period: nothing due

	ld a,MIDI_CLOCK
	out (8),a		; one bare OUT, no pacing needed
	jr midiclkadd1		; more than one due? (very low tempo)

midiclkadd3:
	add hl,bc		; undo the overshoot
	ld (midiclkacc),hl

midiclkadd4:
	pop hl
	pop bc
	ret

;; Latch the step length at each step boundary and start a new one.

steplatch:
	ld a,(usemidisync)	; charge the clock generator's own cost,
	or a			; but only in the modes that run the clock
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
	ld hl,0			; underflow guard
steplatch1:
	ld (steptime),hl
	;; fall through: tempo is page specific, so recompute every step

settarget:
	;; steptarget = TEMPOBASE + tempo*112   (112 = 7 << 4)
	ld a,(tempo)
	ld l,a
	ld h,0
	ld d,h
	ld e,l
	add hl,hl		; 2t
	add hl,de		; 3t
	add hl,hl		; 6t
	add hl,de		; 7t
	add hl,hl		; 14t
	add hl,hl		; 28t
	add hl,hl		; 56t
	add hl,hl		; 112t
	ld de,TEMPOBASE
	add hl,de
	ld (steptarget),hl
	ret


;; ---------------------------------------------------------------
;; Send a single MIDI real time byte in a. One byte, no pacing needed.
;; ---------------------------------------------------------------

sendrt:
	ld b,a
	ld a,(usemidisync)
	or a
	ret z			; off
	cp 3
	ret z			; MMC only: FA/FC are meaningless to a
				; receiver that is getting no clock from us
	ld a,b
	out (8),a
	ret

;; set/clear the guard so short_delay does not emit a clock mid message
midiclkupd:
	ld hl,WHLNORM
	ld a,(usemidisync)
	or a
	jr z,midiclkupd1	; off
	cp 3
	jr z,midiclkupd1	; MMC only: no clock overhead to compensate
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
	ld c,a			; c = command, survives short_delay
	ld a,(usemidisync)
	cp 2			; MMC goes out in mode 2 (both) and 3 (MMC)
	ret c
	call midibusyon

	ld a,$f0
	out (8),a
	call short_delay
	ld a,$7f		; universal real time sysex
	out (8),a
	call short_delay
	ld a,$7f		; device id: all call
	out (8),a
	call short_delay
	ld a,$06		; MMC command
	out (8),a
	call short_delay
	ld a,c
	out (8),a
	call short_delay
	ld a,$f7		; end of sysex
	out (8),a
	call short_delay
	call midibusyoff
	ret

;; Transport helpers -----------------------------------------------

midisyncstartr:
	ld a,(usemidisync)
	or a
	ret z
	ld hl,0			; restart the clock phase cleanly
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
	out (8),a

showmidisyncstatus:
	ld hl,midisyncchars
	ld a,(usemidisync)
	ld e,a
	ld d,0
	add hl,de
	ld a,(hl)
	ld hl,$3c00 + 64 + 10
	ld (hl), a

	jp cont

midisyncchars:	byte ' ','C','B','M'

midiflushpanic:

	call midipanicr
	call midiflush
	
	jp cont

midipanicr:

	ld b, $10 

channeloffr:

	ld a, b
	dec a
	add $b0	
	out (8),a  		; MIDI CC for Channel in a 
	call short_delay

	ld a,123
	out (8),a  		; MIDI NOTE OFF 
	call short_delay

	ld a,0
	out (8),a  		; Don't Care 
	call short_delay
	
	;;  repeat for all 16 Channels 
	djnz channeloffr
	
	ret 

drumnocurrent:
	call gettrackdrum
	ld a, (curnote)
	and $7f
	ld (hl), a
	jp cont 
	
drumnoup:
	call gettrackdrum
	inc a 
	and $7f
	ld (hl), a
	jp cont 

drumnodown:
	call gettrackdrum
	dec a 
	and $7f
	ld (hl), a
	jp cont

channelup:
	call gettrackchannel 
	inc a 
	and $0f
	ld (hl), a
	
	call gettracknr
	dec a
	call setinstrument

	jp cont 

channeldown:
	call gettrackchannel
	dec a 
	and $0f 
	ld (hl), a

	call gettracknr
	dec a
	call setinstrument

	jp cont

instrumentup:
	call gettrackinstrument
	inc a 
	and $7f
	ld (hl), a

	call gettracknr
	dec a
	call setinstrument
	
	jp cont 

instrumentdown:	
	call gettrackinstrument
	dec a 
	and $7f
	ld (hl), a

	call gettracknr
	dec a
	call setinstrument
	
	jp cont

velocityup:
	call gettrackvelocity
	inc a 
	and $7f
	ld (hl), a
	
	call gettracknr
	dec a
	call setinstrument
	
	jp cont 

velocitydown:	
	call gettrackvelocity
	dec a 
	and $7f
	ld (hl), a

	call gettracknr
	dec a
	call setinstrument

	jp cont

restorecellx macro 
	ld a,(memcursorx)
	
	ld hl,data
	ld d,0
	ld e,a
	add hl,de	
	ld a,(hl)
	endm 

setgridx macro
	call memcursor
	; ld (hl),SETSYM
	ld a, (curnote)
	add DISPMIDINOTEOFFSET 

	ld (hl), a 
	ld hl,lastcur
	; ld (hl),SETSYM
	ld (hl), a
	endm 

erasegridx macro
	call memcursor
	ld a, (hl)
	;;  erase
	push hl
	restorecellx 
	pop hl
	ld (hl),a
	ld hl,lastcur
	ld (hl),a 
	endm 

gettrackdrumx macro 
	call gettracknr
	dec a
	ld hl,drumnostracks
	ld d,0
	ld e,a
	add hl, de 
	ld a,(hl)
	endm

gettrackchannelx macro 
	call gettracknr
	dec a
	ld hl,channeltracks
	ld d,0
	ld e,a
	add hl, de 
	ld a,(hl)
	endm

gettrackinstrumentx macro 
	call gettracknr
	dec a
	ld hl,instrumenttracks
	ld d,0
	ld e,a
	add hl, de 
	ld a,(hl)
	endm

gettrackgatex macro 
	call gettracknr
	dec a
	ld hl,gatetracks
	ld d,0
	ld e,a
	add hl, de 
	ld a,(hl)
	endm

gettrackvelocityx macro 
	call gettracknr
	dec a
	ld hl,velocitytracks 
	ld d,0
	ld e,a
	add hl, de 
	ld a,(hl)
	endm

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
	call midipanicr		; stopping must silence whatever is still sounding
	ld hl,$3c00 + 64 + 6
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

	call midibusyon		; no clocks during the reset pre-roll:
	call midipanicr		; they would precede the FA start byte
	call long_delay

	call setmiditrackinstruments
	call long_delay
	call midibusyoff

	ld hl,$3c00 + 64 + 6
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
	
	ld hl, songdata 	; load song pattern at song index pos 
	ld a, (songpos)
	ld d, 0
	ld e, a
	add hl, de
	ld a, (hl) 		; a has pattern

	cp '.' 			; empty? stop
	jr z, stopsong 

	cp '*' 			; repeat?
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
	call midipanicr		; stopping must silence whatever is still sounding
	ld hl,$3c00 + 64 + 6
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

	call midibusyon		; no clocks during the reset pre-roll
	call midipanicr
	call long_delay
	
	call setmiditrackinstruments
	call long_delay

	call midibusyoff

	ld hl,$3c00 + 64 + 6
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
	
	ld hl,$3c00 + 64 + 8
	ld a, playbacks 
	ld (hl), a
	
	jp cont
	
showrecordstatus:	
	ld hl,$3c00 + 64 + 8
	ld a, records
	ld (hl), a
	
	jp cont 


extclockstatus:
	ld a,(useextclock)
	xor 1
	ld (useextclock), a
	or a
	jr nz, showextclockstatus 
	
	ld hl,$3c00 + 64 + 9 
	ld a, '|'
	ld (hl), a
	
	jp cont
	
showextclockstatus:
	ld hl,$3c00 + 64 + 9 
	ld a, extclocks 
	ld (hl), a
	
	jp cont 


trackstatus:
	ld a,(track)
	xor 1
	ld (track), a
	or a
	jr nz, showtrackstatus
	
	ld hl,$3c00 + 64 + 7
	ld a, frees
	ld (hl), a
	
	jp cont
	
showtrackstatus:	
	ld hl,$3c00 + 64 + 7
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
	ld hl,$3c00
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

	
dly.01:	ld	bc,d10000th
	sett	0
dly:	dec	bc
	ld	a,b
	or	c
	jp	nz,dly
	ret

clearextclockr:

	ld a, (trsversion)
	cp 1 ; Model 1? 
	jr z, clearextclockm1r

	;; in a, (M3_PRINTER_IO)	; Model III Printer Input
	;; note that that the above does ONLY work on the Model III, not the 4!
	;; THIS works on both: 
	ld hl, M1_PRINTER_RAM	; MODEL 1 Printer Input 
	ld a, (hl)
	ld b, a
	ld hl, lastextclockin1	
	ld a, (hl)
	ld (hl), b

	ret	

clearextclockm1r:

	ld hl, M1_PRINTER_RAM	; MODEL 1 Printer Input 
	ld a, (hl)
	ld b, a 
	ld hl, lastextclockin2
	ld a, (hl)
	ld (hl), b

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

	call nz, putpat 	; only store if recording active (optimization to prevent lag during playback)

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
	jr z, nextnotecontpat ; no requested pattern switch

	;; else, switch to requested pattern at end of current bar

	ld a, (qtrackpos)
	inc a
	and 00001111b
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
	ld b,WHLSLICES		; slices of the per step calibrated delay
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

	ld a, (record)		; don't sample if not in record mode 
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
	
	ld	hl,title+2*64 
	ld	de,$3c00+2*64 
	ld	bc,64 
	ldir

	ld	hl,title+9*64 
	ld	de,$3c00+9*64 
	ld	bc,64 
	ldir

	ld a,(qtrackpos)
	
	ld hl,$3c00+2*64
	ld e,a
	ld d,0 
	add hl,de

	bit 6,a
	jr nz,showcurtrack2
	
	ld (hl),POSMARKSYM
	ret

showcurtrack2:
	ld de,6*64
	add hl,de
	ld (hl),POSMARKSYM
	ret
	
	
d10000th	equ	1774080 / t($) / 10000

	  
screenupdate:
	
	;;  swap in track 1 
	ld	hl,tracks1	
	ld	de,$3c00+3*64 
	ld	bc,6*64
	ldir

	;;  swap in track 1 
	ld	hl,tracks2 
	ld	de,$3c00+10*64 
	ld	bc,6*64
	ldir

	ret

showcursor:

	ld hl,(lastcurpos)
	ld a,(lastcur)
	ld (hl),a
	call cursor
	ld (lastcurpos),hl
	ld a,(hl)
	ld (lastcur),a
	
	ld a,(blink)
	cp a,127
	jr c,cur2
	ld (hl), CURSYM 
	ret 

cur2:
	push hl
	restorecellx
	pop hl 
	ret
	
	
byte2ascii: 			; input c, output de ASCII 
   ld a, c
   rra
   rra
   rra
   rra
   call convnibble 
   ld d, a	
   ld  a,c
convnibble:
   and  $0F
   add  a,$90
   daa
   adc  a,$40
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
	ld hl,$3c00+64+23
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
	ret z			; unchanged: digits are still valid
	ld (hl),a

	call settarget		; steplatch only runs while playing, so keep
				; the period in step with tempo here too

	ld hl,bpmk3		; pick the constant for this machine
	ld a,(trsversion)
	cp 1
	jr nz,calcbpm1
	ld hl,bpmk1
calcbpm1:
	ld de,dvnd
	ld bc,4
	ldir

	ld a,(tempo)		; divisor = BPMBASE + 97*tempo
	ld l,a
	ld h,0
	ld d,h
	ld e,l
	add hl,hl		; 2t
	add hl,de		; 3t
	add hl,hl		; 6t
	add hl,hl		; 12t
	add hl,hl		; 24t
	add hl,hl		; 48t
	add hl,hl		; 96t
	add hl,de		; 97t
	ld de,BPMBASE
	add hl,de
	ld (bpmdiv),hl

	srl h			; round to nearest instead of truncating:
	rr l			; bias the dividend by half the divisor
	ld de,(dvnd)
	add hl,de
	ld (dvnd),hl
	jr nc,calcbpm0
	ld hl,(dvnd+2)
	inc hl
	ld (dvnd+2),hl
calcbpm0:

	ld hl,0			; remainder
	ld b,32
calcbpm2:
	or a			; shift dvnd left, carry out of the top
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

	adc hl,hl		; bring that bit into the remainder
	ld de,(bpmdiv)
	or a
	sbc hl,de
	jr nc,calcbpm3
	add hl,de		; did not fit: restore
	jr calcbpm4
calcbpm3:
	ld a,(dvnd)		; it fit: set the quotient bit
	or 1
	ld (dvnd),a
calcbpm4:
	djnz calcbpm2

	ld hl,(dvnd)		; quotient -> three ASCII digits
	ld de,bpmdigits
	ld bc,-100
	call bpmdigit
	ld bc,-10
	call bpmdigit
	ld a,l
	add a,'0'
	ld (de),a

	ld a,(bpmdigits)	; blank a leading zero
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
	sbc hl,bc		; one too far: add it back
	ld (de),a
	inc de
	ret

bpmk3:	byte $00,$01,$1d,$00	; 1900800, little endian
bpmk1:	byte $d0,$20,$19,$00	; 1646800, little endian -- 1663200 scaled
				; by the Model I's ~1% longer step in T states

gettracknr:
	ld a,(memcursory)
	add 1
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

gettrackdrumreg: ; input: e register, starting at 0
	ld hl,drumnostracks
	ld d,0
	add hl, de 
	ld b,(hl)
	ret

gettrackchannelreg: ; input: e register, starting at 0
	ld hl,channeltracks
	ld d,0
	add hl, de 
	ld b,(hl)
	ret

showtrackdrum:
	call gettrackdrum
	ld c, a
	ld hl,$3c00+64+52
	call byte2ascii
	ld (hl),d
	inc hl
	ld (hl),e
	ret

showtrackchannel:
	call gettrackchannel 
	ld c, a
	ld hl,$3c00+64+43
	call convnibble 
	ld (hl),e
	ret

showtrackinstrument:
	call gettrackinstrument
	ld c, a
	ld hl,$3c00+64+47
	call byte2ascii
	ld (hl),d
	inc hl
	ld (hl),e
	ret

showtrackvelocity:
	call gettrackvelocity
	ld c, a
	ld hl,$3c00+64+57
	call byte2ascii
	ld (hl),d
	inc hl
	ld (hl),e
	ret

showtrack:
	call gettracknr 
	ld c,a 
	ld hl,$3c00+64+17
	call convnibble 
	ld (hl),e
	ret

setinstrument: 			; a has track number 

	push af 
	ld ix,channeltracks 	; retrieve MIDI channel for track a
	ld c,a
	ld b,0
	add ix,bc
	ld a,(ix) 		; MIDI channel for track a is now in a 
	
	ld b,$c0		; add $c0 for change instrument for MIDI channel in a 
	add a, b
	out (8),a  		; change instrument for channel in a 
	call short_delay

	pop af 
	ld ix,instrumenttracks	; retrieve instrument for track a 
	ld c,a
	ld b,0
	add ix,bc
	ld a,(ix) 		; MIDI instrument for track a is now in a 

	out (8),a		; change MIDI instrument to a 
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
	ld a,(qtrackpos)
	
	bit 6,a
	jr nz,playhightracks ; >= 64  

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
	
	ld c,(hl) ; -> c is note off
	ld d,0
	ld e,0 ; e is track number 
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
	ld e,0 ; e is track number 
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
	
	
playnote: ; input note on in c; track number 0..5 in e; hl track start, ix note of track start 

	ld a, (qtrackpos)	; add note index offset
	res 6, a		; reset high tracks bit 

	ld b, a			; save note index to b 

	push de			; save track number in e 
	ld d, 0			; compute note pointer 
	ld e, a
	add hl, de
	pop de 
	
        ld a, (hl) 		; get note; note on, <> 0? no -> return 
	cp DISPMIDINOTEOFFSET+1
	jr nc, playnote1

	;; else, waste some time!

	call short_delay
	call short_delay

	ret 

playnote1:

	; note index in b, note to play in a,
	; e track number, hl note pointer,
	; ix start of note off low  tracks
	; iy start of note off high tracks

	push	af	        ; save note in a	
	
	ld hl,channeltracks 	; determine MIDI channel for track in e 
	add hl, de 
	ld a,(hl) 		; MIDI channel for track  

	add $90			; MIDI NOTE ON for MIDI channel in a 
	out (8),a

	push de			; protect track number in e 
	call short_delay
	pop de

	pop af			; output note number
	push af			
	sub DISPMIDINOTEOFFSET		
	out (8), a
	
	push de			; protect track number in e 
	call short_delay
	pop de

	ld hl,velocitytracks 	; determine MIDI velocity for track in e  
	add hl, de 
	ld a,(hl) 		; MIDI velocity for track in e 
	out (8),a

	;; compute and set note off in noteoff tracks 

	ld hl,gatetracks
	add hl, de 		; gate duration index 
	ld c, (hl)		; gate duration for track 	

	ld a, (qtrackpos) 	; load note index, with bit 6 set if >= 64
	add c 			; add gate duration 
	
	ld hl, numticks
	ld c, (hl)
	cp c			; a > numticks? wrap around! use iy as basis 
	jr c, nowrap

	; else, we need to wrap around, sub 64; c has note position + gate duration offset
	; a has numticks 

	sub c

nowrap: ; a has note position + gate duration offset, wrapped around - check if high or low tracks 

	bit 6,a
	jr nz, storenoteoffhigh  ; >= 64, high off tracks
	
	bit 7,a
	jr nz, storenoteoffhigh2  ; >= 128, low off tracks

storenoteofflow:

	push ix	 ; low off tracks 
	pop hl

	jr storenoteoff
	
storenoteoffhigh:

	res 6,a	; -> low tracks 

	push iy  ; high off tracks 
	pop hl

	jr storenoteoff

storenoteoffhigh2:

	res 7,a	; -> low tracks (wrap around at end track 6, > 127!) 

	push ix  ; low off tracks 
	pop hl

	jr storenoteoff

storenoteoff: 

	ld d, 0
	ld e, a
	add hl, de		; hl has high or low note pos in off tracks 

	pop af			; restore note to play / turn off
	ld (hl), a 		; store note in note off grid

	ret 


stopnote: ; input note off in c; track number 0..5 in e 

        ld a, c 		; note on <> 0? no; return
	or a 
	jr nz, stopnote1

	;; else, waste some time!

	call short_delay
	call short_delay

	ret
	
stopnote1:

	ld (hl), 0 		; hl = note pointer; erase note for now, will be rescheduled when played again!	

	push bc
	
	ld hl,channeltracks 	; determine MIDI channel for track in e 
	;; ld d,0
	;; ld e,e 
	add hl, de 
	ld a,(hl) 		; MIDI channel for track in e

	add $80			; MIDI NOTE OFF for MIDI channel in a 
	out (8),a

	push de
	call short_delay
	pop de

	ld a,c			; c has the note number -> MIDI out 
	sub DISPMIDINOTEOFFSET		
	out (8),a

	push de
	call short_delay
	pop de 
	
	pop bc

	ld hl,velocitytracks 	; determine MIDI velocity for track in e  
	;; ld d,0
	;; ld e,e 
	add hl, de 
	ld a,(hl) 		; MIDI velocity for track in e 
	out (8),a

cost1   equ     t($)-t(stopnote1)

	ret 

showgridres:
	ld a,(gridres)
	ld c, a
	ld hl,$3c00+64+36
	call byte2ascii
	ld (hl),d
	inc hl
	ld (hl),e
	ret

showpat:
	ld a,(curpat)
	ld hl,$3c00+64+4
	ld (hl),a 
	ret
	

showgate:
	call gettrackgate
	ld c, a
	ld hl,$3c00+64+62
	call byte2ascii
	ld (hl),d
	inc hl
	ld (hl),e
	ret
	
showbars:
	ld a,(numbars)
	ld c, a
	ld hl,$3c00+64+32
	call convnibble
	ld (hl),e
	ret

long_delay:
    ld de,$1000 
delloop1: 
    dec de
    ld a,d
    or e
    jp nz,delloop1 
    ret 

short_delay:
    ld de,$0020
delloop: 
    dec de
    ld a,d
    or e
    jp nz,delloop
    ;; account for the time just burned, and emit a clock if one is due.
    ;; MIDI explicitly permits real time bytes between the bytes of
    ;; another message, which is what makes this legal inside playnote.
    ld hl,shortdivc
    dec (hl)
    jr nz,shortnoclk
    ld (hl),SHORTDIV
    ld de,SHORTDLY_U
    call midiclkadd
shortnoclk:
    ret 

;; ---------------------------------------------------------------
;; Direct keyboard matrix scan, replacing the ROM @KBD call.
;;
;; @KBD measured 55836 T per step, ~48% of the entire step and by far
;; the largest single cost in the tracker. It does general purpose
;; debounce and key handling we do not need here. Reading the 7 key
;; rows directly costs a few hundred T instead.
;;
;; Returns ASCII in a, or 0 for "no new key". A key must be released
;; before it reports again, matching how @KBD behaved for this program
;; (deliberately no typematic repeat: with repeat, holding a toggle key
;; such as P would flip play on and off many times per second).
;;
;; Clobbers a, bc, de, hl -- exactly as the ROM call did.
;; ---------------------------------------------------------------

kbdscan:
	ld a,($3880)		; row 7 is the shift key alone
	and 1
	ld (kbdshift),a

	ld c,1			; row select: $01,$02,$04,...,$40
	ld b,7			; rows 0..6 carry the actual keys
	ld e,0			; row number

kbdrow:
	ld h,$38		; keyboard matrix is at $3800 + rowmask
	ld l,c
	ld a,(hl)
	or a
	jr nz,kbdfound
	inc e
	sla c
	djnz kbdrow

	;; Nothing held. Let the latch go, but only once the contacts have
	;; stayed open for KBDSETTLE scans running, so bounce cannot turn one
	;; press into several. A is already 0 here, and the settled case -- by
	;; far the common one -- costs 28 T against the 27 T this used to be,
	;; so the step timing calibration is unaffected.
	ld a,(kbdsettlec)
	or a
	ret z			; already settled, latch is clear, A = 0
	dec a
	ld (kbdsettlec),a
	jr nz,kbdstl		; still settling: hold the latch
	ld (lastkey),a		; settled: A is 0, release the latch
	ret
kbdstl:
	xor a
	ret

kbdfound:
	ld d,0			; lowest set bit gives the column
kbdbit:
	rra
	jr c,kbdgot
	inc d
	jr kbdbit

kbdgot:
	ld a,KBDSETTLE		; contacts closed: restart the settle timer
	ld (kbdsettlec),a
	ld a,e			; index = row*8 + column
	add a,a
	add a,a
	add a,a
	add a,d
	ld l,a
	ld h,0

	ld de,kbdtab
	ld a,(kbdshift)
	or a
	jr z,kbdplain
	ld de,kbdtabsh
kbdplain:
	add hl,de
	ld a,(hl)
	or a
	ret z			; unmapped matrix position

	ld hl,lastkey
	cp (hl)
	jr z,kbdheld		; still the same key: report nothing
	ld (hl),a		; a new key: latch it and report it
	ret
kbdheld:
	xor a
	ret

;; waitkey -- wait for a keypress using our own matrix scan.
;;
;; @KEY reads the DOS type ahead buffer, and that is a race we now lose:
;; kbdscan reacts to a key in about a millisecond, while the interrupt
;; driven DOS keyboard driver only scans every 25 ms or so. Any keypress
;; held longer than that gets queued by the DOS as well, so the next @KEY
;; returns that same key immediately -- the help page is dismissed by the
;; very H that opened it, and a Y/N prompt answers itself.
;;
;; Waiting on kbdscan instead sidesteps the DOS buffer completely. The
;; first loop also insists the keyboard is fully released and settled, so
;; the press that got us here cannot be read a second time.

waitkey:
	call kbdscan		; drain the press that brought us here
	ld a,(lastkey)
	or a
	jr nz,waitkey
waitkey1:
	call kbdscan		; now wait for a fresh one
	or a
	jr z,waitkey1
	ret

kbdtab:				; unshifted
	byte '@','A','B','C','D','E','F','G'
	byte 'H','I','J','K','L','M','N','O'
	byte 'P','Q','R','S','T','U','V','W'
	byte 'X','Y','Z',0,0,0,0,0
	byte '0','1','2','3','4','5','6','7'
	byte '8','9',$3a,$3b,$2c,$2d,$2e,$2f
	byte 13,31,1,KCURUP,KCURDOWN,KCURLEFT,KCURRIGHT,32

kbdtabsh:			; shifted
	byte '@','A','B','C','D','E','F','G'
	byte 'H','I','J','K','L','M','N','O'
	byte 'P','Q','R','S','T','U','V','W'
	byte 'X','Y','Z',0,0,0,0,0
	byte '0',$21,$22,$23,$24,$25,$26,$27
	byte $28,$29,$2a,$2b,$3c,$3d,$3e,$3f
	byte 13,31,1,KCURUP,KCURDOWN,KCURLEFT,KCURRIGHT,32

loaddisk:

	ld hl, filename
	
	ld de, dcb              ; ready to get TRS-80 filename from (HL)
        call @fspec
        jp nz, diskerror 
        
	ld hl, iobuf
        ld de, dcb
        ld b, 0
        call @open               ; open the file
        jr z, readfile
        
        ld c, a                  ; error code 
        jp diskerror
        
readfile:

        ; call getern
	ld b, 88
	ld c, 0

	ld de, datastart
	
rloop:  push de

	ld de, dcb
	ld hl, iobuf 
	call @read              ; read file

	pop de
	
        jr z, rok               ; got a full 256 bytes
        
        ld c, a
        jp diskerror          ; oops, i/o error
        ret
       
rok:    ld	hl,iobuf	; source hl; de = datastart + page offset
	push bc 		; save pagecounter 
	ld	bc,256 		; # bytes to copy
	push de			; save de 
	ldir 			; hl -> de / bc bytes
	pop de			; restore de 
	pop bc			; restore pagecounter
	
	inc d			; inc. page offset 
	djnz rloop

        ld de, dcb
        call @close              ; close the TRS-80 file
        jr z, diskreadok
        
        ld c, a
        jp diskerror           ; oops, i/o error
        
diskreadok: ret 

	
savedisk:

        ld hl, filename 

	ld de, dcb              ; ready to get TRS-80 filename from (HL)
        call @fspec
        jp nz, diskerror 

	ld hl, datastart
        ld de, dcb
        ld b, 0
        call @init               ; open the file
        jr z, writefile
	
        ld c, a                  ; error code 
        jp diskerror
        ret 
        
writefile:

        ld hl, datastart 
        ld de, dcb
        ld bc, datalength
	inc b
	
wloop:	ld (dcb+3), hl
        call @write             ; write 256 bytes to file
        jr z, wrok
        ld c, a
        jp diskerror          ; oops, i/o error
	ret
        
wrok:   inc h
	djnz wloop		; write next block unitl b = 0; remainder in c 

	ld a, c			; remainder of last record 
        ld (dcb+8), a
	
	;; ld (dcb+3), hl
        call setern             ; set ERN (in case shortening file)
	
        ld de, dcb
        call @close              ; close the TRS-80 file
        jr z, disksaveok

	ld c, a
        jp diskerror              ; oops, i/o error
	ret
        
disksaveok: ret

diskerror:
	ld	hl,errorm 
	ld	de,$3c00+64
	ld	bc,64
	ldir
	call waitkey
	call restorestatus
	ret

yesnoprompt:
	push hl 
	call savestatus
	pop hl
	ld	de,$3c00+64
	ld	bc,64
	ldir
	call waitkey
	cp 'Y'
	call restorestatus

	push af	
	;; ensure enter doesn't register... 
	call long_delay
	call long_delay
	call long_delay
	pop af	

	ret

;;
;; getmodel - return TRS-80 Model number in A (1, 3 or 4).
;; Thanks to G. Phillips
;; 	

getmodel:
	in	a,(0ffh)	; read OUTMOD latches
	ld	b,a		; save original settings
	ld	c,60h
	xor	c		; invert CPU Fast, DISWAIT
	out	(0ech),a	; set latches
	in	a,(0ffh)	; read latches
	xor	c		; flip to original value
	xor	b		; compare against original
	ld	c,0ech
	out	(c),b		; restore original settings
	rlca
	rlca
	jr	nc,.ism4		; CPU Fast unchanged, must be Model 4
	rlca
	ld	a,3
	ret	nc		; DISWAIT same, Model III
	ld	a,1		; otherwise, it's a Model I
	ret
.ism4:	ld	a,4
	ret
	
;;
;; setern by Frederic Vecoven and Tim Mann
;; https://github.com/veco/FreHDv1/blob/main/sw/z80/utils/import2.z80
;;

;; EOF handling differs between TRS-80 DOSes:
;;  For TRSDOS 2.3 and LDOS, word (dcb+12) contains the number of
;;  256 byte records in the file, byte (dcb+8) contains the EOF
;;  offset in the last record (0=256).
;;  For NEWDOS/80 and TRSDOS 1.3, byte (dcb+8) and word (dcb+12) 
;;  form a 24 bit number containing the relative byte address of EOF.
;;  Thus (dcb+12) differs by one if the file length is not a
;;  multiple of 256 bytes.  DOSPLUS also uses this convention,
;;  and NEWDOS 2.1 probably does too (not checked).

; Set ending record number of file to current position
; EOF offset in C; destroys A, HL
setern:
	ld hl, (dcb+10)		; current record number
	ld a, (ernldos)         ; get ERN convention
	or a
	jr nz, noadj            ; go if TRSDOS 2.3/LDOS convention
adj:	or c			; length multiple of 256 bytes?
	jr z, noadj             ; go if so
	dec hl			; no, # of records - 1
noadj:	ld (dcb+12), hl
	ret	
;;
;; getern by Frederic Vecoven and Tim Mann
;; https://github.com/veco/FreHDv1/blob/main/sw/z80/utils/export2.z80
;;

;; EOF handling differs between TRS-80 DOSes:
;;  For TRSDOS 2.3 and LDOS, word (dcb+12) contains the number of
;;  256 byte records in the file, byte (dcb+8) contains the EOF
;;  offset in the last record (0=256).
;;  For NEWDOS/80 and TRSDOS 1.3, byte (dcb+8) and word (dcb+12) 
;;  form a 24 bit number containing the relative byte address of EOF.
;;  Thus (dcb+12) differs by one if the file length is not a
;;  multiple of 256 bytes.  DOSPLUS also uses this convention,
;;  and NEWDOS 2.1 probably does too (not checked).

; Returns number of (partial or full) records in BC, destroys A
getern:
        ld bc, (dcb+12)
        ld a, (ernldos)         ; get ERN convention
        and a
        ret nz                  ; done if TRSDOS 2.3/LDOS convention
        ld a, (dcb+8)           ; length multiple of 256 bytes?
        and a
        ret z                   ; done if so
        inc bc                  ; no, # of records = last full record + 1
        ret     


;; 
;; Cycle Wasting Routines by G. Phillips 
;; http://48k.ca/beamhack3.html
;;

; wHL -- Waste HL + 100 T states. Only uses A, HL.

wHL256:
        dec     h               ;<0>  | <4>
        ld      a,256-4-4-12-4-7-17-81       ; 81 is wA overhead
                                ;<0>  | <7>
        call    wA              ;<0>  | <17+A>
wHL:    inc     h               ;<4>  | <4>
        dec     h               ;<4>  | <4>
        jr      nz,wHL256       ;<7>  | <12>
        ld      a,l             ;<4>
wA:     rrca                    ;<4>
        jr      c,wHL_0s        ;<7>  | <12> 1 extra cycle if bit 0 set
        nop                     ;<4>  | <0>
wHL_0s: rrca                    ;<4>
        jr      nc,wHL_1c       ;<12> | <7>  2 extra cycles if bit 1 set
        jr      nc,wHL_1c       ;<0>  | <7>
wHL_1c: rrca                    ;<4>
        jr      nc,wHL_2c       ;<12> | <7>  4 extra cycles if bit 2 set
        ret     nc              ;<0>  | <5>
        nop                     ;<0>  | <4>
wHL_2c: rrca                    ;<4>
        jr      nc,wHL_3c       ;<12> | <7>  8 extra cycles if bit 3 set
        ld      (0),a           ;<0>  | <13>
wHL_3c: and     a,0fh           ;<7>
        ret     z               ;<11> | <5>  done if no other bits set
wHL_16: dec     a               ;<0>  | <4>  loop away 16 for remaining count
        jr      nz,wHL_16       ;<0>  | <12>
        ret     z               ;<0>  | <11>
; Last jr was 7, but the extra 5 from "ret z" keeps us at 16 * A.
; The "ret z" cost balances the previous "ret z" in the 0 case.

;;
;; data region 
;; 
	
	org $8000

trsversion  byte 0

;; MIDI sync state. Deliberately placed BEFORE datastart so that
;; datalength is unchanged and existing DUMP files still load.
usemidisync	byte 0		; 0 = off, 1 = send MIDI clock + MMC
midiclkacc	word 0		; Bresenham accumulator, in 6*T-state units
steptime	word 0		; T-states accumulated so far this step
laststeptime	word 0		; previous step total (kept for reference)
steptarget	word 0		; intended step length, from tempo
bpmtempo	byte $ff	; tempo the BPM digits were computed for
bpmdigits	byte '-','-','-'
dvnd		defs 4		; scratch dividend for the BPM division
midiclkbusy	byte 0		; re-entrancy guard while sending a message
lastkey		byte 0		; debounce latch for the direct key scan
kbdsettlec	byte 0		; scans of quiet still needed before a new key
bpmdiv		word 0		; divisor behind the BPM readout, NOT the step period
kbdshift	byte 0		; shift state of the current scan
passdivc	byte 1		; main loop call divider
shortdivc	byte 1		; short_delay call divider
whlslicecur	word WHLNORM	; active step delay slice (shrinks when sync on)

datastart

startmarker 	ascii 'START-OF-FILE-MARKER'

statusbuffer		defs	2*64

instrumenttracks 	byte 1, 2, 3, 4, 5, 1 

lastcur	     byte	'.'
lastcurpos   word 	$3c00+3*64 

memcursorx byte 	0
memcursory byte 	0
	
cursorx	byte 	0
cursory	byte 	3
blink   byte    0
status  byte    0
track	byte    0
record  byte    0

trackpos   byte  0
qtrackpos  byte  0

useextclock   byte	 0

midicount         byte  0
curnote           byte  0
curvelocity       byte  0
lastcurnote       byte  0
lastcurvelocity   byte  0

extclockout      byte	 0
lastextclockin1  byte	 0
lastextclockin2  byte	 0


clear_registered byte 0 
space_registered byte 0 
enter_registered byte 0 
midi_registered  byte 0 

tracksoff1 	defs    6*64 		
tracksoff2 	defs    6*64

; there is some bug in the code from tracksoff that messes with the songdata! double check at some point... for now, put a hack in here to protect song data:

buffer 	defs    64	

songdata	ascii	'A...............................................................'
songcur		byte 	0
songpos		byte 	0

curpat		ascii   'A'
topat		ascii   'A'
nextpat		byte	 0 

;; page-specific variables


pagestart

delayc 	byte	0
tempo   byte	$2a
numbars byte	8
numticks byte	8*16 
gridres byte  	4
quantpat   byte  11111100b

drumnostracks		byte 36, 38, 40, 51, 44, 46 
channeltracks 		byte 0, 1, 2, 3, 4, 9
;; these will be global; too much overhead to change instruments with each page
;; instrumenttracks 	byte 1, 2, 3, 4, 5, 1 
velocitytracks	 	byte 127, 127, 127, 127, 127, 127
gatetracks	 	byte 8,8,8,8,8,8

tracks1 	defs    6*64 		
tracks2 	defs    6*64

pagelen 	equ $-pagestart

pages		defs 26*pagelen	; pages A-Z

endmarker 	ascii 'END-OF-FILE-MARKER'

dataend 	equ $
datalength 	equ $-datastart

	
	end main 

	
