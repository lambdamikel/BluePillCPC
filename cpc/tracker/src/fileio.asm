;; ---------------------------------------------------------------
;; TRACKER/CPC - file I/O (AMSDOS)
;;
;; Replaces the TRS-80 side's 88 iteration @read/@write loop, its 256
;; byte staging buffer and its ERN fixup. AMSDOS moves a whole file in
;; one call, so all of that goes away.
;;
;; THE THING THAT MATTERS, and it cost a day to find: when BASIC's RUN"
;; hands control to a binary, AMSDOS puts the CASSETTE jumpblock back at
;; &BC77..&BC9D. Read from the emulator:
;;
;;      at the BASIC prompt   &BC77: DF 8B A8   RST &18 -> &A88B  (disc)
;;      inside a running prog &BC77: CF E5 A4   RST 8   -> &A4E5  (tape)
;;
;; Call them as they stand and you get "Press PLAY then any key". A
;; machine code program must put the disc vectors back itself - which is
;; exactly what TADITRANS (Michael Wessel, 1987) does at &937A.
;;
;; All 13 DOS vectors take the same three bytes and are contiguous, so one
;; LDIR does the lot. AMSDOS tells the calls apart by reading the stacked
;; return address (the RST leaves vector+3) and adding &10D2. That is also
;; why this pattern may ONLY live in genuine jumpblock slots: reached from
;; anywhere else the arithmetic is nonsense and the machine crashes.
;; ("Das grosse Floppy-Buch zum CPC", section 2.1.14.)
;;
;; Verified end to end under MAME: TRACKER's full 22645 byte data segment
;; saved as DUMP, wiped from memory, read back, 0 mismatches.
;; ---------------------------------------------------------------

CAS_IN_OPEN    equ #BC77
CAS_IN_CLOSE   equ #BC7A
CAS_IN_DIRECT  equ #BC83
CAS_OUT_OPEN   equ #BC8C
CAS_OUT_CLOSE  equ #BC8F
CAS_OUT_DIRECT equ #BC98

;; Put the disc jumpblock back. Call once at startup, and again after
;; anything that might have handed control through the firmware.
dsk_select:
    ld hl,dsk_vectors
    ld de,CAS_IN_OPEN
    ld bc,13*3
    ldir
    ret

dsk_vectors:
    repeat 13
    defb #DF,#8B,#A8            ; RST &18 / DEFW &A88B
    rend

;; Save DSK_START..+DSK_LEN as "DUMP". Carry set on success.
dsk_save:
    call dsk_select
    ld b,dsk_fnend-dsk_fname
    ld hl,dsk_fname
    ld de,dsk_buffer
    call CAS_OUT_OPEN
    ret nc
    ld hl,DSK_START
    ld de,DSK_LEN
    ld bc,0                     ; no entry address; it is data, not code
    ld a,2                      ; file type 2 = binary
    call CAS_OUT_DIRECT
    push af
    call CAS_OUT_CLOSE
    pop af
    ret

;; Load "DUMP" back over DSK_START. Carry set on success.
dsk_load:
    call dsk_select
    ld b,dsk_fnend-dsk_fname
    ld hl,dsk_fname
    ld de,dsk_buffer
    call CAS_IN_OPEN
    ret nc
    ld hl,DSK_START
    call CAS_IN_DIRECT
    push af
    call CAS_IN_CLOSE
    pop af
    ret

dsk_fname:  defb "DUMP"         ; the name TRACKER has always used
dsk_fnend:
