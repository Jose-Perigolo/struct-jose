
# RUN: python -m unittest discover -s tests
# RUN-SOME: python -m unittest discover -s tests -k getpath

import os
import json
import unittest

from voxgig_struct import (
    clone,
    escre,
    escurl,
    getpath,
    getprop,
    inject,
    isempty,
    iskey,
    islist,
    ismap,
    isnode,
    items,
    merge,
    setprop,
    stringify,
    transform,
    walk,
)


# Test utilities
# ==============

def walkpath(_key, val, _parent, path):
    """
    Annotate values with key path to value.
    """
    if isinstance(val, str):
        return val + '~' + '.'.join(path)
    return val


def test_set(testcase, tests, test_fn):
    """
    Runs each input through test_fn
    and checks for expected outputs or expected errors.
    """
    for entry in tests.get('set', []):
        try:
            input_data = entry.get('in')
            result = test_fn(input_data)
            testcase.assertEqual(result, entry.get('out'))

        except Exception as err:
            entry_err = entry.get('err')
            if entry_err is not None:
                if entry_err == True or (entry.get('err') in str(err)):
                    continue
                entry['thrown'] = str(err)
                testcase.fail(msg=f"Unexpected error: {json.dumps(entry)}")
            else:
                raise

# Since json.load uses None for null, assume
# user will represent null in another way with a defined value.
def fixnull(obj):
    if obj is None:
        return "__NULL__"
    elif isinstance(obj, list):
        return [fixnull(item) for item in obj]
    elif isinstance(obj, dict):
        return {k: fixnull(v) for k, v in obj.items()}
    else:
        return obj

def unfixnull(obj):
    if obj == "__NULL__":
        return None
    elif isinstance(obj, list):
        return [unfixnull(item) for item in obj]
    elif isinstance(obj, dict):
        return {k: unfixnull(v) for k, v in obj.items()}
    else:
        return obj

    
    
class TestStruct(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        test_json_path = os.path.join(
            os.path.dirname(__file__),
            '..', '..', 'build', 'test', 'test.json'
        )
        with open(test_json_path, 'r', encoding='utf-8') as f:
            cls.TESTSPEC = fixnull(json.load(f))


    # minor tests
    # ===========
            
    def test_minor_exists(self):
        self.assertTrue(callable(clone))
        self.assertTrue(callable(escre))
        self.assertTrue(callable(escurl))
        self.assertTrue(callable(getprop))
        self.assertTrue(callable(isempty))
        self.assertTrue(callable(iskey))
        self.assertTrue(callable(islist))
        self.assertTrue(callable(ismap))
        self.assertTrue(callable(isnode))
        self.assertTrue(callable(items))
        self.assertTrue(callable(setprop))
        self.assertTrue(callable(stringify))

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
        test_set(self, testspec_data, lambda vin: [list(item) for item in items(vin)])

    def test_minor_getprop(self):
        def apply_fn(vin):
            if vin.get('alt') is None:
                return getprop(vin.get('val'), vin.get('key'))
            else:
                return getprop(vin.get('val'), vin.get('key'), vin.get('alt'))

        testspec_data = clone(self.TESTSPEC['minor']['getprop'])
        test_set(self, testspec_data, apply_fn)

    def test_minor_setprop(self):
        def apply_fn(vin):
            return setprop(vin.get('parent'), vin.get('key'), vin.get('val'))

        testspec_data = clone(self.TESTSPEC['minor']['setprop'])
        test_set(self, testspec_data, apply_fn)

    def test_minor_isempty(self):
        testspec_data = unfixnull(clone(self.TESTSPEC['minor']['isempty']))
        test_set(self, testspec_data, isempty)

    def test_minor_escurl(self):
        testspec_data = clone(self.TESTSPEC['minor']['escurl'])
        test_set(self, testspec_data, escurl)

    def test_minor_escre(self):
        testspec_data = clone(self.TESTSPEC['minor']['escre'])
        test_set(self, testspec_data, escre)

    def test_minor_stringify(self):
        testspec_data = clone(self.TESTSPEC['minor']['stringify'])
        test_set(self, testspec_data, lambda vin: stringify(vin.get('val')) if None == vin.get('max') else stringify(vin['val'], vin['max']))

        
    # walk tests
    # ==========

    def test_walk_exists(self):
        self.assertTrue(callable(walk))

    def test_walk_basic(self):
        testspec_data = clone(self.TESTSPEC['walk']['basic'])
        test_set(self, testspec_data, lambda vin: walk(vin, walkpath))


    # merge tests
    # ===========
            
    def test_merge_exists(self):
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


    # getpath tests
    # =============
    
    def test_getpath_exists(self):
        self.assertTrue(callable(getpath))

    def test_getpath_basic(self):
        def apply_fn(vin):
            return getpath(vin.get('path'), vin.get('store'))

        testspec_data = clone(self.TESTSPEC['getpath']['basic'])
        test_set(self, testspec_data, apply_fn)

    def test_getpath_current(self):
        def apply_fn(vin):
            return getpath(vin.get('path'), vin.get('store'), vin.get('current'))

        testspec_data = clone(self.TESTSPEC['getpath']['current'])
        test_set(self, testspec_data, apply_fn)

    def test_getpath_state(self):
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
            return getpath(vin.get('path'), vin.get('store'), vin.get('current'), state)

        testspec_data = clone(self.TESTSPEC['getpath']['state'])
        test_set(self, testspec_data, apply_fn)

        
    # inject tests
    # ============

    def test_inject_exists(self):
        self.assertTrue(callable(inject))

    def test_inject_basic(self):
        test_data = clone(self.TESTSPEC['inject']['basic'])
        result = inject(test_data['in']['val'], test_data['in'].get('store'))
        self.assertEqual(result, test_data['out'])

    def test_inject_string(self):
        def apply_fn(vin):
            return inject(vin.get('val'), vin.get('store'), None, vin.get('current'))

        testspec_data = clone(self.TESTSPEC['inject']['string'])
        test_set(self, testspec_data, apply_fn)

    def test_inject_deep(self):
        testspec_data = clone(self.TESTSPEC['inject']['deep'])
        def apply_fn(vin):
            return inject(vin.get('val'), vin.get('store'))
        test_set(self, testspec_data, apply_fn)

        
    # transform tests
    # ===============

    def test_transform_exists(self):
        self.assertTrue(callable(transform))

    def test_transform_basic(self):
        test_data = clone(self.TESTSPEC['transform']['basic'])
        result = transform(
            test_data['in'].get('data'),
            test_data['in'].get('spec'),
            test_data['in'].get('store')
        )
        self.assertEqual(result, test_data['out'])

    def test_transform_paths(self):
        testspec_data = clone(self.TESTSPEC['transform']['paths'])
        test_set(self, testspec_data,
                 lambda vin: transform(vin.get('data'), vin.get('spec'), vin.get('store')))

    def test_transform_cmds(self):
        testspec_data = clone(self.TESTSPEC['transform']['cmds'])
        test_set(self, testspec_data,
                 lambda vin: transform(vin.get('data'), vin.get('spec'), vin.get('store')))

    def test_transform_each(self):
        testspec_data = clone(self.TESTSPEC['transform']['each'])
        test_set(self, testspec_data,
                 lambda vin: transform(vin.get('data'), vin.get('spec'), vin.get('store')))

    def test_transform_pack(self):
        testspec_data = clone(self.TESTSPEC['transform']['pack'])
        test_set(self, testspec_data,
                 lambda vin: transform(vin.get('data'), vin.get('spec'), vin.get('store')))

    def test_transform_modify(self):
        """
        Tests a custom modify function passed to transform.
        If val is a string, prefix it with '@'.
        """
        def modify_fn(key, val, parent, *args):
            if key is not None and parent is not None and isinstance(val, str):
                parent[key] = '@' + val

        def apply_fn(vin):
            return transform(vin['data'], vin['spec'], vin.get('store'), modify=modify_fn)

        testspec_data = clone(self.TESTSPEC['transform']['modify'])
        test_set(self, testspec_data, apply_fn)

    def test_transform_extra(self):
        def upper_transform_fn(state, val, current, store):
            """
            This transform function returns the uppercase name
            of the current path element.
            getprop(path, path.length - 1) is the last element
            of the path array
            """
            path = state.get('path', [])
            if len(path) == 0:
                return ''
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

