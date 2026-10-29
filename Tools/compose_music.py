"""Render four original, deterministic 16-bar game loops with NumPy.

Usage: python3 Tools/compose_music.py /tmp/the-cube-music
Convert the resulting WAV masters to the app's M4A files with afconvert.
No downloaded samples, external compositions, or runtime synthesis are used.
"""
from pathlib import Path
import json
import sys
import wave
import numpy as np

RATE = 44100
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/tmp/the-cube-music')
OUT.mkdir(parents=True, exist_ok=True)


def envelope(t, duration, attack=0.008, release=0.04, decay=0.0):
    return (np.minimum(t / attack, 1) * np.minimum((duration - t) / release, 1)
            * np.exp(-t * decay)).clip(0, 1)


def voice(note, duration, kind):
    t = np.arange(round(duration * RATE)) / RATE
    f = 440 * 2 ** ((note - 69) / 12)
    phase = 2 * np.pi * f * t
    if kind == 'pad':
        signal = (np.sin(phase) + .22 * np.sin(phase * 2 + .1 * np.sin(t * 3))) / 1.22
        env = envelope(t, duration, .18, .35)
    elif kind == 'bass':
        signal = .8 * np.sin(phase) + .13 * np.sin(phase * 2) + .06 * np.sin(phase * 3)
        env = envelope(t, duration, .006, .05, 1.2)
    elif kind == 'marimba':
        signal = np.sin(phase) + .35 * np.exp(-t * 18) * np.sin(phase * 4)
        env = envelope(t, duration, .003, .04, 6)
    elif kind == 'flute':
        signal = np.sin(phase + .035 * np.sin(2 * np.pi * 5 * t)) + .13 * np.sin(phase * 2)
        env = envelope(t, duration, .035, .12, 1)
    elif kind == 'neon':
        signal = (np.sin(phase) + .20 * np.sin(phase * 2) + .10 * np.sin(phase * 3)
                  + .035 * np.sin(phase * 5))
        env = envelope(t, duration, .007, .07, 2.5)
    else:
        signal = np.sin(phase) + .11 * np.sin(phase * 3)
        env = envelope(t, duration, .008, .06, 3)
    return signal * env


def compose(name, bpm, chords, melodies, seed):
    rng = np.random.default_rng(seed)
    beat = 60 / bpm
    count = round(64 * beat * RATE)
    mix = np.zeros((count, 2), dtype=np.float64)

    def add(signal, at, gain, pan=0):
        # Wrap note tails across the loop boundary rather than cutting them off.
        start = round(at * beat * RATE) % count
        weights = np.sqrt([(1 - pan) / 2, (1 + pan) / 2])
        signal = signal[:, None] * weights[None, :] * gain
        first = min(len(signal), count - start)
        mix[start:start + first] += signal[:first]
        if first < len(signal):
            mix[:len(signal) - first] += signal[first:]

    def note(midi, at, beats, kind, gain, pan=0):
        add(voice(midi, beats * beat, kind), at, gain, pan)

    def drum(at, kind, gain):
        duration = .28 if kind in ('kick', 'conga') else .14
        t = np.arange(round(duration * RATE)) / RATE
        if kind == 'kick':
            frequency = 48 + 95 * np.exp(-t * 35)
            phase = 2 * np.pi * np.cumsum(frequency) / RATE
            signal = np.sin(phase) * np.exp(-t * 19)
        elif kind == 'conga':
            signal = (np.sin(2 * np.pi * 155 * t + 1.8 * np.exp(-t * 60))
                      + .25 * np.sin(2 * np.pi * 235 * t)) * np.exp(-t * 20)
        elif kind == 'snare':
            signal = (.65 * rng.normal(size=len(t)) * np.exp(-t * 45)
                      + .25 * np.sin(2 * np.pi * 185 * t) * np.exp(-t * 28))
        else:
            noise = rng.normal(size=len(t))
            signal = (noise - np.roll(noise, 1)) * np.exp(-t * (80 if kind == 'hat' else 45))
        signal *= envelope(t, duration, .001, .008)
        add(signal, at, gain, -.2 if kind == 'shaker' else 0)

    for bar in range(16):
        chord = chords[(bar // 2) % len(chords)]
        at = bar * 4
        if bar % 2 == 0:
            for index, pitch in enumerate(chord):
                note(pitch, at, 8.4, 'pad', .065 if name == 'menu' else .04, (index - 1) * .45)
        for step in range(4):
            if name == 'menu' and step % 2:
                continue
            pitch = chord[0] - 12 + (7 if step == 3 and name == 'neon' else 0)
            note(pitch, at + step, .65, 'bass', .13 if name == 'menu' else .18)
        for step in range(8):
            pitch = chord[[0, 1, 2, 1, 0, 2, 1, 2][step]] + 12
            if name == 'menu' and step % 2:
                continue
            note(pitch, at + step * .5, .7, 'marimba' if name == 'jungle' else 'soft',
                 .075 if name == 'jungle' else .035, .38 * (-1 if step % 2 else 1))
        motif = melodies[bar % len(melodies)]
        for step, pitch in enumerate(motif):
            if pitch is None:
                continue
            length = .85 if step % 2 == 0 else .55
            kind = 'flute' if name == 'jungle' else 'neon' if name == 'neon' else 'soft'
            note(pitch, at + step * .5, length, kind, .13 if name == 'menu' else .15, -.08)
        if name == 'menu':
            drum(at, 'kick', .10)
            drum(at + 2.5, 'shaker', .015)
        elif name == 'jungle':
            for step in [0, 1.5, 2.5, 3.25]:
                drum(at + step, 'conga', .11 if step == 0 else .075)
            drum(at, 'kick', .22)
            drum(at + 2, 'kick', .18)
            for step in range(8):
                drum(at + step / 2, 'shaker', .018 if step % 2 else .026)
        else:
            for step in ([0, 1, 2, 3] if name == 'neon' else [0, 2, 2.75]):
                drum(at + step, 'kick', .26)
            for step in [1, 3]:
                drum(at + step, 'snare', .10)
            for step in range(8):
                drum(at + step / 2, 'hat', .018 if step % 2 else .026)
        if bar in (7, 15) and name != 'menu':
            for step in [3.25, 3.5, 3.75]:
                drum(at + step, 'conga' if name == 'jungle' else 'snare', .045)

    # Circular delays preserve a continuous tail at the exact bar boundary.
    dry = mix.copy()
    for beats, gain in [(.75, .14), (1.5, .06)]:
        mix += np.roll(dry[:, ::-1], round(beats * beat * RATE), axis=0) * gain
    mix = np.tanh(mix * 1.1)
    mix -= mix.mean(axis=0)
    mix *= .72 / np.max(np.abs(mix))
    pcm = (mix * 32767).round().astype('<i2')
    with wave.open(str(OUT / f'{name}.wav'), 'wb') as file:
        file.setnchannels(2)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(pcm.tobytes())
    stats = {'bpm': bpm, 'bars': 16, 'seconds': count / RATE,
             'peak': float(np.max(np.abs(mix))), 'rms': float(np.sqrt(np.mean(mix ** 2))),
             'loop_step': float(np.max(np.abs(mix[0] - mix[-1])))}
    print(name, json.dumps(stats))
    return stats


# Original motifs; None leaves space between phrases.
minor = [[57, 60, 64], [53, 57, 60], [60, 64, 67], [55, 59, 62]]
melody_a = [
    [76, None, 79, 81, None, 79, 76, None],
    [72, None, 76, None, 74, 72, None, None],
    [77, None, 76, 72, None, 69, 72, None],
    [76, 72, None, 69, 72, None, None, None],
    [79, None, 76, 79, 84, None, 83, 79],
    [76, None, 79, None, 76, 74, None, None],
    [74, None, 79, 78, None, 74, 71, None],
    [74, None, 71, 67, 71, None, 76, None],
]
neon_chords = [[50, 53, 57], [46, 50, 53], [53, 57, 60], [48, 52, 55]]
neon_melody = [[n - 7 if n is not None else None for n in phrase] for phrase in melody_a]
jungle_chords = [[50, 53, 57], [55, 59, 62], [57, 60, 64], [48, 52, 55]]
jungle_melody = [
    [74, None, 77, 81, None, 77, 74, None],
    [72, 74, None, 69, 74, None, None, None],
    [79, None, 83, 86, None, 83, 81, None],
    [79, None, 74, None, 71, 74, None, None],
    [81, None, 84, 88, None, 84, 81, None],
    [79, 81, None, 76, 72, None, None, None],
    [79, None, 76, 72, None, 76, 79, None],
    [76, None, 74, 72, 67, None, 69, None],
]
metadata = {}
metadata['menu'] = compose('menu', 96, minor, melody_a, 101)
metadata['twilight'] = compose('twilight', 110, minor, melody_a[2:] + melody_a[:2], 202)
metadata['neon'] = compose('neon', 124, neon_chords, neon_melody, 303)
metadata['jungle'] = compose('jungle', 116, jungle_chords, jungle_melody, 404)
(OUT / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
