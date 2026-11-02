#!/usr/bin/env python3
"""
ECHOES -- procedural synthwave-chiptune soundtrack + SFX synthesizer.
(Adapted from Last Light's tools/make_audio.py.)

    python3 tools/make_audio.py            # render everything, verify, draw PNGs
    python3 tools/make_audio.py --no-png   # skip spectrogram PNGs

Output: assets/audio/*.wav  (16-bit PCM, mono, 32000 Hz)
        assets/audio/png/*.png (waveform + spectrogram sanity plots; has .gdignore)

Same tiny tracker / polyBLEP oscillators / periodic loop-wrapping engine as Last
Light, plus synthwave voices: detuned saw+pulse leads, filter-envelope saw bass,
80s gated snare, noise risers and beat-synced sidechain "pump" on pad/bass.
Loops are exactly periodic (tails folded, effects run over 3 tiled copies) and
carry a RIFF 'smpl' loop chunk [0, N) for Godot's "Detect From WAV".
"""
import os
import struct
import sys
from fractions import Fraction

import numpy as np
from scipy import signal

SR = 32000
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
OUT = os.path.join(ROOT, 'assets', 'audio')
PNG = os.path.join(OUT, 'png')

MUSIC_PEAK = 10 ** (-3 / 20)   # -3 dBFS
SFX_PEAK = 10 ** (-1 / 20)     # -1 dBFS

RNG = np.random.default_rng(20261101)   # deterministic renders

# ----------------------------------------------------------------------------
# pitch helpers
# ----------------------------------------------------------------------------
_PC = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def midi(name):
    name = name.strip()
    pc = _PC[name[0].upper()]
    i = 1
    while i < len(name) and name[i] in '#b':
        pc += 1 if name[i] == '#' else -1
        i += 1
    return 12 * (int(name[i:]) + 1) + pc


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


# ----------------------------------------------------------------------------
# filters
# ----------------------------------------------------------------------------
def _sos(kind, f, order=2):
    nyq = SR / 2
    if kind == 'band':
        return signal.butter(order, [f[0] / nyq, min(f[1] / nyq, 0.99)], 'bandpass', output='sos')
    return signal.butter(order, min(f / nyq, 0.99), kind, output='sos')


def lowpass(x, f, order=2):
    return signal.sosfilt(_sos('low', f, order), x)


def highpass(x, f, order=2):
    return signal.sosfilt(_sos('high', f, order), x)


def bandpass(x, lo, hi, order=2):
    return signal.sosfilt(_sos('band', (lo, hi), order), x)


def sweep_lowpass(x, cutoff):
    """Two-pole (cascaded one-pole) low-pass with a per-sample cutoff array."""
    a = 1.0 - np.exp(-2 * np.pi * np.asarray(cutoff) / SR)
    y1 = y2 = 0.0
    out = np.empty_like(x)
    for i in range(len(x)):
        y1 += a[i] * (x[i] - y1)
        y2 += a[i] * (y1 - y2)
        out[i] = y2
    return out


# ----------------------------------------------------------------------------
# oscillators (band-limited with polyBLEP)
# ----------------------------------------------------------------------------
def _blep(t, dt):
    out = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    out[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    x = (t[m] - 1.0) / dt[m]
    out[m] = x * x + x + x + 1.0
    return out


def _phase(f, ph0=0.0):
    dt = np.asarray(f, dtype=float) / SR
    ph = (np.cumsum(dt) - dt[0] + ph0) % 1.0
    return ph, np.minimum(dt, 0.45)


def osc_pulse(f, duty=0.5, ph0=0.0):
    t, dt = _phase(f, ph0)
    y = np.where(t < duty, 1.0, -1.0)
    y += _blep(t, dt)
    y -= _blep((t - duty) % 1.0, dt)
    return y - (2 * duty - 1)


def osc_saw(f, ph0=0.0):
    t, dt = _phase(f, ph0)
    return 2 * t - 1 - _blep(t, dt)


def osc_tri(f, steps=16, ph0=0.0):
    t, _ = _phase(f, ph0)
    y = 4 * np.abs(t - 0.5) - 1
    if steps:
        y = np.round((y + 1) / 2 * (steps - 1)) / (steps - 1) * 2 - 1   # 4-bit chip triangle
    return y


def osc_sine(f, ph0=0.0):
    t, _ = _phase(f, ph0)
    return np.sin(2 * np.pi * t)


def noise(n):
    return RNG.standard_normal(n)


# ----------------------------------------------------------------------------
# envelopes / modulation
# ----------------------------------------------------------------------------
def adsr(n_gate, a=0.005, d=0.1, s=0.7, r=0.08):
    n_gate = max(int(n_gate), 8)
    na, nd, nr = max(int(a * SR), 1), max(int(d * SR), 1), max(int(r * SR), 1)
    i = np.arange(n_gate)
    env = np.where(i < na, i / na, s + (1 - s) * np.exp(-(i - na) / (nd / 3.0)))
    rel = env[-1] * (1 - np.arange(nr) / nr) ** 2
    return np.concatenate([env, rel])


def vibrato(n, cents, rate=5.5, delay=0.2, ramp=0.25):
    t = np.arange(n) / SR
    depth = np.clip((t - delay) / ramp, 0, 1)
    return 2 ** (cents / 1200.0 * np.sin(2 * np.pi * rate * t) * depth)


def fades(x, fin=0.002, fout=0.01):
    x = x.copy()
    ni, no = int(fin * SR), int(fout * SR)
    if ni:
        x[:ni] *= np.linspace(0, 1, ni) ** 2
    if no:
        x[-no:] *= np.linspace(1, 0, no) ** 2
    return x


# ----------------------------------------------------------------------------
# instruments:   play(pitch_or_drum_name, duration_seconds, velocity) -> array
# ----------------------------------------------------------------------------
def Pulse(duty=0.5, a=0.004, d=0.2, s=0.6, r=0.06, vib=0.0, vrate=5.5, vdelay=0.2,
          gate=0.92, lp=None, blip=0.0, detune=0.0):
    def play(p, dur, vel):
        env = adsr(dur * gate * SR, a, d, s, r)
        n = len(env)
        f = np.full(n, hz(p) * 2 ** (detune / 1200))
        if vib:
            f *= vibrato(n, vib, vrate, vdelay)
        if blip:   # tiny pitch drop at attack -> "chip" articulation
            f *= 2 ** (blip / 12 * np.exp(-np.arange(n) / (0.012 * SR)))
        y = osc_pulse(f, duty)
        if lp:
            y = lowpass(y, lp)
        return y * env * vel
    return play


def Tri(a=0.003, d=0.12, s=0.8, r=0.03, gate=0.9, steps=16, lp=6000):
    def play(p, dur, vel):
        env = adsr(dur * gate * SR, a, d, s, r)
        y = osc_tri(np.full(len(env), hz(p)), steps)
        if lp:
            y = lowpass(y, lp)
        return y * env * vel
    return play


def Bell(tau=0.65, ring=1.1, bright=0.35, tine=0.10, dark=False):
    """Music-box / celesta: sine + decaying 2nd/3rd partials + inharmonic tine."""
    def play(p, dur, vel):
        f = hz(p)
        n = int((dur + ring) * SR)
        t = np.arange(n) / SR
        y = np.sin(2 * np.pi * f * t)
        y += bright * np.exp(-t / 0.18) * np.sin(2 * np.pi * 2 * f * t + 0.3)
        y += 0.10 * np.exp(-t / 0.35) * np.sin(2 * np.pi * 3 * f * t)
        if not dark and 5.4 * f < 14000:
            y += tine * np.exp(-t / 0.025) * np.sin(2 * np.pi * 5.4 * f * t)
        env = np.exp(-t / tau) * np.minimum(t / 0.0015, 1)
        y = fades(y * env, 0, 0.03)
        return y * vel
    return play


def Strings(voices=5, spread=14.0, cutoff=2000, a=0.3, d=0.5, s=0.85, r=0.6, gate=1.0, vib=5.0):
    det = np.linspace(-spread, spread, voices)
    phs = [0.0, 0.37, 0.71, 0.13, 0.55, 0.89, 0.24][:voices]

    def play(p, dur, vel):
        env = adsr(dur * gate * SR, a, d, s, r)
        n = len(env)
        base = hz(p) * vibrato(n, vib, 4.8, 0.3, 0.6)
        y = sum(osc_saw(base * 2 ** (c / 1200), ph) for c, ph in zip(det, phs)) / np.sqrt(voices)
        y = lowpass(y, cutoff, 2)
        return y * env * vel
    return play


# -- drums -------------------------------------------------------------------
def _t(sec):
    return np.arange(int(sec * SR)) / SR


def d_kick(vel, tone=48, punch=130):
    t = _t(0.32)
    f = tone + punch * np.exp(-t / 0.022)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.13)
    y = np.tanh(2.4 * y)                                   # harmonics -> audible on phones
    y += 0.35 * highpass(noise(len(t)), 2000) * np.exp(-t / 0.0025)
    return y * vel


def d_snare(vel):
    t = _t(0.26)
    nz = np.repeat(noise(len(t) // 2 + 1), 2)[:len(t)]      # slightly lo-fi noise
    nz = bandpass(nz, 900, 9000) * np.exp(-t / 0.075)
    f = 175 + 90 * np.exp(-t / 0.012)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.045)
    return (0.9 * nz + 0.65 * body) * vel


def d_hat(vel):
    t = _t(0.07)
    return highpass(noise(len(t)), 7000, 2) * np.exp(-t / 0.016) * vel


def d_ohat(vel):
    t = _t(0.35)
    return highpass(noise(len(t)), 6000, 2) * np.exp(-t / 0.11) * vel


def d_crash(vel):
    t = _t(1.8)
    y = highpass(noise(len(t)), 3500, 2) * np.exp(-t / 0.55)
    y += 0.3 * bandpass(noise(len(t)), 5000, 9000) * np.exp(-t / 0.2)
    return y * vel


def _tom(vel, base):
    t = _t(0.35)
    f = base + base * 0.7 * np.exp(-t / 0.035)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.13)
    y = np.tanh(1.8 * y) + 0.15 * bandpass(noise(len(t)), 500, 4000) * np.exp(-t / 0.03)
    return y * vel


DRUMS = {
    'kick': d_kick, 'snare': d_snare, 'hat': d_hat, 'ohat': d_ohat, 'crash': d_crash,
    'tomh': lambda v: _tom(v, 200), 'tomm': lambda v: _tom(v, 150), 'toml': lambda v: _tom(v, 105),
    'bkick': lambda v: d_kick(v, 42, 160),                 # heavier boss kick
}


def Drum(name):
    return lambda p, dur, vel: DRUMS[name](vel)


# ----------------------------------------------------------------------------
# effects
# ----------------------------------------------------------------------------
def echo(delay_s, fb=0.35, mix=0.3, lp_hz=2800):
    """SNES-style echo: feedback delay with a low-pass inside the loop."""
    def fx(x):
        D = int(round(delay_s * SR))
        sos = _sos('low', lp_hz, 1)
        zi = np.zeros((sos.shape[0], 2))
        wet = np.zeros(len(x))
        for st in range(D, len(x), D):
            en = min(st + D, len(x))
            src = x[st - D:en - D] + fb * wet[st - D:en - D]
            y, zi = signal.sosfilt(sos, src, zi=zi)
            wet[st:en] = y
        return x + mix * wet
    return fx


def make_ir(rt60=1.8, predelay=0.018, lp=4500, seed=7):
    rng = np.random.default_rng(seed)
    n = int(rt60 * 1.2 * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-6.9 * t / rt60)
    dark = lowpass(ir, lp * 0.35)                      # high end dies faster
    w = np.clip(t / rt60, 0, 1)
    ir = lowpass(ir, lp) * (1 - w) + dark * w
    for dly, g in ((0.011, 0.5), (0.023, 0.35), (0.037, 0.25)):    # early reflections
        ir[int(dly * SR)] += g * 6
    ir = np.concatenate([np.zeros(int(predelay * SR)), ir])
    return ir / np.sqrt(np.sum(ir ** 2))


def reverb(ir):
    return lambda x: signal.oaconvolve(x, ir)[:len(x)]


def chain(fxs):
    def run(x):
        for f in fxs:
            x = f(x)
        return x
    return run


# ----------------------------------------------------------------------------
# the tracker
# ----------------------------------------------------------------------------
def seq(text, start=0, bpb=4, vel=1.0, transpose=0, check=True):
    """Parse 'A4:.75 C5:.5 r:1 | ...' into (start_beat, dur_beats, midi, vel)."""
    ev, t = [], Fraction(start)
    for bi, bar in enumerate(text.split('|')):
        toks = bar.split()
        if not toks:
            continue
        bt = Fraction(0)
        for tok in toks:
            v = vel
            if '@' in tok:
                tok, vs = tok.split('@')
                v = vel * float(vs)
            name, d = tok.split(':')
            d = Fraction(d)
            if name not in ('r', '-'):
                for nm in name.split('+'):
                    ev.append((float(t + bt), float(d), midi(nm) + transpose, v))
            bt += d
        if check and bt != bpb:
            raise ValueError(f'bar {bi} ({bar.strip()!r}) has {bt} beats, expected {bpb}')
        t += bt
    return ev


def grid(name, bar0, bars, bpb=4, steps=16, vel=1.0):
    """Drum grid: one string per bar; '.' rest, 'x' full, 'o' soft, '1'-'9' = n/10."""
    ev = []
    step = bpb / steps
    for bi, pat in enumerate(bars):
        pat = pat.replace(' ', '')
        assert len(pat) == steps, (name, bar0 + bi, pat)
        for si, ch in enumerate(pat):
            if ch == '.':
                continue
            v = {'x': 1.0, 'o': 0.5}.get(ch)
            if v is None:
                v = int(ch) / 10.0
            ev.append(((bar0 + bi) * bpb + si * step, step, name, v * vel))
    return ev


class Song:
    def __init__(self, bpm, bpb, bars, rev_ir=None, rev_mix=1.0):
        self.bpm, self.bpb, self.bars = bpm, bpb, bars
        self.spb = 60.0 / bpm
        self.channels = []
        self.rev_ir, self.rev_mix = rev_ir, rev_mix

    @property
    def n(self):
        return int(round(self.bars * self.bpb * self.spb * SR))

    def ch(self, name, inst, gain=1.0, fx=None, rev=0.0):
        c = dict(name=name, inst=inst, gain=gain, fx=fx or [], rev=rev, ev=[], raw=None)
        self.channels.append(c)
        return c

    def add(self, name, events):
        for c in self.channels:
            if c['name'] == name:
                c['ev'].extend(events)
                return
        raise KeyError(name)


def _render_dry(c, S, L):
    buf = np.zeros(L + 4 * SR)
    for st, du, p, v in c['ev']:
        s0 = int(round(st * S.spb * SR))
        y = c['inst'](p, du * S.spb, v)
        e = s0 + len(y)
        if e > len(buf):
            buf = np.concatenate([buf, np.zeros(e - len(buf))])
        buf[s0:e] += y
    if c['raw'] is not None:
        buf[:len(c['raw'])] += c['raw']
    return buf


def _fold(buf, L):
    """Wrap everything past the loop end back onto the start."""
    out = buf[:L].copy()
    k = L
    while k < len(buf):
        seg = buf[k:k + L]
        out[:len(seg)] += seg
        k += L
    return out


def _periodic(x, fn):
    """Run an LTI effect on a periodic signal: 3 copies, keep the middle."""
    L = len(x)
    y = fn(np.tile(x, 3))
    err = np.max(np.abs(y[L:2 * L] - y[2 * L:3 * L]))   # steady-state check
    return y[L:2 * L], err


def render(S, loop=True, total=None, verbose=True):
    L = S.n if loop else int(round(total * SR))
    mix, send = np.zeros(L), np.zeros(L)
    worst = 0.0
    for c in S.channels:
        dry = _render_dry(c, S, L)
        x = _fold(dry, L) if loop else np.pad(dry, (0, max(0, L - len(dry))))[:L]
        if c['fx']:
            if loop:
                x, err = _periodic(x, chain(c['fx']))
                worst = max(worst, err)
            else:
                x = chain(c['fx'])(x)
        x = x * c['gain']
        if verbose:
            rms = np.sqrt(np.mean(x ** 2)) + 1e-12
            print(f'      {c["name"]:<9} rms {20 * np.log10(rms):6.1f} dB  ({len(c["ev"])} ev)')
        mix += x
        send += x * c['rev']
    if S.rev_ir is not None and np.any(send):
        if loop:
            wet, err = _periodic(send, reverb(S.rev_ir))
            worst = max(worst, err)
        else:
            wet = reverb(S.rev_ir)(send)
        mix += S.rev_mix * wet
    return mix, worst


def master(x, peak, drive=1.4):
    x = x / np.max(np.abs(x))
    x = np.tanh(drive * x) / np.tanh(drive)      # gentle static peak rounding (loop-safe)
    return x * (peak / np.max(np.abs(x)))


# ----------------------------------------------------------------------------
# WAV writer (with optional 'smpl' loop chunk)
# ----------------------------------------------------------------------------
def write_wav(path, x, loop=False):
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype('<i2')
    data = pcm.tobytes()
    body = struct.pack('<4sIHHIIHH', b'fmt ', 16, 1, 1, SR, SR * 2, 2, 16)
    body += struct.pack('<4sI', b'data', len(data)) + data
    if loop:
        n = len(pcm)
        smpl = struct.pack('<9I', 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack('<6I', 0, 0, 0, n, 0, 0)     # forward loop [0, n)
        body += struct.pack('<4sI', b'smpl', len(smpl)) + smpl
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sI4s', b'RIFF', 4 + len(body), b'WAVE') + body)




# ============================================================================
# extra synthwave instruments / fx
# ============================================================================
def Saw(voices=1, spread=0.0, cutoff=4000, a=0.005, d=0.2, s=0.7, r=0.08, vib=0.0, vrate=5.5,
        vdelay=0.2, gate=0.92, pulse_mix=0.0, duty=0.25, blip=0.0, droop=0.0):
    """Detuned saw (+ optional pulse layer) lead. droop = semitones of 'power-down' fall over the note."""
    det = list(np.linspace(-spread, spread, voices)) if voices > 1 else [0.0]
    phs = [0.0, 0.37, 0.71, 0.13, 0.55, 0.89, 0.24]

    def play(p, dur, vel):
        env = adsr(dur * gate * SR, a, d, s, r)
        n = len(env)
        f = np.full(n, hz(p))
        if vib:
            f *= vibrato(n, vib, vrate, vdelay)
        if blip:
            f *= 2 ** (blip / 12 * np.exp(-np.arange(n) / (0.012 * SR)))
        if droop:
            f *= 2 ** (-droop / 12 * np.clip(np.arange(n) / n * 1.6 - 0.4, 0, 1) ** 2)
        y = sum(osc_saw(f * 2 ** (c / 1200), ph) for c, ph in zip(det, phs)) / np.sqrt(len(det))
        if pulse_mix:
            y = (1 - pulse_mix) * y + pulse_mix * osc_pulse(f, duty)
        y = lowpass(y, cutoff)
        return y * env * vel
    return play


def SawBass(lo=350, hi=2600, fdecay=0.07, a=0.002, d=0.12, s=0.75, r=0.025, gate=0.82, sub=0.5, sq=0.45):
    """Synthwave bass: saw + square with a plucky filter envelope (crossfaded LPs) + sine sub."""
    def play(p, dur, vel):
        env = adsr(dur * gate * SR, a, d, s, r)
        n = len(env)
        f = np.full(n, hz(p))
        raw = 0.75 * osc_saw(f) + sq * osc_pulse(f, 0.5)
        e = np.exp(-np.arange(n) / (fdecay * SR))
        y = lowpass(raw, lo) * (1 - e) + lowpass(raw, hi) * e
        y += sub * osc_sine(f)
        return y * env * vel
    return play


def Riser(lo=300, hi=9000):
    """Noise riser whose length is the note duration."""
    def play(p, dur, vel):
        n = int(dur * SR)
        u = np.arange(n) / n
        y = sweep_lowpass(highpass(noise(n), 250), lo * (hi / lo) ** u) * 2.5
        return fades(y * u ** 2 * vel, 0, 0.004)
    return play


def d_gsnare(vel):
    """80s gated snare: crack + body + a 'room' that is chopped off by a gate at 150 ms."""
    t = _t(0.24)
    nz = np.repeat(noise(len(t) // 2 + 1), 2)[:len(t)]
    crack = bandpass(nz, 1200, 9500) * np.exp(-t / 0.03)
    gate = np.where(t < 0.15, 1 - 1.4 * t, 0.79 * np.exp(-(t - 0.15) / 0.007))
    room = bandpass(noise(len(t)), 500, 7500) * 0.5 * gate
    f = 190 + 110 * np.exp(-t / 0.01)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.05)
    return (0.8 * crack + room + 0.7 * body) * vel


DRUMS['gsnare'] = d_gsnare
DRUMS['skick'] = lambda v: d_kick(v, 50, 140)


def pump(spb, depth=0.55, rel=0.32):
    """Sidechain-style ducking on every beat (exactly periodic: spb*SR is an integer here)."""
    P = int(round(spb * SR))

    def fx(x):
        ph = (np.arange(len(x)) % P) / P
        return x * (1 - depth * (1 - np.minimum(ph / rel, 1)) ** 2)
    return fx


def arp(S, ch, t0, beats, tones, pattern, step, vel=1.0, acc_every=4, up=0, gate_vel=0.72):
    k = 0
    t = 0.0
    while t < beats - 1e-9:
        m = tones[pattern[k % len(pattern)]] + up
        v = vel * (1.0 if k % acc_every == 0 else gate_vel)
        S.add(ch, [(t0 + t, step, m, v)])
        t += step
        k += 1


def notes(spec):
    return [midi(x) for x in spec.split()]


# ============================================================================
# COMPOSITIONS
# ============================================================================
def bass_note(root_name, lo, hi):
    m = midi(root_name + '4')
    while m > hi:
        m -= 12
    while m < lo:
        m += 12
    return m


def root_of(chd):
    return chd.replace('m', '').replace('p', '').replace('7', '')


# ---------------------------------------------------------------------------
# 1. TITLE -- "Neon Afterimage"   F# minor, 100 bpm, 14 bars = 33.6 s
# ---------------------------------------------------------------------------
def song_title():
    S = Song(100, 4, 14, rev_ir=make_ir(2.8, 0.03, 4500), rev_mix=1.0)
    prog = ['F#m', 'D'] + ['F#m', 'D', 'A', 'E'] * 2 + ['Bm', 'D', 'A', 'C#']
    pad = {'F#m': 'F#3+C#4+A4', 'D': 'F#3+D4+A4', 'A': 'E3+C#4+A4', 'E': 'E3+B3+G#4',
           'Bm': 'F#3+D4+B4', 'C#': 'E#3+C#4+G#4'}
    arpt = {'F#m': 'F#4 A4 C#5 F#5', 'D': 'D4 F#4 A4 D5', 'A': 'C#4 E4 A4 C#5', 'E': 'B3 E4 G#4 B4',
            'Bm': 'B3 D4 F#4 B4', 'C#': 'C#4 E#4 G#4 C#5'}

    tease = 'C#6:1 F#6:1 A6:2 | r:4'
    melA = """
      C#5:1 F#5:1 A5:1.5 G#5:.5        | F#5:3 E5:.5 F#5:.5
    | E5:.75 C#5:.75 E5:.5 A5:1.5 B5:.5 | G#5:3 r:1 """
    melA2 = """
      C#5:1 F#5:1 A5:1.5 G#5:.5        | F#5:3 E5:.5 F#5:.5
    | E5:.75 C#5:.75 E5:.5 A5:1.5 B5:.5 | G#5:1.5 A5:.5 B5:1 C#6:1 """
    melB = """
      D6:2 C#6:1 B5:1                  | A5:2 F#5:1 A5:1
    | E5:1.5 C#5:.5 E5:1 A5:1          | G#5:2 E#5:1 C#5:1 """

    ech = lambda fb=0.42, mix=0.36, lp=2600: echo(0.75 * S.spb, fb, mix, lp)
    S.ch('lead', Saw(2, 7, 3300, a=0.015, d=0.4, s=0.75, r=0.25, vib=18, vrate=5.2, vdelay=0.22,
                     pulse_mix=0.35, duty=0.25), 0.21, fx=[ech()], rev=0.45)
    S.ch('bell', Bell(tau=0.6, ring=1.0, bright=0.3, tine=0.1), 0.13, fx=[ech(0.45, 0.45, 3000)], rev=0.6)
    S.ch('arp', Pulse(0.25, a=0.002, d=0.12, s=0.3, r=0.06, gate=0.7, lp=3200), 0.10,
         fx=[ech(0.4, 0.4, 2200)], rev=0.35)
    S.ch('spark', Pulse(0.125, a=0.001, d=0.05, s=0.1, r=0.03, gate=0.6, lp=5000), 0.045,
         fx=[echo(0.5 * S.spb, 0.4, 0.4, 3500)], rev=0.4)
    S.ch('pad', Strings(6, 16, 1500, a=0.8, d=1.0, s=0.9, r=1.2, vib=4), 0.075,
         fx=[pump(S.spb, 0.35, 0.45)], rev=0.6)
    S.ch('bass', SawBass(220, 1100, 0.09, gate=0.75, sub=0.6, sq=0.3), 0.20, fx=[pump(S.spb, 0.3, 0.4)], rev=0.05)
    for nm, g in (('skick', 0.20), ('gsnare', 0.24), ('hat', 0.06), ('ohat', 0.035), ('crash', 0.06)):
        S.ch(nm, Drum(nm), g, rev={'gsnare': 0.35, 'crash': 0.3}.get(nm, 0.1))

    S.add('bell', seq(tease, 0))
    S.add('lead', seq(melA, 2 * 4))
    S.add('lead', seq(melA2, 6 * 4))
    S.add('bell', seq(melA2, 6 * 4, transpose=12, vel=0.7))
    S.add('lead', seq(melB, 10 * 4))
    S.add('bell', seq('r:4 | r:4 | r:2 E6:1 A6:1 | G#6:2 E#6:1 C#6:1', 10 * 4, vel=0.6))

    for b, chd in enumerate(prog):
        t0 = b * 4
        S.add('pad', seq(pad[chd] + ':4', t0, check=False, vel=0.75 if b < 2 else 1.0))
        tones = notes(arpt[chd])
        arp(S, 'arp', t0, 4, tones, [0, 1, 2, 3, 1, 2, 3, 2], 0.5, vel=0.85 if b < 2 else 1.0)
        if b >= 6:
            arp(S, 'spark', t0, 4, tones, [3, 2, 1, 2, 3, 1, 2, 0], 0.25, up=12, acc_every=2)
        R = bass_note(root_of(chd), 37, 48)
        if b < 2:
            S.add('bass', [(t0, 3.5, R, 0.9)])
        else:
            for i in range(8):
                iv = 12 if (i == 7 and b % 2 == 1) else 0
                S.add('bass', [(t0 + i * 0.5, 0.5, R + iv, 1.0 if i % 2 == 0 else 0.75)])

    D = lambda name, bar0, *bars: S.add(name, grid(name, bar0, list(bars)))
    D('hat', 1, '..o...o...o...o.')
    for b in range(2, 14):
        if b in (2, 6, 10):
            D('crash', b, 'x...............')
        D('skick', b, 'x.......x.......' if b < 6 else 'x.......x.....o.')
        D('hat', b, '..o...o...o...o.' if b < 6 else 'o.x.o.x.o.x.o.x.')
        if b >= 6:
            D('gsnare', b, '........x.......' if b != 13 else '........x...o.o.')
        if b % 4 == 1:
            D('ohat', b, '..............x.')
    return S


# ---------------------------------------------------------------------------
# 2. GAME -- "Run It Back"   A minor, 128 bpm, 26 bars = 48.75 s
# ---------------------------------------------------------------------------
G_ARP = {'Am': 'A3 C4 E4 A4 C5', 'F': 'A3 C4 F4 A4 C5', 'C': 'G3 C4 E4 G4 C5', 'G': 'G3 B3 D4 G4 B4',
         'Dm': 'A3 D4 F4 A4 D5', 'E': 'G#3 B3 E4 G#4 B4'}
G_PAD = {'Am': 'A3+C4+E4', 'F': 'A3+C4+F4', 'C': 'G3+C4+E4', 'G': 'G3+B3+D4', 'Dm': 'A3+D4+F4',
         'E': 'G#3+B3+E4'}


def song_game():
    S = Song(128, 4, 26, rev_ir=make_ir(1.6, 0.015, 5000), rev_mix=1.0)
    intro = ['Am', 'Am']
    A = ['Am', 'F', 'C', 'G'] * 2
    B = ['Dm', 'F', 'C', 'G', 'Dm', 'F', 'E', 'E']
    C = ['Am', 'F', 'C', 'G', 'Am', 'F', 'G', 'E']
    prog = intro + A + B + C
    assert len(prog) == 26

    hook = """
      E5:.75 E5:.75 A5:.5 G5:.75 E5:.75 D5:.5 | C5:.75 C5:.75 D5:.5 E5:2
    | E5:.75 E5:.75 A5:.5 G5:.75 E5:.75 G5:.5 | B5:1.5 A5:.5 G5:1 D5:1 """
    hook2 = hook.replace('B5:1.5 A5:.5 G5:1 D5:1', 'B5:.75 C6:.75 B5:.5 G5:2')
    hookC2 = """
      E5:.75 E5:.75 A5:.5 G5:.75 E5:.75 D5:.5 | C5:.75 C5:.75 D5:.5 E5:2
    | D5:.75 D5:.75 G5:.5 B5:.75 A5:.75 G5:.5 | G#5:1.5 A5:.5 B5:1 E5:1 """
    harmC = """
      C5:.75 C5:.75 E5:.5 E5:.75 C5:.75 A4:.5 | A4:.75 A4:.75 A4:.5 C5:2
    | C5:.75 C5:.75 E5:.5 E5:.75 C5:.75 E5:.5 | G5:1.5 E5:.5 D5:1 B4:1
    | C5:.75 C5:.75 E5:.5 E5:.75 C5:.75 A4:.5 | A4:.75 A4:.75 A4:.5 C5:2
    | B4:.75 B4:.75 D5:.5 G5:.75 E5:.75 D5:.5 | E5:1.5 E5:.5 G#5:1 B4:1 """
    melB = """
      F5:1.5 E5:.5 D5:1 A4:1   | C5:1.5 D5:.5 F5:1 A5:1
    | G5:1.5 E5:.5 C5:1 E5:1   | D5:3 B4:1
    | F5:1.5 E5:.5 D5:1 F5:1   | A5:1.5 G5:.5 F5:1 A5:1
    | G#5:2 B5:1 G#5:1         | E5:.5 G#5:.5 B5:.5 D6:.5 E6:2 """

    ech = echo(0.75 * S.spb, 0.33, 0.30, 2800)
    S.ch('lead', Saw(2, 9, 4200, a=0.004, d=0.25, s=0.72, r=0.08, vib=18, vrate=5.8, vdelay=0.16,
                     pulse_mix=0.4, duty=0.25, blip=0.3), 0.20, fx=[ech], rev=0.25)
    S.ch('thick', Saw(5, 16, 2400, a=0.006, d=0.3, s=0.7, r=0.1, vib=10, vdelay=0.2), 0.075, rev=0.25)
    S.ch('harm', Pulse(0.5, a=0.005, d=0.25, s=0.6, r=0.07, vib=12, vdelay=0.18, lp=3000), 0.075,
         fx=[echo(0.75 * S.spb, 0.3, 0.25, 2400)], rev=0.25)
    S.ch('arp', Pulse(0.25, a=0.001, d=0.06, s=0.25, r=0.025, gate=0.75, lp=4200), 0.095,
         fx=[echo(0.75 * S.spb, 0.3, 0.25, 2400)], rev=0.15)
    S.ch('pad', Strings(6, 18, 1900, a=0.25, d=0.6, s=0.85, r=0.4), 0.075, fx=[pump(S.spb, 0.6, 0.35)], rev=0.4)
    S.ch('bassf', SawBass(160, 700, 0.06, sub=0.6), 0.25, fx=[pump(S.spb, 0.4, 0.3)])
    S.ch('bass', SawBass(380, 2600, 0.07), 0.24, fx=[pump(S.spb, 0.4, 0.3)])
    S.ch('riser', Riser(300, 9000), 0.06, rev=0.3)
    for nm, g in (('kick', 0.24), ('gsnare', 0.26), ('hat', 0.07), ('ohat', 0.06),
                  ('crash', 0.09), ('tomh', 0.22), ('tomm', 0.22), ('toml', 0.24)):
        S.ch(nm, Drum(nm), g, rev={'gsnare': 0.3, 'crash': 0.2}.get(nm, 0.06))

    S.add('lead', seq(hook, 2 * 4))
    S.add('lead', seq(hook2, 6 * 4))
    S.add('lead', seq(melB, 10 * 4))
    S.add('lead', seq(hook, 18 * 4))
    S.add('lead', seq(hookC2, 22 * 4))
    S.add('thick', seq(hook, 18 * 4, transpose=-12))
    S.add('thick', seq(hookC2, 22 * 4, transpose=-12))
    S.add('harm', seq(harmC, 18 * 4))
    S.add('riser', [(9 * 4, 4, 0, 1.0), (17 * 4, 4, 0, 1.0), (25 * 4, 4, 0, 1.0)])

    for b, chd in enumerate(prog):
        t0 = b * 4
        tones = notes(G_ARP[chd])
        pat = [0, 1, 2, 3, 4, 3, 2, 1]
        up = 12 if b >= 18 else 0
        arp(S, 'arp', t0, 4, tones, pat, 0.25, vel=0.8 if b < 2 else 1.0, up=up)
        if b >= 10:
            S.add('pad', seq(G_PAD[chd] + ':4', t0, check=False, vel=0.8 if b < 18 else 1.0))
        R = bass_note(root_of(chd), 36, 47)
        if b < 2:
            for i in range(8):
                S.add('bassf', [(t0 + i * 0.5, 0.5, R, 1.0 if i % 2 == 0 else 0.8)])
        else:
            if b < 10:
                bp = [0, 0, 0, 0, 0, 0, 0, 0] if b % 4 != 3 else [0, 0, 0, 0, 0, 0, 12, 0]
            elif b < 18:
                bp = [0, 12, 0, 12, 0, 12, 0, 12]
            else:
                bp = [0, 12, 0, 12, 0, 12, 7, 12] if b % 2 else [0, 12, 0, 12, 0, 12, 0, 12]
            if b in (9, 17):
                bp = [0, 0, 12, 0, 2, 3, 5, 7] if chd != 'E' else [0, 0, 12, 0, 3, 5, 7, 8]
            for i, iv in enumerate(bp):
                S.add('bass', [(t0 + i * 0.5, 0.5, R + iv, 1.0 if i % 2 == 0 else 0.8)])

    D = lambda name, bar0, *bars: S.add(name, grid(name, bar0, list(bars)))
    # intro: kick + building snare
    D('kick', 0, 'x...x...x...x...', 'x...x...x...x...')
    D('hat', 0, '..o...o...o...o.', '..o...o...o...o.')
    D('gsnare', 1, '........3.4.5.67')
    # A
    for b in range(2, 10):
        if b in (2, 6):
            D('crash', b, 'x...............')
        D('kick', b, 'x...x...x...x...')
        D('gsnare', b, '....x.......x...' if b != 9 else '....x.......x.xx')
        D('hat', b, '..x...x...x...x.')
    # B
    for b in range(10, 18):
        if b in (10, 14):
            D('crash', b, 'x...............')
        D('kick', b, 'x...x...x...x...' if b != 17 else 'x...x...x.......')
        D('gsnare', b, '....x.......x...' if b != 17 else '....x...6.7.8xxx')
        D('hat', b, 'xoxoxoxoxoxoxoxo' if b != 17 else 'xoxoxoxo........')
        D('ohat', b, '..x...x...x...x.' if b != 17 else '................')
    # C
    for b in range(18, 26):
        if b in (18, 22):
            D('crash', b, 'x...............')
        D('kick', b, 'x...x...x...x...' if b != 25 else 'x...x...x...x.x.')
        D('gsnare', b, '....x.......x..o' if b != 25 else '....x.......x...')
        D('hat', b, 'xoxoxoxoxoxoxoxo')
        D('ohat', b, '..x...x...x...x.')
    D('tomh', 25, '........x.x.....')
    D('tomm', 25, '............x.x.')
    D('toml', 25, '.............x.x')
    return S


# ---------------------------------------------------------------------------
# 3. INTENSE -- "Echo Chamber"   A minor / E Phrygian, 150 bpm, 20 bars = 32.0 s
# ---------------------------------------------------------------------------
I_ARP = {'Ep': 'E4 G4 B4 E5 F5', 'Am': 'A4 C5 E5 A5 C6', 'F': 'A4 C5 F5 A5 C6', 'G': 'G4 B4 D5 G5 B5',
         'E': 'G#4 B4 E5 G#5 B5', 'Dm': 'A4 D5 F5 A5 D6'}
I_PAD = {'Ep': 'E3+B3+G4', 'Am': 'A3+C4+E4', 'F': 'A3+C4+F4', 'G': 'G3+B3+D4', 'E': 'G#3+B3+E4',
         'Dm': 'A3+D4+F4'}


def song_intense():
    S = Song(150, 4, 20, rev_ir=make_ir(1.2, 0.01, 5000), rev_mix=0.8)
    prog = ['Ep'] * 4 + ['Am', 'F', 'G', 'E', 'Am', 'F', 'Dm', 'E'] + ['Ep', 'F', 'Ep', 'F', 'Ep', 'F', 'Dm', 'E']

    leadA = """
      A5:.75 A5:.75 C6:.5 B5:.75 A5:.75 E5:.5 | F5:.75 F5:.75 A5:.5 C6:2
    | B5:.75 B5:.75 D6:.5 C6:.75 B5:.75 G5:.5 | G#5:1.5 A5:.5 B5:2
    | A5:.75 A5:.75 C6:.5 B5:.75 A5:.75 E5:.5 | F5:.75 A5:.75 C6:.5 F6:2
    | E6:.75 D6:.75 C6:.5 A5:.75 F5:.75 D5:.5 | E5:.5 F5:.5 G#5:.5 B5:.5 E6:2 """
    leadB = """
      B5:1.5 C6:1.5 B5:1       | A5:1.5 C6:1.5 F6:1
    | E6:2 D6:1 C6:1           | B5:1 C6:1 A5:2
    | B5:1.5 C6:1.5 B5:1       | A5:1.5 C6:1.5 F6:1
    | F6:1 E6:1 D6:1 C6:1      | B5:1 G#5:1 E5:1 r:1 """
    tease = 'r:4 | r:4 | E5:.5 F5:.5 G5:.5 B5:.5 E6:2 | F6:.75 E6:.75 B5:.5 F5:2'

    S.ch('lead', Saw(2, 10, 4000, a=0.003, d=0.2, s=0.75, r=0.06, vib=22, vrate=6.4, vdelay=0.12,
                     pulse_mix=0.45, duty=0.25, blip=0.4), 0.19, fx=[echo(0.5 * S.spb, 0.3, 0.26, 2800)], rev=0.22)
    S.ch('thick', Saw(5, 18, 2200, a=0.004, d=0.25, s=0.7, r=0.08, vib=10, vdelay=0.15), 0.07, rev=0.2)
    S.ch('arp', Pulse(0.125, a=0.001, d=0.05, s=0.3, r=0.02, gate=0.75, lp=4500), 0.085,
         fx=[echo(0.75 * S.spb, 0.3, 0.25, 2600)], rev=0.12)
    S.ch('riff', Pulse(0.5, a=0.002, d=0.08, s=0.5, r=0.02, gate=0.75, lp=2200), 0.09)
    S.ch('bass', SawBass(420, 3000, 0.06, gate=0.75), 0.24, fx=[pump(S.spb, 0.4, 0.3)])
    S.ch('pad', Strings(6, 20, 1800, a=0.15, d=0.5, s=0.85, r=0.3), 0.07, fx=[pump(S.spb, 0.65, 0.4)], rev=0.35)
    S.ch('riser', Riser(300, 9000), 0.06, rev=0.3)
    for nm, g in (('kick', 0.25), ('gsnare', 0.27), ('hat', 0.07), ('ohat', 0.06),
                  ('crash', 0.09), ('tomh', 0.24), ('tomm', 0.24), ('toml', 0.26)):
        S.ch(nm, Drum(nm), g, rev={'gsnare': 0.28, 'crash': 0.2}.get(nm, 0.05))

    S.add('lead', seq(tease, 0, vel=0.8))
    S.add('lead', seq(leadA, 4 * 4))
    S.add('lead', seq(leadB, 12 * 4))
    S.add('thick', seq(leadB, 12 * 4, transpose=-12))
    S.add('riser', [(2 * 4, 8, 0, 1.0), (11 * 4, 4, 0, 1.0), (19 * 4, 4, 0, 1.0)])

    riff = [0, 0, 12, 0, 1, 0, 3, 1]
    E2 = midi('E2')
    for b, chd in enumerate(prog):
        t0 = b * 4
        tones = notes(I_ARP[chd])
        arp(S, 'arp', t0, 4, tones, [0, 1, 2, 3, 4, 3, 2, 1] if b % 2 == 0 else [0, 2, 1, 3, 2, 4, 3, 1],
            0.25, vel=0.85 if b < 4 else 1.0)
        if b >= 4:
            S.add('pad', seq(I_PAD[chd] + ':4', t0, check=False))
        if chd in ('Ep', 'F'):
            off = 0 if chd == 'Ep' else 1
            rf = riff if b != 3 else [0, 0, 12, 0, 1, 2, 3, 4]
            for i, iv in enumerate(rf):
                S.add('bass', [(t0 + i * 0.5, 0.5, E2 + off + iv, 1.0 if i % 2 == 0 else 0.8)])
                S.add('riff', [(t0 + i * 0.5, 0.5, E2 + 12 + off + iv, 1.0 if i in (0, 2) else 0.75)])
        else:
            R = bass_note(root_of(chd), 36, 47)
            bp = [0, 12, 0, 12, 0, 12, 0, 12] if b % 2 == 0 else [0, 12, 0, 12, 0, 12, 7, 12]
            for i, iv in enumerate(bp):
                S.add('bass', [(t0 + i * 0.5, 0.5, R + iv, 1.0 if i % 2 == 0 else 0.8)])

    D = lambda name, bar0, *bars: S.add(name, grid(name, bar0, list(bars)))
    D('crash', 0, 'x...............')
    D('kick', 0, 'x...x...x...x...', 'x...x...x...x...', 'x...x...x...x...', 'x...x...x.x.x.xx')
    D('hat', 0, 'x.x.x.x.x.x.x.x.', 'x.x.x.x.x.x.x.x.', 'xoxoxoxoxoxoxoxo', 'xoxoxoxo........')
    D('gsnare', 2, '....x.......x...', '....x...5.6.7889')
    for b in range(4, 20):
        if b in (4, 8, 12, 16):
            D('crash', b, 'x...............')
        last = b in (11, 19)
        if b < 12:
            D('kick', b, 'x...x...x...x...')
            D('gsnare', b, '....x.......x...' if not last else '....x.......xxxx')
            D('hat', b, 'xoxoxoxoxoxoxoxo')
            D('ohat', b, '..x...x...x...x.' if not last else '..x...x.........')
        else:
            D('kick', b, 'x...x...x...x.x.' if not last else 'x...x...x.......')
            D('gsnare', b, '....x..o....x..o' if not last else '....x...........')
            D('hat', b, 'xxoxxxoxxxoxxxox' if not last else 'xxoxxxox........')
            D('ohat', b, '..x...x...x...x.' if not last else '................')
    D('tomh', 19, '........x.x.....')
    D('tomm', 19, '............x.x.')
    D('toml', 19, '.............x.x')
    return S


# ---------------------------------------------------------------------------
# jingles (tracker one-shots)
# ---------------------------------------------------------------------------
def sfx_clear():
    # the shard pentatonic run (A C D E G) resolving to A, with a sparkle tail
    S = Song(160, 4, 2, rev_ir=make_ir(1.0, 0.01, 6500), rev_mix=0.7)
    S.ch('lead', Saw(1, 0, 6000, a=0.002, d=0.15, s=0.7, r=0.2, vib=20, vrate=7, vdelay=0.1,
                     pulse_mix=0.6, duty=0.25), 0.30, fx=[echo(0.375 * S.spb, 0.3, 0.3, 4500)], rev=0.25)
    S.ch('bell', Bell(tau=0.35, ring=0.6, bright=0.4, tine=0.15), 0.25, rev=0.3)
    S.ch('harm', Pulse(0.5, a=0.002, d=0.2, s=0.6, r=0.2, vib=12, vrate=7, vdelay=0.1, lp=4000), 0.14, rev=0.2)
    S.ch('spark', Pulse(0.125, a=0.001, d=0.04, s=0.0, r=0.02, lp=8000), 0.07,
         fx=[echo(0.25 * S.spb, 0.4, 0.4, 6000)], rev=0.3)
    S.ch('bass', SawBass(400, 2000, 0.05, gate=1.0, r=0.15), 0.30)
    run = 'A5:1/8 C6:1/8 D6:1/8 E6:1/8 G6:1/8 A6:1.4'
    S.add('lead', seq(run, 0, check=False))
    S.add('bell', seq(run, 0, check=False, transpose=12, vel=0.6))
    S.add('harm', seq('r:5/8 E6+C6:1.4', 0, check=False))
    S.add('spark', seq('E7:.25 A7:.25 E7:.25 C7:.25', 5 / 8 + 0.25, check=False, vel=0.8))
    S.add('bass', seq('r:5/8 A2:1.2', 0, check=False))
    x, _ = render(S, loop=False, total=0.9, verbose=False)
    return fades(x, 0.002, 0.22)


def jingle_gameover():
    # A minor, 100 bpm: E D C B | A -- the last note 'powers down' like a dying CRT
    S = Song(100, 4, 2, rev_ir=make_ir(2.2, 0.03, 3500), rev_mix=1.0)
    S.ch('lead', Saw(2, 8, 2800, a=0.01, d=0.4, s=0.75, r=0.3, vib=16, vrate=4.8, vdelay=0.2,
                     pulse_mix=0.4, duty=0.25), 0.26, fx=[echo(0.75 * S.spb, 0.35, 0.3, 2200)], rev=0.45)
    S.ch('last', Saw(2, 8, 2400, a=0.01, d=0.5, s=0.8, r=0.3, vib=12, vrate=4.5, vdelay=0.25,
                     pulse_mix=0.4, duty=0.25, droop=2.0), 0.26, fx=[echo(0.75 * S.spb, 0.35, 0.3, 2000)], rev=0.5)
    S.ch('harm', Pulse(0.5, a=0.02, d=0.4, s=0.6, r=0.4, vib=10, vdelay=0.25, lp=1800), 0.10, rev=0.45)
    S.ch('pad', Strings(5, 18, 1200, a=0.12, d=0.6, s=0.85, r=0.6), 0.10, rev=0.6)
    S.ch('bass', SawBass(220, 900, 0.1, gate=1.0, r=0.3, sub=0.6), 0.30, rev=0.1)
    S.add('lead', seq('E5:.5 D5:.5 C5:.5 B4:.5', 0, check=False))
    S.add('last', seq('A4:1.9', 2, check=False))
    S.add('harm', seq('C5:.5 A4:.5 A4:.5 G#4:.5 E4:1.9', 0, check=False))
    S.add('pad', seq('A3+C4+E4:.5', 0, check=False) + seq('A3+C4+F4:1', 0.5, check=False)
          + seq('G#3+B3+E4:.5', 1.5, check=False) + seq('A3+C4+E4:1.9', 2, check=False, vel=0.9))
    S.add('bass', seq('A2:.5 F2:1 E2:.5 A1:1.9', 0, check=False))
    x, _ = render(S, loop=False, total=2.5, verbose=False)
    return fades(x, 0.003, 0.35)


def sfx_best():
    # 'new best!': A major (Picardy) fanfare climbing to A6 with a sparkle shower
    S = Song(150, 4, 2, rev_ir=make_ir(1.4, 0.015, 6500), rev_mix=0.8)
    S.ch('lead', Saw(2, 6, 6000, a=0.002, d=0.2, s=0.75, r=0.25, vib=24, vrate=6.5, vdelay=0.1,
                     pulse_mix=0.5, duty=0.25, blip=0.4), 0.26, fx=[echo(0.375 * S.spb, 0.3, 0.25, 4500)], rev=0.25)
    S.ch('harm', Pulse(0.5, a=0.002, d=0.25, s=0.65, r=0.25, vib=14, vrate=6.5, vdelay=0.1, lp=4000), 0.12, rev=0.25)
    S.ch('bell', Bell(tau=0.3, ring=0.5, bright=0.4, tine=0.2), 0.16,
         fx=[echo(0.25 * S.spb, 0.35, 0.35, 7000)], rev=0.35)
    S.ch('bass', SawBass(400, 2200, 0.06, gate=1.0, r=0.2), 0.32)
    S.ch('kick', Drum('kick'), 0.35)
    S.ch('crash', Drum('crash'), 0.12, rev=0.3)
    S.add('lead', seq('E5:1/4 A5:1/4 C#6:1/4 E6:1/4 A6:1.8', 0, check=False))
    S.add('harm', seq('r:1 C#6+E6:1.8', 0, check=False))
    S.add('bell', seq('A6:.25 C#7:.25 E7:.25 A7:.25 E7:.25 C#7:.25 E7:.25 A7:.25', 1, check=False, vel=0.8))
    S.add('bass', seq('r:1 A2:1.6', 0, check=False))
    S.add('kick', [(1, 1, 'kick', 1.0)])
    S.add('crash', [(1, 1, 'crash', 1.0)])
    x, _ = render(S, loop=False, total=1.2, verbose=False)
    return fades(x, 0.002, 0.3)


# ============================================================================
# SFX
# ============================================================================
def crush(x, hold):
    return np.repeat(x[::hold], hold)[:len(x)]


def _place(out, y, st):
    s0 = int(st * SR)
    seg = y[:len(out) - s0]
    out[s0:s0 + len(seg)] += seg


SHARD_NOTES = ['A5', 'C6', 'D6', 'E6', 'G6']     # A minor pentatonic, rising


def make_shard(k):
    note = SHARD_NOTES[k]
    dur = 0.15
    out = np.zeros(int(dur * SR))
    f0 = hz(midi(note))
    # grace blip a fourth below -> "b-ling"
    t = _t(0.028)
    g = osc_pulse(np.full(len(t), f0 * 2 ** (-5 / 12)), 0.25) * np.exp(-t / 0.012) * 0.45
    _place(out, fades(g, 0.0005, 0.004), 0.0)
    t = _t(dur - 0.022)
    f = f0 * (1 + 0.008 * np.exp(-t / 0.006))
    y = (osc_sine(f) + 0.35 * osc_pulse(f, 0.25) * np.exp(-t / 0.035)
         + 0.25 * osc_sine(2 * f) * np.exp(-t / 0.05) + 0.12 * osc_sine(3 * f) * np.exp(-t / 0.02))
    y *= np.minimum(t / 0.0015, 1) * np.exp(-t / 0.055) * (1 + 0.06 * k)
    _place(out, y, 0.022)
    out = echo(0.04, 0.3, 0.3, 7000)(out)
    return fades(lowpass(out, 11000), 0.0005, 0.02)


def sfx_spawn():
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    # forward ghost shimmer: detuned, beating cluster (A minor add9 + tritone ghost)
    fwd = np.zeros(n)
    for nt, v in (('E5', 0.7), ('A5', 1.0), ('B5', 0.5), ('C6', 0.8), ('D#6', 0.35), ('E6', 0.6), ('A6', 0.4)):
        f = hz(midi(nt))
        for c in (-9, 9):
            fwd += v * osc_sine(f * 2 ** (c / 1200) * vibrato(n, 25, 6.0, 0.0, 0.01))
    fwd *= np.exp(-t / 0.12) * np.minimum(t / 0.002, 1)
    fwd += 0.6 * highpass(noise(n), 4000) * np.exp(-t / 0.05)
    wet = signal.oaconvolve(fwd, make_ir(0.9, 0.0, 7000, seed=3))[:n]
    rev = (0.4 * fwd + 2.5 * wet)[::-1]                    # reversed -> swells in
    rev = rev[int(0.12 * SR):]                             # trim the reversed silent tail
    swell = np.zeros(n)
    swell[:len(rev)] = rev
    # breathy whoosh rising with it
    cut = 300 * (8000 / 300) ** np.clip(t / 0.58, 0, 1)
    wh = sweep_lowpass(noise(n), cut) * np.clip(t / 0.58, 0, 1) ** 3 * np.where(t < 0.58, 1, np.exp(-(t - 0.58) / 0.02))
    swell += 0.5 * wh / (np.max(np.abs(wh)) + 1e-9) * np.max(np.abs(swell))
    # it 'lands': a soft ghostly ping
    pt = _t(0.7 - 0.56)
    ping = (osc_sine(hz(midi('E6')) * vibrato(len(pt), 30, 7, 0.0, 0.01)) + 0.5 * osc_sine(np.full(len(pt), hz(midi('A6')))))
    ping *= np.minimum(pt / 0.003, 1) * np.exp(-pt / 0.05)
    _place(swell, 0.5 * np.max(np.abs(swell)) * ping / np.max(np.abs(ping)), 0.56)
    return fades(lowpass(swell, 10000), 0.01, 0.03)


def sfx_death():
    n = int(1.2 * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    # 1. noise burst
    burst = np.tanh(2 * highpass(noise(n), 200)) * np.exp(-t / 0.06) * np.minimum(t / 0.001, 1)
    out += 0.9 * burst
    # 2. bitcrushed falling pitch with glitch gating
    f = 35 + 1100 * np.exp(-t / 0.16)
    tone = 0.6 * osc_pulse(f, 0.5) + 0.35 * osc_saw(f * 1.5)
    tone *= np.minimum(t / 0.002, 1) * np.where(t < 0.62, 1, np.exp(-(t - 0.62) / 0.03))
    seg = int(0.018 * SR)
    gate = np.repeat(RNG.random(n // seg + 1) > 0.22, seg)[:n].astype(float)
    gate[t < 0.06] = 1
    tone *= gate
    crushed = np.zeros(n)
    blk = 1024
    for i in range(0, n, blk):
        hold = 2 + int(22 * min(i / (0.6 * SR), 1))
        crushed[i:i + blk] = crush(tone[i:i + blk], hold)
    crushed = np.round(crushed * 6) / 6                   # ~3-bit amplitude
    # stutter: repeat a 40 ms chunk a few times (glitch)
    a0, L = int(0.10 * SR), int(0.04 * SR)
    chunk = crushed[a0:a0 + L].copy()
    for k in range(3):
        crushed[a0 + (k + 1) * L:a0 + (k + 2) * L] = chunk * (0.9 - 0.15 * k)
    out += 0.8 * lowpass(crushed, 7000)
    # 3. low thud
    tt = _t(1.2 - 0.6)
    ft = 48 + 90 * np.exp(-tt / 0.03)
    thud = np.tanh(2.8 * np.sin(2 * np.pi * np.cumsum(ft) / SR)) * np.exp(-tt / 0.18)
    thud += 0.3 * lowpass(noise(len(tt)), 600) * np.exp(-tt / 0.03)
    _place(out, 1.3 * lowpass(thud, 2000), 0.6)
    return fades(out, 0.001, 0.08)


def sfx_close():
    t = _t(0.2)
    n = len(t)
    env = np.where(t < 0.07, (t / 0.07) ** 2, np.exp(-(t - 0.07) / 0.035))
    cut = 900 + 6000 * np.exp(-((t - 0.07) / 0.04) ** 2)
    y = sweep_lowpass(highpass(noise(n), 500), cut) * env
    y += 0.4 * bandpass(noise(n), 3000, 9000) * env * np.exp(-((t - 0.07) / 0.03) ** 2)
    return fades(y, 0.002, 0.02)


def sfx_tick():
    t = _t(0.05)
    y = osc_sine(np.full(len(t), 2900.0)) * np.exp(-t / 0.007)
    y += 0.25 * osc_sine(np.full(len(t), 5800.0)) * np.exp(-t / 0.003)
    y += 0.15 * highpass(noise(len(t)), 6000) * np.exp(-t / 0.0015)
    y *= np.minimum(t / 0.0005, 1)
    return fades(lowpass(y, 9000), 0.0003, 0.01)


def sfx_select():
    out = np.zeros(int(0.15 * SR))
    for st, nt, ln in ((0.0, 'A5', 0.05), (0.045, 'E6', 0.105)):
        t = _t(ln)
        y = osc_pulse(np.full(len(t), hz(midi(nt))), 0.25) + 0.4 * osc_sine(np.full(len(t), hz(midi(nt))))
        y = fades(y * np.minimum(t / 0.002, 1) * np.exp(-t / 0.045), 0, 0.008)
        _place(out, y, st)
    y = echo(0.03, 0.3, 0.25, 4000)(out)
    return fades(lowpass(y, 6500), 0.001, 0.015)


def sfx_move():
    t = _t(0.05)
    f = hz(midi('E6')) * (1 + 0.04 * np.exp(-t / 0.005))
    y = osc_pulse(f, 0.5) * np.minimum(t / 0.001, 1) * np.exp(-t / 0.012)
    return fades(lowpass(y, 5000), 0.001, 0.008)


def sfx_go():
    t = _t(0.4)
    n = len(t)
    glide = 2 ** (-1.0 * np.exp(-t / 0.025))               # leaps up an octave into the chord
    y = np.zeros(n)
    for nt in ('A3', 'E4', 'A4', 'C5', 'E5'):
        f = hz(midi(nt)) * glide
        for c, ph in ((-12, 0.1), (0, 0.5), (12, 0.8)):
            y += osc_saw(f * 2 ** (c / 1200), ph)
    y /= 8
    e = np.exp(-t / 0.12)
    y = lowpass(y, 900) * (1 - e) + lowpass(y, 7000) * e
    y *= np.minimum(t / 0.002, 1) * np.where(t < 0.14, 1, np.exp(-(t - 0.14) / 0.08))
    y = echo(0.09, 0.3, 0.3, 4000)(y)
    kt = _t(0.25)
    kick = np.tanh(2.5 * np.sin(2 * np.pi * np.cumsum(50 + 150 * np.exp(-kt / 0.02)) / SR)) * np.exp(-kt / 0.08)
    _place(y, 0.7 * kick, 0.0)
    y += 0.4 * highpass(noise(n), 3000) * np.exp(-t / 0.02)
    return fades(np.tanh(1.5 * y), 0.001, 0.04)


# ============================================================================
# verification + plots
# ============================================================================
def read_wav(path):
    with open(path, 'rb') as f:
        raw = f.read()
    assert raw[:4] == b'RIFF' and raw[8:12] == b'WAVE'
    pos, fmt, data, loop = 12, None, None, None
    while pos < len(raw):
        cid, size = struct.unpack('<4sI', raw[pos:pos + 8])
        body = raw[pos + 8:pos + 8 + size]
        if cid == b'fmt ':
            fmt = struct.unpack('<HHIIHH', body[:16])
        elif cid == b'data':
            data = np.frombuffer(body, '<i2')
        elif cid == b'smpl':
            loop = struct.unpack('<6I', body[36:60])[2:4]
        pos += 8 + size + (size & 1)
    return fmt, data, loop


def verify(name, expect_dur, is_loop):
    fmt, pcm, lp = read_wav(os.path.join(OUT, name))
    tag, ch, sr, _, _, bits = fmt
    x = pcm.astype(float) / 32768
    dur = len(x) / sr
    peak = np.max(np.abs(x))
    clip = int(np.sum(np.abs(pcm.astype(int)) >= 32767))
    ok = tag == 1 and ch == 1 and sr == SR and bits == 16 and np.all(np.isfinite(x)) and clip == 0
    ok &= abs(dur - expect_dur) < 0.002
    line = (f'  {name:<22} {dur:7.3f} s  peak {20 * np.log10(peak):5.2f} dBFS  '
            f'rms {20 * np.log10(np.sqrt(np.mean(x ** 2))):6.1f} dB  clip {clip}')
    if is_loop:
        n50 = int(0.05 * SR)
        steps = np.abs(np.diff(np.concatenate([x[-n50:], x[:n50]])))
        jump = abs(x[0] - x[-1])
        rms_end, rms_start = np.sqrt(np.mean(x[-n50:] ** 2)), np.sqrt(np.mean(x[:n50] ** 2))
        line += (f'\n      seam: |x[0]-x[-1]| = {jump:.5f}  (median step {np.median(steps):.5f}, '
                 f'p99 step {np.percentile(steps, 99):.5f}, max step whole file {np.max(np.abs(np.diff(x))):.4f})'
                 f'\n            rms last 50ms {rms_end:.4f} vs first 50ms {rms_start:.4f};  '
                 f'smpl loop = {lp}')
        ok &= jump <= np.percentile(steps, 99) and lp == (0, len(x))
    print(('OK ' if ok else 'BAD') + line)
    return ok, x


def plot(name, x, is_loop, zoom=None):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    music = name.startswith(('music', 'jingle'))
    rows = 2 + (zoom is not None) + is_loop
    fig, ax = plt.subplots(rows, 1, figsize=(14, 2.6 * rows + 0.6))
    t = np.arange(len(x)) / SR
    ax[0].plot(t, x, lw=0.3, color='#204060')
    ax[0].set_xlim(0, t[-1])
    ax[0].set_ylim(-1, 1)
    ax[0].set_title(f'{name}  waveform')

    def spec(a, seg, t0=0.0, linear_zoom=False):
        nps = (4096 if linear_zoom else 2048) if music else 256
        f, tt, Sx = signal.spectrogram(seg, SR, nperseg=nps, noverlap=nps * 7 // 8)
        a.pcolormesh(tt + t0, f, 10 * np.log10(Sx + 1e-12), shading='auto', cmap='magma',
                     vmin=10 * np.log10(Sx.max() + 1e-12) - (60 if linear_zoom else 75))
        if linear_zoom:
            a.set_ylim(60, 2000)
        elif music:
            a.set_yscale('log')
            a.set_ylim(50, 8000)
        else:
            a.set_ylim(0, 16000)
        a.set_ylabel('Hz')

    spec(ax[1], x)
    ax[1].set_title('spectrogram' + (' (log freq)' if music else ''))
    r = 2
    if zoom is not None:
        z0, z1 = zoom
        spec(ax[r], x[int(z0 * SR):int(z1 * SR)], z0, True)
        ax[r].set_title(f'zoom {z0:.1f}-{z1:.1f} s (linear 60-2000 Hz)')
        r += 1
    if is_loop:
        n50 = int(0.05 * SR)
        seam = np.concatenate([x[-n50:], x[:n50]])
        ax[r].plot((np.arange(len(seam)) - n50) / SR * 1000, seam, lw=0.6)
        ax[r].axvline(0, color='r', lw=0.8)
        ax[r].set_title('loop seam: last 50 ms  |  first 50 ms')
        ax[r].set_xlabel('ms')
    fig.tight_layout()
    fig.savefig(os.path.join(PNG, name.replace('.wav', '.png')), dpi=90)
    plt.close(fig)


# ============================================================================
def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PNG, exist_ok=True)
    gd = os.path.join(PNG, '.gdignore')
    if not os.path.exists(gd):
        open(gd, 'w').close()
    want_png = '--no-png' not in sys.argv
    jobs = []

    for name, fn, zoom in (('music_title.wav', song_title, (4.8, 14.4)),
                           ('music_game.wav', song_game, (3.75, 11.25)),
                           ('music_intense.wav', song_intense, (6.4, 12.8))):
        print(f'rendering {name}')
        S = fn()
        x, err = render(S, loop=True)
        print(f'      periodic steady-state error {err:.2e}')
        write_wav(os.path.join(OUT, name), master(x, MUSIC_PEAK), loop=True)
        jobs.append((name, S.n / SR, True, zoom))

    print('rendering jingle_gameover.wav')
    write_wav(os.path.join(OUT, 'jingle_gameover.wav'), master(jingle_gameover(), MUSIC_PEAK, drive=1.2))
    jobs.append(('jingle_gameover.wav', 2.5, False, None))

    sfx = [(f'sfx_shard{k + 1}.wav', (lambda k=k: make_shard(k)), 0.15) for k in range(5)]
    sfx += [('sfx_clear.wav', sfx_clear, 0.9), ('sfx_spawn.wav', sfx_spawn, 0.7),
            ('sfx_death.wav', sfx_death, 1.2), ('sfx_close.wav', sfx_close, 0.2),
            ('sfx_tick.wav', sfx_tick, 0.05), ('sfx_select.wav', sfx_select, 0.15),
            ('sfx_move.wav', sfx_move, 0.05), ('sfx_go.wav', sfx_go, 0.4),
            ('sfx_best.wav', sfx_best, 1.2)]
    for name, fn, dur in sfx:
        y = fn()
        assert len(y) == int(round(dur * SR)), (name, len(y))
        assert np.all(np.isfinite(y)), name
        y = y / np.max(np.abs(y)) * SFX_PEAK
        write_wav(os.path.join(OUT, name), y)
        jobs.append((name, dur, False, None))

    print('\nverification')
    allok = True
    for name, dur, is_loop, zoom in jobs:
        ok, x = verify(name, dur, is_loop)
        allok &= ok
        if want_png:
            plot(name, x, is_loop, zoom)
    print('\nALL OK' if allok else '\nSOME CHECKS FAILED')
    return 0 if allok else 1


if __name__ == '__main__':
    sys.exit(main())
