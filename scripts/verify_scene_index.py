#!/usr/bin/env python3
"""Focused real-media scene-index -> chapter edit -> offline player workflow.
Run under the retained run_phase.py native lock. No network or provider calls.
"""
import argparse, hashlib, json, subprocess
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--source',type=Path,required=True)
p.add_argument('--target',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
a.output.mkdir(parents=False,exist_ok=False)
commands=[]
def run(args, fail=False):
    args=[str(s) for s in args]
    r=subprocess.run(args,capture_output=True,text=True,timeout=360)
    n=len(commands)+1
    (a.output/f'{n:02}-stdout.txt').write_text(r.stdout)
    (a.output/f'{n:02}-stderr.txt').write_text(r.stderr)
    commands.append({'argv':args,'exit_code':r.returncode,'expected_refusal':fail})
    (a.output/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    assert (r.returncode != 0) if fail else (r.returncode == 0), (args,r.stdout,r.stderr)
    return r.stdout

def exe(name):
    return a.target/'native/debug/build/cmd'/name/f'{name}.exe'
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

media=a.output/'café ; four scenes.mp4'
run(['/usr/bin/ffmpeg','-hide_banner','-v','error','-nostdin','-n',
     '-f','lavfi','-i',
     'color=black:size=160x90:rate=25:duration=2[b0];color=white:size=160x90:rate=25:duration=2[w0];color=black:size=160x90:rate=25:duration=2[b1];color=white:size=160x90:rate=25:duration=2[w1];[b0][w0][b1][w1]concat=n=4:v=1:a=0',
     '-f','lavfi','-i','sine=frequency=440:sample_rate=48000:duration=8',
     '-map','0:v:0','-map','1:a:0','-c:v','libx264','-threads','1','-pix_fmt','yuv420p','-c:a','aac','-shortest',media])
source_hash=sha(media)
preview=json.loads(run([exe('scene_index'),'preview',media,10,500]))
index=preview['index']
assert [c['start_ms'] for c in index['candidates']]==[2000,4000,6000], index
assert [s['start_ms'] for s in index['scenes']]==[0,2000,4000,6000]
assert index['source_sha256']==source_hash
prefix=a.output/'detected'
export=json.loads(run([exe('scene_index'),'export',media,10,500,prefix]))
assert export==preview
assert json.loads((a.output/'detected.scenes.json').read_text())==preview
chapter=a.output/'detected.chapters.json'
assert json.loads(chapter.read_text())==index['chapters']
assert '00:00:06.000 --> 00:00:08.000' in (a.output/'detected.chapters.vtt').read_text()
assert 'START=4000\nEND=6000' in (a.output/'detected.ffmetadata').read_text()
# The output works in existing editing commands, rather than being an isolated report.
edited=a.output/'edited.chapters.json'
run([exe('chapters'),'set',chapter,'scene-2',2100,'Café & seedlings',edited])
assert json.loads(chapter.read_text())['markers'][1]['start_tick']==2000
assert json.loads(edited.read_text())['markers'][1]['title']=='Café & seedlings'
screen=a.output/'scene screening'
player=json.loads(run([exe('screening'),'export',media,'-',edited,'Detected scene review',screen]))
assert [c['start_ms'] for c in player['plan']['chapters']]==[0,2100,4000,6000]
assert 'Café &amp; seedlings' in (screen/'index.html').read_text()
assert sha(screen/'media.mp4')==source_hash
for item in player['artifacts']:
    assert sha(screen/item['path'])==item['sha256'], item
run(['/usr/bin/ffmpeg','-hide_banner','-v','error','-nostdin','-i',screen/'media.mp4','-map','0:v:0','-map','0:a:0','-f','null','/dev/null'])
# Adjustable gap shows all suppressed candidates and does not fabricate scenes.
sparse=json.loads(run([exe('scene_index'),'preview',media,10,3000]))['index']
assert [s['start_ms'] for s in sparse['scenes']]==[0,4000]
assert [c['included'] for c in sparse['candidates']]==[False,True,False]
assert len(sparse['candidates'])==3
no_changes=json.loads(run([exe('scene_index'),'preview',media,100,500]))['index']
assert len(no_changes['scenes'])==1 and not no_changes['candidates']
static=a.output/'static.mp4'
run(['/usr/bin/ffmpeg','-hide_banner','-v','error','-nostdin','-n','-f','lavfi','-i',
     'color=black:size=160x90:rate=25:duration=0.4','-c:v','libx264','-threads','1','-pix_fmt','yuv420p',static])
static_result=json.loads(run([exe('scene_index'),'preview',static,10,1000]))['index']
assert static_result['duration_ms']==400
assert len(static_result['scenes'])==1 and not static_result['candidates']
# Fixed-prefix output collisions are refused, preserving every original byte.
outputs=[a.output/('detected'+suffix) for suffix in ['.scenes.json','.chapters.json','.chapters.vtt','.ffmetadata']]
before={str(f):sha(f) for f in outputs}
run([exe('scene_index'),'export',media,10,500,prefix],fail=True)
assert before=={str(f):sha(f) for f in outputs}
invalid=a.output/'invalid'
run([exe('scene_index'),'export',media,0,500,invalid],fail=True)
assert not list(a.output.glob('invalid.*'))
broken=a.output/'broken.mp4'; broken.write_text('not video')
run([exe('scene_index'),'export',broken,10,500,a.output/'broken-output'],fail=True)
assert not list(a.output.glob('broken-output.*'))
assert sha(media)==source_hash
result={'contract':'mooncast.scene-index-workflow-check.v1','commands':len(commands),
        'real_video_boundaries_ms':[2000,4000,6000], 'editable_chapter_handoff':True,
        'screening_handoff_and_real_av_decode':True,'source_bytes_unchanged':True,
        'sparse_scene_starts_ms':[0,4000], 'static_video_single_scene':True,
        'source_sha256':source_hash,
        'boundary':'synthetic local media; no browser, semantic detection accuracy, external client or provider qualification'}
(a.output/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
