;; ---------------------------------------------------------------
;; TRACKER/CPC - the display layer
;;
;; TRACKER writes characters straight into TRS-80 video RAM, computing
;; addresses like  #3C00 + 14*64 + 35.  The CPC has no text mode, so the
;; port keeps a 64x16 SHADOW BUFFER laid out exactly like TRS-80 video
;; RAM and points all of that existing code at it.  The buffer is put at
;; #3C00, the TRS-80's own video address, so every address calculation in
;; the tracker - screenupdate's LDIR included - ports across untouched.
;;
;; A renderer turns the buffer into pixels:
;;   - the two cursors are rendered on demand, so they are instant
;;   - everything else is caught by an incremental dirty scan that walks
;;     a sixteenth of the buffer per main loop pass, comparing against a
;;     copy of what was last drawn.  Full coverage every 16 passes, and
;;     correct by construction: nothing can stay stale, and no caller has
;;     to remember to mark anything.
;;
;; LAYOUT.  The 64x16 grid is spread over mode 2's 80x25 rather than
;; packed into 16 consecutive rows.  Packed, it filled 80% of the width
;; but only 64% of the height, which read as horizontally stretched -
;; the CPC's character cell is 8x8 where the TRS-80's is 8x12.  Spread
;; over 20 of the 25 rows the block is 80% x 80%, so it has the same
;; shape on screen as it does on a TRS-80.
;; ---------------------------------------------------------------

VCOLS   equ 64                  ; TRS-80 geometry, kept deliberately
VROWS   equ 16
VSIZE   equ VCOLS*VROWS
VSLICES equ 16                  ; dirty scan granularity
VSLICE  equ VSIZE/VSLICES       ; 64 cells a pass, ~0.9 ms

XOFF    equ 8                   ; centre 64 columns in 80
SCRBASE equ #C000
SCRCOLS equ 80
FONT    equ fontpix             ; 8 pages: FONT + scanline*256 + char

SCR_SET_MODE   equ #BC0E
SCR_SET_INK    equ #BC32
SCR_SET_BORDER equ #BC38

PAPER   equ 0                   ; black
INK     equ 24                  ; bright yellow
BORDER  equ 0                   ; black

;; ---------------------------------------------------------------
;; setscreen - mode 2 and the palette, together.
;;
;; They belong together because SCR SET MODE resets the palette to the
;; firmware default (paper 1, blue), so anything that re-establishes the
;; mode - startup, and coming back from an AMSDOS call, which can print
;; over the screen - has to put the colours back too. B and C are the two
;; flash colours; setting them equal gives a steady colour.
;;
;; SCR SET INK only writes the firmware's ink TABLE. The gate array is
;; programmed from that table by the frame flyback interrupt handler -
;; which is how flashing inks work - so with interrupts off the colours
;; never reach the hardware. Disabling interrupts straight after this
;; call left the screen on the default blue paper until the first disc
;; access happened to run AMSDOS with interrupts on, at which point the
;; ISR pushed the table through and the paper turned black. So the
;; interrupts are let in here, deliberately, for two frames.
;; ---------------------------------------------------------------
setscreen:
    ld a,2                      ; 640x200, 2 colours, 80 columns
    call SCR_SET_MODE
    ld a,0                      ; pen 0, the paper
    ld b,PAPER
    ld c,PAPER
    call SCR_SET_INK
    ld a,1                      ; pen 1, the text
    ld b,INK
    ld c,INK
    call SCR_SET_INK
    ld b,BORDER
    ld c,BORDER
    call SCR_SET_BORDER

    ei                          ; let the flyback ISR program the gate
    ld b,16                     ; array from the table it was just given
setscr1:
    halt
    djnz setscr1
    di
    ret

;; ---------------------------------------------------------------
;; rendercell - draw the single cell at HL (a pointer into VRAM).
;; Preserves HL, which renderall and renderslice rely on.
;; Screen address comes from a 16 entry row table rather than being
;; recomputed; that was costing more than the eight pixel writes.
;; ---------------------------------------------------------------
rendercell:
    push hl
    push bc
    push de
    ld de,VRAM
    or a
    sbc hl,de                   ; hl = offset 0..1023
    ld a,l
    and 63
    ld c,a                      ; c = column
    ld a,l                      ; row = offset >> 6
    rlca
    rlca
    and 3
    ld b,a
    ld a,h
    rlca
    rlca
    and #0c
    or b
    add a,a                     ; *2 to index a word table
    ld e,a
    ld d,0
    ld hl,rowtab
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; de = screen address of this row, col 0
    ld a,e
    add a,c
    ld e,a
    jr nc,rc0
    inc d
rc0:
    pop hl                      ; discard the saved de
    pop bc
    pop hl                      ; hl = the VRAM pointer again
    push hl
    ld a,(hl)
    ld l,a
    ld h,FONT/256
    ld b,8
rc1:
    ld a,(hl)
    ld (de),a
    inc h                       ; next scanline's font page
    ld a,d
    add a,8                     ; next scanline's screen block
    ld d,a
    djnz rc1
    pop hl
    ret

;; render the cell at HL and mark it clean, so the dirty scan will not
;; find it again. Preserves HL.
rendercellc:
    call rendercell
    ;; fall through

;; copy the character at HL into the matching slot of SHADOW
markclean:
    push hl
    push de
    ld de,SHADOW-VRAM
    ld a,(hl)
    add hl,de
    ld (hl),a
    pop de
    pop hl
    ret

;; ---------------------------------------------------------------
;; Where each of the 16 tracker rows lands on the CPC's 25.
;;
;; The sequencer wants gaps: packed into 16 consecutive rows it fills 80%
;; of the width but only 64% of the height, which reads as horizontally
;; stretched, because a CPC character cell is 8x8 where a TRS-80's is
;; 8x12. Spread over 20 of the 25 rows the block is 80% x 80% and has the
;; same shape on screen that it has on a TRS-80.
;;
;; The help page is the opposite: 16 solid lines of text that want no
;; gaps at all. So there are two maps and setrows swaps them.
;;
;;   sequencer                        help page        MIDORG
;;   title             ->  2          banner  ->  2     all 16 rows
;;   status            ->  4          body    ->  5..19  -> 4..19
;;   ruler, bars 1-4   ->  6
;;   tracks 1-6        ->  7..12
;;   ruler, bars 5-8   ->  15
;;   tracks 1-6        ->  16..21
;; ---------------------------------------------------------------

rowtab: defs 2*VROWS             ; the live map, filled by setrows

macro ROW r
    defw SCRBASE + {r}*SCRCOLS + XOFF
mend

rowsplit:
    ROW 2
    ROW 4
    ROW 6
    ROW 7
    ROW 8
    ROW 9
    ROW 10
    ROW 11
    ROW 12
    ROW 15
    ROW 16
    ROW 17
    ROW 18
    ROW 19
    ROW 20
    ROW 21

rowflat:
    ROW 2                        ; the banner, then a gap
    repeat VROWS-1, N
    defw SCRBASE + (N+4)*SCRCOLS + XOFF
    rend

;; A third map: sixteen consecutive rows, centred. MIDORG's artwork is one
;; solid block of keyboard diagram and wants no gaps anywhere.
rowplain:
    repeat VROWS, N
    defw SCRBASE + (N+3)*SCRCOLS + XOFF
    rend

;; make the map at HL live: the two use different screen rows, so the
;; screen is wiped as well, and the caller repaints with renderall.
setrows:
    ld de,rowtab
    ld bc,2*VROWS
    ldir
    ld hl,SCRBASE
    ld de,SCRBASE+1
    ld bc,#4000-1
    ld (hl),0
    ldir
    ret

;; ---------------------------------------------------------------
;; renderall - the whole buffer, using the fast row/scanline walk
;; rather than 1024 independent address computations.  84 ms, so this
;; is for startup and for leaving the help page, nothing per step.
;; ---------------------------------------------------------------
renderall:
    ld ix,rowtab
    ld hl,VRAM
    ld (textp),hl
    ld c,VROWS
raRow:
    ld b,0
raLine:
    push bc
    ld a,b
    add a,FONT/256
    ld h,a
    ld l,0                      ; hl = font page for this scanline
    ld e,(ix+0)
    ld d,(ix+1)                 ; de = row base
    ld a,b
    add a,a
    add a,a
    add a,a
    add a,d
    ld d,a                      ; + scanline*#800
    ld iy,raBack
    ld (savesp),sp
    ld sp,(textp)
    jp rowrender
raBack:
    ld sp,(savesp)
    pop bc
    inc b
    ld a,b
    cp 8
    jr nz,raLine
    ld hl,(textp)               ; next row of the buffer
    ld de,VCOLS
    add hl,de
    ld (textp),hl
    ld de,2                     ; next row of the table
    add ix,de
    dec c
    jr nz,raRow
    ;; the screen now matches the buffer
    ld hl,VRAM
    ld de,SHADOW
    ld bc,VSIZE
    ldir
    xor a
    ld (slice),a
    ret

;; one scanline of VCOLS characters. SP is the text pointer, so "pop bc"
;; fetches two characters in 3us; interrupts must be off.
rowrender:
    repeat VCOLS/2
    pop bc
    ld l,c
    ld a,(hl)
    ld (de),a
    inc de
    ld l,b
    ld a,(hl)
    ld (de),a
    inc de
    rend
    jp (iy)

textp:  defw 0
savesp: defw 0

;; ---------------------------------------------------------------
;; renderslice - compare a sixteenth of the buffer against SHADOW and
;; redraw only what changed.  Called once per main loop pass; the whole
;; screen is covered every 16 passes, about 26 ms, and nothing can stay
;; stale however the buffer was written.
;;
;; Two pointers rather than one plus an offset: "ld a,(de) : cp (hl)"
;; costs 4 us where the earlier add/push/pop form cost 33 us a cell.
;;
;; It counts what it drew, in `rendered`. A cell costs 250 us and a
;; pattern switch dirties about 140 of them, so a slice can be 35 ms of
;; real work where a clean one is nothing. The main loop charges that to
;; the step clock; uncharged, it was added to the step instead of coming
;; out of its idle delay, and every pattern change in a song stalled the
;; music by about 40 ms.
;; ---------------------------------------------------------------
renderslice:
    xor a
    ld (rendered),a
    ld a,(slice)
    ld l,a
    ld h,0
    repeat 6
    add hl,hl                   ; slice * VSLICE (64)
    rend
    ld de,VRAM
    add hl,de
    push hl
    ld de,SHADOW-VRAM
    add hl,de
    ex de,hl                    ; de = SHADOW ptr
    pop hl                      ; hl = VRAM ptr
    ld b,VSLICE
rs1:
    ld a,(de)
    cp (hl)                     ; changed since last drawn?
    jr nz,rs3
rs2:
    inc hl
    inc de
    djnz rs1
    ld a,(slice)
    inc a
    cp VSLICES
    jr c,rs4
    xor a
rs4:
    ld (slice),a
    ret
rs3:
    ld a,(hl)
    ld (de),a                   ; mark clean
    push bc
    push de
    call rendercell             ; preserves hl
    pop de
    pop bc
    ld a,(rendered)             ; one more cell of real work this pass
    inc a
    ld (rendered),a
    jr rs2

slice:    defb 0
rendered: defb 0            ; cells drawn by the last renderslice

;; ---------------------------------------------------------------
;; renderrun - push BC cells starting at HL straight to the screen.
;; For the places that write the buffer and then block, or that have no
;; main loop running the incremental scan at all, so it would never get
;; its turn. Marks them clean, so the scan will not redraw them.
;; ---------------------------------------------------------------
renderrun:
    call rendercellc
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,renderrun
    ret
