#!/usr/bin/env python3
"""Deterministic synthetic media only. Re-runnable; no account/media inputs."""
import json, pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parent / 'fixtures'
ROOT.mkdir(exist_ok=True)
def run(args):
    # Never retain a truncated fixture after an encoder or process failure.
    output=pathlib.Path(args[-1]); temporary=output.with_name(output.stem+'.partial'+output.suffix)
    try:
        subprocess.run([*args[:-1],str(temporary)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        temporary.replace(output)
    except BaseException:
        if temporary.exists(): temporary.unlink()
        raise
def encode(name, size='1920x1080', codec='libx264', extra=(), duration=30):
    output = ROOT/name
    if output.exists(): return
    run(['ffmpeg','-y','-f','lavfi','-i',f'testsrc2=size={size}:rate=24','-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t',str(duration),'-c:v',codec,'-threads','4',*extra,'-c:a','aac','-ac','2','-b:a','128k',str(output)])
encode('h264.mp4',extra=['-preset','veryfast','-g','48','-pix_fmt','yuv420p','-movflags','+faststart'],duration=120)
encode('hevc10.mp4',codec='libx265',extra=['-preset','ultrafast','-pix_fmt','yuv420p10le','-x265-params','pools=4:frame-threads=2:keyint=48','-tag:v','hvc1'])
encode('hevc4k.mp4',size='3840x2160',codec='libx265',extra=['-preset','ultrafast','-pix_fmt','yuv420p10le','-x265-params','pools=4:frame-threads=2:keyint=48','-tag:v','hvc1'])
encode('hdr10.mp4',codec='libx265',extra=['-preset','ultrafast','-pix_fmt','yuv420p10le','-x265-params','pools=4:frame-threads=2:keyint=48:hdr10=1:repeat-headers=1:colorprim=9:transfer=16:colormatrix=9:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400','-tag:v','hvc1'])
encode('hlg.mp4',codec='libx265',extra=['-preset','ultrafast','-pix_fmt','yuv420p10le','-x265-params','pools=4:frame-threads=2:keyint=48:colorprim=9:transfer=18:colormatrix=9','-tag:v','hvc1'])
encode('av1.mp4',codec='libsvtav1',extra=['-preset','12','-crf','45','-svtav1-params','lp=4'])
(ROOT/'captions.srt').write_text('1\n00:00:00,500 --> 00:00:15,000\nSRT synthetic subtitle\n\n2\n00:00:15,000 --> 00:00:29,000\nSecond cue\n')
(ROOT/'styled.ass').write_text('''[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,64,&H0000FFFF,&H000000FF,&H00000000,&H00000000,-1,0,0,0,100,100,0,0,1,3,2,2,30,30,40,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.50,0:00:29.00,Default,,0,0,0,,{\\i1}Styled ASS synthetic subtitle
''')
for source in ['h264','hevc10','hevc4k','hdr10','hlg','av1']:
    out=ROOT/(source+'.mkv')
    if not out.exists():
        run(['ffmpeg','-y','-i',str(ROOT/(source+'.mp4')),'-i',str(ROOT/'captions.srt'),'-i',str(ROOT/'styled.ass'),'-map','0:v','-map','0:a','-map','0:a','-map','1','-map','2','-c:v','copy','-c:a:0','ac3','-ac:a:0','6','-c:a:1','eac3','-ac:a:1','6','-c:s','copy','-metadata:s:a:0','language=eng','-metadata:s:a:1','language=fra','-metadata:s:s:0','language=eng','-disposition:s:0','default+forced',str(out)])
# AAC control exercises text/audio switching on devices without AC3/EAC3 decoders.
if not (ROOT/'tracks-aac.mkv').exists():
    run(['ffmpeg','-y','-i',str(ROOT/'h264.mp4'),'-i',str(ROOT/'captions.srt'),'-i',str(ROOT/'styled.ass'),'-t','30','-map','0:v','-map','0:a','-map','0:a','-map','1','-map','2','-c:v','copy','-c:a','aac','-ac','2','-c:s','copy','-metadata:s:a:0','language=eng','-metadata:s:a:1','language=fra','-disposition:s:0','default+forced',str(ROOT/'tracks-aac.mkv')])
for name,start,length in [('part1.mp4',0,30),('part2.mp4',30,30),('eof.mp4',0,7)]:
    if not (ROOT/name).exists(): run(['ffmpeg','-y','-ss',str(start),'-i',str(ROOT/'h264.mp4'),'-t',str(length),'-c:v','libx264','-preset','veryfast','-threads','4','-g','48','-c:a','aac','-ac','2',str(ROOT/name)])
# MP4 internal subtitles use mov_text, so test the MP4 enumeration independently.
if not (ROOT/'tracks.mp4').exists():
    run(['ffmpeg','-y','-i',str(ROOT/'h264.mp4'),'-i',str(ROOT/'captions.srt'),'-map','0:v','-map','0:a','-map','0:a','-map','1','-c:v','copy','-c:a','aac','-ac','2','-c:s','mov_text','-metadata:s:a:0','language=eng','-metadata:s:a:1','language=fra','-metadata:s:s:0','language=eng','-disposition:s:0','default+forced',str(ROOT/'tracks.mp4')])
for name,codec in [('mpeg2.mkv','mpeg2video'),('unsupported-video.mkv','ffv1')]:
    encode(name,size='640x360',codec=codec)
for codec in ['truehd','dca']:
    path=ROOT/(codec+'.mkv')
    if not path.exists(): run(['ffmpeg','-y','-i',str(ROOT/'h264.mp4'),'-t','30','-c:v','copy','-c:a',codec,'-ac','6',*(['-channel_layout','5.1(side)'] if codec=='dca' else []),'-strict','-2',str(path)])
if not (ROOT/'no-cues.mkv').exists(): run(['ffmpeg','-y','-i',str(ROOT/'h264.mp4'),'-c','copy','-live','1',str(ROOT/'no-cues.mkv')])
# Controls for extractor-omitted media types; valid alternatives must remain playable.
controls = {
 'unsupported-audio.mkv': ['-i',str(ROOT/'h264.mp4'),'-t','12','-c:v','copy','-c:a','wavpack'],
 'audio-only.mkv': ['-i',str(ROOT/'h264.mp4'),'-t','12','-vn','-c:a','aac'],
 'video-only.mkv': ['-i',str(ROOT/'h264.mp4'),'-t','12','-an','-c:v','copy'],
 'mixed-audio.mkv': ['-i',str(ROOT/'h264.mp4'),'-t','12','-map','0:v','-map','0:a','-map','0:a','-c:v','copy','-c:a:0','wavpack','-c:a:1','aac'],
 'mixed-video.mkv': ['-i',str(ROOT/'unsupported-video.mkv'),'-i',str(ROOT/'h264.mp4'),'-t','12','-map','0:v','-map','1:v','-map','1:a','-c','copy'],
}
for name,args in controls.items():
    if not (ROOT/name).exists(): run(['ffmpeg','-y',*args,str(ROOT/name)])
# MP4 omission and same-extractor initialization controls.
encode('unknown-jp2.mp4',size='320x180',codec='jpeg2000',duration=8)
mp4_controls = {
 'audio-only.mp4': ['-i',str(ROOT/'h264.mp4'),'-t','12','-vn','-c','copy'],
 'video-only.mp4': ['-i',str(ROOT/'h264.mp4'),'-t','12','-an','-c','copy'],
 'late-moov.mp4': ['-i',str(ROOT/'h264.mp4'),'-t','12','-c','copy'],
 'mixed-video.mp4': ['-i',str(ROOT/'unknown-jp2.mp4'),'-i',str(ROOT/'h264.mp4'),'-t','8','-map','0:v','-map','1:v','-map','1:a','-c','copy'],
 'mixed-audio-source.mp4': ['-i',str(ROOT/'h264.mp4'),'-t','12','-map','0:v','-map','0:a','-map','0:a','-c','copy'],
 'fragmented.mp4': ['-i',str(ROOT/'h264.mp4'),'-t','12','-c','copy','-movflags','frag_keyframe+empty_moov+default_base_moof'],
 'unknown-fragmented.mp4': ['-i',str(ROOT/'unknown-jp2.mp4'),'-c','copy','-movflags','frag_keyframe+empty_moov+default_base_moof'],
 'second-fragmented.mp4': ['-i',str(ROOT/'h264.mp4'),'-t','12','-c','copy','-output_ts_offset','12','-movflags','frag_keyframe+empty_moov+default_base_moof'],
 'second-unknown-fragmented.mp4': ['-i',str(ROOT/'unknown-jp2.mp4'),'-t','12','-c','copy','-output_ts_offset','12','-movflags','frag_keyframe+empty_moov+default_base_moof'],
}
for name,args in mp4_controls.items():
    if not (ROOT/name).exists(): run(['ffmpeg','-y',*args,str(ROOT/name)])
# Unknown sample-entry tag is an explicit structural control, not an actual audio codec.
for source,target,count in [('late-moov.mp4','unknown-audio.mp4',1),('mixed-audio-source.mp4','mixed-audio.mp4',2)]:
    if not (ROOT/target).exists():
        data=(ROOT/source).read_bytes();assert data.count(b'mp4a')==count
        (ROOT/target).write_bytes(data.replace(b'mp4a',b'zzza',1))
for target,second in [('repeat-fragmented.mp4','second-fragmented.mp4'),('repeat-unknown-fragmented.mp4','second-unknown-fragmented.mp4')]:
    if not (ROOT/target).exists(): (ROOT/target).write_bytes((ROOT/'fragmented.mp4').read_bytes()+(ROOT/second).read_bytes())
# An additional continuous-timestamp control must render actual segment-two frames.
from continuous_fragments import shifted_segment
if not (ROOT/'repeat-continuous-fragmented.mp4').exists():
    (ROOT/'repeat-continuous-fragmented.mp4').write_bytes((ROOT/'fragmented.mp4').read_bytes()+shifted_segment(ROOT/'second-fragmented.mp4',12))
if not (ROOT/'indexed-first.mp4').exists():
    run(['ffmpeg','-y','-i',str(ROOT/'h264.mp4'),'-t','60','-c','copy','-movflags','frag_keyframe+empty_moov+default_base_moof+global_sidx',str(ROOT/'indexed-first.mp4')])
if not (ROOT/'indexed-repeat-unknown.mp4').exists():
    (ROOT/'indexed-repeat-unknown.mp4').write_bytes((ROOT/'indexed-first.mp4').read_bytes()+shifted_segment(ROOT/'second-unknown-fragmented.mp4',60))
if not (ROOT/'indexed-repeat-valid.mp4').exists():
    (ROOT/'indexed-repeat-valid.mp4').write_bytes((ROOT/'indexed-first.mp4').read_bytes()+shifted_segment(ROOT/'second-fragmented.mp4',60))
(ROOT/'chapters.ffmetadata').write_text(';FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=5000\ntitle=Synthetic chapter one\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=5000\nEND=12000\ntitle=Synthetic chapter two\n')
if not (ROOT/'chapters.mp4').exists(): run(['ffmpeg','-y','-i',str(ROOT/'h264.mp4'),'-i',str(ROOT/'chapters.ffmetadata'),'-t','12','-map_metadata','1','-c','copy',str(ROOT/'chapters.mp4')])
# Malformed late-moov parent bound: the real loader must map the observer's IO error to container_error.
if not (ROOT/'bad-parent.mp4').exists():
    import struct
    data=bytearray((ROOT/'late-moov.mp4').read_bytes());position=0
    while position+8<=len(data):
        size,kind=struct.unpack_from('>I4s',data,position);assert size>=8
        if kind==b'moov': struct.pack_into('>I',data,position,16);break
        position+=size
    else: raise RuntimeError('missing_fixture_moov')
    (ROOT/'bad-parent.mp4').write_bytes(data)
facts={}
for path in sorted(ROOT.glob('*')):
    if path.suffix not in ('.mkv','.mp4'): continue
    probe=subprocess.run(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)],capture_output=True)
    if path.name=='bad-parent.mp4':
        if probe.returncode not in (0,1): raise RuntimeError('ffprobe_tool_failure')
        facts[path.name]={'negativeControl':True,'returnCode':probe.returncode,'probe':json.loads(probe.stdout or b'{}')}
    else:
        if probe.returncode: raise RuntimeError('ffprobe_fixture_failed')
        facts[path.name]=json.loads(probe.stdout)
(ROOT/'ffprobe.json').write_text(json.dumps(facts,indent=2))
print('fixtures complete; PGS unavailable from installed encoders: U8-only')
