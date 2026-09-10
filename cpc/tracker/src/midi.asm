;; ---------------------------------------------------------------
;; TRACKER/CPC - the MIDI layer (BluePillCPC "Ultimate MIDI Card")
;;
;;   &FBEE  write : send a MIDI byte     read : fetch a pending byte
;;   &FBFE  read  : status, is a byte waiting?
;;
;; Same shape as MIDI/80 on the TRS-80, but with one hazard. There,
;; "out (8),a" touches no registers. Here the CPC decodes 16 bit port
;; addresses, so it has to be "ld bc,#FBEE : out (c),a" - and BC is live
;; across several of TRACKER's MIDI sends (playnote loads the gate
;; duration into C, for one). So these wrappers preserve everything but
;; the flags, and the porting rule is mechanical:
;;
;;      out (8),a      ->   call midiout
;;      in  a,(9)      ->   call midistat
;;      in  a,(8)      ->   call midiin
;;
;; ---------------------------------------------------------------
;; BYTE PACING, and why it lives HERE rather than at the call sites.
;;
;; MIDI runs at 31250 baud, 1 start + 8 data + 1 stop, so a byte occupies
;; the wire for 10/31250 = 320 us and nothing can go out faster than that,
;; whatever the card's FIFO does. Exceed it for long enough and bytes are
;; dropped.
;;
;; The TRS-80 paced with short_delay between sends: 32 iterations of a 24 T
;; loop = 768 T = 379 us on a Model III, safely over one byte time. The
;; first CPC version of short_delay was tuned for step timing instead and
;; came out at 98 us - measured, 88% of all bytes were leaving faster than
;; the wire could carry them. The symptom was six program changes going out
;; as 12 bytes in 2.4 ms where they need 3.84: some were lost, and a channel
;; that loses its program change stays on program 0, Acoustic Grand Piano.
;; Michael heard piano on track 2 of BOOGIE on the real 6128.
;;
;; So the wait is here, in midiout, and not at the call sites. Every byte
;; then pays it - including the clock bytes and the panic messages, which
;; are sent as bare OUTs with no short_delay anywhere near them, and which
;; the call site approach silently missed. No caller can forget.
;;
;; Cost is ~330 us a byte. TRACKER sends at most 18 note bytes and 6 clocks
;; in a step, so 8 ms of a 107 ms step: 7.4%, and it comes out of the step
;; delay, so the tempo is unchanged.
;; ---------------------------------------------------------------

MDATA equ #FBEE
MSTAT equ #FBFE

MIDIWAIT equ 44                 ; 44 * 7 us = 308 us; plus the call and the
                                ; OUT itself, comfortably over 320 us

;; send the byte in A, then hold the wire for one byte time.
;; All registers preserved, flags included.
midiout:
    push bc
    ld bc,MDATA
    out (c),a
    pop bc
    push af
    push hl
    ld hl,MIDIWAIT
midiow:
    dec hl
    ld a,h
    or l
    jr nz,midiow
    pop hl
    pop af
    ret

;; A = status byte, Z set if nothing is waiting. BC preserved.
midistat:
    push bc
    ld bc,MSTAT
    in a,(c)
    pop bc
    or a
    ret

;; A = the next pending MIDI byte. BC preserved.
midiin:
    push bc
    ld bc,MDATA
    in a,(c)
    pop bc
    ret
