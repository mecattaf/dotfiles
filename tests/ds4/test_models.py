"""Reject a broken pinned model transaction without downloading any weights."""
import base64
import json
import sys

for path in sys.argv[1:]:
    for name, artifact in json.load(open(path)).items():
        source = artifact['source']
        assert len(source['revision']) == 40, (name, 'mutable source')
        names = [entry['path'] for entry in source['files']]
        assert len(names) == len(set(names))
        assert source['primary'] in names
        for entry in source['files']:
            assert entry['bytes'] > 0
            assert len(entry['oid']) == 64
            assert entry['hash'] == 'sha256-' + base64.b64encode(bytes.fromhex(entry['oid'])).decode()
            assert not entry['path'].startswith('/')
            assert '..' not in entry['path'].split('/')
print('Pinned manifests: complete primary, unique paths, sizes and matching SHA-256/SRI verified')
