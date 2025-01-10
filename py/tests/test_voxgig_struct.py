

import unittest

from voxgig_struct import merge

class TestVoxgigStruct(unittest.TestCase):
    def test_exists(self):
        self.assertEqual(type(merge).__name__, 'function')

        
    def test_merge_basic(self):
        input_data = [
            {'a': 1, 'b': 2},
            {'b': 3, 'd': 4},
        ]
        expected_output = {'a': 1, 'b': 3, 'd': 4}
        self.assertEqual(merge(input_data), expected_output)

        
    def test_merge_children(self):
        input_data = [
            {"a": 1, "b": 2},
            {"b": 3, "d": {"e": 4, "ee": 5}, "f": 6},
            {"x": {"y": {"z": 7, "zz": 8}}, "q": {"u": 9, "uu": 10}, "v": 11},
        ]
        expected_output = {
            "a": 1,
            "b": 3,
            "d": {"e": 4, "ee": 5},
            "f": 6,
            "x": {"y": {"z": 7, "zz": 8}},
            "q": {"u": 9, "uu": 10},
            "v": 11,
        }
        self.assertEqual(merge(input_data), expected_output)


    def test_merge_array(self):
        self.assertEqual(merge([]), None)

        self.assertEqual(merge([[1]]), [1])

        self.assertEqual(merge([[1], [11]]), [11])

        self.assertEqual(merge([{}, {"a": [1]}]), {"a": [1]})

        self.assertEqual(
            merge([{}, {"a": [{"b": 1}], "c": [{"d": [2]}]}]),
            {"a": [{"b": 1}], "c": [{"d": [2]}]},
        )

        self.assertEqual(
            merge([{"a": [1, 2], "b": {"c": 3, "d": 4}}, {"a": [11], "b": {"c": 33}}]),
            {"a": [11, 2], "b": {"c": 33, "d": 4}},
        )

        
        
if __name__ == "__main__":
    unittest.main()
