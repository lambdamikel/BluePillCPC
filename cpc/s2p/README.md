MIDI player for Willy + S2P
===========================

This is a version of LambdaMikel's MIDI player for the Willy adapter combined with the S2P MIDI
synthetizer.

Changes made compared to the original version:
- Added initialization of the S2P card at the start of replay
- Changed address where to send the MIDI data (unfortunately, due to lack of coordination, Willy
  can't be configured to use the same addresses as LambdaMikel's interfaces. Sorry about that.)

This version of the player is compatible with the files found in PLAYBCK1.DSK. The players for the
other versions could easily be adjusted too, but I don't have a 512K memory expansion on my CPC (yet) so
I can't try them all. It probably makes more sense, anyway, to either stream the data from disk
if UniDOS-compatible storage is available (like the VGM player for Willy+OPL3 does), or compress
it somehow (I expect that songs with repeated sections could compress quite well, but there are not
much readily-usable options for a streaming decompression system on the CPC).
