#!/usr/bin/env python3
"""Focused local bilingual composition -> edit -> selectable MP4 -> reopen.
All inputs, outputs, intermediate files and command logs are retained.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--target', required=True)
p.add_argument('--output', required=True)
a = p.parse_args()
s, t, o = (Path(x).resolve() for x in (a.source, a.target, a.output))
assert t.is_absolute() and t != s and s not in t.parents
o.mkdir(exist_ok=False)
bins = t / 'native/debug/build/cmd'
cli = bins / 'bilingual_captions/bilingual_captions.exe'
edit = bins / 'caption_edit/caption_edit.exe'
media = bins / 'caption_media/caption_media.exe'
assert all(x.is_file() for x in (cli, edit, media))
runs = []


def run(args, success=True):
    args = list(map(str, args))
    result = subprocess.run(args, capture_output=True, text=True, timeout=60)
    n = len(runs) + 1
    (o / f'{n:02d}.stdout').write_text(result.stdout)
    (o / f'{n:02d}.stderr').write_text(result.stderr)
    runs.append({'command': args, 'exit': result.returncode, 'expected_success': success})
    (o / 'commands.json').write_text(json.dumps(runs, indent=2) + '\n')
    assert (result.returncode == 0) == success, (args, result.returncode, result.stderr)
    return result.stdout


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


primary = s / 'fixtures/bilingual-primary.json'
secondary = s / 'fixtures/bilingual-secondary.json'
before = {str(x): digest(x) for x in (primary, secondary)}
preview = json.loads(run([cli, 'preview', primary, secondary]))
c = preview['composition']
assert c['coverage'] == {
    'shared_ms': 2500, 'primary_only_ms': 1000,
    'secondary_only_ms': 1000, 'uncaptioned_ms': 1500,
}
assert preview['primary_sha256'] == before[str(primary)]
assert preview['secondary_sha256'] == before[str(secondary)]
assert c['primary_source_file'] == read(primary)['source_file']
assert c['secondary_source_file'] == read(secondary)['source_file']
assert len(c['draft']['cues']) == len(c['segments']) == 7
assert [(x['start_ms'], x['end_ms']) for x in c['draft']['cues']] == [
    (500, 1000), (1000, 2000), (2000, 2500), (2500, 3000),
    (3500, 4000), (4000, 5000), (5000, 5500),
], 'independent expected boundary list'
# Source cue numbers are verified against exact half-open activity, not index matching.
for segment, cue in zip(c['segments'], c['draft']['cues']):
    texts = []
    for name, path in [('primary', primary), ('secondary', secondary)]:
        active = [(i + 1, x) for i, x in enumerate(read(path)['cues'])
                  if x['start_ms'] <= cue['start_ms'] < x['end_ms']]
        assert segment.get(name + '_cue') == (active[0][0] if active else None)
        if active:
            assert cue['end_ms'] <= active[0][1]['end_ms']
            texts.append(active[0][1]['text'])
    assert cue['text'] == '\n'.join(texts)

bundle = o / 'Bilingual review 世界'
run([cli, 'export', primary, secondary, bundle])
assert (bundle / 'primary.json').read_bytes() == primary.read_bytes()
assert (bundle / 'secondary.json').read_bytes() == secondary.read_bytes()
assert read(bundle / 'composition.json') == preview
assert read(bundle / 'captions.json') == c['draft']
run([edit, 'show', bundle / 'captions.json'])
for suffix in ['srt', 'vtt']:
    run([edit, 'import', bundle / f'captions.{suffix}', 6000, o / f'reopened-{suffix}.json'])
    assert read(o / f'reopened-{suffix}.json')['cues'] == c['draft']['cues']
run([edit, 'set', bundle / 'captions.json', 1, 500, 1000,
     'Hello, revised garden!', o / 'corrected.json'])
assert read(o / 'corrected.json')['cues'][0]['text'] == 'Hello, revised garden!'
assert read(bundle / 'captions.json')['cues'][0]['text'] == 'Hello, garden!'

# Actual existing product attachment/extraction, not just a synthetic sidecar echo.
video = o / 'original.mp4'
run(['ffmpeg', '-v', 'error', '-nostdin', '-n', '-threads', '1',
     '-f', 'lavfi', '-i', 'color=c=navy:s=160x90:r=10:d=6',
     '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
     '-threads', '1', video])
video_before = digest(video)
receipt = json.loads(run([media, 'attach', o / 'corrected.json', video, 'mul',
                         'English + Chinese', o / 'Captioned video']))
assert receipt['verified_cues'] == len(c['draft']['cues'])
index = receipt['added_track']['index']
output_media = o / 'Captioned video/media.mp4'
run(['ffmpeg', '-v', 'error', '-nostdin', '-threads', '1', '-i', output_media,
     '-map', '0:v:0', '-f', 'null', '-'])
run([media, 'extract', output_media, index, o / 'Extracted captions'])
assert read(o / 'Extracted captions/captions.json')['cues'] == read(o / 'corrected.json')['cues']

# User-recoverable failures retain inputs and produce no new export.
overlap = read(primary)
overlap['cues'][1]['start_ms'] = 2000
(o / 'overlap.json').write_text(json.dumps(overlap))
unequal = read(secondary)
unequal['duration_ms'] = 6500
(o / 'unequal.json').write_text(json.dumps(unequal))
for name, left, right in [('overlap', o / 'overlap.json', secondary),
                          ('duration', primary, o / 'unequal.json')]:
    destination = o / ('rejected-' + name)
    run([cli, 'export', left, right, destination], False)
    assert not destination.exists()
retained = {x.name: digest(x) for x in bundle.iterdir()}
run([cli, 'export', primary, secondary, bundle], False)
assert retained == {x.name: digest(x) for x in bundle.iterdir()}
link = o / 'occupied-link'
link.symlink_to(o / 'absent-target')
run([cli, 'export', primary, secondary, link], False)
assert link.is_symlink() and not link.exists()
assert before == {str(x): digest(x) for x in (primary, secondary)}
assert digest(video) == video_before
summary = {'passed': True, 'commands': len(runs), 'input_sha256': before,
           'composed_cues': len(c['draft']['cues']), 'coverage': c['coverage'],
           'actual_product_subtitle_roundtrip': True, 'pixel_rendering_claim': False}
(o / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary))
