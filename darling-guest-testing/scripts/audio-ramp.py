#!/usr/bin/env python3
# audio-ramp.py: make a test tone whose level rises linearly, and read a
# recording of it back as positions in the tone.
#
#   audio-ramp.py gen out.wav [--seconds 4] [--rate 44100] [--freq 440]
#   audio-ramp.py analyze capture.raw [--seconds 4] [--rate 44100]
#
# Because the level rises linearly, each level identifies one point of the
# tone, so the recording shows what was lost and where:
# the start (head), the end (tail), or data in the middle, as opposed to a
# stall that only inserted silence. analyze reads what audio-capture.sh writes
# (raw s16le, mono) and works out the playback gain itself, so the volume
# does not have to be 100%.
import argparse, math, struct, sys, wave

START, END = 0.1, 0.9      # level at the start and the end of the tone
WIN_MS = 10                # analysis window
FLOOR = 0.02               # below this (relative to full scale) a window is silent


def gen(a):
    n = int(a.seconds * a.rate)
    w = wave.open(a.out, 'wb')
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(a.rate)
    frames = bytearray()
    for i in range(n):
        level = START + (END - START) * i / n
        v = int(32767 * level * math.sin(2 * math.pi * a.freq * i / a.rate))
        frames += struct.pack('<hh', v, v)
    w.writeframes(bytes(frames))
    w.close()
    print('%s: %.2f s, %d Hz, %g Hz tone, level %.1f -> %.1f' % (a.out, a.seconds, a.rate, a.freq, START, END))


def analyze(a):
    raw = open(a.capture, 'rb').read()
    s = struct.unpack('<%dh' % (len(raw) // 2), raw[:len(raw) // 2 * 2])
    win = a.rate * WIN_MS // 1000
    # peak, not RMS: a window only partly filled by the tone still shows its level
    lv = [max(abs(x) for x in s[i:i + win]) / 32767 for i in range(0, len(s) - win + 1, win)]
    segs, cur = [], None
    for i, l in enumerate(lv):
        if l > FLOOR:
            cur = [i, i] if cur is None else [cur[0], i]
        elif cur is not None:
            segs.append(cur)
            cur = None
    if cur is not None:
        segs.append(cur)
    if not segs:
        print('silent: nothing above %.0f%% of full scale in %.2f s' % (FLOOR * 100, len(s) / a.rate))
        return 1

    # level per second of tone at unity gain; the median rise per window gives
    # the playback gain (the median ignores the jumps where data was lost)
    k = (END - START) / a.seconds
    w = WIN_MS / 1000
    steps = [lv[i + 1] - lv[i] for g0, g1 in segs for i in range(g0 + 1, g1 - 1)]
    if len(steps) < 10:
        print('too little audio to analyse')
        return 1
    step = sorted(steps)[len(steps) // 2]
    # stretches with no silence and no jump; within them the level follows
    # the tone exactly, so a least-squares slope shared by all of them gives
    # the gain (one intercept per stretch)
    runs = []
    for g0, g1 in segs:
        r0 = g0 + 1
        for i in range(g0 + 1, g1 - 1):
            if lv[i + 1] - lv[i] > 2.5 * step:
                runs.append((r0, i))
                r0 = i + 1
        runs.append((r0, g1 - 1))
    sxy = sxx = 0.0
    for r0, r1 in runs:
        idx = range(r0, r1 + 1)
        if len(idx) < 3:
            continue
        mx = sum(idx) / len(idx)
        my = sum(lv[i] for i in idx) / len(idx)
        sxy += sum((i - mx) * (lv[i] - my) for i in idx)
        sxx += sum((i - mx) ** 2 for i in idx)
    gain = (sxy / sxx if sxx else step) / (k * w)
    if gain <= 0:
        print('the level does not rise: not a recording of the ramp tone, or heavily distorted')
        return 1

    def pos(i):        # position in the tone (s) at the end of window i
        return (lv[i] / gain - START) / k

    print('capture %.2f s, playback gain %.2f, audible %d run(s); resolution about +-%d ms'
          % (len(s) / a.rate, gain, len(segs), WIN_MS))
    # the edge windows are only partly filled; assume half
    head = pos(segs[0][0] + 1) - 1.5 * w
    tail = a.seconds - pos(segs[-1][1] - 1) - 0.5 * w
    print('head lost: %4.0f ms' % max(0, head * 1000))
    for n, (g0, g1) in enumerate(segs):
        for i in range(g0 + 1, g1 - 1):
            if lv[i + 1] - lv[i] > 2.5 * step:
                print('jump at %.2f s of capture: %.0f ms of tone lost, no silence'
                      % ((i + 1) * w, (pos(i + 1) - pos(i) - w) * 1000))
        if n + 1 < len(segs):
            b0 = segs[n + 1][0]
            silence = (b0 - g1 - 1) * w
            skipped = pos(b0 + 1) - pos(g1 - 1) - ((b0 - g1 + 2) * w - silence)
            what = 'data lost' if skipped > 2 * w else 'stall (nothing lost)'
            print('gap at %.2f s of capture: %.0f ms silent, %+.0f ms of tone skipped -> %s'
                  % ((g1 + 1) * w, silence * 1000, skipped * 1000, what))
    print('tail lost: %4.0f ms' % max(0, tail * 1000))
    return 0


p = argparse.ArgumentParser()
sub = p.add_subparsers(dest='cmd', required=True)
g = sub.add_parser('gen')
g.add_argument('out')
g.add_argument('--seconds', type=float, default=4)
g.add_argument('--rate', type=int, default=44100)
g.add_argument('--freq', type=float, default=440)
n = sub.add_parser('analyze')
n.add_argument('capture')
n.add_argument('--seconds', type=float, default=4)
n.add_argument('--rate', type=int, default=44100)
a = p.parse_args()
if a.cmd == 'gen':
    gen(a)
else:
    sys.exit(analyze(a))
