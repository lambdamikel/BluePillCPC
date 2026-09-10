
;; ===================================================================
;; MIDORG/CPC  -  MIDI ORGAN V1.1 for the Ultimate MIDI Card
;; (C)2026 LAMBDAMIKEL + G.PHILLIPS + CLAUDE.  Assembles with rasm.
;;
;; Play the CPC keyboard as a two manual MIDI organ. Michael Wessel's
;; TRS-80 program, with the self-modifying keyboard scanner and the
;; keyboard artwork contributed by George Phillips. Four things change
;; for the CPC:
;;
;;   keyboard  the TRS-80 matrix is memory mapped, so "ld a,($3801)" is a
;;             row of keys. The CPC's sits behind the PSG, so the whole
;;             matrix is scanned into kbdmap once per pass and the key
;;             macros read that instead. A CPC key reads 0 when pressed,
;;             the opposite of a TRS-80, so the copy is inverted - after
;;             which every one of the original's tests is correct as
;;             written, self-modifying scanner included.
;;   MIDI      "out (8),a" becomes "call midiout".
;;   video     TRACKER's display layer, so #3C00 is a 64x16 shadow buffer
;;             laid out like TRS-80 video RAM. Every screen address in the
;;             program is therefore right as it stands.
;;   exit      BREAK becomes ESC, and there is no DOS to return to.
;;
;; THE PART THAT MAKES IT WORK, and it is George's, not mine: each key
;; test ends in "call nz,key_down". The handler pops the return address,
;; rewrites those three bytes in place to "call z,key_up", and jumps back.
;; So the same instruction that started the note is now the one watching
;; for its release, and there is no key-state table at all. It ports
;; across untouched because the macro keeps "call nz,handler" as its last
;; three bytes - that offset, (iy-3), is load bearing.
;; ===================================================================

VRAM    equ #3C00               ; the TRS-80's video address, kept
SHADOW  equ #9880               ; what the screen currently shows

;; kbdcpc.asm wants these; the organ itself uses none of them.
KCURLEFT        equ 8
KCURRIGHT       equ 9
KCURUP          equ 91
KCURDOWN        equ 10

    org #0800
    include "font.asm"

    org #1000
    run #1000
    jp start

    include "midi.asm"
    include "render.asm"
    include "kbdcpc.asm"

;; ---- the keyboard, inverted -----------------------------------------
;; A pressed CPC key reads 0. The TRS-80's reads 1, and every test in this
;; program is written that way, so the scan is complemented once per pass
;; and the rest of the file needs no thought at all.
kbdscanorg:
    call kbdraw
    ld hl,kbdmap
    ld de,kbdmapi
    ld b,10
kso1:
    ld a,(hl)
    cpl
    ld (de),a
    inc hl
    inc de
    djnz kso1
    ret

kbdmapi:    defs 10

title:	defb   "* ULT.MIDI CARD ORGAN V1.1 (C)2026 LAMBDAMIKEL+PHILLIPS+CLAUDE *"
	defb   "----------------------------------------------------------------"
	defb   "   _____ _____       _____ _____ _____       _____ _____        "
	defb   "   |*c'# |*d'#|    |*f'# |*g'# |*a'# |     |*c''#|*d''#|        "
	defb   "  _|__2__|__3_|____|__5__|__6__|__7__|_____|__9__|__0__|_ ____  "
	defb   " |*c'|* d' |*e' |*f' |* g' |* a' |* b' |*c'' |*d'' |*e'' |*f''| "
	defb   " |_Q_|__W__|_E__|_R__|__T__|__Y__|__U__|__I__|__O__|__P__|__@_| "
	defb   "     _____ _____       _____ _____ _____       _____ _____      "
	defb	"    |* c# |* d# |     |* f# |* g# |* a# |     |*c'# |*d'# |     "
	defb   "   _|__S__|__D__|_____|__G__|__H__|__J__|_____|__L__|__;__|_    "
	defb   "  |*c |* d  |* e  |* f  |* g  |* a  |* b  |*c'  |*d'  |*e'  |   "
	defb	"  |_Z_|__X__|__C__|__V__|__B__|__N__|__M__|__,__|__.__|__/__|   "
	defb   "                                                                "
	defb   "ESC:QUIT  L/R:INSTR UP/DOWN:VOL SPACE/ENT:CHANNEL  AF/14:OCT +/-"
	defb   "CUR <OCT/MIDI CHANNEL/INSTR/VOL>: <XX/XX/XX/XX> -  XX/XX/XX/XX  "
	defb   "----------------------------------------------------------------"

title_len equ $-title


current	defb 0
chan1	defb 0
chan2	defb 1
oct1	defb 48
oct2	defb 60
instr1	defb 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
instr2	defb 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
vol1	defb 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127
vol2	defb 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127


start:
    call setscreen              ; mode 2, black paper, bright yellow text

    ;; rowtab is filled at runtime, and NOTHING renders correctly until it
    ;; is: an empty table sends every cell to 0 + scanline*#800, which for
    ;; MIDORG meant the font being drawn over its own code at #1000.
    ;; The artwork is one solid block, so it gets the gapless map.
    ld hl,rowplain
    call setrows

    ld  hl,title
    ld  de,VRAM
    ld  bc,title_len
    ldir



;; zmac built these with a macro and a REPT; they are simply 0..31, so
;; here they are spelled out and rasm needs no equivalent.
step_0   equ 0
step_1   equ 1
step_2   equ 2
step_3   equ 3
step_4   equ 4
step_5   equ 5
step_6   equ 6
step_7   equ 7
step_8   equ 8
step_9   equ 9
step_10  equ 10
step_11  equ 11
step_12  equ 12
step_13  equ 13
step_14  equ 14
step_15  equ 15
step_16  equ 16
step_17  equ 17
step_18  equ 18
step_19  equ 19
step_20  equ 20
step_21  equ 21
step_22  equ 22
step_23  equ 23
step_24  equ 24
step_25  equ 25
step_26  equ 26
step_27  equ 27
step_28  equ 28
step_29  equ 29
step_30  equ 30
step_31  equ 31


st_c0	equ	step_0
st_c0s	equ	step_1
st_d0	equ	step_2
st_d0s	equ	step_3
st_e0	equ	step_4
st_f0	equ	step_5
st_f0s	equ	step_6
st_g0	equ	step_7
st_g0s	equ	step_8
st_a0	equ	step_9
st_a0s	equ	step_10
st_b0	equ	step_11

st_c1	equ	step_12
st_c1s	equ	step_13
st_d1	equ	step_14
st_d1s	equ	step_15
st_e1	equ	step_16
st_f1	equ	step_17
st_f1s	equ	step_18
st_g1	equ	step_19
st_g1s	equ	step_20
st_a1	equ	step_21
st_a1s	equ	step_22
st_b1	equ	step_23

st_c2	equ	step_24
st_c2s	equ	step_25
st_d2	equ	step_26
st_d2s	equ	step_27
st_e2	equ	step_28
st_f2	equ	step_29



;; The only change from the TRS-80 version: the row comes from kbdmapi,
;; the inverted copy of the last scan, rather than straight off the
;; keyboard at #38xx. "call nz,down" stays the last three bytes, which is
;; what the self-modifying key handlers depend on.

macro key addrmask,st,down
    ld  b,{st}
    ld  a,(kbdmapi + ({addrmask} >> 8))
    and {addrmask} % 256
    call nz,{down}
mend

;; Note keys work like the plain ones but also carry the id of their '*'
;; marker in C, so the down/up handlers know which key box to light up.
macro notekey addrmask,st,down,id
    ld  b,{st}
    ld  c,{id}
    ld  a,(kbdmapi + ({addrmask} >> 8))
    and {addrmask} % 256
    call nz,{down}
mend



macro key_l addrmask,st,id
    notekey {addrmask},{st},key_down_lower,{id}
mend

macro key_r addrmask,st,id
    notekey {addrmask},{st},key_down_upper,{id}
mend



;; Amstrad CPC keyboard matrix. Read line n, bit b: the key is DOWN when
;; the bit is 0, which kbdscanorg inverts, so these read like the TRS-80's.
;;
;;         bit  0     1     2     3     4     5     6      7
;;  line 0    curup currgt curdn  f9    f6    f3   enter   f.
;;  line 1    curlft copy   f7    f8    f5    f1    f2     f0
;;  line 2    clr    [     return  ]    f4   shift   \    ctrl
;;  line 3    ^      -      @     P     ;     :      /     .
;;  line 4    0      9      O     I     L     K      M     ,
;;  line 5    8      7      U     Y     H     J      N    space
;;  line 6    6      5      R     T     G     F      B     V
;;  line 7    4      3      E     W     S     D      C     X
;;  line 8    1      2     esc    Q    tab    A     caps   Z
;;  line 9    joystick / del
;;
;; BREAK does not exist on a CPC, so ESC takes its place.

k_up     equ (0<<8) | %00000001
k_right  equ (0<<8) | %00000010
k_down   equ (0<<8) | %00000100
k_left   equ (1<<8) | %00000001
k_clear  equ (2<<8) | %00000001
k_enter  equ (2<<8) | %00000100
k_shift  equ (2<<8) | %00100000
k_dash   equ (3<<8) | %00000010
k_@      equ (3<<8) | %00000100
k_P      equ (3<<8) | %00001000
k_semi   equ (3<<8) | %00010000
k_colon  equ (3<<8) | %00100000
k_slash  equ (3<<8) | %01000000
k_dot    equ (3<<8) | %10000000
k_0      equ (4<<8) | %00000001
k_9      equ (4<<8) | %00000010
k_O      equ (4<<8) | %00000100
k_I      equ (4<<8) | %00001000
k_L      equ (4<<8) | %00010000
k_K      equ (4<<8) | %00100000
k_M      equ (4<<8) | %01000000
k_comma  equ (4<<8) | %10000000
k_8      equ (5<<8) | %00000001
k_7      equ (5<<8) | %00000010
k_U      equ (5<<8) | %00000100
k_Y      equ (5<<8) | %00001000
k_H      equ (5<<8) | %00010000
k_J      equ (5<<8) | %00100000
k_N      equ (5<<8) | %01000000
k_space  equ (5<<8) | %10000000
k_6      equ (6<<8) | %00000001
k_5      equ (6<<8) | %00000010
k_R      equ (6<<8) | %00000100
k_T      equ (6<<8) | %00001000
k_G      equ (6<<8) | %00010000
k_F      equ (6<<8) | %00100000
k_B      equ (6<<8) | %01000000
k_V      equ (6<<8) | %10000000
k_4      equ (7<<8) | %00000001
k_3      equ (7<<8) | %00000010
k_E      equ (7<<8) | %00000100
k_W      equ (7<<8) | %00001000
k_S      equ (7<<8) | %00010000
k_D      equ (7<<8) | %00100000
k_C      equ (7<<8) | %01000000
k_X      equ (7<<8) | %10000000
k_1      equ (8<<8) | %00000001
k_2      equ (8<<8) | %00000010
k_break  equ (8<<8) | %00000100
k_Q      equ (8<<8) | %00001000
k_A      equ (8<<8) | %00100000
k_Z      equ (8<<8) | %10000000


init:

    call scanmarkers
    call screenupdate
    call setinstrument_lower
    call setinstrument_upper
    call renderall              ; establish the screen and its shadow copy



main:
    call kbdscanorg             ; one scan serves every test below


	key_l	k_Z,st_c0,25
	key_l	k_S,st_c0s,18
	key_l	k_X,st_d0,26
	key_l	k_D,st_d0s,19
	key_l	k_C,st_e0,27
	key_l	k_V,st_f0,28
	key_l	k_G,st_f0s,20
	key_l	k_B,st_g0,29
	key_l	k_H,st_g0s,21
	key_l	k_N,st_a0,30
	key_l	k_J,st_a0s,22
	key_l	k_M,st_b0,31
	key_l	k_comma,st_c1,32
	key_l	k_L,st_c1s,23
	key_l	k_dot,st_d1,33
	key_l	k_semi,st_d1s,24
	key_l	k_slash,st_e1,34

	key_r	k_Q,st_c1,7
	key_r	k_2,st_c1s,0
	key_r	k_W,st_d1,8
	key_r	k_3,st_d1s,1
	key_r	k_E,st_e1,9
	key_r	k_R,st_f1,10
	key_r	k_5,st_f1s,2
	key_r	k_T,st_g1,11
	key_r	k_6,st_g1s,3
	key_r	k_Y,st_a1,12
	key_r	k_7,st_a1s,4
	key_r	k_U,st_b1,13
	key_r	k_I,st_c2,14
	key_r	k_9,st_c2s,5
	key_r	k_O,st_d2,15
	key_r	k_0,st_d2s,6
	key_r	k_P,st_e2,16
	key_r	k_@,st_f2,17

	key	k_space,0,swap_channel_down

	key	k_enter,0,incr_channel_down
	key	k_shift,0,decr_channel_down

	key	k_break,0,exit

	key	k_left,0,decr_instr_down
	key	k_right,0,incr_instr_down

	key	k_up,0,incr_vol_down
	key	k_down,0,decr_vol_down

	key	k_A,0,oct1_down_down
	key	k_F,0,oct1_up_down

	key	k_1,0,oct2_down_down
	key	k_4,0,oct2_up_down

	jp	main

; In the simple case a key goes down, it self modifies so that when it goes
; up it turns off 

call_nz	equ	#C4
call_z	equ	#CC

key_down_lower:
	pop	iy; to self-modify key-down check, gets address where call nz,key_down happened 
	ld	(iy-3),call_z; trigger that op code there to a call_z, so when the key goes off, it calls key_up
	ld	(iy-2),key_up_lower % 256
	ld	(iy-1),key_up_lower >> 8

	push	bc; note_on clobbers BC; C still holds our marker id
	call note_on_lower
	pop	bc
	call	keyhilite

	jp	(iy); return to main key scan loop

key_up_lower:
	pop	iy; same idea, but swap call nz <-> call z
	ld	(iy-3),call_nz
	ld	(iy-2),key_down_lower % 256
	ld	(iy-1),key_down_lower >> 8

	push	bc
	call note_off_lower
	pop	bc
	call	keyrestore

	jp	(iy)


key_down_upper:
	pop	iy; to self-modify key-down check, gets address where call nz,key_down happened 
	ld	(iy-3),call_z
	ld	(iy-2),key_up_upper % 256
	ld	(iy-1),key_up_upper >> 8

	push	bc; note_on clobbers BC; C still holds our marker id
	call note_on_upper
	pop	bc
	call	keyhilite

	jp	(iy); return to main key scan loop

key_up_upper:
	pop	iy; same idea, but swap call nz <-> call z
	ld	(iy-3),call_nz
	ld	(iy-2),key_down_upper % 256
	ld	(iy-1),key_down_upper >> 8

	push	bc
	call note_off_upper
	pop	bc
	call	keyrestore

	jp	(iy)

note_on_lower:

  ld a,(chan1)
  ld c,#90
  add a,c
  call midiout

  call short_delay

  ld a,(oct1)
  add a,b
  call midiout

  call short_delay

  ld a,(chan1)
  ld c,a
  ld b,0
  ld ix,vol1
  add ix,bc

  ld a,(ix+0)
  call midiout

  call short_delay

  ret

note_on_upper:

  ld a,(chan2)
  ld c,#90
  add a,c
  call midiout

  call short_delay

  ld a,(oct2)
  add a,b
  call midiout

  call short_delay

  ld a,(chan2)
  ld c,a
  ld b,0
  ld ix,vol2
  add ix,bc

  ld a,(ix+0)
  call midiout

  call short_delay

  ret

note_off_lower:

  ld a,(chan1)
  ld c,#80
  add a,c
  call midiout

  call short_delay

  ld a,(oct1)
  add a,b
  call midiout

  call short_delay

  ld a,(chan1)
  ld c,a
  ld b,0
  ld ix,vol1
  add ix,bc

  ld a,(ix+0)
  call midiout

  call short_delay

  ret


note_off_upper:

  ld a,(chan2)
  ld c,#80
  add a,c
  call midiout

  call short_delay

  ld a,(oct2)
  add a,b
  call midiout

  call short_delay

  ld a,(chan2)
  ld c,a
  ld b,0
  ld ix,vol2
  add ix,bc

  ld a,(ix+0)
  call midiout

  call short_delay

  ret


exit:
    pop iy
    ;; No DOS to go back to - the organ is loaded over BASIC's program
    ;; area - so ESC resets to a clean machine.
    ei
    jp 0


oct1_up_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),oct1_up_up % 256
	ld	(iy-1),oct1_up_up >> 8

	ld a,(oct1)
	cp 96
	jp nc,oct1_up_exit

	ld b,12
	add a,b
	and #7f
	ld (oct1),a

	call screenupdate

oct1_up_exit:
	jp	(iy)

oct1_up_up:

	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),oct1_up_down % 256
	ld	(iy-1),oct1_up_down >> 8

	jp	(iy)

oct2_up_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),oct2_up_up % 256
	ld	(iy-1),oct2_up_up >> 8

	ld a,(oct2)
	cp 96
	jp nc,oct2_up_exit

	ld b,12
	add a,b
	and #7f
	ld (oct2),a

	call screenupdate

oct2_up_exit:
	jp	(iy)

oct2_up_up:

	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),oct2_up_down % 256
	ld	(iy-1),oct2_up_down >> 8

	jp	(iy)

oct1_down_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),oct1_down_up % 256
	ld	(iy-1),oct1_down_up >> 8

	ld a,(oct1)
	cp 25
	jp c,oct1_down_exit

	ld b,12
	sub b
	and #7f
	ld (oct1),a

	call screenupdate

oct1_down_exit:
	jp	(iy)


oct1_down_up:

	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),oct1_down_down % 256
	ld	(iy-1),oct1_down_down >> 8

	jp	(iy)

oct2_down_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),oct2_down_up % 256
	ld	(iy-1),oct2_down_up >> 8

	ld a,(oct2)
	cp 25
	jp c,oct2_down_exit

	ld b,12
	sub b
	and #7f
	ld (oct2),a

	call screenupdate

oct2_down_exit:
	jp	(iy)

oct2_down_up:

	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),oct2_down_down % 256
	ld	(iy-1),oct2_down_down >> 8

	jp	(iy)


swap_channel_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),swap_channel_up % 256
	ld	(iy-1),swap_channel_up >> 8

	ld a,(current)
	inc a
	and #01
	ld (current),a

	call screenupdate

	jp	(iy)

swap_channel_up:

	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),swap_channel_down % 256
	ld	(iy-1),swap_channel_down >> 8

	jp	(iy)

incr_channel_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),incr_channel_up % 256
	ld	(iy-1),incr_channel_up >> 8

	ld a,(current)
	or a
	jr z, incr_channel1

; channel 2 

	ld a, (chan2)
	inc a
	and #0f
	ld (chan2), a

	jr incr_channel_return

incr_channel1:
	ld a, (chan1)
	inc a
	and #0f
	ld (chan1), a

incr_channel_return:
	call screenupdate
	call setinstrument_lower
	call setinstrument_upper

	jp	(iy)


incr_channel_up:

	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),incr_channel_down % 256
	ld	(iy-1),incr_channel_down >> 8

	jp	(iy)

decr_channel_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),decr_channel_up % 256
	ld	(iy-1),decr_channel_up >> 8

	ld a,(current)
	or a
	jr z, decr_channel1

; channel 2 

	ld a, (chan2)
	dec a
	and #0f
	ld (chan2), a

	jr decr_channel_return

decr_channel1:
	ld a, (chan1)
	dec a
	and #0f
	ld (chan1), a

decr_channel_return:
	call screenupdate
	call setinstrument_lower
	call setinstrument_upper

	jp	(iy)

decr_channel_up:

	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),decr_channel_down % 256
	ld	(iy-1),decr_channel_down >> 8

	jp	(iy)

incr_instr_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),incr_instr_up % 256
	ld	(iy-1),incr_instr_up >> 8

	ld a,(current)
	or a
	jr z, incr_instr1

; channel 2 

	ld a, (chan2)
	ld c, a
	ld b, 0
	ld ix, instr2
	jr incr_instr_return

incr_instr1:

	ld a, (chan1)
	ld c, a
	ld b, 0
	ld ix, instr1

incr_instr_return:

	add ix, bc

	ld a, (ix+0)
	inc a
	and #7f
	ld (ix+0), a

	call screenupdate
	call setinstrument_lower
	call setinstrument_upper

	jp	(iy)

incr_instr_up:

	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),incr_instr_down % 256
	ld	(iy-1),incr_instr_down >> 8

	jp	(iy)

decr_instr_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),decr_instr_up % 256
	ld	(iy-1),decr_instr_up >> 8

	ld a,(current)
	or a
	jr z, decr_instr1

; channel 2 

	ld a, (chan2)
	ld c, a
	ld b, 0
	ld ix, instr2
	jr decr_instr_return

decr_instr1:

	ld a, (chan1)
	ld c, a
	ld b, 0
	ld ix, instr1

decr_instr_return:

	add ix, bc

	ld a, (ix+0)
	dec a
	and #7f
	ld (ix+0), a

	call screenupdate
	call setinstrument_lower
	call setinstrument_upper

	jp	(iy)


decr_instr_up:

	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),decr_instr_down % 256
	ld	(iy-1),decr_instr_down >> 8

	jp	(iy)

incr_vol_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),incr_vol_up % 256
	ld	(iy-1),incr_vol_up >> 8

	ld a,(current)
	or a
	jr z, incr_vol1

; channel 2 

	ld a, (chan2)
	ld c, a
	ld b, 0
	ld ix, vol2
	jr incr_vol_return

incr_vol1:

	ld a, (chan1)
	ld c, a
	ld b, 0
	ld ix, vol1

incr_vol_return:

	add ix, bc

	ld a, (ix+0)
	inc a
	and #7f
	ld (ix+0), a

	call screenupdate

	jp	(iy)

incr_vol_up:

	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),incr_vol_down % 256
	ld	(iy-1),incr_vol_down >> 8

	jp	(iy)

decr_vol_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),decr_vol_up % 256
	ld	(iy-1),decr_vol_up >> 8

	ld a,(current)
	or a
	jr z, decr_vol1

; channel 2 

	ld a, (chan2)
	ld c, a
	ld b, 0
	ld ix, vol2
	jr decr_vol_return

decr_vol1:

	ld a, (chan1)
	ld c, a
	ld b, 0
	ld ix, vol1

decr_vol_return:

	add ix, bc

	ld a, (ix+0)
	dec a
	and #7f
	ld (ix+0), a

	call screenupdate

	jp	(iy)

decr_vol_up:

	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),decr_vol_down % 256
	ld	(iy-1),decr_vol_down >> 8

	jp	(iy)



;; Byte pacing is midiout's job on this machine - MIDI is 31250 baud, so
;; a byte owns the wire for 320 us and the wait has to cover every byte,
;; including ones sent nowhere near here. This is left only because the
;; original calls it between sends.
short_delay:
    ld de,4
sdloop:
    dec de
    ld a,d
    or e
    jp nz,sdloop
    ret


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

showvalue:; input ix mem cell, hl screen location 
	ld c,(ix+0)
	call byte2ascii
	ld (hl),d
	inc hl
	ld (hl),e
	inc hl
	inc hl

ret



screenupdate:
    call screenupdate0
    ld hl,VRAM+14*64            ; the status row is the only thing it
    ld bc,64                    ; touches, and nothing else redraws it
    jp renderrun

screenupdate0:

	ld hl,#3c00+14*64+35

	ld ix,oct1
	call showvalue

	ld ix,chan1
	call showvalue

	ld ix,instr1
	ld a,(chan1)
	ld c,a
	ld b,0
	add ix,bc
	call showvalue


	ld ix,vol1
	ld a,(chan1)
	ld c,a
	ld b,0
	add ix,bc
	call showvalue

	inc hl
	inc hl
	inc hl
	inc hl

	ld ix,oct2
	call showvalue

	ld ix,chan2
	call showvalue

	ld ix,instr2
	ld a,(chan2)
	ld c,a
	ld b,0
	add ix,bc
	call showvalue

	ld ix,vol2
	ld a,(chan2)
	ld c,a
	ld b,0
	add ix,bc
	call showvalue

;;
;;
;;

	ld a,(current)
	or a
	jr nz, showcur2

	ld hl,#3c00+14*64+34
	ld (hl),60
	ld hl,#3c00+14*64+46
	ld (hl),62

	ld hl,#3c00+14*64+50
	ld (hl),' '
	ld hl,#3c00+14*64+62
	ld (hl),' '

	ret

showcur2:

	ld hl,#3c00+14*64+34
	ld (hl),' '
	ld hl,#3c00+14*64+46
	ld (hl),' '


	ld hl,#3c00+14*64+50
	ld (hl),60
	ld hl,#3c00+14*64+62
	ld (hl),62

	ret


setinstrument_lower:

	ld b,#c0
	ld a,(chan1)
	add a,b
	call midiout; change instrument for channel
	call short_delay

	ld ix,instr1
	ld a,(chan1)
	ld c,a
	ld b,0
	add ix,bc

	ld a,(ix+0); instrument for selected channel
	call midiout; change instrument 
	call short_delay

	ret

setinstrument_upper:

	ld b,#c0
	ld a,(chan2)
	add a,b
	call midiout; change instrument for channel
	call short_delay

	ld ix,instr2
	ld a,(chan2)
	ld c,a
	ld b,0
	add ix,bc

	ld a,(ix+0); instrument for selected channel
	call midiout; change instrument 
	call short_delay

	ret


;
; ---- On-screen key highlighting -------------------------------------------
;
; Each key box in the artwork carries a '*' marker.  scanmarkers walks the
; art once at startup, notes where every marker sits on screen and how wide
; its box is, then blanks the marker.  Pressing a key fills that box with
; solid graphics blocks; releasing it copies the original text back out of
; the title image, which is still sitting untouched in RAM at "title".
;
; The TRS-80 has no reverse-video attribute for text on either the Model I
; or the Model III - $C0-$FF is a symbol set on the III and a copy of the
; graphics blocks on the I - so a filled block is as close to inverse video
; as the hardware gets.
;

NKEYS	 equ	35; '*' markers in the artwork, one per note key
KBROW	 equ	3; first row of art carrying markers
KBROWS	 equ	8; rows of art to scan (3..10)
MAXFIELD equ	8; widest box we are willing to light up

;; The CPC's mode 2 has two colours and no attributes, so a filled cell is
;; as close to inverse video as this gets - the same answer the TRS-80
;; reached for a different reason. Character #8F is the only solid block
;; in the CPC font; checked against the ROM, it is the one glyph whose
;; eight scanlines are all #FF.
HILITE   equ    #8F


scanmarkers:
	ld	hl,#3c00+KBROW*64
	ld	ix,keytab
	ld	bc,KBROWS*64
scan1:
	ld	a,(hl)
	cp	42
	jr	nz,scan5

	push	bc
	ld	(hl),' '; blank the marker on screen ...
	ld	bc,title-#3c00
	push	hl
	add	hl,bc
	ld	(hl),' '; ... and in the copy keyrestore reads back
	pop	hl

	ld	(ix+0),l; where this box starts
	ld	(ix+1),h

	push	hl; how wide it is: marker up to the next '|'
	ld	b,0
scan2:
	inc	hl
	inc	b
	ld	a,b
	cp	MAXFIELD
	jr	nc,scan3; runaway guard
	ld	a,(hl)
	cp	124
	jr	nz,scan2
scan3:
	ld	(ix+2),b
	pop	hl

	ld	bc,3
	add	ix,bc
	pop	bc
scan5:
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,scan1
	ret

; Entry: C = marker id.  Exit: HL = screen address, B = width (0 = no box).

keyaddr:
	ld	a,c
	add a,a
	add a,c; 3 bytes per entry; id <= 34, so this stays 8-bit
	ld	e,a
	ld	d,0
	ld	hl,keytab
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	b,(hl)
	ex	de,hl
	ret


;; Both of these push their own pixels. MIDORG has no main loop doing an
;; incremental screen scan - it is a tight keyboard poll - and a key that
;; lights up 26 ms after you press it is not an organ.
keyhilite:
    call    keyaddr
    ld  a,b
    or  a
    ret z
    push    hl
    push    bc
    ld  a,HILITE
keyhi1:
    ld  (hl),a
    inc hl
    djnz    keyhi1
    pop bc
    pop hl
    ld  c,b
    ld  b,0
    jp  renderrun



keyrestore:
    call    keyaddr
    ld  a,b
    or  a
    ret z
    ld  d,h         ; screen is the destination
    ld  e,l
    push    de
    ld  de,title-VRAM
    add hl,de       ; the original text is this far along
    pop de
    ld  c,a
    ld  b,0
    push    de
    push    bc
    ldir
    pop bc
    pop hl
    jp  renderrun


keytab:                         ; screen address + width, per marker
    defs NKEYS*3


    save "MIDORG.BIN", #0800, $-#0800, AMSDOS, start
