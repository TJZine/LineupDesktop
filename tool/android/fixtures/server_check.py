import http.client,json,pathlib,ssl
from server import TOKEN
cert=pathlib.Path.home()/'.config/lineup-android/fixture-ca/ca.crt'
context=ssl.create_default_context(cafile=str(cert))
rows=[]
for route,status,headers in [('h264.mp4',401,{}),('h264.mp4',206,{'X-Plex-Token':TOKEN,'Range':'bytes=10-29'}),('same',302,{'X-Plex-Token':TOKEN}),('cross-host',302,{'X-Plex-Token':TOKEN}),('cross-port',302,{'X-Plex-Token':TOKEN}),('nested.m3u8',200,{'X-Plex-Token':TOKEN})]:
    c=http.client.HTTPSConnection('localhost',18443,context=context)
    c.request('GET','/auth/'+route,headers=headers); r=c.getresponse(); body=r.read() if route!='h264.mp4' or status==206 else b''
    assert r.status==status
    if status==206: assert len(body)==20 and r.getheader('Content-Range').startswith('bytes 10-29/')
    rows.append({'case':route,'status':r.status,'pass':True}); c.close()
print(json.dumps(rows,indent=2))
