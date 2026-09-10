#!/usr/bin/env python3
"""Build midorg.asm (CPC) from the TRS-80 midorg.asm.

Same approach as mktracker.py: a mechanical zmac -> rasm syntax pass plus
named region replacements, one per thing that is genuinely machine
specific. MIDORG is far more contained than TRACKER - the only machine
dependencies are the keyboard matrix, the MIDI port, the exit path and the
solid-block character - so almost all of it crosses over untouched,
including the self-modifying key scanner, which is the clever part.
"""
import re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'midorg7.asm')
for cand in (os.path.expanduser('~/claude/midi80/MIDI-80/trs-80/zmac/midorg.asm'),):
    if os.path.exists(cand):
        SRC = cand
        break
DST = os.path.join(HERE, 'midorg.asm')

sys.path.insert(0, HERE)
from zmac2rasm import convert

STEPS = 'step_0   equ 0\nstep_1   equ 1\nstep_2   equ 2\nstep_3   equ 3\nstep_4   equ 4\nstep_5   equ 5\nstep_6   equ 6\nstep_7   equ 7\nstep_8   equ 8\nstep_9   equ 9\nstep_10  equ 10\nstep_11  equ 11\nstep_12  equ 12\nstep_13  equ 13\nstep_14  equ 14\nstep_15  equ 15\nstep_16  equ 16\nstep_17  equ 17\nstep_18  equ 18\nstep_19  equ 19\nstep_20  equ 20\nstep_21  equ 21\nstep_22  equ 22\nstep_23  equ 23\nstep_24  equ 24\nstep_25  equ 25\nstep_26  equ 26\nstep_27  equ 27\nstep_28  equ 28\nstep_29  equ 29\nstep_30  equ 30\nstep_31  equ 31'
# The two lines of on-screen text that are not true on a CPC: the card is
# the Ultimate MIDI Card, not a MIDI/80, and there is no BREAK key. Both
# are exactly 64 columns and must stay that way - they are screen images,
# LDIRed straight into the buffer.
TEXT = [
 ("** MIDI/80 ORGAN V1.1 - (C)2026 G.PHILLIPS+LAMBDAMIKEL+CLAUDE **",
  "* ULT.MIDI CARD ORGAN V1.1 (C)2026 LAMBDAMIKEL+PHILLIPS+CLAUDE *"),
 ("BREAK:QUIT L/R:INSTR UP/DOWN:VOL SPACE/ENT:CHANNEL AF/14:OCT +/-",
  "ESC:QUIT  L/R:INSTR UP/DOWN:VOL SPACE/ENT:CHANNEL  AF/14:OCT +/-"),
]

lines = convert(open(SRC).read()).split('\n')

def find(label, start=0):
    pat = re.compile(r'\s*' + re.escape(label.rstrip(':')) + r'(?![A-Za-z0-9_])')
    for i in range(start, len(lines)):
        if pat.match(lines[i]):
            return i
    raise SystemExit('anchor not found: ' + label)

edits = []
def R(a, b, text):
    edits.append((a, b, text))

# ===================================================================== #
R(None, 'title:', r'''
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
''')

R('macro defstep', 'st_c0', '''
;; zmac built these with a macro and a REPT; they are simply 0..31, so
;; here they are spelled out and rasm needs no equivalent.
%s

''' % STEPS)

R('start:', 'macro defstep', r'''
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

''')

# --- the key matrix constants ----------------------------------------
# CPC keynumber = line*8 + bit; the macros want (line << 8) | mask.
CPCKEYS = {
    '@': 26, 'A': 69, 'B': 54, 'C': 62, 'D': 61, 'E': 58, 'F': 53, 'G': 52,
    'H': 44, 'I': 35, 'J': 45, 'K': 37, 'L': 36, 'M': 38, 'N': 46, 'O': 34,
    'P': 27, 'Q': 67, 'R': 50, 'S': 60, 'T': 51, 'U': 42, 'V': 55, 'W': 59,
    'X': 63, 'Y': 43, 'Z': 71,
    '0': 32, '1': 64, '2': 65, '3': 57, '4': 56, '5': 49, '6': 48, '7': 41,
    '8': 40, '9': 33,
    'colon': 29, 'semi': 28, 'comma': 39, 'dash': 25, 'dot': 31, 'slash': 30,
    'enter': 18, 'clear': 16, 'break': 66, 'up': 0, 'down': 2,
    'left': 8, 'right': 1, 'space': 47, 'shift': 21,
}
ktab = ["""
;; Amstrad CPC keyboard matrix. Read line n, bit b: the key is DOWN when
;; the bit is 0, which kbdscanorg inverts, so these read like the TRS-80's.
;;
;;         bit  0     1     2     3     4     5     6      7
;;  line 0    curup currgt curdn  f9    f6    f3   enter   f.
;;  line 1    curlft copy   f7    f8    f5    f1    f2     f0
;;  line 2    clr    [     return  ]    f4   shift   \\    ctrl
;;  line 3    ^      -      @     P     ;     :      /     .
;;  line 4    0      9      O     I     L     K      M     ,
;;  line 5    8      7      U     Y     H     J      N    space
;;  line 6    6      5      R     T     G     F      B     V
;;  line 7    4      3      E     W     S     D      C     X
;;  line 8    1      2     esc    Q    tab    A     caps   Z
;;  line 9    joystick / del
;;
;; BREAK does not exist on a CPC, so ESC takes its place.
"""]
for name, kn in sorted(CPCKEYS.items(), key=lambda kv: kv[1]):
    ktab.append("k_%-6s equ (%d<<8) | %%%s" % (name, kn // 8, format(1 << (kn % 8), '08b')))
R('k_@', 'init:', '\n'.join(ktab) + '\n')

# --- the macros read the scanned copy rather than the matrix ----------
R('macro key', 'macro key_l', r'''
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

''')

R('macro key_l', 'k_@', r'''
macro key_l addrmask,st,id
    notekey {addrmask},{st},key_down_lower,{id}
mend

macro key_r addrmask,st,id
    notekey {addrmask},{st},key_down_upper,{id}
mend

''')

R('init:', 'main:', r'''
init:

    call scanmarkers
    call screenupdate
    call setinstrument_lower
    call setinstrument_upper
    call renderall              ; establish the screen and its shadow copy

''')

R('main:', 'key_l\tk_Z', r'''
main:
    call kbdscanorg             ; one scan serves every test below

''')

R('exit:', 'oct1_up_down:', r'''
exit:
    pop iy
    ;; No DOS to go back to - the organ is loaded over BASIC's program
    ;; area - so ESC resets to a clean machine.
    ei
    jp 0

''')

R('short_delay:', 'byte2ascii:', r'''
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

''')

R('screenupdate:', '\tld hl,#3c00+14*64+35', r'''
screenupdate:
    call screenupdate0
    ld hl,VRAM+14*64            ; the status row is the only thing it
    ld bc,64                    ; touches, and nothing else redraws it
    jp renderrun

screenupdate0:
''')

R('HILITE\t equ', 'scanmarkers:', r'''
;; The CPC's mode 2 has two colours and no attributes, so a filled cell is
;; as close to inverse video as this gets - the same answer the TRS-80
;; reached for a different reason. Character #8F is the only solid block
;; in the CPC font; checked against the ROM, it is the one glyph whose
;; eight scanlines are all #FF.
HILITE   equ    #8F

''')

R('keyhilite:', 'keyrestore:', r'''
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

''')

R('keyrestore:', 'keytab:', r'''
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

''')

R('end start', None, '''
    save "MIDORG.BIN", #0800, $-#0800, AMSDOS, start
''')

# ===================================================================== #
spans = []
for a, b, text in edits:
    i = 0 if a is None else find(a)
    j = len(lines) if b is None else find(b, i + 1)
    spans.append((i, j, text))
spans.sort(key=lambda s: -s[0])
for i, j, text in spans:
    lines[i:j] = text.split('\n')

out = '\n'.join(lines)

for a, b in TEXT:
    assert len(a) == len(b) == 64, (len(a), len(b))
    assert out.count(a) == 1, a
    out = out.replace(a, b)

# zmac's REPT/ENDM has no rasm equivalent here, and the table is just zeros
out = out.replace('''keytab:; screen address + width, per marker
\trept\tNKEYS
\tdefw\t0
\tdefb\t0
mend''', '''keytab:                         ; screen address + width, per marker
    defs NKEYS*3''')

# rasm wants "name equ value", never "name: equ value"
out = re.sub(r'^(\w+)\s*:(\s+)equ\b', r'\1\2equ', out, flags=re.M | re.I)

# zmac's low()/high() -> rasm arithmetic.
# NOTE: it must be ">> 8", not "/ 256". rasm's division ROUNDS rather than
# truncating - #0880 / 256 assembles as 9, not 8 - so every self-modified
# jump target with a low byte >= #80 got a high byte one too large, and the
# key handlers rewrote themselves to jump into the middle of other code.
# and no wrapping parentheses either: a leading '(' makes rasm read the
# operand as memory addressing rather than an immediate value.
out = re.sub(r'\blow\(([^)]+)\)',  r'\1 % 256', out)
out = re.sub(r'\bhigh\(([^)]+)\)', r'\1 >> 8', out)

# the '@' suffix on the sharp-note labels is not a rasm identifier char
out = re.sub(r'\b(st_[a-g][0-9])@', r'\1s', out)

open(DST, 'w').write(out)
print('wrote %s, %d lines' % (DST, out.count('\n') + 1))
