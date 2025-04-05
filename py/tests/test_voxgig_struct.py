
# RUN: python -m unittest discover -s tests
# RUN-SOME: python -m unittest discover -s tests -k getpath

import unittest

from runner import (
    makeRunner,
    nullModifier,
    NULLMARK,
)

from sdk import SDK

from voxgig_struct import InjectState


sdk_client = SDK.test()
runner = makeRunner('../../build/test/test.json', sdk_client)
runparts = runner('struct')

spec = runparts["spec"]
runset = runparts["runset"]
runsetflags = runparts["runsetflags"]
client = runparts["client"]

# Get all the struct utilities from the client
struct_utils = client.utility().struct
clone = struct_utils.clone
escre = struct_utils.escre
escurl = struct_utils.escurl
getpath = struct_utils.getpath
getprop = struct_utils.getprop
haskey = struct_utils.haskey
inject = struct_utils.inject
isempty = struct_utils.isempty
isfunc = struct_utils.isfunc
iskey = struct_utils.iskey
islist = struct_utils.islist
ismap = struct_utils.ismap
isnode = struct_utils.isnode
items = struct_utils.items
joinurl = struct_utils.joinurl
keysof = struct_utils.keysof
merge = struct_utils.merge
pathify = struct_utils.pathify
setprop = struct_utils.setprop
stringify = struct_utils.stringify
strkey = struct_utils.strkey
transform = struct_utils.transform
typify = struct_utils.typify
validate = struct_utils.validate
walk = struct_utils.walk

minorSpec     = spec["minor"]
walkSpec      = spec["walk"]
mergeSpec     = spec["merge"]
getpathSpec   = spec["getpath"]
injectSpec    = spec["inject"]
transformSpec = spec["transform"]
validateSpec  = spec["validate"]

        
class TestStruct(unittest.TestCase):

    # minor tests
    # ===========

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
        self.assertTrue(callable(pathify))

        self.assertTrue(callable(setprop))
        self.assertTrue(callable(stringify))
        self.assertTrue(callable(strkey))
        self.assertTrue(callable(typify))


    def test_minor_isnode(self):
        runset(minorSpec["isnode"], isnode)

        
    def test_minor_ismap(self):
        runset(minorSpec["ismap"], ismap)

        
    def test_minor_islist(self):
        runset(minorSpec["islist"], islist)

        
    def test_minor_iskey(self):
        runsetflags(minorSpec["iskey"], {"null": False}, iskey)

        
    def test_minor_strkey(self):
        runsetflags(minorSpec["strkey"], {"null": False}, strkey)

        
    def test_minor_isempty(self):
        runsetflags(minorSpec["isempty"], {"null": False}, isempty)

        
    def test_minor_isfunc(self):
        runset(minorSpec["isfunc"], isfunc)
        def f0():
            return None
        self.assertTrue(isfunc(f0))
        self.assertTrue(isfunc(lambda: None))

        
    def test_minor_clone(self):
        runsetflags(minorSpec["clone"], {"null": False}, clone)
        def f0():
            return None
        self.assertEqual({"a":f0}, clone({"a":f0}))

        
    def test_minor_escre(self):
        runset(minorSpec["escre"], escre)

        
    def test_minor_escurl(self):
        runset(minorSpec["escurl"], escurl)

        
    def test_minor_stringify(self):
        runset(minorSpec["stringify"],
               lambda vin: stringify("null" if NULLMARK == vin.get('val') else
                                     vin.get('val'), vin.get('max')))

        
    def test_minor_pathify(self):
        def pathify_wrapper(vin=None):
            path = vin.get("path")
            path = None if NULLMARK == path else path 
            pathstr = pathify(path, vin.get("from")).replace("__NULL__.","")
            pathstr = pathstr.replace(">", ":null") if NULLMARK == vin.path else pathstr
            return pathstr
            

    def test_minor_items(self):
        runset(minorSpec["items"], items)


    def test_minor_getprop(self):
        def getprop_wrapper(vin):
            if vin.get("alt") is None:
                return getprop(vin.get("val"), vin.get("key"))
            else:
                return getprop(vin.get("val"), vin.get("key"), vin.get("alt"))
        runset(minorSpec["getprop"], getprop_wrapper)

        
    def test_minor_setprop(self):
        def setprop_wrapper(vin):
            return setprop(vin.get("parent"), vin.get("key"), vin.get("val"))
        runset(minorSpec["setprop"], setprop_wrapper)

        
    def test_minor_haskey(self):
        runset(minorSpec["haskey"], haskey)

        
    def test_minor_keysof(self):
        runset(minorSpec["keysof"], keysof)

        
    def test_minor_joinurl(self):
        runsetflags(minorSpec["joinurl"], {"null": False}, joinurl)


    def test_minor_typify(self):
        runsetflags(minorSpec["typify"], {"null": False}, typify)
        

    # walk tests
    # ==========

    def test_walk_exists(self):
        self.assertTrue(callable(walk))

    def test_walk_basic(self):
        def walkpath(_key, val, _parent, path):
            if isinstance(val, str):
                return val + '~' + '.'.join(str(p) for p in path)
            return val

        def walk_wrapper(vin=None):
            return walk(vin, walkpath)

        runset(walkSpec["basic"], walk_wrapper)

        
    # merge tests
    # ===========

    def test_merge_exists(self):
        self.assertTrue(callable(merge))

    def test_merge_basic(self):
        test_data = clone(spec["merge"]["basic"])
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
            return getpath(vin.get("path"), vin.get("store"))
        runset(spec["getpath"]["basic"], getpath_wrapper)

    def test_getpath_current(self):
        def getpath_wrapper(vin):
            return getpath(vin["path"], vin.get("store"), vin.get("current"))
        runset(spec["getpath"]["current"], getpath_wrapper)

    def test_getpath_state(self):
        def handler_fn(state, val, _current=None, _ref=None, _store=None):
            out = f"{state.meta['step']}:{val}"
            state.meta["step"] = state.meta["step"]+1 
            return out

        state = InjectState(
                meta = {"step":0},
                handler = handler_fn,
                mode = "val",
                full = False,
                keyI = 0,
                keys = ["$TOP"],
                key = "$TOP",
                val = "",
                parent = {},
                path = ["$TOP"],
                nodes = [{}],
                base = "$TOP",
                errs = [],
            )

        runset(spec["getpath"]["state"],
               lambda vin: getpath(vin.get("path"), vin.get("store"), vin.get("current"), state))

    # -------------------------------------------------
    # inject tests
    # -------------------------------------------------

    def test_inject_exists(self):
        self.assertTrue(callable(inject))

    def test_inject_basic(self):
        test_data = clone(spec["inject"]["basic"])
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
        test_data = clone(spec["transform"]["basic"])
        test_data_in = test_data.get("in")
        self.assertEqual(
            transform(
                test_data_in.get("data"),
                test_data_in.get("spec"),
                test_data_in.get("store")
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
        def modifier(val, key, parent, _state, _current, _store):
            if isinstance(val, str):
                setprop(parent, key, '@' + val)

        runset(spec["transform"]["modify"],
               lambda vin: transform(vin.get("data"), vin.get("spec"), vin.get("store"), modifier))

    def test_transform_extra(self):
        """
        Equivalent to JS:
            transform({ a: 1 }, { x: '`a`', b: '`$COPY`', c: '`$UPPER`' }, { b: 2, $UPPER: (...) => {...} })
        """
        def upper_func(state, val, current, store):
            path = state.path
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

        
    def test_validate_invalid(self):
        runset(spec["validate"]["node"], lambda vin: validate(vin.get("data"), vin.get("spec")))

        
    def test_validate_custom(self):
        errs = []

        def integer_check(state, _val, current, store):
            key = state.key
            out = current.get(key)
            if not isinstance(out, int):
                state.errs.append(
                    f"Not an integer at {'.'.join(state.path[1:])}: {out}"
                )
            return out

        extra = {
            "$INTEGER": integer_check
        }

        validate({"a": 1}, {"a": "`$INTEGER`"}, extra, errs)
        self.assertEqual(len(errs), 0)

        validate({"a": "A"}, {"a": "`$INTEGER`"}, extra, errs)
        self.assertEqual(errs, ["Not an integer at a: A"])


runparts_client = runner('check')

spec_client = runparts_client["spec"]
runset_client = runparts_client["runset"]
subject_client = runparts_client["subject"]

        
class TestClient(unittest.TestCase):

    def test_client_check_basic(self):
        runset_client(spec_client["basic"], subject_client)

        
# If you want to run this file directly, add:
if __name__ == "__main__":
    unittest.main()
