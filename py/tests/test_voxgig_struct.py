
import os
import unittest
import json

from voxgig_struct import (
    clone,
    isnode,
    ismap,
    islist,
    items,
    prop,
    getpath,
    inject,
    merge,
    walk
)

with open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       '../../build/test/test.json'), 'r') as file:
    TESTSPEC = json.load(file)

def clone(obj):
    return json.loads(json.dumps(obj))


class TestVoxgigStruct(unittest.TestCase):

    def set_test(self, tests, apply, show=False):
        for entry in tests.get("set", []):
            print('TEST-ENTRY', entry) if show else None
            self.assertEqual(apply(entry.get("in")), entry.get("out"))


    def test_minor_exists(self):
        self.assertEqual(type(clone).__name__, 'function')
        self.assertEqual(type(isnode).__name__, 'function')
        self.assertEqual(type(ismap).__name__, 'function')
        self.assertEqual(type(islist).__name__, 'function')
        self.assertEqual(type(items).__name__, 'function')
        self.assertEqual(type(prop).__name__, 'function')

    def test_minor_clone(self):
        test = clone(TESTSPEC['minor']['clone'])
        self.set_test(test, lambda vin: clone(vin))

    def test_minor_isnode(self):
        test = clone(TESTSPEC['minor']['isnode'])
        self.set_test(test, lambda vin: isnode(vin))

    def test_minor_ismap(self):
        test = clone(TESTSPEC['minor']['ismap'])
        self.set_test(test, lambda vin: ismap(vin))

    def test_minor_islist(self):
        test = clone(TESTSPEC['minor']['islist'])
        self.set_test(test, lambda vin: islist(vin))

    def test_minor_items(self):
        test = clone(TESTSPEC['minor']['items'])
        self.set_test(test, lambda vin: [list(item) for item in items(vin)])

    def test_minor_prop(self):
        test = clone(TESTSPEC['minor']['prop'])
        self.set_test(test, lambda vin: prop(vin['val'], vin['key'], vin.get('alt')))
        
    def test_merge_exists(self):
        self.assertEqual(type(merge).__name__, 'function')

    def test_merge_basic(self):
        test = clone(TESTSPEC['merge']['basic'])
        self.assertEqual(merge(test['in']), test['out'])

    def test_merge_children(self):
        test = clone(TESTSPEC['merge']['children'])
        self.assertEqual(merge(test['in']), test['out'])

    def test_merge_array(self):
        test = clone(TESTSPEC['merge']['array'])
        self.set_test(test, lambda vin: merge(vin))


    def test_walk_exists(self):
        self.assertEqual('function', type(walk).__name__)

    def test_walk_basic(self):
        self.set_test(clone(TESTSPEC["walk"]["basic"]), lambda vin: walk(vin, walkpath))


    def test_getpath_exists(self):
        self.assertEqual('function', type(getpath).__name__)

    def test_getpath_basic(self):
        self.set_test(clone(TESTSPEC["getpath"]["basic"]),
                      lambda vin: getpath(vin.get("path"), vin.get("store")))

        
    def test_inject_exists(self):
        self.assertEqual('function', type(inject).__name__)

    def test_inject_basic(self):
        self.set_test(clone(TESTSPEC["inject"]["basic"]), lambda vin: inject(vin, walkpath))

    def test_inject_deep(self):
        self.set_test(clone(TESTSPEC["inject"]["deep"]),
                      lambda vin: inject(vin.get("val"), vin.get("store")), True)




        
def walkpath(_key: str | None, val: any, _parent: any, path: list[str]) -> any:
    return f"{val}~{'.'.join(path)}" if isinstance(val, str) else val


if __name__ == "__main__":
    unittest.main()
