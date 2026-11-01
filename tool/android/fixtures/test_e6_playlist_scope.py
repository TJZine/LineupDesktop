import json
from pathlib import Path
import unittest
from e6_playlist_scope import validate, inspect_shape, ScopeFailure, TAGS, REASONS, EXTINF_CLASSES

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
            validate(text.replace('#EXTINF:10,','#EXTINF:10.0000001,title').encode(),variant='https://localhost:21443/e6-clock/index.m3u8',offset_us=0,target=None,durations_us=None)
        self.assertEqual(e.exception.reason,'extinf_format')
    def shape(self, data, **kwargs):
        return inspect_shape(data, variant='https://localhost:21443/e6-clock/index.m3u8',
            offset_us=kwargs.get('offset_us', 0), target=kwargs.get('target', 10),
            durations_us=kwargs.get('durations_us', [10000000, 10000000]))

    def test_complete_shape_does_not_stop_at_first_error(self):
        data = ('\ufeff #EXTM3U\n#EXT-X-KEY:URI="PRIVATE_SENTINEL"\n'
            '#EXT-X-PRIVATE_SENTINEL:private-value\n#EXT-X-PRIVATE_SENTINEL:again\n'
            '#EXT-X-TARGETDURATION:11\n#EXT-X-TARGETDURATION:12\n'
            '#EXTINF:10,PRIVATE_TITLE\n0.m4s\n#EXT-X-MAP:URI="init.mp4"\n'
            '#EXTINF:10.1234567,\n1.m4s\n#EXT-X-ENDLIST\n').encode()
        first = None
        try: validate(data, variant='https://localhost:21443/e6-clock/index.m3u8', offset_us=0, target=10, durations_us=[10000000,10000000])
        except ScopeFailure as error: first = error.reason
        shape = self.shape(data)
        self.assertEqual(first, 'bom_or_whitespace')
        self.assertEqual(set(shape['failing_reasons']), {'bom_or_whitespace','unknown_tag',
            'target_mismatch','map_position','missing_media_sequence','duplicate_tag','extinf_format'})
        self.assertEqual(shape['tag_names'], ['EXT-X-ENDLIST','EXT-X-KEY','EXT-X-MAP','EXT-X-TARGETDURATION','EXTINF','EXTM3U'])
        self.assertEqual(shape['other_tag_count'], 2)
        self.assertEqual(shape['duplicate_tag_count'], 1)
        self.assertEqual(shape['extinf_format_classes'], ['decimal_gt_6','has_title','integer'])
        for key in ('bom_present','leading_whitespace_present'): self.assertTrue(shape[key])
        for key in ('media_sequence_present','map_before_first_segment'): self.assertFalse(shape[key])
        for private in ('PRIVATE_SENTINEL','PRIVATE_TITLE','private-value','init.mp4','0.m4s'):
            self.assertNotIn(private, json.dumps(shape))

    def test_shared_vectors_keep_first_reason_and_report_closed_shape(self):
        for row in json.loads((ROOT/'e6_playlist_scope_cases.json').read_text()):
            with self.subTest(name=row['name']):
                data = bytes.fromhex(row['hex']) if 'hex' in row else row['text'].encode()
                shape = inspect_shape(data, variant=row.get('variant','https://localhost:21443/e6-clock/index.m3u8'),
                    offset_us=0, target=10, durations_us=[10000000,10000000])
                if row['reason'] is not None: self.assertIn(row['reason'], shape['failing_reasons'])
                else: self.assertEqual(shape['failing_reasons'], [])
                self.assertLessEqual(set(shape['failing_reasons']), REASONS)
                self.assertLessEqual(set(shape['tag_names']), TAGS)
                self.assertLessEqual(set(shape['extinf_format_classes']), EXTINF_CLASSES)
                self.assertEqual(len(shape['failing_reasons']),len(set(shape['failing_reasons'])))
                self.assertNotIn('PRIVATE_SENTINEL', json.dumps(shape))

    def test_formats_are_additive_and_repeatable_segments_are_not_duplicates(self):
        data = ('#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:0\n'
            '#EXT-X-MAP:URI="init.mp4"\n#EXTINF:10,\n0.m4s\n'
            '#EXTINF:10.000001,\n1.m4s\n#EXTINF:10.0000001,private\n2.m4s\n#EXT-X-ENDLIST\n').encode()
        shape = self.shape(data, durations_us=None)
        self.assertEqual(set(shape['extinf_format_classes']), EXTINF_CLASSES)
        self.assertEqual(shape['duplicate_tag_count'],0)
        self.assertTrue(shape['map_before_first_segment']);self.assertTrue(shape['media_sequence_present'])
        self.assertEqual(shape['failing_reasons'],['extinf_format'])

    def test_failures_after_endlist_and_invalid_utf8_are_still_observed(self):
        data = ('#EXTM3U\n#EXT-X-ENDLIST\n#EXT-X-START:TIME-OFFSET=1\n'
            '#EXT-X-START:TIME-OFFSET=2\n#EXT-X-VERSION:11\n'
            '#EXT-X-MEDIA-SEQUENCE:7\n#EXT-X-MAP:URI="../PRIVATE_PATH"\n'
            '#EXTINF:0,\nPRIVATE_MEDIA\n').encode()+b'\xff\n'
        shape=self.shape(data)
        self.assertLessEqual({'utf8_format','segment_structure','start_mismatch',
            'duplicate_tag','version_format','media_sequence_mismatch','reference_scope','target_mismatch'},set(shape['failing_reasons']))
        self.assertNotIn('PRIVATE',json.dumps(shape))

    def test_presence_and_position_do_not_imply_valid_tag_values(self):
        data = (b'#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE\n'
            b'#EXT-X-MAP\n#EXTINF:10,\n0.m4s\n#EXT-X-ENDLIST\n')
        shape=self.shape(data)
        self.assertTrue(shape['media_sequence_present']);self.assertTrue(shape['map_before_first_segment'])
        self.assertIn('unknown_tag',shape['failing_reasons'])

    def test_whole_bounded_prefix_is_scanned_without_losing_later_facts(self):
        data=b' '*(1024*1024-100)+b'#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-KEY:private\n'
        shape=self.shape(data)
        self.assertTrue(shape['leading_whitespace_present']);self.assertTrue(shape['media_sequence_present'])
        self.assertIn('EXT-X-KEY',shape['tag_names']);self.assertIn('unknown_tag',shape['failing_reasons'])

    def test_shape_byte_bound_is_not_bypassed(self):
        with self.assertRaises(ValueError):self.shape(b'x'*(1024*1024+1))

if __name__=='__main__':unittest.main()
