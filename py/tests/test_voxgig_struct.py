
# RUN: python -m unittest discover -s tests
# RUN-SOME: python -m unittest discover -s tests -k getpath


import unittest

from runner import runner
        
from voxgig_struct import (
    clone,
    escre,
    escurl,
    getpath,
    getprop,
    haskey,
    inject,
    isempty,
    isfunc,
    iskey,
    islist,
    ismap,
    isnode,
    items,
    joinurl,
    keysof,
    merge,
    setprop,
    stringify,
    transform,
    validate,
    walk
)




def walkpath(_key, val, _parent, path):
    if isinstance(val, str):
        return val + '~' + '.'.join(str(p) for p in path)
    return val


def nullModifier(key, val, parent):
    if "__NULL__" == val:
        parent[key] = None
    elif isinstance(val, str):
        parent[key] = val.replace("__NULL__", "null")
        
    
class Provider:
    def __init__(self, opts=None):
        pass

    @staticmethod
    def test(opts=None):
        return Provider(opts)

    def utility(self):
        return {
            "struct": {
                "clone": clone,
                "escre": escre,
                "escurl": escurl,
                "getpath": getpath,
                "getprop": getprop,
                "inject": inject,
                "isempty": isempty,
                "isfunc": isfunc,
                "iskey": iskey,
                "islist": islist,
                "ismap": ismap,
                "isnode": isnode,
                "items": items,
                "haskey": haskey,
                "keysof": keysof,
                "merge": merge,
                "setprop": setprop,
                "stringify": stringify,
                "transform": transform,
                "walk": walk,
                "validate": validate,
                "joinurl": joinurl,
            }
        }


provider = Provider.test()

runparts = runner(
    name='struct',
    store={},
    testfile='../../build/test/test.json',  # adapt path as needed
    provider=provider
)

spec = runparts["spec"]
runset = runparts["runset"]


class TestStruct(unittest.TestCase):

    # -------------------------------------------------
    # minor-exists
    # -------------------------------------------------

    def test_minor_exists(self):
        self.assertTrue(callable(clone))
        self.assertTrue(callable(escre))
        self.assertTrue(callable(escurl))
        self.assertTrue(callable(getprop))
        self.assertTrue(callable(haskey))
        self.assertTrue(callable(isempty))
        self.assertTrue(callable(isfunc))
        self.assertTrue(callable(iskey))
        self.assertTrue(callable(islist))
        self.assertTrue(callable(ismap))
        self.assertTrue(callable(isnode))
        self.assertTrue(callable(items))
        self.assertTrue(callable(joinurl))
        self.assertTrue(callable(keysof))
        self.assertTrue(callable(setprop))
        self.assertTrue(callable(stringify))

        
    def test_minor_isnode(self):
        runset(spec["minor"]["isnode"], isnode, {"fixjson": False})

    def test_minor_ismap(self):
        runset(spec["minor"]["ismap"], ismap, {"fixjson": False})

    def test_minor_islist(self):
        runset(spec["minor"]["islist"], islist, {"fixjson": False})

    def test_minor_iskey(self):
        runset(spec["minor"]["iskey"], iskey, {"fixjson": False})

    def test_minor_isempty(self):
        runset(spec["minor"]["isempty"], isempty, {"fixjson": False})

    def test_minor_isfunc(self):
        runset(spec["minor"]["isfunc"], isfunc, {"fixjson": False})
        def f0():
            return None
        self.assertTrue(isfunc(f0))
        self.assertTrue(isfunc(lambda: None))

    def test_minor_clone(self):
        runset(spec["minor"]["clone"], clone)
        def f0():
            return None
        self.assertEqual({"a":f0}, clone({"a":f0}))
        
    def test_minor_items(self):
        runset(spec["minor"]["items"], items)

    def test_minor_escre(self):
        runset(spec["minor"]["escre"], escre)

    def test_minor_escurl(self):
        runset(spec["minor"]["escurl"], escurl)

    def test_minor_stringify(self):
        def stringify_wrapper(vin):
            if vin.get("max") is None:
                return stringify(vin.get("val"))
            else:
                return stringify(vin.get("val"), vin.get("max"))
        runset(spec["minor"]["stringify"], stringify_wrapper)

    def test_minor_getprop(self):
        def getprop_wrapper(vin):
            if vin.get("alt") is None:
                return getprop(vin.get("val"), vin.get("key"))
            else:
                return getprop(vin.get("val"), vin.get("key"), vin.get("alt"))
        runset(spec["minor"]["getprop"], getprop_wrapper)

    def test_minor_setprop(self):
        def setprop_wrapper(vin):
            return setprop(vin.get("parent"), vin.get("key"), vin.get("val"))
        runset(spec["minor"]["setprop"], setprop_wrapper)

    def test_minor_haskey(self):
        runset(spec["minor"]["haskey"], haskey)

    def test_minor_keysof(self):
        runset(spec["minor"]["keysof"], keysof)

    def test_minor_joinurl(self):
        runset(spec["minor"]["joinurl"], joinurl, {"fixjson": False})


    # -------------------------------------------------
    # walk tests
    # -------------------------------------------------

    def test_walk_exists(self):
        self.assertTrue(callable(walk))

    def test_walk_basic(self):
        def walk_wrapper(vin=None):
            return walk(vin, walkpath)
        runset(spec["walk"]["basic"], walk_wrapper)

    # -------------------------------------------------
    # merge tests
    # -------------------------------------------------

    def test_merge_exists(self):
        self.assertTrue(callable(merge))

    def test_merge_basic(self):
        test_data = self.clone(spec["merge"]["basic"])
        self.assertEqual(merge(test_data["in"]), test_data["out"])

    def test_merge_cases(self):
        runset(spec["merge"]["cases"], merge)

    def test_merge_array(self):
        runset(spec["merge"]["array"], merge)

    def test_merge_special(self):
        def f0():
            return None
        self.assertEqual(merge([f0]), f0)
        self.assertEqual(merge([None, f0]), f0)
        self.assertEqual(merge([{"a": f0}]), {"a": f0})
        self.assertEqual(merge([{"a": {"b": f0}}]), {"a": {"b": f0}})

    # -------------------------------------------------
    # getpath tests
    # -------------------------------------------------

    def test_getpath_exists(self):
        self.assertTrue(callable(getpath))

    def test_getpath_basic(self):
        def getpath_wrapper(vin):
            return getpath(vin["path"], vin.get("store"))
        runset(spec["getpath"]["basic"], getpath_wrapper)

    def test_getpath_current(self):
        def getpath_wrapper(vin):
            return getpath(vin["path"], vin.get("store"), vin.get("current"))
        runset(spec["getpath"]["current"], getpath_wrapper)

    def test_getpath_state(self):
        def handler_fn(state, val, _current, _ref, _store):
            out = f"{state['step']}:{val}"
            state["step"] += 1
            return out

        def getpath_wrapper(vin):
            state = {
                "handler": handler_fn,
                "step": 0,
                "mode": "val",
                "full": False,
                "keyI": 0,
                "keys": ["$TOP"],
                "key": "$TOP",
                "val": "",
                "parent": {},
                "path": ["$TOP"],
                "nodes": [{}],
                "base": "$TOP",
                "errs": [],
            }
            return getpath(vin["path"], vin.get("store"), vin.get("current"), state)

        runset(spec["getpath"]["state"], getpath_wrapper)

    # -------------------------------------------------
    # inject tests
    # -------------------------------------------------

    def test_inject_exists(self):
        self.assertTrue(callable(inject))

    def test_inject_basic(self):
        test_data = self.clone(spec["inject"]["basic"])
        self.assertEqual(
            inject(test_data["in"]["val"], test_data["in"]["store"]),
            test_data["out"]
        )

    def test_inject_string(self):
        def inject_wrapper(vin):
            return inject(vin.get("val"), vin.get("store"), nullModifier, vin.get("current"))
        runset(spec["inject"]["string"], inject_wrapper)

    def test_inject_deep(self):
        runset(spec["inject"]["deep"], lambda vin: inject(vin.get("val"), vin.get("store")))

    # -------------------------------------------------
    # transform tests
    # -------------------------------------------------

    def test_transform_exists(self):
        self.assertTrue(callable(transform))

    def test_transform_basic(self):
        test_data = self.clone(spec["transform"]["basic"])
        self.assertEqual(
            transform(
                test_data["in"]["data"],
                test_data["in"]["spec"],
                test_data["in"]["store"]
            ),
            test_data["out"]
        )

    def test_transform_paths(self):
        def transform_wrapper(vin):
            return transform(vin.get("data"), vin.get("spec"), vin.get("store"))
        runset(spec["transform"]["paths"], transform_wrapper)

    def test_transform_cmds(self):
        def transform_wrapper(vin):
            return transform(vin.get("data"), vin.get("spec"), vin.get("store"))
        runset(spec["transform"]["cmds"], transform_wrapper)

    def test_transform_each(self):
        def transform_wrapper(vin):
            return transform(vin.get("data"), vin.get("spec"), vin.get("store"))
        runset(spec["transform"]["each"], transform_wrapper)

    def test_transform_pack(self):
        def transform_wrapper(vin):
            return transform(vin.get("data"), vin.get("spec"), vin.get("store"))
        runset(spec["transform"]["pack"], transform_wrapper)

    def test_transform_modify(self):
        def modifier(val, key, parent):
            if key is not None and parent is not None and isinstance(val, str):
                parent[key] = '@' + val

        def transform_wrapper(vin):
            return transform(vin.get("data"), vin.get("spec"), vin.get("store"), modifier)
        runset(spec["transform"]["modify"], transform_wrapper)

    def test_transform_extra(self):
        """
        Equivalent to JS:
            transform({ a: 1 }, { x: '`a`', b: '`$COPY`', c: '`$UPPER`' }, { b: 2, $UPPER: (...) => {...} })
        """
        from my_struct_lib import getprop  # or getprop

        def upper_func(state):
            path = state["path"]
            this_key = path[-1] if path else None
            return str(this_key).upper()

        data = {"a": 1}
        spc = {"x": "`a`", "b": "`$COPY`", "c": "`$UPPER`"}
        store = {
            "b": 2,
            "$UPPER": upper_func
        }

        self.assertEqual(
            transform(data, spc, store),
            {"x": 1, "b": 2, "c": "C"}
        )

    def test_transform_funcval(self):
        def f0():
            return 99

        self.assertEqual(transform({}, {"x": 1}), {"x": 1})
        self.assertEqual(transform({}, {"x": f0}), {"x": f0})
        self.assertEqual(transform({"a": 1}, {"x": "`a`"}), {"x": 1})
        self.assertEqual(transform({"f0": f0}, {"x": "`f0`"}), {"x": f0})

    # -------------------------------------------------
    # validate tests
    # -------------------------------------------------

    def test_validate_exists(self):
        self.assertTrue(callable(validate))

    def test_validate_basic(self):
        def validate_wrapper(vin):
            return validate(vin.get("data"), vin.get("spec"))
        runset(spec["validate"]["basic"], validate_wrapper)

    def test_validate_node(self):
        def validate_wrapper(vin):
            return validate(vin.get("data"), vin.get("spec"))
        runset(spec["validate"]["node"], validate_wrapper)

    def test_validate_custom(self):
        """
        In JS:
          const extra = { $INTEGER: (state, _val, current) => { ... } };
          validate({ a: 1 }, { a: '`$INTEGER`' }, extra, errs)
        """
        from my_struct_lib import getprop  # or getprop

        errs = []

        def integer_check(state, _val, current):
            key = state["key"]
            out = current.get(key)
            if not isinstance(out, int):
                state["errs"].append(
                    f"Not an integer at {'.'.join(state['path'][1:])}: {out}"
                )
            return out

        extra = {
            "$INTEGER": integer_check
        }

        validate({"a": 1}, {"a": "`$INTEGER`"}, extra, errs)
        self.assertEqual(len(errs), 0)

        validate({"a": "A"}, {"a": "`$INTEGER`"}, extra, errs)
        self.assertEqual(errs, ["Not an integer at a: A"])


# If you want to run this file directly, add:
if __name__ == "__main__":
    unittest.main()



    
