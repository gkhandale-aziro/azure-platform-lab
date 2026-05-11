import os
import urllib.request
import pytest

DEV_URL = os.getenv('DEV_URL')

@pytest.mark.skipif(not DEV_URL, reason='DEV_URL not set; skip smoke that requires cluster')
def test_dev_smoke():
    # Simple smoke test that checks the dev frontend root responds 200
    resp = urllib.request.urlopen(DEV_URL)
    assert resp.status == 200
