# BluePillCPC
An Extension Board for the Amstrad CPC based on the Blue Pill Microcontroller 

It's a generic IO interface to the CPC, so use cases are generic. 
 
## The Ultimate CPC MIDI Sound & MIDI Interface Card

The first application of this IO interface: using an S2 Waveblaster from
Serdashop and an Adafruit Midifeather board to create the ultimate
CPC MIDI sound + MIDI interface card. 

Features:

- CPC MIDI Soundcard using the S2 GM MIDI Module from Serdashop
- CPC can send MIDI data over output port `&FBEE` to the S2
- MIDI IN and MIDI OUT via Adadfruit Midifeather (standard MIDI DIN sockets) 
- MIDI IN to the CPC: check for new MIDI byte on input port `&FBFE` and fetch pending byte from buffer via `&FBEE`
- MIDI soft through: all incoming MIDI data (from CPC or MIDI IN) can be forwarded / relayed to the MIDI OUT socket ("MIDI SOFT THRU")
- CPC MIDI Synthesizer software in machine code (MIDI INPUT demo) 
- CPC GM Drumcomputer software in BASIC (MIDI OUTPUT demo) 
- "Lazy engineering": MX4 compatible CPC extension board using three
sockets, one for the Blue Pill, one for the S2, one for the optional Midifeather.
- Only one additional chip required - a GAL22V10 programmed as an address decoder. The Blue Bill does not have enough 5V-compatible GPIO ports to do the
decoding fully in sofware
- Everything else is done purely in software - unlike LampdaSpeak, no additional glue logic is required to manage the databus (e.g., no flip flop to latch 
the databus upon IOWRITE requests, or busdriver to tristate the microcontroller output to the bus upon IOREAD requests). The 72 MHz Blue Pill is fast enough to respond to and manage IO requests and the databus via ISRs (Interupt Service Routines). It was tedious to get the timing of the ISRs right (done by inserting ``__asm__("nop")`` at the right spots), but it works flawlessly by now.
- No extra circuitry for Z80 /WAIT management 
- Low cost - final PCB will be in the 50 to 60 EUR range 
- Very DIY friendly (no SMD, plug and play of standard modules)

![Schematics](pics/schematics.png) 

Some YouTube videos: 

[Standalone CPC MIDI Playback](https://youtu.be/9-n1bf7yXhg) 

[First PCB Demo](https://youtu.be/ioN5ufExyvQ) 

[DIN MIDI IN to CPC and CPC Synthesizer](https://youtu.be/qN9ypJHENk0)

[DIN MIDI IN to S2 / General Midi MID Playback](https://youtu.be/xLs3ZQm0AvA)

[Sending MIDI Data from the CPC to the S2](https://youtu.be/EcW2L8-IfYQ)

## First Batch Ready!

![First Batch](pics/first-batch.jpg) 

## Prototype PCB 

![Pic PCB 1](pics/board-1.jpg) 
![Pic PCB 2](pics/board-2.jpg) 
![Pic PCB 3](pics/board-3.jpg) 
![Pic PCB 4](pics/board-4.jpg) 
![Pic PCB 5](pics/board-5.jpg) 


## Breadboard Pics

![Pic 1](pics/breadboard2.jpg) 

![Pic 2](pics/breadboard.jpg) 

![Pic 3](pics/pic4.jpg) 

## DIL Switch 

----------------------------------------------
| Switch | Explanation                       | 
|--------|-----------------------------------|
|   1    | Route CPC to S2                   | 
|   2    | Route CPC to MIDI OUT             | 
|   3    | Route MIDI IN to S2               | 
|   4    | Route MIDI IN to MIDI OUT         | 
|   5    | Route S2 L Channel to CPC Speaker | 
|   6    | Route S2 R Channel to CPC Speaker | 
|   7    | 1 = Enable card - make sure 8 = 0 | 
|   8    | 0 = Enable card - make sure 7 = 1 | 
----------------------------------------------

## First Steps with the Ultimate MIDI Sound Card 

A recent customer asked me for this, so here we go. 

First, load the [cpc/ULTMIDI2.dsk](ULTMIDI.dsk) and check out the
programs `MIDIOUT.BAS` and `MIDIDRUM.BAS`, as demonstrated here:
[https://youtu.be/xLs3ZQm0AvA](https://youtu.be/xLs3ZQm0AvA).

That should give you some sound from the stereo socket, and you should
also be able to hear MIDI sound in the CPC speaker if **DIP switches 5
and 6** are set to ON; see above for the DIP switch table.

Note that, for the CPC to S2 MIDI routing to work , you must have
**DIP switch 1** set to ON position ("Route CPC to S2").

Next, try to play the MIDI song `SONG2.BIN` from 

[cpc/ULTMIDI3.dsk](cpc/ULTMIDI3.dsk) 

Use the `Play` option when the program starts, and see if you can hear
Alan Parsons! See 
[https://youtu.be/zATfSDlGLWw](https://youtu.be/zATfSDlGLWw).

There are many more such "song fragments" on
[cpc/ULTMIDI2.dsk](cpc/ULTMIDI2.dsk). Read below to learn how you can
record your own song fragments from a MID file being played back by
the PC or Mac.


Next, if you have a *MIDI Sound Module or synthesizer*, you can try
connecting it to the *MIDI OUT* socket and see if you can playback the
same sounds / songs with this external device. Note that you must have
**DIP switch 2** set to ON ("Route CPC to MIDI OUT"). Both switch 1
and 2 can be �N at the same time. In this case, the CPC-generated MIDI
data will be played via the connected external module, and via the S2
(or X2GS, ... or whatever is plugged in at the S2 connector at the back
of the card).

Next, you can try *MIDI Input*. For that, you will need a *MIDI device
that can generate MIDI data*, e.g., a synth or keyboard, or a MIDI USB
cable and a PC / Mac program that can generate MIDI data. Some come
with a virtual "piano keyboard" that can be used to send MIDI data.
Or you can play back a MID file from the PC that way. 

Now, with the external MIDI data generating device connected to MIDI
IN, if **DIP switch 3** is set to ON, then the firmware will
automatically forward any received MIDI message to the S2 (X2GS, ...,
whatever is connected to the S2 plugin header at the back of the
card). *And without CPC involvement.*

So, this allows you to use the card as a *standalone MIDI instrument*.
You only need to supply 5V power via the CPC, but no CPC program is
required. If you can find a way to feed 5 V into the card without the
CPC, you have a real standalone GM Midi expander like the Roland
Sound Canvas (and it sounds equally good, especially with the X2GS!). 

Next, the card can also act as an additional MIDI Forwarder /
Repeater. So, this is like the *MIDI THROUGH* socket on MIDI
devices. Each incoming MIDI message is automatically forwarded to the
MIDI OUT DIN socket if **DIP switch 4** is ON. Hence, with switches 3
and 4 enabled, you can play MIDI on the card, and forward the data at
the same time to another externally connected MIDI device. That way,
you can send MIDI data to the internal MIDI module (S2, X2GS, ...),
and to an externally connected MIDI device (over the MIDI OUT socket)
at the same time. 

Now, if you want to *process the MIDI data coming over the MIDI IN
socket with the CPC,* then you want to *disable switch 3*, because
else every incoming MIDI message would be played automatically by the
S2 (X2GS, ...), firmware-based.

So the next test then is to *disable switch 3*, connect your MIDI
synth / keyboard or PC USB MIDI cable to MIDI IN as before, and now
load the program `CPCSYNTH.BAS` from the
[cpc/ULTMIDI.dsk](cpc/ULTMIDI.dsk). You will need the **MAXAM 1.4
assembler** in ROM. Once the program starts (press a key), you should  
see incoming MIDI sync messages on the screen from the external MIDI 
device (or MIDI USB PC cable). 

Any incoming MIDI Note On / Off message will be played in the CPC
speaker; i.e., the CPC's internal AY-3-8912 soundchip now acts as a
MIDI instrument. It is 3note polyphonic.

Whereas `CPCSYNTH.BAS` demonstrates how to turn the CPC into a simple
3note polyphonic MIDI keyboard using MIDI IN, the `CPCTHRU.BAS`
program on the [cpc/ULTMIDI.dsk](cpc/ULTMIDI.dsk) demonstrates how to
receive MIDI data and simply forward it with a CPC program. Again,
MAXAM assembler in ROM is required. So, with this program running, any
incoming MIDI message will be forwarded / echoed / relayed to MIDI
OUT. This achieves the same effect as described above, but this time
the "forwarding function" is computed by the CPC rather than the
firmware.

This gives of course more flexibility, because now we can change the
MIDI data stream *on the fly* with a CPC program. This is demonstrated
with the `CPCTRAFO.BAS` MAXAM assembler program. Here, MIDI data can
be transposed by 0, 1, 2 octaves on the fly. See
[https://youtu.be/Th2IpnHSq80](https://youtu.be/Th2IpnHSq80).

Finally, you can try to record a whole complex MIDI Data Sequence "in
realtime" into CPC memory, play it back from there, and save it to
disk. This is what the program `RECORDER2.BAS` on
[cpc/ULTMIDI3.dsk](cpc/ULTMIDI3.dsk) is doing (MAXAM assembler again).
All the song fragments on [cpc/ULTMIDI2.dsk](cpc/ULTMIDI2.dsk) and
[cpc/ULTMIDI3.dsk](cpc/ULTMIDI3.dsk) were created that way - I simply
played back a complex GM MID song on the PC using a MID player
program, and the MIDI messages that got "streamed" into the CPC via a
PC USB MIDI cable were recorded into memory, and saved to disk using
above `RECORDER2.BAS` program. The MIDI data is saved together with
timestamp data to facilitate that.

However, the data format is not optimized yet, and the program is
proof-of-concept and "bare bones" only. So depending on the complexity
of the MIDI data that is being recorded in that way, you'll reach the
end of the CPC memory after about 45 seconds to 1 minute, and then the
program crashes when firmware locations are overwritten in RAM by the
`RECORDER2.BAS`. I should find some time to improve the program at
some point. So, when recording, make sure to hit the "x" key to quit
"early enough" during recording, else it crashes your CPC.

There is a video of the recording process:
[https://youtu.be/9-n1bf7yXhg?t=780](https://youtu.be/9-n1bf7yXhg?t=780)

And a note of warning: depending on the complexity of the MIDI
recorded that way, this is really at the limit of what the BluePill &
CPC combo can do. If the MIDI is too complex, then the CPC might also
crash. This is casued by the BluePill. Note that I am doing all the
CPC `IOREAD / IOWRITE` request handling in software in the BluePill.
If there are too many ISR (Interupt Service) Requests being generated
in the BluePill from very complex incoming MIDI data, then the
BluePill does not have enough processing bandwith to also serve the
ISRs generated by the CPC for IORequests in a timely fashion, hence
violating the Z80 IO port protocol, crashing the system. The songs on
`ULTIMIDI2.dsk` and `ULTMIDI3.dsk` are at the absolut limit of what
can be recorded in REALTIME with the CPC + BluePill combo, and I had
to record them with the CPC 464, as my 6128 was having timing issues
here. It is possible that I will try to tweak the firmware a bit more
at some point, but not much can be done to eleviate this problem, as
the bandwidth / speed is simply not there in the BluePill (one would
think 72 MHz are enough, but... it is at the limit).

Note that this problem only occurs for ultra-complex polyphonic MIDI
data realtime recording / streaming (i.e., a whole MIDI song is being
recorded in that way in realtime, not only a single MIDI instrument
track as one would usually do in a classical MIDI sequencer
application), and that the problem only occurs for recording, not for
playback. Also, less complex MID songs are entirely unproblematic,
i.e., recording classical music that usually consists of piano track
only etc. does not cause any bandwidth issues.

At some point, I also want to write a MID file player for the CPC
(other customers are also working on this). Then there would be no
need to "record" the MIDI songs in that way. 

## Latest News

- 7/1/2021: MIDI Data Stream Recorder implemented - I can now record & play back complex GM MIDI songs from the CPC memory. As usual, the Z80 assembler source code of the [MIDI recorder & playback program and a number of BIN song files are in the repo](cpc/ULTMIDI2.dsk). A demo of the program and the 8 song `BIN`s is on YouTube: [Standalone CPC MIDI Playback](https://youtu.be/9-n1bf7yXhg). I expect this kind of "MIDI data playback from CPC memory" to be the main application for the card, so most people will just use it as a MIDI sound card for their CPCs. However, unlike other MIDI sound cards, you can effortlessly create MIDI songs simply by recording the MIDI stream; hence, content / song creation for the card is literally effortless if you have a PC USB MIDI cable. 

The friends from [Matrixsynth](https://www.matrixsynth.com/2021/07/the-ultimate-cpc-midi-soundcard.html) also posted my update - thanks, guys! 

![Matrixsynth New](pics/matrixsynth4.png) 

 
- 6/23/2021: First batch produced and sold! 

![First Batch](pics/first-batch.jpg) 


- 6/19/2021: The Prototype PCBs are working! 

![Pic PCB 1](pics/board-1.jpg) 

- 6/11/2021: The Prototype PCBs have been designed and are currently in production. 

![PCB 1](pics/pcb.png) 
![PCB 2](pics/pcb2.png) 


- 6/1/2021: The project was featured by Matrixsynth. 

![Maxrix 1](pics/matrixsynth1.png) 

![Maxrix 2](pics/matrixsynth3.png) 

![Maxrix 3](pics/matrixsynth3.png) 

## About

Soon! 


