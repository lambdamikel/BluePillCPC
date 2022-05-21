README for the Ultimate MIDI Card for the Amstrad CPC
=====================================================

A recent customer asked me how to get going with the card, so I wrote
this little README. 

There isn't more documentation at this point other than this README
and the Github material. I would suggest to just start with the
ULTMIDI.DSK and programs

MIDIOUT.BAS and MIDIDRUM.BAS

See

https://youtu.be/xLs3ZQm0AvA

That should give you some sound from the stereo socket, and also in
the CPC speaker if you have set the DIP switches 5 & 6 correctly.

Next, I would try to play the MIDI song "SONG2.BIN" from

ULTMIDI3.DSK

(use "Play" option when the program starts), and see if you can hear
Alan Parson's.

See

https://youtu.be/zATfSDlGLWw

For CPC -> S2 card working, you must have DIP Switch 1 set correctly
("Route CPC to S2") See Github for explanation of the switches.

Next, if you have a MIDI Sound Module or synthesizer, you can try
connecting it to the MIDI DIN OUT socket and see if you can playback
the same sounds / songs with the external device. Note that you need
to have DIP Switch 2 set correctly ("Route CPC to MIDI OUT"). You can
have both 1 and 2 at the same time.

Next, you can try MIDI Input. For that, you will need a MIDI device
that can generate MIDI data, e.g., a synth or keyboard, or a MIDI USB
PC Cable and a program on the PC / Mac that can generate MIDI data.

Now, with the MIDI Device connected to MIDI IN, if the DIP switch 3 is
enabled, then the firmware will automatically forward any incoming /
received MIDI message to the S2. Without CPC involvement. So allows
you to use the card as a standalone MIDI instrument, really. You only
need 5V power from the CPC, but no CPC program. This then basically
like a "standalone Roland SOund Canvas". If you can find a way to feed
5 V into the card without the CPC, you have a real standalone GM Midi
expander like the sound blaster.

Next, the card can also act as an additional MIDI Forwarder /
Repeater. So, this is like the MIDI THROUGH socket on synthesizer /
MIDI devices. Each incoming MIDI message is automatically forwarded to
MIDI OUT if DIP switch 4 is enabled. Then, with 3 and 4 enable, you
can play MIDI on the card, and forward the same data at the same time
to another connected MIDI device that gets connected to the MIDI OUT
socket of the card. This is basically to "daisy chain" MIDI devices.

Now, if you want to process the incoming MIDI data from the MIDI IN
socket with the CPC, then you want to disable switch 3 (because else
everything is played automatically by the S2).

So next test then is to disable switch 3, connect your MIDI keyboard
or PC USB MIDI cable to MIDI IN as before, and load the program
"CPCSYNTH.BAS" from the ULTMIDI.DSK. You will need MAXAM 1.4 assembler
in ROM. Once the program starts, (press a key), you should see
incoming MIDI synch messages on the screen from the external MIDI
device or MIDI USB PC cable.

Any incoming MIDI Note On / Off message will be played in the CPC
speaker; i.e., the AY-3-8912 / CPC acts as a MIDI instrument now. It
is 3note polyphonic.

Whereas CPCSYNTH demonstrates how to turn the CPC into a MIDI
instrument using MIDI IN, the CPCTHRU.BAS program demonstrates how,
with the CPC, receive MIDI data, and simply forward it. So, with an
external MIDI exander connected to MIDI OUT, any incoming MIDI message
will be relayed *by the CPC program, not by the firmware* to the other
device. Note that this achieves the same effect as described above,
but this time the forwarding function is "computed" by the CPC rather
than the firmware.

Of course, this gives more flexibility, because now we can change the
MIDI data stream "on the fly" with a CPC program, and this is
demonstrated in "CPCTRAFO.BAS". Here, MIDI data can be transposed by
0, 1, 2 octaves with the CPC program.

See

https://youtu.be/Th2IpnHSq80

Finally, you can try to record a whole complex MIDI Data Sequence into
CPC memory, and save it to disk. This is how the songs on ULTMIDI3.DSK
and ULTMIDI2.DSK were created. I played back a GM MID song on the PC,
streamed the MIDI messages via the CPC USB MIDI cable into the card,
and used the "RECORDER2" program on ULTMIDI3.DSK to sample and store
to CPC memory any received MIDI message. Together with timestamp
data. This allows me then to play the song back from CPC
memory. However, the data format is not optmiized, and the program is
proof-of-concept and bare bones. So depending on the complexity of the
MIDI data that is being recorder in that way, you'll reach end of CPC
memory after about 30 seconds to 1 minute, and then the program
crashes when firmware locations are overwritten in RAM I should find
some time to improve the program. So, when you are recording, make
sure to hit "x" for quit early enough during recording, else it
crashes your CPC.

For the recording process, see here: 

https://youtu.be/9-n1bf7yXhg?t=780

Also, depending on the complexity of the MIDI, this is at the limit of
what the CPC can do. If the MIDI is too complex, the CPC might also
crash. And this is casued by the Blue Pill. Note that I am doing all
the IOREAD / IOWRITE request handling in software in the BluePill
microcontroller. So if there are too many IORequests happening and at
the same time, Interupt Requests from the incoming MIDI data, then the
BluePill does not have enough speed / time to process the CPC databus
IORQ timely enough, and that crashes the system. The songs on
ULTIMIDI2 and ULTMIDI3 are at the absolut limit, and I had to record
them with the CPC 464, as my 6128 was having timing issues here.

It is possible that I will try to tweak the firmware a bit more at
some point, but not much can be done to eleviate this problem, as the
processing power is simply not there.

However, if you are only using a single track of music via MIDI in in
that way, or classical music, then there shouldn't be an issue at all
with the bandwith. Also, I want to write a MID file player at some
point (somebody else is also working on this). Then there is no need
to "record" these multi mega complex MIDI stream in realtime with the
CPC anyhow.

All the best, let me know if you have any issues with it,
