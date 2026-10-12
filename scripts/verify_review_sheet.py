#!/usr/bin/env python3
"""Exercise the real native review_sheet CLI with locally generated media.
Only stdlib, installed FFmpeg/FFprobe and the built native executable are used.
All generated files and intentional failure logs remain in a new output folder.
"""
import argparse, hashlib, json, shutil, subprocess
from html.parser import HTMLParser
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--source', required=True, type=Path)
p.add_argument('--target', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
a = p.parse_args()
a.output = a.output.resolve()
a.output.mkdir(exist_ok=False)
exe = a.target.resolve() / 'native/debug/build/cmd/review_sheet/review_sheet.exe'
assert exe.is_file(), exe
runs = []

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(label, argv, fail=False, binary=False):
    result = subprocess.run([str(x) for x in argv], capture_output=True, timeout=180)
    record = {'label': label, 'argv': [str(x) for x in argv], 'exit_code': result.returncode,
              'expected_failure': fail, 'stdout_bytes': len(result.stdout),
              'stdout_sha256': hashlib.sha256(result.stdout).hexdigest()}
    runs.append(record)
    (a.output / (label + '.stderr.log')).write_bytes(result.stderr)
    if not binary:
        (a.output / (label + '.stdout.log')).write_bytes(result.stdout)
    (a.output / 'commands.json').write_text(json.dumps(runs, indent=2) + '\n')
    assert (result.returncode != 0) == fail, (label, result.returncode, result.stderr.decode(errors='replace'))
    return result.stdout

def write(name, data):
    path = a.output / name
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    return path

media = a.output / 'cut café & colors.mp4'
run('make-video', ['ffmpeg', '-v', 'error', '-nostdin', '-n',
    '-f', 'lavfi', '-i', 'color=c=red:s=320x180:r=25:d=2',
    '-f', 'lavfi', '-i', 'color=c=green:s=320x180:r=25:d=2',
    '-f', 'lavfi', '-i', 'color=c=blue:s=320x180:r=25:d=2',
    '-filter_complex', '[0:v][1:v][2:v]concat=n=3:v=1:a=0[v]', '-map', '[v]',
    '-c:v', 'libx264', '-threads', '1', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', media])
captions = {'contract': 'mooncast.caption-draft.v1', 'source_file': 'selected draft', 'duration_ms': 6000,
    'cues': [{'start_ms': 0, 'end_ms': 500, 'text': 'Opening.'},
             {'start_ms': 500, 'end_ms': 1800, 'text': 'Red & café.\n第二行'},
             {'start_ms': 1800, 'end_ms': 2600, 'text': 'Crossing the cut.'},
             {'start_ms': 2500, 'end_ms': 3500, 'text': 'Another speaker.'},
             {'start_ms': 4500, 'end_ms': 5900, 'text': 'Blue ending.'}]}
chapters = {'contract': 'mooncast.chapter-draft.v1', 'project_id': 'local.synthetic', 'project_revision': 3,
    'timeline_id': 'main', 'timeline_revision': 2, 'ticks_per_second': 1000, 'duration_ticks': 6000,
    'markers': [{'marker_id': 'red', 'start_tick': 500, 'title': 'Red <script>alert(1)</script>'},
                {'marker_id': 'green', 'start_tick': 2500, 'title': 'Green & "café"'},
                {'marker_id': 'blue', 'start_tick': 4500, 'title': 'Blue ending'}]}
cp = write('captions.json', captions)
ch = write('chapters.json', chapters)
originals = {str(x): sha(x) for x in [media, cp, ch]}

preview = json.loads(run('preview-uniform', [exe, 'preview', media, 'uniform', '3', cp, 'Episode review']))
assert [c['requested_ms'] for c in preview['plan']['cards']] == [1000, 3000, 5000]
assert not (a.output / 'uniform').exists()
uniform = a.output / 'uniform'
run('export-uniform', [exe, 'export', media, 'uniform', '3', cp, 'Episode review', uniform])
chapter = a.output / 'chapter sheet café'
run('export-chapters', [exe, 'export', media, 'chapters', ch, cp, 'Cut <review> & notes', chapter])
plain = a.output / 'without-captions'
run('export-no-captions', [exe, 'export', media, 'uniform', '1', '-', 'One frame', plain])
assert 'No caption draft supplied.' in (plain / 'index.html').read_text()
assert json.loads((plain / 'result.json').read_text())['source']['caption_sha256'] is None

class SheetParser(HTMLParser):
    def __init__(self):
        super().__init__(); self.images=[]; self.hrefs=[]; self.ids=set(); self.scripts=[]; self.articles=0
    def handle_starttag(self, tag, attrs):
        at = dict(attrs)
        if tag == 'img':
            self.images.append(at['src']); assert at.get('alt') and at.get('width') == '640' and at.get('height') == '360'
        if tag == 'a': self.hrefs.append(at['href'])
        if tag == 'script': self.scripts.append(at)
        if tag == 'article': self.articles += 1
        if 'id' in at:
            assert at['id'] not in self.ids; self.ids.add(at['id'])
        assert not any(key.startswith('on') for key in at)

checks=[]
def inspect(folder, expected_colors):
    receipt=json.loads((folder / 'result.json').read_text())
    assert receipt['client_acceptance'] is False
    assert receipt['source']['source_sha256'] == originals[str(media)]
    assert receipt['source']['caption_sha256'] == originals[str(cp)]
    assert receipt['index_sha256'] == sha(folder / 'index.html')
    html=(folder / 'index.html').read_text()
    parsed=SheetParser(); parsed.feed(html)
    assert not parsed.scripts and parsed.articles == len(expected_colors)
    assert len(parsed.images) == len(expected_colors)
    assert str(a.output) not in html and 'file://' not in html and 'http://' not in html and 'https://' not in html
    for href in parsed.hrefs:
        if href.startswith('#'): assert href[1:] in parsed.ids
        else: assert (folder / href).is_file() and not Path(href).is_absolute()
    assert [f['image'] for f in receipt['frames']] == parsed.images
    for n,(frame, color) in enumerate(zip(receipt['frames'], expected_colors)):
        path=folder / frame['image']
        assert sha(path) == frame['sha256'] and path.stat().st_size == frame['bytes']
        raw=run(folder.name.replace(' ', '-') + '-decode-' + str(n),
            ['ffmpeg', '-v', 'error', '-i', path, '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-threads', '1', 'pipe:1'], binary=True)
        assert len(raw) == 640*360*3
        # Inspect center pixels, excluding potential letterboxing; independently
        # prove sampling reaches each colored portion rather than repeating frame 0.
        rgb=raw[(180*640+320)*3:(180*640+320)*3+3]
        assert rgb[color] > 80 and rgb[color] > max(rgb[(color+1)%3],rgb[(color+2)%3]) + 50, (frame, list(rgb))
    checks.append({'folder':folder.name, 'cards':len(expected_colors), 'all_frames_decoded':True, 'dominant_colors_verified':expected_colors,
                   'html_references_resolve':True,'source_identity_verified':True})
    return receipt

u=inspect(uniform, [0,1,2])
c=inspect(chapter, [0,0,1,2])
assert [x['requested_ms'] for x in c['plan']['cards']] == [250,1500,3500,5250]
assert c['plan']['cards'][0]['title'] == 'Before first chapter'
assert c['source']['chapter_sha256'] == originals[str(ch)]
assert [q['cue_number'] for q in c['plan']['cards'][1]['excerpts']] == [2,3]
assert [q['cue_number'] for q in c['plan']['cards'][2]['excerpts']] == [3,4]
assert '&lt;script&gt;' in (chapter/'index.html').read_text() and '第二行' in (chapter/'index.html').read_text()
assert (chapter/'captions.json').read_bytes() == cp.read_bytes()
assert (chapter/'chapters.json').read_bytes() == ch.read_bytes()
portable=a.output/'relocated'
shutil.copytree(chapter,portable)
inspect(portable,[0,0,1,2])

# Actual Matroska input, rather than treating a suffix as proof of container.
mkv=a.output/'same-cut.mkv'
run('make-mkv', ['ffmpeg','-v','error','-nostdin','-n','-i',media,'-c','copy',mkv])
run('export-mkv', [exe,'export',mkv,'uniform','2','-','Matroska',a.output/'mkv-sheet'])

# A portrait source remains portrait inside the 16:9 image, with black side bars.
portrait=a.output/'portrait.mp4'
run('make-portrait', ['ffmpeg','-v','error','-nostdin','-n','-f','lavfi','-i','color=c=red:s=180x320:r=10:d=1',
    '-c:v','libx264','-threads','1',portrait])
portrait_sheet=a.output/'portrait-sheet'
run('export-portrait', [exe,'export',portrait,'uniform','1','-','Portrait review',portrait_sheet])
raw=run('decode-portrait',['ffmpeg','-v','error','-i',portrait_sheet/'frames/frame-1.png',
    '-f','rawvideo','-pix_fmt','rgb24','-threads','1','pipe:1'],binary=True)
assert len(raw)==640*360*3
assert max(raw[(180*640+10)*3:(180*640+10)*3+3]) < 8
assert raw[(180*640+320)*3] > 200
assert max(raw[(180*640+630)*3:(180*640+630)*3+3]) < 8
checks.append({'folder':'portrait-sheet','letterboxing_verified':True,'all_frames_decoded':True})

# Failures before output creation, plus one genuine decode-tail failure after
# output starts. No failure is silently renamed a successful delivery.
run('reject-existing', [exe,'export',media,'uniform','3',cp,'Review',uniform],fail=True)
link=a.output/'existing-link'; link.symlink_to(a.output/'absent-target')
run('reject-dangling-output', [exe,'export',media,'uniform','1','-','Review',link],fail=True)
wrong=write('wrong-duration.json',{**captions,'duration_ms':7000})
run('reject-duration', [exe,'export',media,'uniform','3',wrong,'Review',a.output/'wrong-duration-sheet'],fail=True)
assert not (a.output/'wrong-duration-sheet').exists()
run('reject-count', [exe,'export',media,'uniform','121','-','Review',a.output/'too-many'],fail=True)
assert not (a.output/'too-many').exists()
run('reject-zero', [exe,'preview',media,'uniform','0','-','Review'],fail=True)
run('reject-missing', [exe,'preview',a.output/'missing.mp4','uniform','3','-','Review'],fail=True)
nonmedia=a.output/'not-video.mp4'; nonmedia.write_text('not a media file')
run('reject-not-media', [exe,'preview',nonmedia,'uniform','3','-','Review'],fail=True)
source_link=a.output/'source-link.mp4'; source_link.symlink_to(media)
run('reject-source-link', [exe,'preview',source_link,'uniform','3','-','Review'],fail=True)
bad=write('fractional-chapters.json',{**chapters,'ticks_per_second':24000,'duration_ticks':144000,
    'markers':[{'marker_id':'fractional','start_tick':1,'title':'Fractional'}]})
run('reject-fractional', [exe,'export',media,'chapters',bad,'-','Review',a.output/'fractional'],fail=True)
assert not (a.output/'fractional').exists()
# Bounded supported-video profile: anamorphic requires another workflow.
anamorphic=a.output/'anamorphic.mp4'
run('make-anamorphic',['ffmpeg','-v','error','-nostdin','-n','-f','lavfi','-i','color=c=red:s=160x90:r=10:d=1',
    '-vf','setsar=2/1','-c:v','libx264','-threads','1',anamorphic])
run('reject-anamorphic',[exe,'preview',anamorphic,'uniform','1','-','Review'],fail=True)
# Video ends early but audio extends the container. Later requested images cannot
# be produced; the retained partial folder must lack index/result success files.
tail=a.output/'short-video-long-audio.mp4'
run('make-short-video',['ffmpeg','-v','error','-nostdin','-n','-f','lavfi','-i','color=c=red:s=160x90:r=10:d=1',
    '-f','lavfi','-i','anullsrc=r=48000:cl=mono','-t','4','-c:v','libx264','-threads','1','-c:a','aac',tail])
partial=a.output/'partial-sheet'
run('reject-empty-frame',[exe,'export',tail,'uniform','4','-','Review',partial],fail=True)
assert partial.is_dir() and (partial/'plan.json').exists()
assert not (partial/'index.html').exists() and not (partial/'result.json').exists()
run('reject-partial-reuse',[exe,'export',media,'uniform','1','-','Review',partial],fail=True)
for name,digest in originals.items(): assert sha(Path(name)) == digest
summary={'result':'PASS','checks':checks,'source_files_unchanged':True,'intentional_failures':sum(r['expected_failure'] for r in runs),
         'portable_relative_resources':True,'actual_media_encodes':True,'browser_or_print_engine_tested':False,
         'partial_decode_retained_without_success_receipt':True}
(a.output/'SUMMARY.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
