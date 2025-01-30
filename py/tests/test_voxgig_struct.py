import os
import json
import unittest

# Suppose your converted Python code is in a file called struct.py
# Adjust the import path as needed.
from voxgig_struct import (
    clone,
    isnode,
    ismap,
    islist,
    iskey,
    items,
    getprop,
    setprop,
    getpath,
    inject,
    merge,
    transform,
    walk,
)

########################################
# Utilities for testing
########################################

def walkpath(_key, val, _parent, path):
    """
    Replicates the walk callback from the JS test:
    return string + '~' + path.join('.') if val is a string,
    else return val unchanged.
    """
    if isinstance(val, str):
        return val + '~' + '.'.join(path)
    return val

def test_set(testcase, tests, apply_fn):
    """
    This replicates the logic of `function test_set(tests.set, apply) { ... }`
    from the original tests. It runs each input through apply_fn
    and checks for expected outputs or expected errors.
    """
    for entry in tests.get('set', []):
        try:
            # The original code used deepEqual(apply(entry.in), entry.out).
            # In Python, assertEqual will do a deep comparison of lists/dicts.
            input_data = entry['in']
            result = apply_fn(input_data)
            testcase.assertEqual(result, entry['out'])
        except Exception as err:
            # If an error is expected in the entry
            if entry.get('err') is not None:
                # If err == True or the error message includes the expected substring
                if entry['err'] == True or (entry['err'] in str(err)):
                    # That means the error is expected. We're done for this entry.
                    continue
                # Otherwise, record the actual error message and fail.
                entry['thrown'] = str(err)
                testcase.fail(msg=f"Unexpected error: {json.dumps(entry)}")
            else:
                # No error expected, so re-raise
                raise


class TestStruct(unittest.TestCase):
    """
    Translation of the Node.js test suite into Python unittest.
    """

    @classmethod
    def setUpClass(cls):
        """
        Loads the TESTSPEC JSON once for all tests.
        Mirrors: 
          JSON.parse(readFileSync(join(__dirname, '..', '..', 'build/test/test.json'), 'utf8'))
        """
        # Adjust to your folder structure as needed:
        test_json_path = os.path.join(
            os.path.dirname(__file__),
            '..', '..', 'build', 'test', 'test.json'
        )
        with open(test_json_path, 'r', encoding='utf-8') as f:
            cls.TESTSPEC = json.load(f)

    ########################################
    # Minor tests
    ########################################
    def test_minor_exists(self):
        # equal('function', typeof clone)  =>  check that these are callables in Python
        self.assertTrue(callable(clone))
        self.assertTrue(callable(isnode))
        self.assertTrue(callable(ismap))
        self.assertTrue(callable(islist))
        self.assertTrue(callable(iskey))
        self.assertTrue(callable(items))
        self.assertTrue(callable(getprop))
        self.assertTrue(callable(setprop))

    def test_minor_clone(self):
        # test_set(clone(TESTSPEC.minor.clone), clone)
        testspec_data = clone(self.TESTSPEC['minor']['clone'])
        test_set(self, testspec_data, clone)

    def test_minor_isnode(self):
        testspec_data = clone(self.TESTSPEC['minor']['isnode'])
        test_set(self, testspec_data, isnode)

    def test_minor_ismap(self):
        testspec_data = clone(self.TESTSPEC['minor']['ismap'])
        test_set(self, testspec_data, ismap)

    def test_minor_islist(self):
        testspec_data = clone(self.TESTSPEC['minor']['islist'])
        test_set(self, testspec_data, islist)

    def test_minor_iskey(self):
        testspec_data = clone(self.TESTSPEC['minor']['iskey'])
        test_set(self, testspec_data, iskey)

    def test_minor_items(self):
        testspec_data = clone(self.TESTSPEC['minor']['items'])
        test_set(self, testspec_data, items)

    def test_minor_getprop(self):
        def apply_fn(vin):
            # If vin.alt is null, call getprop(vin.val, vin.key)
            # else getprop(vin.val, vin.key, vin.alt)
            if vin.get('alt') is None:
                return getprop(vin['val'], vin['key'])
            else:
                return getprop(vin['val'], vin['key'], vin['alt'])

        testspec_data = clone(self.TESTSPEC['minor']['getprop'])
        test_set(self, testspec_data, apply_fn)

    def test_minor_setprop(self):
        def apply_fn(vin):
            # setprop(vin.parent, vin.key, vin.val)
            return setprop(vin['parent'], vin['key'], vin['val'])

        testspec_data = clone(self.TESTSPEC['minor']['setprop'])
        test_set(self, testspec_data, apply_fn)

    ########################################
    # merge tests
    ########################################
    def test_merge_exists(self):
        # equal('function', typeof merge)
        self.assertTrue(callable(merge))

    def test_merge_basic(self):
        # basic test merges
        test_data = clone(self.TESTSPEC['merge']['basic'])
        result = merge(test_data['in'])
        self.assertEqual(result, test_data['out'])

    def test_merge_cases(self):
        testspec_data = clone(self.TESTSPEC['merge']['cases'])
        test_set(self, testspec_data, merge)

    def test_merge_array(self):
        testspec_data = clone(self.TESTSPEC['merge']['array'])
        test_set(self, testspec_data, merge)

    ########################################
    # walk tests
    ########################################
    def test_walk_exists(self):
        # equal('function', typeof walk)
        self.assertTrue(callable(walk))

    def test_walk_basic(self):
        def apply_fn(vin):
            return walk(vin, walkpath)

        testspec_data = clone(self.TESTSPEC['walk']['basic'])
        test_set(self, testspec_data, apply_fn)

    ########################################
    # getpath tests
    ########################################
    def test_getpath_exists(self):
        self.assertTrue(callable(getpath))

    def test_getpath_basic(self):
        def apply_fn(vin):
            return getpath(vin['path'], vin['store'])

        testspec_data = clone(self.TESTSPEC['getpath']['basic'])
        test_set(self, testspec_data, apply_fn)

    def test_getpath_current(self):
        def apply_fn(vin):
            return getpath(vin['path'], vin['store'], vin['current'])

        testspec_data = clone(self.TESTSPEC['getpath']['current'])
        test_set(self, testspec_data, apply_fn)

    def test_getpath_state(self):
        # The state object in TypeScript:
        # ...
        # we replicate the same structure in Python
        state = {
            'handler': lambda s, val, _c, _st: f"{s['step']}:{val}" if not isinstance(val, dict) else val,
            'step': 0,
            'mode': 'val',
            'full': False,
            'keyI': 0,
            'keys': ['$TOP'],
            'key': '$TOP',
            'val': '',
            'parent': {},
            'path': ['$TOP'],
            'nodes': [{}],
            'base': '$TOP',
        }

        def handler_wrapper(s, val, current, store):
            out = f"{s['step']}:{val}"
            s['step'] += 1
            return out

        state['handler'] = handler_wrapper

        def apply_fn(vin):
            return getpath(vin['path'], vin['store'], vin['current'], state)

        testspec_data = clone(self.TESTSPEC['getpath']['state'])
        test_set(self, testspec_data, apply_fn)

    ########################################
    # inject tests
    ########################################
    def test_inject_exists(self):
        self.assertTrue(callable(inject))

    def test_inject_basic(self):
        test_data = clone(self.TESTSPEC['inject']['basic'])
        # deepEqual(inject(test.in.val, test.in.store), test.out)
        result = inject(test_data['in']['val'], test_data['in']['store'])
        self.assertEqual(result, test_data['out'])

    def test_inject_string(self):
        def apply_fn(vin):
            # inject(vin.val, vin.store, vin.current)
            # The original code passes 3 arguments but in the TS code:
            #   inject(val, store, modify, current)
            # We'll match usage: (val, store, modify=None, current=None)
            return inject(vin['val'], vin['store'], None, vin.get('current'))

        testspec_data = clone(self.TESTSPEC['inject']['string'])
        test_set(self, testspec_data, apply_fn)

    def test_inject_deep(self):
        testspec_data = clone(self.TESTSPEC['inject']['deep'])
        def apply_fn(vin):
            return inject(vin['val'], vin['store'])
        test_set(self, testspec_data, apply_fn)

    ########################################
    # transform tests
    ########################################
    def test_transform_exists(self):
        self.assertTrue(callable(transform))

    def test_transform_basic(self):
        test_data = clone(self.TESTSPEC['transform']['basic'])
        result = transform(
            test_data['in']['data'],
            test_data['in']['spec'],
            test_data['in']['store']
        )
        self.assertEqual(result, test_data['out'])

    def test_transform_paths(self):
        def apply_fn(vin):
            return transform(vin['data'], vin['spec'], vin['store'])

        testspec_data = clone(self.TESTSPEC['transform']['paths'])
        test_set(self, testspec_data, apply_fn)

    def test_transform_cmds(self):
        def apply_fn(vin):
            return transform(vin['data'], vin['spec'], vin['store'])

        testspec_data = clone(self.TESTSPEC['transform']['cmds'])
        test_set(self, testspec_data, apply_fn)

    def test_transform_each(self):
        def apply_fn(vin):
            return transform(vin['data'], vin['spec'], vin['store'])

        testspec_data = clone(self.TESTSPEC['transform']['each'])
        test_set(self, testspec_data, apply_fn)

    def test_transform_pack(self):
        def apply_fn(vin):
            return transform(vin['data'], vin['spec'], vin['store'])

        testspec_data = clone(self.TESTSPEC['transform']['pack'])
        test_set(self, testspec_data, apply_fn)

    def test_transform_modify(self):
        """
        Tests a custom modify function passed to transform.
        If val is a string, prefix it with '@'.
        """
        def modify_fn(key, val, parent, *args):
            if key is not None and parent is not None and isinstance(val, str):
                parent[key] = '@' + val

        def apply_fn(vin):
            return transform(vin['data'], vin['spec'], vin['store'], modify=modify_fn)

        testspec_data = clone(self.TESTSPEC['transform']['modify'])
        test_set(self, testspec_data, apply_fn)

    def test_transform_extra(self):
        """
        The 'transform-extra' test:
        deepEqual(transform({ a: 1 },
          { x: '`a`', b: '`$COPY`', c: '`$UPPER`' },
          {
            b: 2,
            $UPPER: (state: any) => { ... }
          }
        ), { x: 1, b: 2, c: 'C' })
        """
        def upper_transform_fn(state):
            """
            This transform function returns the uppercase name
            of the current path element.
            getprop(path, path.length - 1) is the last element
            of the path array
            """
            path = state.get('path', [])
            if len(path) == 0:
                return ''
            # The TypeScript code does:
            #   return ('' + getprop(path, path.length - 1)).toUpperCase()
            # But in Python, we can do:
            last_key = path[-1]
            return str(last_key).upper()

        result = transform(
            {'a': 1},
            {'x': '`a`', 'b': '`$COPY`', 'c': '`$UPPER`'},
            {
                'b': 2,
                '$UPPER': upper_transform_fn
            }
        )
        self.assertEqual(result, {'x': 1, 'b': 2, 'c': 'C'})


# If you want to run from the command line:
# python -m unittest test_struct.py
#
# Adjust the module/class name as needed.
