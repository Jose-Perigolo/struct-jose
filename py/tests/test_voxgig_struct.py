
import os
import unittest
import json

from voxgig_struct import merge, walk


with open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       '../../build/test/test.json'), 'r') as file:
    TESTSPEC = json.load(file)

def clone(obj):
    return json.loads(json.dumps(obj))


class TestVoxgigStruct(unittest.TestCase):

    def testset(self, tests: dict, apply: callable):
        for entry in tests.get("set", []):
            self.assertEqual(apply(entry.get("in")), entry.get("out"))


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
        self.testset(test, lambda vin: merge(vin))


    def test_walk_exists(self):
        self.assertEqual('function', type(merge).__name__)

    def test_walk_basic(self):
        self.testset(clone(TESTSPEC["walk"]["basic"]), lambda vin: walk(vin, walkpath))


def walkpath(_key: str | None, val: any, _parent: any, path: list[str]) -> any:
    return f"{val}~{'.'.join(path)}" if isinstance(val, str) else val


if __name__ == "__main__":
    unittest.main()
