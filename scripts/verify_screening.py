#!/usr/bin/env python3
"""Real native CLI/media journey plus emitted player JavaScript interaction checks.
No browser engine is installed or claimed; DOM/API behavior uses a bounded test double.
"""
import argparse, hashlib, json, subprocess, shutil, re
from pathlib import Path
from html.parser import HTMLParser

class Page(HTMLParser):
    def __init__(self):
        super().__init__(); self.nodes=[]; self.scripts=[]; self.script=None; self.urls=[]
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs); self.nodes.append({'tag':tag,'attrs':attrs})
        for attr in ('src','href'):
            if attr in attrs:self.urls.append(attrs[attr])
        if tag=='script':self.script={'attrs':attrs,'text':''}; self.scripts.append(self.script)
    def handle_data(self,data):
        if self.script is not None:self.script['text']+=data
    def handle_endtag(self,tag):
        if tag=='script':self.script=None

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,required=True);ap.add_argument('--target',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    exe=a.target.resolve()/'native/debug/build/cmd/screening/screening.exe'
    assert exe.is_file(),exe
    commands=[]
    def run(args,label,success=True):
        proc=subprocess.run([str(x) for x in args],capture_output=True)
        (out/(label+'.stdout')).write_bytes(proc.stdout);(out/(label+'.stderr')).write_bytes(proc.stderr)
        commands.append({'label':label,'args':[str(x) for x in args],'exit_code':proc.returncode})
        assert (proc.returncode==0)==success,(label,proc.returncode,proc.stderr.decode(errors='replace'))
        return proc.stdout
    media=out/'sample café.mp4'
    run(['ffmpeg','-hide_banner','-v','error','-nostdin','-n','-f','lavfi','-i','testsrc2=size=192x108:rate=10:duration=6','-f','lavfi','-i','sine=frequency=440:duration=6','-c:v','libx264','-threads','1','-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart','-shortest',media],'fixture')
    captions={'contract':'mooncast.caption-draft.v1','source_file':'spoken café.srt','duration_ms':6000,'cues':[
        {'start_ms':500,'end_ms':2500,'text':'Café &amp; 🌱\nSecond line'},
        {'start_ms':1500,'end_ms':3000,'text':'Another speaker'},
        {'start_ms':4000,'end_ms':6000,'text':'Final words'}]}
    chapters={'contract':'mooncast.chapter-draft.v1','project_id':'synthetic','project_revision':1,'timeline_id':'cut','timeline_revision':2,'ticks_per_second':30000,'duration_ticks':180000,'markers':[
        {'marker_id':'intro','start_tick':30000,'title':'First <chapter>'},
        {'marker_id':'outro','start_tick':90030,'title':'Next & café'}]}
    cp=out/'captions.json';ch=out/'chapters.json'
    cp.write_text(json.dumps(captions,ensure_ascii=False));ch.write_text(json.dumps(chapters,ensure_ascii=False))
    title='Review </script><script>bad()</script> & café'
    base=[media,cp,ch,title]
    preview=json.loads(run([exe,'preview',*base],'preview'))
    assert preview['plan']['chapters'][1]['start_ms']==3001
    assert preview['plan']['cues']==captions['cues']
    bundle=out/'screening café'
    result=json.loads(run([exe,'export',*base,bundle],'export'))
    assert result['source']['source_sha256']==digest(media)
    assert not result['client_acceptance']
    assert digest(bundle/'media.mp4')==digest(media)
    assert (bundle/'captions.json').read_bytes()==cp.read_bytes()
    assert (bundle/'chapters.json').read_bytes()==ch.read_bytes()
    assert 'Café &amp;amp; 🌱' in (bundle/'captions.vtt').read_text()
    # Full decode demonstrates playable audio/video bytes for the actual output.
    run(['ffmpeg','-hide_banner','-v','error','-nostdin','-threads','1','-i',bundle/'media.mp4','-map','0:v','-map','0:a','-f','null','-'],'decode-output')
    page=Page();page.feed((bundle/'index.html').read_text())
    assert len(page.scripts)==2
    data=json.loads(page.scripts[0]['text']);assert data==result['plan']
    assert '<script>bad()' not in (bundle/'index.html').read_text()
    assert all(not url.startswith(('http:', 'https:', '//', 'file:', '/')) for url in page.urls)
    assert not any(n['tag']=='script' and 'src' in n['attrs'] for n in page.nodes)
    for artifact in result['artifacts']:assert digest(bundle/artifact['path'])==artifact['sha256']
    relocated=out/'relocated folder';shutil.copytree(bundle,relocated)
    for url in page.urls:
        if not url.startswith('#'):assert (relocated/url).is_file(),url
    assert digest(relocated/'media.mp4')==digest(media)
    # Player script comes from the generated HTML, not a duplicate test implementation.
    payload=out/'player-payload.json';payload.write_text(json.dumps({'nodes':page.nodes,'data':data,'script':page.scripts[1]['text']}))
    run(['node',a.source.resolve()/'scripts/verify_screening_player.cjs',payload],'player-interactions')
    bare=out/'media-only';run([exe,'export',media,'-','-','Media only',bare],'bare-export')
    barepage=Page();barepage.feed((bare/'index.html').read_text())
    payload2=out/'bare-payload.json';payload2.write_text(json.dumps({'nodes':barepage.nodes,'data':json.loads(barepage.scripts[0]['text']),'script':barepage.scripts[1]['text']}))
    run(['node',a.source.resolve()/'scripts/verify_screening_player.cjs',payload2],'bare-player')
    # A mismatched draft fails before creating output; existing folders stay unchanged.
    wrong=out/'wrong.json';wrong.write_text(json.dumps({**captions,'duration_ms':7000}))
    reject=out/'should-not-exist';run([exe,'export',media,wrong,ch,'Wrong',reject],'wrong-duration',False);assert not reject.exists()
    before={p.name:digest(p) for p in bundle.iterdir()}
    run([exe,'export',*base,bundle],'existing-folder',False)
    assert before=={p.name:digest(p) for p in bundle.iterdir()}
    # Reject Matroska even when codecs happen to be browser-capable.
    mkv=out/'sample.mkv';run(['ffmpeg','-hide_banner','-v','error','-nostdin','-n','-i',media,'-c','copy',mkv],'mkv-fixture')
    run([exe,'preview',mkv,cp,ch,'Unsupported container'],'reject-mkv',False)
    # yuv444p is outside the expressly supported browser-oriented profile.
    unsupported=out/'yuv444.mp4';run(['ffmpeg','-hide_banner','-v','error','-nostdin','-n','-f','lavfi','-i','color=red:s=64x64:r=10:d=1','-c:v','libx264','-threads','1','-pix_fmt','yuv444p',unsupported],'yuv444-fixture')
    run([exe,'preview',unsupported,'-','-','Unsupported pixels'],'reject-pixels',False)
    run([exe,'help'],'help')
    (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    receipt={'contract':'mooncast.screening-workflow-check.v1','native_cli':True,'real_media_decode':True,'relocated_resources_verified':True,'emitted_javascript_interactions':'Node DOM/API test double; not browser qualification','commands':len(commands),'artifacts':len(result['artifacts']),'source_sha256':digest(media)}
    (out/'verification.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))
if __name__=='__main__':main()
