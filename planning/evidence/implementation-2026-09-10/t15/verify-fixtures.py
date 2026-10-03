from pathlib import Path
import hashlib,json
root=Path('tests/testthat/fixtures/windows')
expected=json.loads((root/'sha256.json').read_text())
assert all(hashlib.sha256((root/n).read_bytes()).hexdigest()==h for n,h in expected.items())
print('Seven independent OME fixtures match pinned SHA256 values.')
