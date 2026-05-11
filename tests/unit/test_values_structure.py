def test_values_dev_contains_image_keys():
    p = 'kubernetes/apps/three-tier/values-dev.yaml'
    s = open(p).read()
    assert 'backend:' in s, 'backend: block missing in values-dev.yaml'
    assert 'frontend:' in s, 'frontend: block missing in values-dev.yaml'
    assert 'image:' in s, 'image: key missing in values-dev.yaml'
    assert 'repository' in s, 'repository key missing in values-dev.yaml'
    assert 'tag' in s, 'tag key missing in values-dev.yaml'

def test_values_prod_contains_image_keys():
    p = 'kubernetes/apps/three-tier/values-prod.yaml'
    s = open(p).read()
    assert 'backend:' in s
    assert 'frontend:' in s
    assert 'image:' in s
    assert 'repository' in s
    assert 'tag' in s
