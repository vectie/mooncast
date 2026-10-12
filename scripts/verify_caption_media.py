#!/usr/bin/env python3
"""Focused offline caption-media workflow using generated synthetic MP4/MKV."""
import argparse, hashlib, json, pathlib, subprocess
p = argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--target', required=True)
p.add_argument('--output', required=True)
a = p.parse_args()
root = pathlib.Path(a.output).resolve(); root.mkdir(exist_ok=False)
source = pathlib.Path(a.source).resolve(); target = pathlib.Path(a.target).resolve()
exe = target/'native/debug/build/cmd/caption_media/caption_media.exe'
edit = target/'native/debug/build/cmd/caption_edit/caption_edit.exe'
records = []
def run(args, ok=True):
    args = list(map(str, args))
    r = subprocess.run(args, capture_output=True, text=True, timeout=330)
    n = len(records)
    (root/f'{n:02d}.stdout').write_text(r.stdout)
    (root/f'{n:02d}.stderr').write_text(r.stderr)
    records.append({'argv': args, 'exit_code': r.returncode, 'expected_success': ok})
    (root/'commands.json').write_text(json.dumps(records, indent=2))
    assert (r.returncode == 0) == ok, (args, r.returncode, r.stderr)
    return r.stdout

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def packets(path, selector):
    result = json.loads(run(['ffprobe', '-v', 'error', '-select_streams', selector,
        '-show_packets', '-show_data_hash', 'sha256', '-show_entries', 'packet=data_hash',
        '-of', 'json', path]))
    return [x['data_hash'] for x in result['packets']]

srt = root/'source 中文.srt'
srt.write_text('1\n00:00:00,250 --> 00:00:01,500\n字幕 & captions\n\n2\n00:00:03,000 --> 00:00:05,500\nOriginal second cue\n')
metadata = root/'chapters.ffmetadata'
metadata.write_text(';FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=2500\ntitle=Opening\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=2500\nEND=6000\ntitle=Detail 标题\n')
mp4 = root/'source with spaces.mp4'
run(['ffmpeg', '-v', 'error', '-nostdin', '-n', '-f', 'lavfi', '-i',
    'testsrc2=size=160x90:rate=24:duration=6', '-f', 'lavfi', '-i',
    'sine=frequency=440:sample_rate=48000:duration=6', '-f', 'lavfi', '-i',
    'sine=frequency=880:sample_rate=48000:duration=6', '-i', srt, '-i', metadata,
    '-map', '0:v', '-map', '1:a', '-map', '2:a', '-map', '3:s', '-map_chapters', '4',
    '-c:v', 'libx264', '-threads', '1', '-preset', 'ultrafast', '-c:a', 'aac',
    '-c:s', 'mov_text', '-metadata:s:a:0', 'language=eng', '-metadata:s:a:1', 'language=fra',
    '-metadata:s:s:0', 'language=zho', '-metadata:s:s:0', 'handler_name=中文', '-t', '6', mp4])
new_srt = root/'English.srt'
new_srt.write_text('1\n00:00:00,501 --> 00:00:01,777\nCafé & 🌱\nSecond line.\n\n2\n00:00:03,001 --> 00:00:05,551\nA quieter conclusion.\n')
draft = root/'editable.json'
run([edit, 'import', new_srt, '6000', draft])
expected = json.loads(draft.read_text())['cues']
originals = {str(path): digest(path) for path in (mp4, srt, new_srt, draft, metadata)}
inspection = json.loads(run([exe, 'inspect', mp4]))
assert [(t['index'],t['language']) for t in inspection['inspection']['tracks'] if t['kind']=='subtitle'] == [(3,'zho')]
preview = json.loads(run([exe, 'preview', draft, mp4, 'eng', 'English captions 🌱']))
assert preview['new_track'] == 'append' and not preview['new_track_default']
bundle = root/'captioned MP4'
receipt = json.loads(run([exe, 'attach', draft, mp4, 'eng', 'English captions 🌱', bundle]))
assert receipt['added_track']['index'] == 4
assert receipt['added_track']['language'] == 'eng'
assert not receipt['added_track']['is_default'] and not receipt['added_track']['forced']
assert receipt['verified_cues'] == 2
assert receipt['output_probe']['chapters'][1]['tags']['title'] == 'Detail 标题'
for stream in ('v:0', 'a:0', 'a:1', 's:0'):
    assert packets(mp4, stream) == packets(bundle/'media.mp4', stream), stream
run(['ffmpeg', '-v', 'error', '-i', bundle/'media.mp4', '-map', '0:v', '-map', '0:a', '-f', 'null', '-'])
extracted = root/'extracted English'
run([exe, 'extract', bundle/'media.mp4', '4', extracted])
assert json.loads((extracted/'captions.json').read_text())['cues'] == expected
original_track = root/'extracted Chinese'
run([exe, 'extract', bundle/'media.mp4', '3', original_track])
assert json.loads((original_track/'captions.json').read_text())['cues'][0]['text'] == '字幕 & captions'
assert '&amp;' in (extracted/'captions.vtt').read_text()
edited = root/'corrected.json'
run([edit, 'set', extracted/'captions.json', '2', '3001', '5551', 'Corrected wording.', edited])
revised = root/'revised MP4'
# Attach the correction to the original master, avoiding obsolete added tracks.
run([exe, 'attach', edited, mp4, 'eng', 'English corrected', revised])
reopened = root/'reopened correction'
run([exe, 'extract', revised/'media.mp4', '4', reopened])
assert json.loads((reopened/'captions.json').read_text())['cues'][1]['text'] == 'Corrected wording.'
assert json.loads((bundle/'captions.json').read_text())['cues'] == expected
mkv = root/'source.mkv'
run(['ffmpeg', '-v', 'error', '-nostdin', '-n', '-f', 'lavfi', '-i',
    'testsrc2=size=160x90:rate=2:duration=6', '-i', srt, '-i', metadata,
    '-map', '0:v', '-map', '1:s', '-map_chapters', '2', '-c:v', 'ffv1', '-threads', '1',
    '-c:s', 'srt', '-metadata:s:s:0', 'language=zho', '-t', '6', mkv])
mkv_bundle = root/'captioned MKV'
run([exe, 'attach', draft, mkv, 'eng', 'English captions 🌱', mkv_bundle])
run([exe, 'extract', mkv_bundle/'media.mkv', '2', root/'extracted MKV'])
assert json.loads((root/'extracted MKV/captions.json').read_text())['cues'] == expected
for stream in ('v:0', 's:0'):
    assert packets(mkv, stream) == packets(mkv_bundle/'media.mkv', stream)
# A master without captions gets MP4's first-subtitle default, disclosed before writing.
no_captions = root/'uncaptioned.mp4'
run(['ffmpeg', '-v', 'error', '-nostdin', '-n', '-i', mp4, '-map', '0:v',
    '-map', '0:a', '-map_chapters', '0', '-c', 'copy', no_captions])
first_preview = json.loads(run([exe, 'preview', draft, no_captions, 'und', 'Unlabelled captions']))
assert first_preview['new_track_default'] and not first_preview['new_track_forced']
first = root/'first captions'
first_receipt = json.loads(run([exe, 'attach', draft, no_captions, 'und', 'Unlabelled captions', first]))
assert first_receipt['added_track']['language'] == 'und'
assert first_receipt['added_track']['is_default']
assert not first_receipt['added_track']['forced']
run([exe, 'extract', first/'media.mp4', '3', root/'first extracted'])
assert json.loads((root/'first extracted/captions.json').read_text())['cues'] == expected
# Expected input failures do not create outputs or alter earlier files.
kept = digest(bundle/'media.mp4')
run([exe, 'attach', draft, mp4, 'eng', 'English', bundle], ok=False)
assert digest(bundle/'media.mp4') == kept
link = root/'dangling'; link.symlink_to(root/'missing')
run([exe, 'attach', draft, mp4, 'eng', 'English', link], ok=False)
for index in ('0', '99'):
    dest = root/f'wrong-stream-{index}'
    run([exe, 'extract', mp4, index, dest], ok=False)
    assert not dest.exists()
wrong = json.loads(draft.read_text()); wrong['duration_ms'] = 7000
wrong_path = root/'wrong-duration.json'; wrong_path.write_text(json.dumps(wrong))
run([exe, 'attach', wrong_path, mp4, 'eng', 'English', root/'wrong duration'], ok=False)
assert not (root/'wrong duration').exists()
run([exe, 'attach', draft, mp4, 'en', 'English', root/'wrong language'], ok=False)
assert not (root/'wrong language').exists()
wrong = json.loads(draft.read_text()); wrong['cues'][1]['start_ms'] = 1000
wrong_path = root/'overlap.json'; wrong_path.write_text(json.dumps(wrong))
run([exe, 'attach', wrong_path, mp4, 'eng', 'English', root/'overlap'], ok=False)
assert not (root/'overlap').exists()
for path, sha in originals.items(): assert digest(pathlib.Path(path)) == sha
result = {'status': 'passed', 'checks': [
    'Existing caption_edit import -> inspect/preview -> append selectable English MP4 captions',
    'Two audio languages, Chinese subtitle and chapters retained; all existing stream packet hashes identical',
    'Actual added MP4 track extracted by explicit index with exact Unicode, line breaks and millisecond timings',
    'Existing caption_edit correction -> new media version -> selected-track reopening',
    'Matroska subtitle append/extract with exact cues and unchanged FFV1/subrip packet payloads',
    'First MP4 caption track uses unknown language with its default disposition disclosed in preview',
    'MP4 video/audio fully decoded; inputs and earlier versions unchanged',
    'Existing/dangling destinations, wrong stream, mismatched duration, language and overlap refused',
], 'commands': len(records), 'source_files_sha256': originals}
(root/'RESULT.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
