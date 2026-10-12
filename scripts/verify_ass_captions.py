#!/usr/bin/env python3
"""Focused ASS/SSA -> editable captions -> real embedded subtitle workflow.
All generated inputs, logs, partial outputs and failures are retained. No cleanup.
"""
import argparse, hashlib, json, subprocess
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('--source',required=True); p.add_argument('--target',required=True); p.add_argument('--output',required=True); a=p.parse_args()
s=Path(a.source).resolve(); t=Path(a.target).resolve(); o=Path(a.output).resolve(); o.mkdir(exist_ok=False)
cli=t/'native/debug/build/cmd/ass_captions/ass_captions.exe'; edit=t/'native/debug/build/cmd/caption_edit/caption_edit.exe'
assert cli.is_file() and edit.is_file()
runs=[]
def run(args, success=True):
    args=list(map(str,args)); n=len(runs)+1
    result=subprocess.run(args,capture_output=True,text=True,timeout=60)
    (o/f'{n:02d}.stdout').write_text(result.stdout); (o/f'{n:02d}.stderr').write_text(result.stderr)
    runs.append({'command':args,'exit':result.returncode,'expected_success':success})
    (o/'commands.json').write_text(json.dumps(runs,indent=2)+'\n')
    assert (result.returncode==0)==success, (args,result.returncode,result.stdout,result.stderr)
    return result.stdout
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def cues(path): return json.loads(path.read_text())['cues']
inputs=[s/'fixtures/plain-import.ass',s/'fixtures/plain-import.ssa']; before={str(x):digest(x) for x in inputs}
# Preview is read-only and exposes every converted cue plus explicit omissions.
preview=json.loads(run([cli,'preview',inputs[0],6000]))
assert preview['import']['reordered'] and preview['import']['comment_events']==1
assert preview['import']['override_cues']==3 and len(preview['omissions'])==3
assert preview['import']['draft']['cues']==[
 {'start_ms':250,'end_ms':1750,'text':'Hello, 世界 🌙\nWelcome back.'},
 {'start_ms':2000,'end_ms':3500,'text':'Plant\u00a0seeds then water.'},
 {'start_ms':2000,'end_ms':3000,'text':'Another voice.'},
 {'start_ms':4000,'end_ms':5500,'text':'Goodbye, garden.'}]
assert preview['source_sha256']==before[str(inputs[0])]
run([cli,'import',inputs[0],6000,o/'ASS captions 世界'])
bundle=o/'ASS captions 世界'; assert (bundle/'original.ass').read_bytes()==inputs[0].read_bytes()
assert json.loads((bundle/'import.json').read_text())==preview
run([edit,'show',bundle/'captions.json'])
run([edit,'import',bundle/'captions.srt',6000,o/'srt-reopen.json'])
run([edit,'import',bundle/'captions.vtt',6000,o/'vtt-reopen.json'])
assert cues(o/'srt-reopen.json')==cues(bundle/'captions.json')==cues(o/'vtt-reopen.json')
# Correct a line and resolve the overlap before a real MP4 subtitle handoff.
run([edit,'set',bundle/'captions.json',1,250,1750,'Hello, garden!\nWelcome back.',o/'corrected.json'])
run([edit,'merge',o/'corrected.json',2,3,'Plant seeds, then water. Another voice agrees.',o/'merged.json'])
run([edit,'export',o/'merged.json',o/'final'])
assert cues(o/'merged.json')[0]['text']=='Hello, garden!\nWelcome back.'
# Independently parse the source with FFprobe. Its real packets must have the same exact intervals.
probe=json.loads(run(['ffprobe','-v','error','-show_packets','-of','json',inputs[0]]))
clock=sorted((round(float(x['pts_time'])*1000),round((float(x['pts_time'])+float(x['duration_time']))*1000)) for x in probe['packets'])
assert clock==sorted((x['start_ms'],x['end_ms']) for x in cues(bundle/'captions.json'))
# Produce and fully decode a real playable MP4, then extract its actual subtitle stream and reopen it.
run(['ffmpeg','-v','error','-nostdin','-n','-threads','1','-f','lavfi','-i','color=c=navy:s=160x90:r=10:d=6','-i',o/'final.srt','-map','0:v','-map','1:0','-c:v','libx264','-preset','ultrafast','-pix_fmt','yuv420p','-threads','1','-c:s','mov_text',o/'captioned.mp4'])
run(['ffmpeg','-v','error','-nostdin','-i',o/'captioned.mp4','-map','0:v','-f','null','-'])
run(['ffmpeg','-v','error','-nostdin','-n','-i',o/'captioned.mp4','-map','0:s:0','-c:s','srt',o/'embedded.srt'])
run([edit,'import',o/'embedded.srt',6000,o/'embedded.json'])
assert cues(o/'embedded.json')==cues(o/'merged.json')
# SSA import exercises the second genuine external format through the CLI.
run([cli,'import',inputs[1],6000,o/'SSA captions'])
assert (o/'SSA captions/original.ssa').read_bytes()==inputs[1].read_bytes()
assert cues(o/'SSA captions/captions.json')==[
 {'start_ms':500,'end_ms':2500,'text':'A legacy line, with a comma.'},
 {'start_ms':3000,'end_ms':4250,'text':'Second line\nWith a break.'}]
# BOM/CRLF preserve original bytes while yielding identical cues.
bom=o/'BOM CRLF.ass'; bom.write_bytes(b'\xef\xbb\xbf'+inputs[0].read_bytes().replace(b'\n',b'\r\n'))
run([cli,'import',bom,6000,o/'BOM captions']); assert cues(o/'BOM captions/captions.json')==cues(bundle/'captions.json')
assert (o/'BOM captions/original.ass').read_bytes()==bom.read_bytes()
# Existing directories and dangling links must not be replaced.
retained={str(x):digest(x) for x in bundle.iterdir() if x.is_file()}
run([cli,'import',inputs[0],6000,bundle],False)
link=o/'occupied-link'; link.symlink_to(o/'absent-target')
run([cli,'import',inputs[0],6000,link],False); assert link.is_symlink()
# Invalid drawing, duration and syntax imports create no output folder.
for name,content in [
 ('drawing',inputs[0].read_text().replace('Goodbye, garden.','{\\p1}m 0 0 l 10 10{\\p0}')),
 ('timer',inputs[0].read_text().replace('Timer: 100.0000','Timer: 99.0000')),
 ('broken',inputs[0].read_text().replace('Welcome back.','Welcome back.{')),
 ('unknown',inputs[0].read_text().replace('[Events]','[Graphics]')),
]:
    bad=o/(name+'.ass'); bad.write_text(content); target=o/('rejected-'+name)
    run([cli,'import',bad,6000,target],False); assert not target.exists()
run([cli,'import',inputs[0],1000,o/'rejected-duration'],False); assert not (o/'rejected-duration').exists()
invalid=o/'invalid-utf8.ass'; invalid.write_bytes(b'\xff\xfe\xff')
run([cli,'import',invalid,6000,o/'rejected-encoding'],False); assert not (o/'rejected-encoding').exists()
assert before=={str(x):digest(x) for x in inputs}
assert retained=={str(x):digest(x) for x in bundle.iterdir() if x.is_file()}
(o/'summary.json').write_text(json.dumps({'passed':True,'commands':len(runs),'source_hashes':before,'imported_cues':4,'ssa_cues':2,'embedded_cues':3,'visual_equivalence_claim':False},indent=2)+'\n')
print(json.dumps({'passed':True,'commands':len(runs),'retained_output':str(o)}))
