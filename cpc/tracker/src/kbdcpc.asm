;; ---------------------------------------------------------------
;; TRACKER/CPC - keyboard
;;
;; The TRS-80's matrix is memory mapped: "ld a,(#3801)" and you have a
;; row. The CPC's sits behind the PSG, reached through the 8255 PPI:
;;      #F4xx  PPI port A   - PSG data
;;      #F6xx  PPI port C   - PSG control in bits 7,6; keyboard row in 0..3
;;      #F7xx  PPI control
;; PSG control bits: 00 inactive, 01 read, 10 write, 11 select register.
;;
;; The expensive setup (point the PSG at register 14, turn port A round)
;; happens once per scan; each of the ten rows then costs one OUT to
;; select it and one IN to read it. A pressed key reads as 0. 323 us for
;; the lot, so the whole matrix is sampled once per main loop pass and
;; every later question - "is SPACE down?", "what was typed?" - is
;; answered from the copy for free. On the TRS-80 those were separate
;; memory reads; here one scan serves them all.
;;
;; No di/ei: the tracker runs with interrupts off throughout, so nothing
;; else is talking to the PSG.
;;
;; The keys TRACKER wants all exist on a CPC in the same shift relation
;; they had on a TRS-80 - ! is SHIFT-1, " is SHIFT-2, # SHIFT-3,
;; & SHIFT-6, ' SHIFT-7, * SHIFT-:, + SHIFT-;, = SHIFT--, ? SHIFT-/ -
;; so the tables below hand TRACKER the very same ASCII codes and almost
;; none of its comparisons had to change.
;;
;; TWO CPC-NATIVE ADDITIONS, because this machine has keys the TRS-80
;; did not and it is strange not to use them:
;;
;;   the ARROW KEYS move the edit cursor. On the TRS-80 they carried the
;;   drum number and the bar position, but the bar position is already on
;;   A and D, so only the drum number needed a new home: SHIFT with the
;;   left and right arrows, which is why KDRUMDOWN/KDRUMUP exist.
;;
;;   COPY sets the note under the cursor and sounds it, the same as ENTER.
;;
;; Note the arrows keep sending KCURLEFT/KCURRIGHT and the *meaning* is
;; changed in TRACKER's key dispatch instead. That matters: the song
;; editor has its own dispatch and moves its cursor on those same two
;; codes, so it goes on working untouched.
;; ---------------------------------------------------------------

;; Consecutive empty scans required before the same key may be reported
;; again; ~20 ms of quiet, which settles contact bounce and is far below
;; anything a player can type. The main loop passes about every 1.6 ms.
KBDSETTLE equ 12

;; Two codes of our own, for the functions the arrow keys used to carry.
;; They are outside ASCII and outside every code TRACKER already tests.
KDRUMDOWN equ 3
KDRUMUP   equ 4

;; matrix positions used directly (keynumber = line*8 + bit)
KROW_CLR    equ 2                  ; line 2 bit 0
KBIT_CLR    equ %00000001
KROW_RET    equ 2                  ; line 2 bit 2
KBIT_RET    equ %00000100
KROW_SPACE  equ 5                  ; line 5 bit 7
KBIT_SPACE  equ %10000000
KROW_COPY   equ 1                  ; line 1 bit 1 - COPY, a second ENTER
KBIT_COPY   equ %00000010

;; --- kbdraw: the whole matrix into kbdmap. ~323 us. ----------------
kbdraw:
    ld bc,#F782                 ; PPI control: port A output
    out (c),c
    ld bc,#F40E                 ; port A = 14, the PSG's I/O port A register
    out (c),c
    ld bc,#F6C0                 ; port C = select-register mode
    out (c),c
    ld bc,#F600                 ; ... then inactive, latching the choice
    out (c),c
    ld bc,#F792                 ; PPI control: port A input, ready to read
    out (c),c

    ld hl,kbdmap
    ld d,10                     ; ten rows
    ld e,#40                    ; PSG read mode, row 0
kbdrow:
    ld bc,#F600
    ld c,e
    out (c),c                   ; select this row
    ld b,#F4
    in a,(c)                    ; and read it
    ld (hl),a
    inc hl
    inc e
    dec d
    jr nz,kbdrow

    ld bc,#F782                 ; hand the PPI back the way the firmware wants
    out (c),c
    ld bc,#F600
    out (c),c
    ret

;; --- kbdkey: decode the last kbdraw. -------------------------------
;; Returns ASCII in a, or 0 for "no new key". A key must be released
;; before it reports again: deliberately no typematic repeat, because
;; holding a toggle key such as P would otherwise flip play on and off
;; many times a second.
;; Clobbers a, bc, de, hl - exactly as the TRS-80 routine did.
kbdkey:
    ld hl,kbdmap+2              ; SHIFT and CONTROL live on line 2 and
    ld a,(hl)                   ; must not be found as "the key pressed"
    ld c,a
    or %10100000
    ld (hl),a
    ld hl,kbdmap+8              ; CAPS LOCK likewise, on line 8
    ld a,(hl)
    or %01000000
    ld (hl),a

    xor a
    bit 5,c                     ; 0 = shift held
    jr nz,kkns
    inc a
kkns:
    ld (kbdshift),a

    ld hl,kbdmap
    ld e,0                      ; line number
    ld b,10
kkrow:
    ld a,(hl)
    inc a                       ; #FF (nothing down) -> 0
    jr nz,kkfound
    inc hl
    inc e
    djnz kkrow

    ;; Nothing held. Let the latch go, but only once the contacts have
    ;; stayed open for KBDSETTLE scans running, so bounce cannot turn
    ;; one press into several.
    ld a,(kbdsettlec)
    or a
    ret z                       ; already settled, latch clear, a = 0
    dec a
    ld (kbdsettlec),a
    jr nz,kkstl                 ; still settling: hold the latch
    ld (lastkey),a              ; settled: a is 0, release the latch
    ret
kkstl:
    xor a
    ret

kkfound:
    ld a,(hl)                   ; lowest ZERO bit gives the column
    ld d,0
kkbit:
    rra
    jr nc,kkgot
    inc d
    jr kkbit

kkgot:
    ld a,KBDSETTLE              ; contacts closed: restart the settle timer
    ld (kbdsettlec),a
    ld a,e                      ; keynumber = line*8 + column
    add a,a
    add a,a
    add a,a
    add a,d
    ld l,a
    ld h,0

    ld de,kbdtab
    ld a,(kbdshift)
    or a
    jr z,kkplain
    ld de,kbdtabsh
kkplain:
    add hl,de
    ld a,(hl)
    or a
    ret z                       ; unmapped matrix position

    ld hl,lastkey
    cp (hl)
    jr z,kkheld                 ; still the same key: report nothing
    ld (hl),a                   ; a new key: latch it and report it
    ret
kkheld:
    xor a
    ret

;; sample and decode in one go, for the places that are not the main loop
kbdscan:
    call kbdraw
    jr kbdkey

;; waitkey -- wait for a keypress. The first loop insists the keyboard
;; is fully released and settled, so the press that got us here cannot
;; be read a second time and dismiss the very page it opened.
waitkey:
    call kbdscan
    ld a,(lastkey)
    or a
    jr nz,waitkey
waitkey1:
    call kbdscan
    or a
    jr z,waitkey1
    ret

;; ---------------------------------------------------------------
;; CPC keynumber -> the ASCII TRACKER expects. 80 entries, line*8+bit.
;; 0 means "not a key TRACKER uses".
;; ---------------------------------------------------------------
kbdtab:                          ; unshifted
    ;   0 curup      1 curright   2 curdown    3 f9
    defb KCURUP,     KCURRIGHT,   KCURDOWN,    0
    ;   4 f6         5 f3         6 enter      7 f.
    defb 0,          0,           13,          '.'
    ;   8 curleft    9 copy      10 f7        11 f8
    defb KCURLEFT,   13,          0,           0
    ;  12 f5        13 f1        14 f2        15 f0
    defb 0,          0,           0,           0
    ;  16 clr       17 [         18 return    19 ]
    defb 31,         0,           13,          0
    ;  20 f4        21 shift     22 \         23 control
    defb 0,          0,           0,           0
    ;  24 ^         25 -         26 @         27 P
    defb 0,          '-',         '@',         'P'
    ;  28 ;         29 :         30 /         31 .
    defb ';',        ':',         '/',         '.'
    ;  32 0         33 9         34 O         35 I
    defb '0',        '9',         'O',         'I'
    ;  36 L         37 K         38 M         39 ,
    defb 'L',        'K',         'M',         ','
    ;  40 8         41 7         42 U         43 Y
    defb '8',        '7',         'U',         'Y'
    ;  44 H         45 J         46 N         47 space
    defb 'H',        'J',         'N',         32
    ;  48 6         49 5         50 R         51 T
    defb '6',        '5',         'R',         'T'
    ;  52 G         53 F         54 B         55 V
    defb 'G',        'F',         'B',         'V'
    ;  56 4         57 3         58 E         59 W
    defb '4',        '3',         'E',         'W'
    ;  60 S         61 D         62 C         63 X
    defb 'S',        'D',         'C',         'X'
    ;  64 1         65 2         66 esc       67 Q
    defb '1',        '2',         0,           'Q'
    ;  68 tab       69 A         70 caps      71 Z
    defb 0,          'A',         0,           'Z'
    ;  72..78 joystick                        79 del
    defb 0,0,0,0,0,0,0,                       31

kbdtabsh:                        ; shifted
    ;   0 curup      1 curright   2 curdown    3 f9
    defb KCURUP,     KDRUMUP,     KCURDOWN,    0
    defb 0,          0,           13,          '.'
    ;   8 curleft    9 copy      10 f7        11 f8
    defb KDRUMDOWN,  13,          0,           0
    defb 0,          0,           0,           0
    defb 31,         0,           13,          0
    defb 0,          0,           0,           0
    ;  24 ^         25 - -> =    26 @ -> |    27 P
    defb 0,          '=',         '|',         'P'
    ;  28 ; -> +    29 : -> *    30 / -> ?    31 . -> >
    defb '+',        '*',         '?',         '>'
    ;  32 0 -> _    33 9 -> )    34 O         35 I
    defb '_',        ')',         'O',         'I'
    ;  36 L         37 K         38 M         39 , -> <
    defb 'L',        'K',         'M',         '<'
    ;  40 8 -> (    41 7 -> '    42 U         43 Y
    defb '(',        39,          'U',         'Y'
    defb 'H',        'J',         'N',         32
    ;  48 6 -> &    49 5 -> %    50 R         51 T
    defb '&',        '%',         'R',         'T'
    defb 'G',        'F',         'B',         'V'
    ;  56 4 -> $    57 3 -> #    58 E         59 W
    defb '$',        '#',         'E',         'W'
    defb 'S',        'D',         'C',         'X'
    ;  64 1 -> !    65 2 -> "    66 esc       67 Q
    defb '!',        '"',         0,           'Q'
    defb 0,          'A',         0,           'Z'
    defb 0,0,0,0,0,0,0,                       31

kbdmap:     defs 10             ; one byte per line, a 0 bit means pressed
kbdshift:   defb 0
lastkey:    defb 0              ; debounce latch
kbdsettlec: defb 0              ; scans of quiet still needed
