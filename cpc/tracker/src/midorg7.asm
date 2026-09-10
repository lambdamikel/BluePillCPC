;
; midorg.z - MIDI Organ for TRS-80 
;
	org	$5200

@EXIT		equ	$402d
@KEY    	equ 	$0049 

title:	ascii   "** MIDI/80 ORGAN V1.1 - (C)2026 G.PHILLIPS+LAMBDAMIKEL+CLAUDE **"
	ascii   "----------------------------------------------------------------"
	ascii   "   _____ _____       _____ _____ _____       _____ _____        "
	ascii   "   |*c'# |*d'#|    |*f'# |*g'# |*a'# |     |*c''#|*d''#|        "
	ascii   "  _|__2__|__3_|____|__5__|__6__|__7__|_____|__9__|__0__|_ ____  "
	ascii   " |*c'|* d' |*e' |*f' |* g' |* a' |* b' |*c'' |*d'' |*e'' |*f''| "
	ascii   " |_Q_|__W__|_E__|_R__|__T__|__Y__|__U__|__I__|__O__|__P__|__@_| "
	ascii   "     _____ _____       _____ _____ _____       _____ _____      "
	ascii	"    |* c# |* d# |     |* f# |* g# |* a# |     |*c'# |*d'# |     "
	ascii   "   _|__S__|__D__|_____|__G__|__H__|__J__|_____|__L__|__;__|_    "
	ascii   "  |*c |* d  |* e  |* f  |* g  |* a  |* b  |*c'  |*d'  |*e'  |   " 
	ascii	"  |_Z_|__X__|__C__|__V__|__B__|__N__|__M__|__,__|__.__|__/__|   "
	ascii   "                                                                "
	ascii   "BREAK:QUIT L/R:INSTR UP/DOWN:VOL SPACE/ENT:CHANNEL AF/14:OCT +/-" 
	ascii   "CUR <OCT/MIDI CHANNEL/INSTR/VOL>: <XX/XX/XX/XX> -  XX/XX/XX/XX  "
	ascii   "----------------------------------------------------------------"

title_len equ $-title


current	byte 0
chan1	byte 0
chan2	byte 1
oct1	byte 48
oct2	byte 60
instr1	byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
instr2	byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
vol1	byte 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127
vol2	byte 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127, 127

start:

	in  a,($ff)
	or  a,$10 		; enable IO on Model III 
	; and a,~$20 		; disable video wait states M III 
	and a,~$40 		; slode mode M4 
	out ($ec),a

	ld	hl,title
	ld	de,$3c00
	ld	bc,title_len
	ldir
	
	
defstep	macro	n,stp
step_&n	equ	stp
	endm

; Get the MIDI note numbers for 32 notes as step_0 .. step_31 

	nt = 0
	note = 0 		; we'll add octave offsets... 
	rept	32

	defstep	%nt,%note

	nt++
	note++ 

	endm

; Define these sensibly

st_c0	equ	step_0
st_c0@	equ	step_1
st_d0	equ	step_2
st_d0@	equ	step_3
st_e0	equ	step_4
st_f0	equ	step_5
st_f0@	equ	step_6
st_g0	equ	step_7
st_g0@	equ	step_8
st_a0	equ	step_9
st_a0@	equ	step_10
st_b0	equ	step_11

st_c1	equ	step_12
st_c1@	equ	step_13
st_d1	equ	step_14
st_d1@	equ	step_15
st_e1	equ	step_16
st_f1	equ	step_17
st_f1@	equ	step_18
st_g1	equ	step_19
st_g1@	equ	step_20
st_a1	equ	step_21
st_a1@	equ	step_22
st_b1	equ	step_23

st_c2	equ	step_24
st_c2@	equ	step_25
st_d2	equ	step_26
st_d2@	equ	step_27
st_e2	equ	step_28
st_f2	equ	step_29


key	macro	addrmask,st,down
	ld	b,st ;; changed to b by MW
	ld	a,(addrmask >> 8)
	and	addrmask % $100
	call	nz,down
	endm

; Note keys work like the plain ones but also carry the id of their '*'
; marker in C, so the down/up handlers know which key box to light up.
; The call stays the last three bytes so the (iy-3) self-modification below
; is unaffected.

notekey	macro	addrmask,st,down,id
	ld	b,st
	ld	c,id
	ld	a,(addrmask >> 8)
	and	addrmask % $100
	call	nz,down
	endm

key_l	macro	addrmask,st,id
	notekey	addrmask,st,key_down_lower,id
	endm

key_r	macro	addrmask,st,id
	notekey	addrmask,st,key_down_upper,id
	endm

; Model 1 keyboard matrix.
;        1   2   4   8  16  32  64  128
; $3801	 @   A   B   C   D   E   F   G
; $3802	 H   I   J   K   L   M   N   O
; $3804	 P   Q   R   S   T   U   V   W
; $3808	 X   Y   Z
; $3810	 0   1   2   3   4   5   6   7
; $3820	 8   9   :   ;   ,   -   .   /
; $3840	ENT CLR BRK UP   DN  LT  RT SPC
; $3880	SFT

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

init:

	call scanmarkers
	call screenupdate
	call setinstrument_lower
	call setinstrument_upper
	
main:	
	key_l	k_Z,st_c0,25
	key_l	k_S,st_c0@,18
	key_l	k_X,st_d0,26
	key_l	k_D,st_d0@,19
	key_l	k_C,st_e0,27
	key_l	k_V,st_f0,28
	key_l	k_G,st_f0@,20
	key_l	k_B,st_g0,29
	key_l	k_H,st_g0@,21
	key_l	k_N,st_a0,30
	key_l	k_J,st_a0@,22
	key_l	k_M,st_b0,31
	key_l	k_comma,st_c1,32
	key_l	k_L,st_c1@,23
	key_l	k_dot,st_d1,33
	key_l	k_semi,st_d1@,24
	key_l	k_slash,st_e1,34

	key_r	k_Q,st_c1,7
	key_r	k_2,st_c1@,0
	key_r	k_W,st_d1,8
	key_r	k_3,st_d1@,1
	key_r	k_E,st_e1,9
	key_r	k_R,st_f1,10
	key_r	k_5,st_f1@,2
	key_r	k_T,st_g1,11
	key_r	k_6,st_g1@,3
	key_r	k_Y,st_a1,12
	key_r	k_7,st_a1@,4
	key_r	k_U,st_b1,13
	key_r	k_I,st_c2,14
	key_r	k_9,st_c2@,5
	key_r	k_O,st_d2,15
	key_r	k_0,st_d2@,6
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

call_nz	equ	$C4
call_z	equ	$CC

key_down_lower:
	pop	iy		; to self-modify key-down check, gets address where call nz,key_down happened 
	ld	(iy-3),call_z	; trigger that op code there to a call_z, so when the key goes off, it calls key_up
	ld	(iy-2),low(key_up_lower)
	ld	(iy-1),high(key_up_lower)

	push	bc		; note_on clobbers BC; C still holds our marker id
	call note_on_lower
	pop	bc
	call	keyhilite

	jp	(iy)		; return to main key scan loop

key_up_lower:
	pop	iy		; same idea, but swap call nz <-> call z
	ld	(iy-3),call_nz
	ld	(iy-2),low(key_down_lower)
	ld	(iy-1),high(key_down_lower)

	push	bc
	call note_off_lower 
	pop	bc
	call	keyrestore

	jp	(iy)		


key_down_upper:
	pop	iy		; to self-modify key-down check, gets address where call nz,key_down happened 
	ld	(iy-3),call_z
	ld	(iy-2),low(key_up_upper)
	ld	(iy-1),high(key_up_upper)

	push	bc		; note_on clobbers BC; C still holds our marker id
	call note_on_upper
	pop	bc
	call	keyhilite

	jp	(iy)		; return to main key scan loop

key_up_upper:
	pop	iy		; same idea, but swap call nz <-> call z
	ld	(iy-3),call_nz
	ld	(iy-2),low(key_down_upper)
	ld	(iy-1),high(key_down_upper)

	push	bc
	call note_off_upper
	pop	bc
	call	keyrestore

	jp	(iy)		

note_on_lower: 

  ld a,(chan1)
  ld c,$90
  add a, c
  out (8),a
  
  call short_delay

  ld a,(oct1)	
  add a, b
  out (8),a
  
  call short_delay

  ld a,(chan1)
  ld c,a
  ld b,0
  ld ix,vol1
  add ix,bc

  ld a,(ix)
  out (8),a
  
  call short_delay  

  ret

note_on_upper:

  ld a,(chan2)
  ld c,$90
  add a, c
  out (8),a
  
  call short_delay

  ld a,(oct2)	
  add a, b	
  out (8),a
  
  call short_delay  
  
  ld a,(chan2)
  ld c,a
  ld b,0
  ld ix,vol2
  add ix,bc

  ld a,(ix)
  out (8),a
  
  call short_delay  

  ret

note_off_lower: 

  ld a,(chan1)
  ld c,$80
  add a, c
  out (8),a
  
  call short_delay

  ld a,(oct1)	
  add a, b
  out (8),a
  
  call short_delay  

  ld a,(chan1)
  ld c,a
  ld b,0
  ld ix,vol1
  add ix,bc

  ld a,(ix)
  out (8),a  
  
  call short_delay  

  ret  


note_off_upper: 

  ld a,(chan2)
  ld c,$80
  add a, c
  out (8),a
  
  call short_delay
  
  ld a,(oct2)	
  add a, b
  out (8),a
  
  call short_delay  

  ld a,(chan2)
  ld c,a
  ld b,0
  ld ix,vol2
  add ix,bc

  ld a,(ix)
  out (8),a  
  
  call short_delay  

  ret  

exit:
	pop	iy
	call @EXIT	

oct1_up_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),low(oct1_up_up)
	ld	(iy-1),high(oct1_up_up)

	ld a,(oct1)
	cp 96
	jp nc,oct1_up_exit
	
	ld b,12
	add a,b
	and $7f
	ld (oct1),a

	call screenupdate
	
oct1_up_exit:	
	jp	(iy)

oct1_up_up:

	pop	iy

	ld	(iy-3),call_nz	
	ld	(iy-2),low(oct1_up_down)
	ld	(iy-1),high(oct1_up_down)

	jp	(iy)

oct2_up_down:
	
	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),low(oct2_up_up)
	ld	(iy-1),high(oct2_up_up)

	ld a,(oct2)
	cp 96
	jp nc,oct2_up_exit

	ld b,12
	add a,b
	and $7f
	ld (oct2),a

	call screenupdate	

oct2_up_exit:	
	jp	(iy)	

oct2_up_up:

	pop	iy

	ld	(iy-3),call_nz	
	ld	(iy-2),low(oct2_up_down)
	ld	(iy-1),high(oct2_up_down)

	jp	(iy)

oct1_down_down:
	
	pop	iy
	
	ld	(iy-3),call_z
	ld	(iy-2),low(oct1_down_up)
	ld	(iy-1),high(oct1_down_up)
	
	ld a,(oct1)
	cp 25
	jp c,oct1_down_exit

	ld b,12
	sub a,b
	and $7f
	ld (oct1),a

	call screenupdate	

oct1_down_exit:	
	jp	(iy)


oct1_down_up:

	pop	iy

	ld	(iy-3),call_nz	
	ld	(iy-2),low(oct1_down_down)
	ld	(iy-1),high(oct1_down_down)

	jp	(iy)
	
oct2_down_down:
	
	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),low(oct2_down_up)
	ld	(iy-1),high(oct2_down_up)	
	
	ld a,(oct2)
	cp 25
	jp c,oct2_down_exit

	ld b,12
	sub a,b
	and $7f
	ld (oct2),a

	call screenupdate	

oct2_down_exit:	
	jp	(iy)	

oct2_down_up:

	pop	iy

	ld	(iy-3),call_nz	
	ld	(iy-2),low(oct2_down_down)
	ld	(iy-1),high(oct2_down_down)

	jp	(iy)

	
swap_channel_down:
		
	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),low(swap_channel_up)
	ld	(iy-1),high(swap_channel_up)	
	
	ld a,(current)
	inc a
	and $01
	ld (current),a

	call screenupdate	
	
	jp	(iy)

swap_channel_up:
		
	pop	iy

	ld	(iy-3),call_nz	
	ld	(iy-2),low(swap_channel_down)
	ld	(iy-1),high(swap_channel_down)

	jp	(iy)

incr_channel_down:
		
	pop	iy
	
	ld	(iy-3),call_z
	ld	(iy-2),low(incr_channel_up)
	ld	(iy-1),high(incr_channel_up)
	
	ld a,(current)
	or a
	jr z, incr_channel1

	; channel 2 

	ld a, (chan2) 
	inc a
	and $0f
	ld (chan2), a

	jr incr_channel_return

incr_channel1:
	ld a, (chan1) 
	inc a
	and $0f
	ld (chan1), a
		
incr_channel_return: 
	call screenupdate
	call setinstrument_lower
	call setinstrument_upper
	
	jp	(iy)

	
incr_channel_up:
		
	pop	iy
	
	ld	(iy-3),call_nz	
	ld	(iy-2),low(incr_channel_down)
	ld	(iy-1),high(incr_channel_down)
	
	jp	(iy)

decr_channel_down:
	
	pop	iy
	
	ld	(iy-3),call_z
	ld	(iy-2),low(decr_channel_up)
	ld	(iy-1),high(decr_channel_up)
	
	ld a,(current)
	or a
	jr z, decr_channel1

	; channel 2 

	ld a, (chan2) 
	dec a
	and $0f
	ld (chan2), a

	jr decr_channel_return

decr_channel1:
	ld a, (chan1) 
	dec a
	and $0f
	ld (chan1), a
		
decr_channel_return: 
	call screenupdate
	call setinstrument_lower
	call setinstrument_upper

	jp	(iy)
	
decr_channel_up:
	
	pop	iy
	
	ld	(iy-3),call_nz	
	ld	(iy-2),low(decr_channel_down)
	ld	(iy-1),high(decr_channel_down)
	
	jp	(iy)

incr_instr_down:
	
	pop	iy
	
	ld	(iy-3),call_z
	ld	(iy-2),low(incr_instr_up)
	ld	(iy-1),high(incr_instr_up)

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

	ld a, (ix) 
	inc a
	and $7f
	ld (ix), a
	
	call screenupdate
	call setinstrument_lower
	call setinstrument_upper

	jp	(iy)

incr_instr_up:
	
	pop	iy
	
	ld	(iy-3),call_nz
	ld	(iy-2),low(incr_instr_down)
	ld	(iy-1),high(incr_instr_down)

	jp	(iy)

decr_instr_down:
	
	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),low(decr_instr_up)
	ld	(iy-1),high(decr_instr_up)
	
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

	ld a, (ix) 
	dec a
	and $7f
	ld (ix), a
	
	call screenupdate
	call setinstrument_lower
	call setinstrument_upper

	jp	(iy)


decr_instr_up:
	
	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),low(decr_instr_down)
	ld	(iy-1),high(decr_instr_down)

	jp	(iy)
	
incr_vol_down:

	pop	iy

	ld	(iy-3),call_z
	ld	(iy-2),low(incr_vol_up)
	ld	(iy-1),high(incr_vol_up)

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

	ld a, (ix) 
	inc a
	and $7f
	ld (ix), a
	
	call screenupdate

	jp	(iy)

incr_vol_up:

	pop	iy

	ld	(iy-3),call_nz
	ld	(iy-2),low(incr_vol_down)
	ld	(iy-1),high(incr_vol_down)

	jp	(iy)

decr_vol_down:
	
	pop	iy
	
	ld	(iy-3),call_z
	ld	(iy-2),low(decr_vol_up)
	ld	(iy-1),high(decr_vol_up)

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

	ld a, (ix) 
	dec a
	and $7f
	ld (ix), a
	
	call screenupdate	
	
	jp	(iy)

decr_vol_up:

	pop	iy

	ld	(iy-3),call_nz	
	ld	(iy-2),low(decr_vol_down)
	ld	(iy-1),high(decr_vol_down)

	jp	(iy)

	
short_delay:
    ld de,$0010
loop: 
    dec de
    ld a,d
    or e
    jp nz,loop
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

showvalue:  ; input ix mem cell, hl screen location 
	ld c,(ix)
	call byte2ascii
	ld (hl),d
	inc hl
	ld (hl),e
	inc hl
	inc hl

ret


screenupdate:
	ld hl,$3c00+14*64+35

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

	ld hl,$3c00+14*64+34
	ld (hl),'<'
	ld hl,$3c00+14*64+46
	ld (hl),'>'

	ld hl,$3c00+14*64+50
	ld (hl),' '
	ld hl,$3c00+14*64+62
	ld (hl),' '

	ret

showcur2:

	ld hl,$3c00+14*64+34
	ld (hl),' '
	ld hl,$3c00+14*64+46
	ld (hl),' '


	ld hl,$3c00+14*64+50
	ld (hl),'<'
	ld hl,$3c00+14*64+62
	ld (hl),'>'
	
	ret


setinstrument_lower:

	ld b,$c0
	ld a,(chan1)
	add a,b
	out (8),a  ; change instrument for channel
	call short_delay

	ld ix,instr1
	ld a,(chan1)
	ld c,a
	ld b,0
	add ix,bc

	ld a,(ix) ; instrument for selected channel
	out (8),a  ; change instrument 
	call short_delay
 
	ret

setinstrument_upper:

	ld b,$c0
	ld a,(chan2)
	add a,b
	out (8),a  ; change instrument for channel
	call short_delay

	ld ix,instr2
	ld a,(chan2)
	ld c,a
	ld b,0
	add ix,bc

	ld a,(ix) ; instrument for selected channel
	out (8),a  ; change instrument 
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

NKEYS	 equ	35		; '*' markers in the artwork, one per note key
KBROW	 equ	3		; first row of art carrying markers
KBROWS	 equ	8		; rows of art to scan (3..10)
MAXFIELD equ	8		; widest box we are willing to light up
HILITE	 equ	128+63		; all six graphics blocks set = solid cell

scanmarkers:
	ld	hl,$3c00+KBROW*64
	ld	ix,keytab
	ld	bc,KBROWS*64
scan1:
	ld	a,(hl)
	cp	'*'
	jr	nz,scan5

	push	bc
	ld	(hl),' '	; blank the marker on screen ...
	ld	bc,title-$3c00
	push	hl
	add	hl,bc
	ld	(hl),' '	; ... and in the copy keyrestore reads back
	pop	hl

	ld	(ix),l		; where this box starts
	ld	(ix+1),h

	push	hl		; how wide it is: marker up to the next '|'
	ld	b,0
scan2:
	inc	hl
	inc	b
	ld	a,b
	cp	MAXFIELD
	jr	nc,scan3	; runaway guard
	ld	a,(hl)
	cp	'|'
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
	add	a,a
	add	a,c		; 3 bytes per entry; id <= 34, so this stays 8-bit
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

keyhilite:
	call	keyaddr
	ld	a,b
	or	a
	ret	z
	ld	a,HILITE
keyhi1:
	ld	(hl),a
	inc	hl
	djnz	keyhi1
	ret

keyrestore:
	call	keyaddr
	ld	a,b
	or	a
	ret	z
	ld	d,h		; screen is the destination
	ld	e,l
	push	de
	ld	de,title-$3c00
	add	hl,de		; the original text is this far along
	pop	de
	ld	c,a
	ld	b,0
	ldir
	ret

keytab:				; screen address + width, per marker
	rept	NKEYS
	defw	0
	defb	0
	endm

  end start
