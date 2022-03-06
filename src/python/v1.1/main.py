#
# Python MIDI -> BIN Converter for the Amstrad CPC
# (C) 2022 by Michael Wessel, aka LambdaMikel
# Version 1.1
#
# License: GPL-3.0
# https://github.com/lambdamikel/BluePillCPC/blob/main/LICENSE
# See https://github.com/lambdamikel/BluePillCPC
#
# Purpose: Given a .MID MIDI song input file, generate a set of 16 KB
# .BIN files suitable for playback by the playback.bin MIDI playback
# program for the Amstrad CPC. This program supports MIDI playback
# from these .BIN files over the Ultimate CPC MIDI Card, LambdaSpeak 3
# and FS, as well as the Willy Soundcard with an S2P.
#

import os
import tkinter
from tkinter import filedialog
from tkinter import messagebox

import mido
import time

import mido.ports
from tkinter import *
import tkinter.font as tkf

messages = []
playback_factor = 300

def load_midi_file(file):

    global messages
    global button1
    global button2
    global button3

    name_ext = os.path.basename(file)
    name = name_ext.split(".")[0][0:20]

    mid = mido.MidiFile(file)

    text_button1 = button1['text']
    button1.configure(text=name)
    button1['background'] = 'red'

    text_button2 = button2['text']
    button2['state'] = tkinter.NORMAL
    button2.configure(text="WAIT")
    button2['background'] = 'red'

    text_button3 = button3['text']
    button3.configure(text=str(round(mid.length)+3) + "s")
    button3['background'] = 'red'

    button1.update()
    button2.update()
    button3.update()

    time.sleep(3)

    messages = []

    for msg in mid.play():
        messages.append(msg)

    #for track in mid.tracks:
    #    for msg in track:
    #        messages.append(msg)
    # messages.sort(key=lambda message: message.time)

    time.sleep(2)

    button1.configure(text=text_button1)
    button1['background'] = 'blue'
    button1.update()

    if messages:
        button2['state'] = tkinter.NORMAL
    else:
        button2['state'] = tkinter.DISABLED

    button2.configure(text=text_button2)
    button2['background'] = 'blue'
    button2.update()

    button3.configure(text=text_button3)
    button3['background'] = 'blue'
    button3.update()

def convert_midi_file(fn):

    global messages
    global playback_factor

    cur = 0
    file_count = 0
    file = None

    last_time = -1

    for msg in messages:

        time1 = msg.time

        #if last_time == -1:
        #    last_time = time1
        #delta = int((time1 - last_time)*50)

        delta = round(time1 * float(playback_factor))

        #print(delta)

        #last_time = time1

        hex_bytes = msg.hex().split()

        for byte in hex_bytes:

            if cur % 0x4000 == 0:
                if file:
                    file.close()
                file = open(fn + str(file_count) + ".bin", "wb")
                file_count += 1

            lenlo = delta & 255
            lenhi = (delta & (255 << 8)) >> 8
            if lenhi > 0 or lenlo == 255:
                #print(f"Warning - out of range: {lenhi, lenlo}. Clipping to 254!")
                lenlo = 254

            #triple_bytes = bytes([int(lenlo), int(lenhi), int(byte, 16)])
            pair_bytes = bytes([int(lenlo), int(byte, 16)])
            file.write(pair_bytes)

            cur += 2
            delta = 0

    if cur % 0x4000 == 0:
        file.close()
        file = open(fn + str(file_count) + ".bin", "wb")
        file_count += 1

    # write end of file marker (length = 0xFFFF)
    byte = bytes([255, 0])

    file.write(byte)
    file.write(byte)
    file.write(byte)

    file.close()

    messagebox.showinfo("Info",
                        "Saved '" + fn + "0.bin'" if file_count == 1 else
                        "Saved '" + fn + "0.bin' - '" + fn + str(file_count-1) +".bin'")

    return

def select_midi_file():
    filetypes = [ ('MIDI files', '*.mid') ]
    f = filedialog.askopenfile(filetypes=filetypes)
    if f:
        return f.name

def select_bin_file():
    filetypes = [ ('BIN files', '*.bin') ]
    f = filedialog.asksaveasfilename(filetypes=filetypes)
    if f:
        return f

def select_load_midi_file():
    fn = select_midi_file()
    if fn:
        load_midi_file(fn)

def save_midi_file():
    fn = select_bin_file()
    if fn:
        convert_midi_file(fn)

def exit_converter():
    root.destroy()

def set_speed(factor):
    global playback_factor
    playback_factor = factor

def main():

    global root
    global button1
    global button2
    global button3
    global playback_factor

    root  = Tk()

    root.geometry("400x400")
    root.resizable(False, False)

    bg = PhotoImage(file="boardbw.png")

    canvas1 = Canvas(root, width=400, height=400)

    canvas1.create_image(0, 0, image=bg, anchor="nw")

    myfontsmaller = tkf.Font(family="Terminal", size=14, weight="bold")
    myfont = tkf.Font(family="Terminal", size=20)

    canvas1.create_text( 200, 25, text = "Load .MID, Convert -> .BIN, & Exit", font=myfontsmaller, fill = "yellow" )

    root.wm_title("Ultimate CPC MIDI Card Converter - v1.1")

    canvas1.pack(fill="both", expand=True)

    # Create Buttons

    button1 = Button(root, text="Load MIDI File", font=myfont, bg="blue", fg="yellow",
                     command = select_load_midi_file )

    button2 = Button(root, text="Convert", font=myfont, bg="blue", fg="yellow",
                     command = save_midi_file )

    button2['state'] = tkinter.DISABLED

    button3 = Button(root, text="Exit", font=myfont, bg="blue", fg="yellow",
                     command = exit_converter )

    scale = Scale(root, from_= 1, to= 1000, orient=HORIZONTAL,  bg="blue", fg="yellow", troughcolor = "blue",
                  highlightbackground = "blue", highlightcolor = "blue",
                  font = myfontsmaller,
                  length = 360,
                  command = set_speed
                  )

    def on_enter_b1(e):
        button1['background'] = 'green'

    def on_leave_b1(e):
        button1['background'] = 'blue'

    def on_enter_b2(e):
        if button2['state'] == tkinter.NORMAL:
            button2['background'] = 'green'

    def on_leave_b2(e):
        button2['background'] = 'blue'

    def on_enter_b3(e):
        button3['background'] = 'green'

    def on_leave_b3(e):
        button3['background'] = 'blue'

    button1.bind( "<Enter>", on_enter_b1)
    button1.bind( "<Leave>", on_leave_b1)

    button2.bind( "<Enter>", on_enter_b2)
    button2.bind( "<Leave>", on_leave_b2)

    button3.bind( "<Enter>", on_enter_b3)
    button3.bind( "<Leave>", on_leave_b3)

    # Display Buttons

    scale.set(playback_factor)

    # Display Buttons
    button1_canvas = canvas1.create_window( 200, 80, anchor = "center", window = button1)
    button2_canvas = canvas1.create_window( 200, 160, anchor = "center", window = button2)
    button3_canvas = canvas1.create_window( 200, 240, anchor = "center", window = button3)

    canvas1.create_text(200, 300, text="Playback Speed (Default 300)", font=myfontsmaller, fill="yellow")
    scale_cancas = canvas1.create_window(200, 340, anchor="center", window=scale)

    fn = "test"
    file_count = 3

    root.mainloop()

main()



