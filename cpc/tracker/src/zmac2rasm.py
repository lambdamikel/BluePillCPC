"""zmac -> rasm syntax pass, plus the TRS-80 -> CPC I/O substitutions.

Mechanical only. Everything machine specific (keyboard, disc, timing model,
video base) is replaced by hand in tracker.asm; this just makes the bulk of
TRACKER's source assemble under rasm.
"""
import re, sys

def convert(text):
    out = []
    for line in text.split('\n'):
        # split off a comment so we never rewrite inside one
        code, sep, comment = line.partition(';')
        # ... but ';' inside a quoted string is not a comment
        if code.count("'") % 2 or code.count('"') % 2:
            code, sep, comment = line, '', ''

        c = code

        # --- MIDI card ------------------------------------------------
        c = re.sub(r'\bout\s*\(\s*8\s*\)\s*,\s*a\b', 'call midiout', c, flags=re.I)
        c = re.sub(r'\bin\s+a\s*,\s*\(\s*9\s*\)', 'call midistat', c, flags=re.I)
        c = re.sub(r'\bin\s+a\s*,\s*\(\s*8\s*\)', 'call midiin', c, flags=re.I)

        # --- numeric literals -----------------------------------------
        c = re.sub(r'\$([0-9a-fA-F]+)\b', r'#\1', c)          # $3c00 -> #3c00
        c = re.sub(r'\b0([0-9a-fA-F]*)[hH]\b', r'#\1', c)     # 0ffh  -> #ff
        c = re.sub(r'\b([01]+)b\b', r'%\1', c)                # 1100b -> %1100

        # --- macros: zmac "name macro args" -> rasm "macro name args" ---
        m = re.match(r'\s*(\w+)\s+macro\s*(.*)$', c, flags=re.I)
        if m:
            c = 'macro ' + m.group(1) + (' ' + m.group(2) if m.group(2).strip() else '')
        elif re.match(r'\s*endm\b', c, flags=re.I):
            c = 'mend'
        elif re.match(r'\s*local\s+\w+', c, flags=re.I):
            c = ''                       # rasm marks macro locals with @

        # --- single character literals rasm's expression parser chokes on.
        # Only on instruction operands: inside a defb list the same pattern
        # matches the comma BETWEEN two literals and eats them both.
        if not re.search(r'\b(defb|defw|defs|ascii|byte|word|db|dw)\b', c, flags=re.I):
            c = re.sub(r"'([^A-Za-z0-9' ])'", lambda m: str(ord(m.group(1))), c)
            c = re.sub(r'"([^A-Za-z0-9" ])"', lambda m: str(ord(m.group(1))), c)

        # --- pseudo ops ------------------------------------------------
        c = re.sub(r'(^|\s)ascii(\s)',  r'\1defb\2', c, flags=re.I)
        c = re.sub(r'(^|\s)byte(\s)',   r'\1defb\2', c, flags=re.I)
        c = re.sub(r'(^|\s)word(\s)',   r'\1defw\2', c, flags=re.I)
        c = re.sub(r'(^|\s)db(\s)',     r'\1defb\2', c, flags=re.I)
        c = re.sub(r'(^|\s)dw(\s)',     r'\1defw\2', c, flags=re.I)

        # --- accumulator forms rasm insists on -------------------------
        c = re.sub(r'\b(add|adc|sub|sbc|and|or|xor|cp)\s+a\s*,\s*',
                   lambda m: m.group(1) + ' ' + ('a,' if m.group(1) in ('add','adc','sbc') else ''), c, flags=re.I)
        # bare "add 16" / "sub 6" -> "add a,16"
        c = re.sub(r'(^|:|\s)(add)\s+(?!a,|hl|ix|iy|sp)([^\s,][^,\n]*)$',
                   r'\1\2 a,\3', c.rstrip(), flags=re.I)
        c = re.sub(r'(^|:|\s)(adc|sbc)\s+(?!a,|hl,)([^\s,][^,\n]*)$',
                   r'\1\2 a,\3', c.rstrip(), flags=re.I)

        # --- ld a,(ix) needs an explicit displacement -------------------
        # ... but "jp (iy)" is a jump through the register, not an indexed
        # load, and rasm rejects "jp (iy+0)".
        if not re.match(r'\s*jp\b', c, flags=re.I):
            c = re.sub(r'\((i[xy])\)', r'(\1+0)', c, flags=re.I)

        out.append(c + (sep + comment if sep else ''))
    return '\n'.join(out)

def extract(text, start_label, end_label):
    """Lines from the line that starts with start_label up to (not incl.) end_label."""
    lines = text.split('\n')
    a = b = None
    for i, l in enumerate(lines):
        if a is None and re.match(r'\s*' + re.escape(start_label) + r'\b', l):
            a = i
        elif a is not None and end_label and re.match(r'\s*' + re.escape(end_label) + r'\b', l):
            b = i
            break
    if a is None:
        raise SystemExit('start label not found: ' + start_label)
    if end_label and b is None:
        raise SystemExit('end label not found: ' + end_label)
    return '\n'.join(lines[a:b])

if __name__ == '__main__':
    src = open(sys.argv[1]).read()
    if len(sys.argv) > 3:
        src = extract(src, sys.argv[2], sys.argv[3] if sys.argv[3] != '-' else None)
    sys.stdout.write(convert(src))
