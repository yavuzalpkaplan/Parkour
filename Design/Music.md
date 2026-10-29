# The Cube soundtrack

Four original instrumental loops, composed and synthesized for this project. No
sample packs, third-party tracks, or online music-generation services are used.

| File | Title | Tempo | Loop length | Arrangement |
| --- | --- | --- | --- | --- |
| menu.m4a | Before the Jump | 96 BPM | 40.00 s | Soft synth melody, wide pads, sparse percussion |
| twilight.m4a | Twilight Stride | 110 BPM | 34.91 s | Arcade lead, plucked arpeggios, bass and drums |
| neon.m4a | Rooftop Circuit | 124 BPM | 30.97 s | Brighter synth lead, driving four-beat electronic rhythm |
| jungle.m4a | Rain Canopy | 116 BPM | 33.10 s | Flute-like lead, marimba, hand drums and shakers |

Each piece is 16 bars in 4/4. Note tails and stereo delay wrap across the loop
boundary. Masters are stereo 44.1 kHz PCM with a 0.72 peak ceiling; bundled
resources use 128 kbps AAC with encoder timing metadata preserved.

## Rebuild the audio

Requires Python 3 and NumPy, plus macOS `afconvert`:

```sh
python3 Tools/compose_music.py /tmp/the-cube-music
```

For each track (`menu`, `twilight`, `neon`, `jungle`):

```sh
afconvert -f m4af -d 'aac ' -b 128000 -q 96 /tmp/the-cube-music/menu.wav Parkour/Audio/menu.m4a
```

## Runtime behavior

- Menus, results, and gameplay all use the selected map's loop. The original
  menu composition is retained as an unused source asset.
- Map changes stop the previous track before fading in the next. Start and Restart
  restart the selected map's track; other menus keep the current playback position.
- Settings > Music and the 0–100% volume slider persist between launches.
  The default volume is 32%, matching the original mix. Adjusting volume while
  Music is off remembers the level without enabling playback.
- Backgrounding pauses audio; returning resumes the current track.
- The ambient audio category respects the iPhone silent switch and mixes with
  other audio. Music is synthesized offline, never during gameplay.
