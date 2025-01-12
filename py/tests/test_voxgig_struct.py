
import os
import unittest
import json

from voxgig_struct import merge


with open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       '../../build/test/test.json'), 'r') as file:
    TESTSPEC = json.load(file)

def clone(obj):
    return json.loads(json.dumps(obj))



class TestVoxgigStruct(unittest.TestCase):
    def test_exists(self):
        self.assertEqual(type(merge).__name__, 'function')

        
    def test_merge_basic(self):
        test = clone(TESTSPEC['merge']['basic'])
        self.assertEqual(merge(test['in']), test['out'])

    def test_merge_children(self):
        test = clone(TESTSPEC['merge']['children'])
        self.assertEqual(merge(test['in']), test['out'])

    def test_merge_array(self):
        test = clone(TESTSPEC['merge']['array'])
        for set_data in test['set']:
            result = merge(set_data['in']) or '$UNDEFINED'
            self.assertEqual(result, set_data['out'])

        
if __name__ == "__main__":
    unittest.main()
