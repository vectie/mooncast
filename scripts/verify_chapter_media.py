#!/usr/bin/env python3
"""Focused native chapter-media interchange with real synthetic MP4/MKV files."""
import argparse, hashlib, json, pathlib, subprocess

p = argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--target', required=True)
p.add_argument('--output', required=True)
a = p.parse_args()
root = pathlib.Path(a.output).resolve()
root.mkdir(exist_ok=False)
source = pathlib.Path(a.source).resolve()
target = pathlib.Path(a.target).resolve()
exe = target/'native/debug/build/cmd/chapter_media/chapter_media.exe'
chapters = target/'native/debug/build/cmd/chapters/chapters.exe'
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

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def packets(path, selector):
    result = json.loads(run(['ffprobe', '-v', 'error', '-select_streams', selector,
        '-show_packets', '-show_data_hash', 'sha256', '-show_entries', 'packet=data_hash',
        '-of', 'json', path]))
    return [x['data_hash'] for x in result['packets']]

draft = {'contract': 'mooncast.chapter-draft.v1', 'project_id': 'synthetic',
    'project_revision': 9, 'timeline_id': 'edit', 'timeline_revision': 4,
    'ticks_per_second': 1000, 'duration_ticks': 6000, 'markers': [
        {'marker_id': 'opening', 'start_tick': 0, 'title': 'Opening & <标题>'},
        {'marker_id': 'detail', 'start_tick': 2250, 'title': 'A=B; #\\ cats'},
        {'marker_id': 'end', 'start_tick': 5000, 'title': 'Conclusion'},
    ]}
draft_path = root/'draft.json'
draft_path.write_text(json.dumps(draft, ensure_ascii=False))
srt = root/'source.srt'
srt.write_text('1\n00:00:00,250 --> 00:00:01,500\n字幕 & captions\n\n2\n00:00:03,000 --> 00:00:05,500\nSecond cue\n')
mp4 = root/'source with spaces.mp4'
run(['ffmpeg', '-v', 'error', '-nostdin', '-n', '-f', 'lavfi', '-i',
    'testsrc2=size=160x90:rate=24:duration=6', '-f', 'lavfi', '-i',
    'sine=frequency=440:sample_rate=48000:duration=6', '-f', 'lavfi', '-i',
    'sine=frequency=880:sample_rate=48000:duration=6', '-i', srt,
    '-map', '0:v', '-map', '1:a', '-map', '2:a', '-map', '3:s',
    '-c:v', 'libx264', '-threads', '1', '-preset', 'ultrafast', '-c:a', 'aac',
    '-c:s', 'mov_text', '-metadata:s:a:0', 'language=eng', '-metadata:s:a:1', 'language=fra',
    '-metadata:s:s:0', 'language=zho', '-t', '6', mp4])
originals = {str(path): digest(path) for path in (mp4, srt, draft_path)}
preview = json.loads(run([exe, 'preview', draft_path, mp4]))
assert len(preview['plan']['stream_indices']) == 4
assert preview['plan']['replaced_chapters'] == 0
bundle = root/'chaptered MP4'
run([exe, 'embed', draft_path, mp4, bundle])
assert (bundle/'result.json').exists()
for stream in ('v:0', 'a:0', 'a:1', 's:0'):
    assert packets(mp4, stream) == packets(bundle/'media.mp4', stream), stream
run(['ffmpeg', '-v', 'error', '-i', bundle/'media.mp4', '-map', '0:v', '-map', '0:a', '-f', 'null', '-'])
extracted = root/'extracted'
run([exe, 'extract', draft_path, bundle/'media.mp4', extracted])
reopened = json.loads((extracted/'chapters.json').read_text())
assert [(m['start_tick'], m['title']) for m in reopened['markers']] == [(m['start_tick'], m['title']) for m in draft['markers']]
assert reopened['project_revision'] == 9 and reopened['timeline_revision'] == 4
edited = root/'edited.json'
run([chapters, 'set', extracted/'chapters.json', 'imported.2', '3000', 'Revised detail', edited])
revised = root/'revised MP4'
run([exe, 'embed', edited, bundle/'media.mp4', revised])
receipt = json.loads((revised/'result.json').read_text())
assert receipt['source']['plan']['replaced_chapters'] == 3
assert receipt['source']['plan']['replaced_chapter_data_streams'] == 1
assert receipt['result']['probe']['chapters'][1]['tags']['title'] == 'Revised detail'
assert receipt['result']['probe']['chapters'][1]['start_time'] == '3.000000'
assert json.loads((bundle/'result.json').read_text())['result']['probe']['chapters'][1]['tags']['title'] == draft['markers'][1]['title']
# Independent Matroska profile: actual nanosecond chapter integers and subtitle stream.
mkv = root/'source.mkv'
run(['ffmpeg', '-v', 'error', '-nostdin', '-n', '-f', 'lavfi', '-i',
    'testsrc2=size=160x90:rate=2:duration=6', '-i', srt,
    '-map', '0:v', '-map', '1:s', '-c:v', 'ffv1', '-threads', '1', '-c:s', 'srt', '-t', '6', mkv])
mkv_bundle = root/'chaptered MKV'
run([exe, 'embed', draft_path, mkv, mkv_bundle])
run([exe, 'extract', draft_path, mkv_bundle/'media.mkv', root/'extracted MKV'])
for stream in ('v:0', 's:0'):
    assert packets(mkv, stream) == packets(mkv_bundle/'media.mkv', stream)
# Fresh-folder/no-overwrite checks include existing and dangling symlink names.
kept = digest(bundle/'media.mp4')
run([exe, 'embed', draft_path, mp4, bundle], ok=False)
assert digest(bundle/'media.mp4') == kept
link = root/'dangling'; link.symlink_to(root/'missing')
run([exe, 'embed', draft_path, mp4, link], ok=False)
run([exe, 'extract', draft_path, mp4, root/'no chapters'], ok=False)
assert not (root/'no chapters').exists()
wrong = dict(draft, duration_ticks=7000)
wrong_path = root/'wrong.json'; wrong_path.write_text(json.dumps(wrong))
run([exe, 'embed', wrong_path, mp4, root/'wrong duration'], ok=False)
assert not (root/'wrong duration').exists()
for path, sha in originals.items():
    assert digest(pathlib.Path(path)) == sha
result = {'status': 'passed', 'checks': [
    'MP4 preview, embed, exact chapter extraction, existing chapter authoring, replacement and reopening',
    'Two audio tracks and Unicode subtitle track retained with exact compressed packet SHA-256 sequences',
    'MP4 video/audio decode passes; source bytes unchanged',
    'Matroska nanosecond chapter round trip; FFV1/subrip payload sequences unchanged',
    'Existing/dangling destination, absent chapters, duration mismatch refused without overwrite',
], 'commands': len(records), 'source_files_sha256': originals}
(root/'RESULT.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
