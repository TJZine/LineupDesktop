import json
from pathlib import Path
import unittest
from e6_playlist_scope import validate, ScopeFailure, TAGS, REASONS

ROOT = Path(__file__).parent
class PlaylistScope(unittest.TestCase):
    def test_shared_native_host_vectors(self):
        for row in json.loads((ROOT/'e6_playlist_scope_cases.json').read_text()):
            with self.subTest(name=row['name']):
                data=bytes.fromhex(row['hex']) if 'hex' in row else row['text'].encode()
                try:
                    result=validate(data,variant=row.get('variant','https://localhost:21443/e6-clock/index.m3u8'),offset_us=0,target=10,durations_us=[10000000,10000000])
                except ScopeFailure as error:
                    self.assertEqual({'playlistScopeReason':row['reason'],'playlistScopeTag':row['tag'],'playlistScopeIndex':row['index']},error.facts())
                    self.assertNotIn('PRIVATE_SENTINEL',str(error)+json.dumps(error.facts()))
                else:
                    self.assertIsNone(row['reason']);self.assertEqual(len(result['media']),2)
    def test_vocabularies_are_exact_schema_mirrors(self):
        schema=json.loads((ROOT/'e6_schema.json').read_text())['fields']
        self.assertEqual(set(schema['playlistScopeReason']['enum']), REASONS)
        self.assertEqual(set(schema['playlistScopeTag']['enum']), TAGS|{'other_tag'})
    def test_config_derivation_is_strict_before_native_load(self):
        text=json.loads((ROOT/'e6_playlist_scope_cases.json').read_text())[0]['text']
        valid=validate(text.encode(),variant='https://localhost:21443/e6-clock/index.m3u8',offset_us=0,target=None,durations_us=None)
        self.assertEqual(valid['target'],10)
        with self.assertRaises(ScopeFailure) as e:
            validate(text.replace('#EXTINF:10,','#EXTINF:10,title').encode(),variant='https://localhost:21443/e6-clock/index.m3u8',offset_us=0,target=None,durations_us=None)
        self.assertEqual(e.exception.reason,'extinf_format')
if __name__=='__main__':unittest.main()
