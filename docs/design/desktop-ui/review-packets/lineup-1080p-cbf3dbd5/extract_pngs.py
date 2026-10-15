"""Extract the untouched screenshots embedded in the adjacent offline viewer."""
import base64
import hashlib
import json
from pathlib import Path
import struct

packet = Path(__file__).resolve().parent
html = (packet / 'comparison.html').read_text(encoding='utf-8')
payload = html.split('<script id="payload" type="application/json">', 1)[1].split('</script>', 1)[0]
entries = json.loads(payload)['entries']
manifest = json.loads((packet / 'manifest.json').read_text(encoding='utf-8'))
expected = {item['image']: item['png_sha256'] for item in manifest['entries']}
output = packet / 'current'
output.mkdir(exist_ok=True)
for entry in entries:
    name = entry['image']
    if Path(name).name != name:
        raise ValueError('Invalid screenshot filename')
    raw = base64.b64decode(entry['imageData'].split(',', 1)[1], validate=True)
    if (hashlib.sha256(raw).hexdigest() != expected[name]
            or raw[:8] != b'\x89PNG\r\n\x1a\n'
            or struct.unpack('>II', raw[16:24]) != (1920, 1080)):
        raise ValueError(f'Screenshot integrity check failed: {name}')
    destination = output / name
    if destination.exists() and destination.read_bytes() != raw:
        raise FileExistsError(f'Preserving different existing file: {name}')
    destination.write_bytes(raw)
print(f'Extracted and verified {len(entries)} original 1920x1080 PNGs.')
