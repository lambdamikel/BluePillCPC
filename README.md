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


