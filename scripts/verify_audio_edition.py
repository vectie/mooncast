#!/usr/bin/env python3
"""Focused real-media acceptance. Every fixture, log and failed output is retained."""
import argparse, array, hashlib, json, math, subprocess, sys, wave
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--source', required=True)
p.add_argument('--target', required=True)
p.add_argument('--output', required=True)
a=p.parse_args()
source=Path(a.source).resolve(); target=Path(a.target); out=Path(a.output)
assert target.is_absolute() and not target.is_relative_to(source), 'absolute external target required'
assert out.is_absolute() and not out.exists(), 'choose a fresh absolute output folder'
out.mkdir()
cli=target/'native/debug/build/cmd/audio_edition/audio_edition.exe'
chapters_cli=target/'native/debug/build/cmd/chapters/chapters.exe'
assert cli.is_file() and chapters_cli.is_file()
commands=[]
def run(args, ok=True):
    args=list(map(str,args)); n=len(commands)+1
    result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=120)
    (out/f'{n:02}.stdout').write_bytes(result.stdout)
    (out/f'{n:02}.stderr').write_bytes(result.stderr)
    commands.append({'argv':args,'exit_code':result.returncode,'expected_success':ok})
    (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    assert (result.returncode==0)==ok, f'command {n}: {args}\n{result.stdout.decode(errors="replace")}\n{result.stderr.decode(errors="replace")}'
    return result.stdout

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def ff(args): return run(['ffmpeg','-hide_banner','-v','error','-nostdin','-n','-threads','1',*args])
def probe(path): return json.loads(run(['ffprobe','-v','error','-show_streams','-show_chapters','-show_format','-of','json',path]))
def decode_and_frequency(path, stem, frequency, channels, reported_duration):
    wav=out/(stem+'.decoded.wav')
    ff(['-i',path,'-map','0:a:0','-c:a','pcm_s16le','-threads','1',wav])
    with wave.open(str(wav),'rb') as w:
        assert w.getnchannels()==channels and w.getframerate()==48000
        # AAC decoding may expose a final partial frame rounded to 1024 samples.
        assert abs(w.getnframes()/48000-reported_duration)<=1024/48000
        w.setpos(48000)
        samples=array.array('h',w.readframes(48000))
        if sys.byteorder!='little': samples.byteswap()
        mono=samples[::channels]
        # Count positive-going crossings over a full second away from AAC delay.
        observed=sum(x<=0<y for x,y in zip(mono,mono[1:]))
        assert abs(observed-frequency)<=2, (observed,frequency)
        assert max(abs(x) for x in mono)>100
    return observed

draft={'contract':'mooncast.chapter-draft.v1','project_id':'listening-test','project_revision':7,
       'timeline_id':'cut','timeline_revision':3,'ticks_per_second':1000,'duration_ticks':5000,
       'markers':[{'marker_id':'intro','start_tick':0,'title':'Opening 标题'},
                  {'marker_id':'detail','start_tick':1750,'title':'A=B; #\\ detail'},
                  {'marker_id':'close','start_tick':3500,'title':'Close & listen'}]}
draft_path=out/'chapters.json'; draft_path.write_text(json.dumps(draft,ensure_ascii=False)+'\n')
media=out/'two languages source.mp4'
ff(['-f','lavfi','-i','color=c=blue:s=160x90:r=25:d=5',
    '-f','lavfi','-i','sine=frequency=440:sample_rate=48000:duration=5',
    '-f','lavfi','-i','sine=frequency=880:sample_rate=44100:duration=5',
    '-map','0:v','-map','1:a','-map','2:a','-c:v','libx264','-preset','ultrafast','-pix_fmt','yuv420p',
    '-c:a','aac','-ac:a:1','2','-metadata:s:a:0','language=eng','-metadata:s:a:1','language=fra','-threads','1',media])
input_hashes={str(media):sha(media),str(draft_path):sha(draft_path)}
inspection=json.loads(run([cli,'inspect',media]))
assert [t['index'] for t in inspection['source']['audio_tracks']]==[1,2]
assert [t['language'] for t in inspection['source']['audio_tracks']]==['eng','fra']
preview=json.loads(run([cli,'preview',media,2,draft_path]))
assert preview['plan']['omitted_stream_indices']==[0,1]
assert preview['plan']['track']['channels']==2

results=[]
def export_and_verify(input_path,index,chapters,folder,frequency,channels,language):
    receipt=json.loads(run([cli,'export',input_path,index,chapters,folder]))
    assert (folder/'result.json').is_file()
    audio=folder/'audio.m4a'; actual=probe(audio)
    streams=actual['streams']
    tracks=[s for s in streams if s['codec_type']=='audio']
    assert len(tracks)==1 and tracks[0]['codec_name']=='aac'
    assert tracks[0]['channels']==channels and tracks[0]['sample_rate']=='48000'
    assert tracks[0].get('tags',{}).get('language','und')==language
    assert all(s['codec_type']=='audio' or (s['codec_type']=='data' and s['codec_tag_string']=='text') for s in streams)
    expected=json.loads(chapters.read_text())
    assert [c['tags']['title'] for c in actual['chapters']]==[m['title'] for m in expected['markers']]
    assert [round(float(c['start_time'])*1000) for c in actual['chapters']]==[m['start_tick'] for m in expected['markers']]
    assert round(float(actual['chapters'][-1]['end_time'])*1000)==5000
    assert json.loads((folder/'chapters.json').read_text())==expected
    assert 'WEBVTT' in (folder/'chapters.vtt').read_text()
    assert receipt['result']['sha256']==sha(audio)
    assert receipt['source']['source_sha256']==sha(input_path)
    assert not receipt['publication_authority'] and not receipt['client_acceptance']
    observed=decode_and_frequency(audio,folder.name,frequency,channels,float(tracks[0]["duration"]))
    results.append({'folder':str(folder),'selected_frequency_hz':observed,'media_sha256':sha(audio)})
    return audio

fra=export_and_verify(media,2,draft_path,out/'French listening édition',880,2,'fra')
export_and_verify(media,1,draft_path,out/'English listening',440,1,'eng')
# Reuse the ordinary chapter editor, then re-export an actual audio-only M4A.
edited=out/'edited-chapters.json'
run([chapters_cli,'set',out/'French listening édition/chapters.json','detail','2000','Revised listening title',edited])
export_and_verify(fra,0,edited,out/'Revised audio-only',880,2,'fra')
# Genuine audio-only recording inputs, with no video, input start time or language.
for extension,frequency,codec in [('wav',330,'pcm_s16le'),('flac',220,'flac')]:
    recording=out/f'recording.{extension}'
    ff(['-f','lavfi','-i',f'sine=frequency={frequency}:sample_rate=44100:duration=5','-c:a',codec,'-threads','1',recording])
    input_hashes[str(recording)]=sha(recording)
    export_and_verify(recording,0,draft_path,out/f'{extension} listening',frequency,1,'und')
# Matroska's absent stream duration is checked against the produced AAC duration.
mkv=out/'source.mkv'
ff(['-i',media,'-map','0','-c','copy',mkv]); input_hashes[str(mkv)]=sha(mkv)
export_and_verify(mkv,2,draft_path,out/'Matroska listening',880,2,'fra')

# A Matroska soundtrack shorter than its video has no stream duration in the
# probe. Its chapter-extended container must not disguise the truncated audio.
short=out/'short-track.mkv'
ff(['-f','lavfi','-i','color=c=red:s=160x90:r=25:d=5',
    '-f','lavfi','-i','sine=frequency=550:sample_rate=48000:duration=1',
    '-map','0:v','-map','1:a','-c:v','libx264','-preset','ultrafast','-c:a','pcm_s16le','-threads','1',short])
input_hashes[str(short)]=sha(short)
run([cli,'export',short,1,draft_path,out/'short-audio-output'],ok=False)
assert not (out/'short-audio-output/result.json').exists()
assert (out/'short-audio-output/audio.m4a').is_file()

# User mistakes fail before output creation and never replace a retained edition.
run([cli,'export',media,0,draft_path,out/'wrong-track'],ok=False)
assert not (out/'wrong-track').exists()
run([cli,'export',media,999,draft_path,out/'missing-track'],ok=False)
assert not (out/'missing-track').exists()
run([cli,'export',media,1,draft_path,out/'English listening'],ok=False)
link=out/'dangling-destination'; link.symlink_to(out/'does-not-exist')
run([cli,'export',media,1,draft_path,link],ok=False)
assert link.is_symlink()
wrong=out/'wrong-duration.json'; wrong.write_text(json.dumps({**draft,'duration_ticks':6000})+'\n')
run([cli,'export',media,1,wrong,out/'wrong-duration'],ok=False)
assert not (out/'wrong-duration').exists()
broken=out/'broken.mp4'; broken.write_text('not media\n')
run([cli,'export',broken,0,draft_path,out/'broken-output'],ok=False)
assert not (out/'broken-output').exists()
for name,digest in input_hashes.items(): assert sha(Path(name))==digest
report={'status':'passed','outputs':results,'commands':len(commands),'source_hashes_unchanged':input_hashes,
        'boundary':'Synthetic local codec/selection/chapter checks, no browser/device or listening-quality certification'}
(out/'summary.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
print(json.dumps(report,indent=2,ensure_ascii=False))
