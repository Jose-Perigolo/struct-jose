# Copyright (c) 2025 Voxgig Ltd. MIT LICENSE.
#
# Voxgig Struct
# =============
#
# Utility functions to manipulate in-memory JSON-like data structures.
# This Python version follows the same design and logic as the original
# TypeScript version, using "by-example" transformation of data.
#
# - isnode, ismap, islist, iskey: identify value kinds
# - clone: create a copy of a JSON-like data structure
# - items: list entries of a map or list as [key, value] pairs
# - getprop: safely get a property value by key
# - setprop: safely set a property value by key
# - getpath: get the value at a key path deep inside an object
# - merge: merge multiple nodes, overriding values in earlier nodes
# - walk: walk a node tree, applying a function at each node and leaf
# - inject: inject values from a data store into a new data structure
# - transform: transform a data structure to an example structure


from typing import *
from datetime import datetime
import urllib.parse
import json
import re
# from pprint import pformat


# Mode value for inject step.
S_MKEYPRE =  'key:pre'
S_MKEYPOST =  'key:post'
S_MVAL =  'val'
S_MKEY =  'key',

# Special keys.
S_DKEY =  '`$KEY`'
S_DTOP =  '$TOP'
S_DERRS =  '$ERRS'
S_DMETA =  '`$META`'

# General strings.
S_array =  'array'
S_base =  'base'
S_boolean =  'boolean'
S_function =  'function'
S_number =  'number'
S_object =  'object'
S_string =  'string'
S_null =  'null'
S_key =  'key'
S_parent =  'parent'
S_MT =  ''
S_BT =  '`'
S_DS =  '$'
S_DT =  '.'
S_KEY =  'KEY'


# The standard undefined value for this language.
UNDEF = None


class InjectState:
    """
    Injection state used for recursive injection into JSON-like data structures.
    """
    def __init__(
        self,
        mode: str,                    # Injection mode: key:pre, val, key:post.
        full: bool,                   # Transform escape was full key name.
        keyI: int,                    # Index of parent key in list of parent keys.
        keys: List[str],              # List of parent keys.
        key: str,                     # Current parent key.
        val: Any,                     # Current child value.
        parent: Any,                  # Current parent (in transform specification).
        path: List[str],              # Path to current node.
        nodes: List[Any],             # Stack of ancestor nodes
        handler: Any,                 # Custom handler for injections.
        errs: List[Any] = None,       # Error collector.
        meta: Dict[str, Any] = None,  # Custom meta data.
        base: Optional[str] = None,   # Base key for data in store, if any. 
        modify: Optional[Any] = None  # Modify injection output.
    ) -> None:
        self.mode = mode
        self.full = full
        self.keyI = keyI
        self.keys = keys
        self.key = key
        self.val = val
        self.parent = parent
        self.path = path
        self.nodes = nodes
        self.handler = handler
        self.errs = errs
        self.meta = meta
        self.base = base
        self.modify = modify


def isnode(val: Any = UNDEF) -> bool:
    "Value is a node - defined, and a map (hash) or list (array)."
    return isinstance(val, (dict, list))


def ismap(val: Any = UNDEF) -> bool:
    "Value is a defined map (hash) with string keys."
    return isinstance(val, dict)


def islist(val: Any = UNDEF) -> bool:
    "Value is a defined list (array) with integer keys (indexes)."
    return isinstance(val, list)


def iskey(key: Any = UNDEF) -> bool:
    "Value is a defined string (non-empty) or integer key."
    if isinstance(key, str):
        return len(key) > 0
    # Exclude bool (which is a subclass of int)
    if isinstance(key, bool):
        return False
    if isinstance(key, int):
        return True
    return False


def strkey(key: Any = UNDEF) -> str:
    if UNDEF == key:
        return S_MT

    if isinstance(key, str):
        return key

    if isinstance(key, bool):
        return S_MT

    if isinstance(key, int):
        return str(key)

    if isinstance(key, float):
        return str(int(key))

    return S_MT


def isempty(val: Any = UNDEF) -> bool:
    "Check for an 'empty' value - None, empty string, array, object."
    if UNDEF == val:
        return True
    
    if val == S_MT:
        return True
    
    if islist(val) and len(val) == 0:
        return True
    
    if ismap(val) and len(val) == 0:
        return True
    
    return False    


def isfunc(val: Any = UNDEF) -> bool:
    "Value is a function."
    return callable(val)


def typify(value: Any = UNDEF) -> str:
    if value is UNDEF:
        return S_null
    if isinstance(value, bool):
        return S_boolean
    if isinstance(value, (int, float)):
        return S_number
    if isinstance(value, str):
        return S_string
    if callable(value):
        return S_function
    if isinstance(value, list):
        return S_array
    return S_object


def getprop(val: Any = UNDEF, key: Any = UNDEF, alt: Any = UNDEF) -> Any:
    """
    Safely get a property of a node. Undefined arguments return undefined.
    If the key is not found, return the alternative value.
    """
    if UNDEF == val:
        return alt

    if UNDEF == key:
        return alt

    out = alt
    
    if ismap(val):
        out = val.get(str(key), alt)
    
    elif islist(val):
        try:
            key = int(key)
        except:
            return alt

        if 0 <= key < len(val):
            return val[key]
        else:
            return alt

    if UNDEF == out:
        out = alt
        
    return out


def keysof(val: Any = UNDEF) -> list[str]:
    "Sorted keys of a map, or indexes of a list."
    if not isnode(val):
        return []
    elif ismap(val):
        return sorted(val.keys())
    else:
        return [str(x) for x in list(range(len(val)))]


def haskey(val: Any = UNDEF, key: Any = UNDEF) -> bool:
    "Value of property with name key in node val is defined."
    return UNDEF != getprop(val, key)

    
def items(val: Any = UNDEF):
    "List the keys of a map or list as an array of [key, value] tuples."
    if ismap(val):
        return [(k, val[k]) for k in keysof(val)]
    elif islist(val):
        return [(k, val[k]) for k in list(range(len(val)))]
    else:
        return []
    

def escre(s: Any):
    "Escape regular expression."
    if UNDEF == s:
        s = ""
    pattern = r'([.*+?^${}()|\[\]\\])'
    return re.sub(pattern, r'\\\1', s)


def escurl(s: Any):
    "Escape URLs."
    if UNDEF == s:
        s = S_MT
    return urllib.parse.quote(s, safe="")


def joinurl(sarr):
    "Concatenate url part strings, merging forward slashes as needed."
    sarr = [s for s in sarr if s is not None and s != ""]

    transformed = []
    for i, s in enumerate(sarr):
        s = re.sub(r'([^/])/{2,}', r'\1/', s)

        if i == 0:
            s = re.sub(r'/+$', '', s)
        else:
            s = re.sub(r'^/+', '', s)
            s = re.sub(r'/+$', '', s)

        transformed.append(s)

    transformed = [s for s in transformed if s != ""]

    return "/".join(transformed)


def stringify(val: Any, maxlen: int = UNDEF):
    "Safely stringify a value for printing (NOT JSON!)."
    if UNDEF == val:
        return S_MT

    json_str = S_MT

    try:
        json_str = json.dumps(val, separators=(',', ':'))
    except Exception:
        json_str = "S"+str(val)
    
    json_str = json_str.replace('"', '')

    if maxlen is not UNDEF:
        json_len = len(json_str)
        json_str = json_str[:maxlen]
        
        if 3 < maxlen < json_len:
            json_str = json_str[:maxlen - 3] + '...'
    
    return json_str


def pathify(val: Any = UNDEF, from_index: int = UNDEF) -> str:
    pathstr = UNDEF
    path = UNDEF
    
    # Convert input to a path array
    if islist(val):
        path = val
    elif isinstance(val, str):
        path = [val]
    elif isinstance(val, (int, float)):
        path = [str(int(val))]
    
    # Determine starting index
    start = 0
    if from_index is not UNDEF:
        start = from_index if -1 < from_index else 0

    if UNDEF != path and 0 <= start:
        if len(path) <= start:
            start = len(path)
            
        path = path[start:]
        
        if 0 == len(path):
            pathstr = "<root>"
        else:
            path = [strkey(part) for part in path if iskey(part)]
            pathstr = S_DT.join(path)
    
    # Handle the case where we couldn't create a path
    if UNDEF == pathstr:
        pathstr = f"<unknown-path:{S_MT if UNDEF == val else S_CN+stringify(val, 47)}>"

    return pathstr


def clone(val: Any = UNDEF):
    """
    Clone a JSON-like data structure.
    NOTE: function value references are copied, *not* cloned.
    """
    if UNDEF == val:
        return UNDEF

    refs = []

    def replacer(item):
        if callable(item):
            refs.append(item)
            return f'`$FUNCTION:{len(refs) - 1}`'
        elif isinstance(item, dict):
            return {k: replacer(v) for k, v in item.items()}
        elif isinstance(item, (list, tuple)):
            return [replacer(elem) for elem in item]
        else:
            return item

    transformed = replacer(val)

    json_str = json.dumps(transformed, separators=(',', ':'))

    def reviver(item):
        if isinstance(item, str):
            match = re.match(r'^`\$FUNCTION:(\d+)`$', item)
            if match:
                index = int(match.group(1))
                return refs[index]
            else:
                return item
        elif isinstance(item, list):
            return [reviver(elem) for elem in item]
        elif isinstance(item, dict):
            return {k: reviver(v) for k, v in item.items()}
        else:
            return item

    parsed = json.loads(json_str)

    return reviver(parsed)


def setprop(parent: Any, key: Any, val: Any):
    """
    Safely set a property on a dictionary or list.
    - If `val` is UNDEF, delete the key from parent.
    - For lists, negative key -> prepend.
    - For lists, key > len(list) -> append.
    - For lists, UNDEF value -> remove and shift down.
    """
    if not iskey(key):
        return parent

    if ismap(parent):
        key = str(key)
        if UNDEF == val:
            parent.pop(key, UNDEF)
        else:
            parent[key] = val

    elif islist(parent):
        # Convert key to int
        try:
            key_i = int(key)
        except ValueError:
            return parent

        # Delete an element
        if UNDEF == val:
            if 0 <= key_i < len(parent):
                # Shift items left
                for pI in range(key_i, len(parent) - 1):
                    parent[pI] = parent[pI + 1]
                parent.pop()
        else:
            # Non-empty insert
            if key_i >= 0:
                if key_i >= len(parent):
                    # Append if out of range
                    parent.append(val)
                else:
                    parent[key_i] = val
            else:
                # Prepend if negative
                parent.insert(0, val)

    return parent


def walk(
        # These arguments are the public interface.
        val: Any,
        apply: Any,

        # These areguments are used for recursive state.
        key: Any = UNDEF,
        parent: Any = UNDEF,
        path: Any = UNDEF
):
    """
    Walk a data structure depth-first, calling apply at each node (after children).
    """
    if path is UNDEF:
        path = []
    if isnode(val):
        for (ckey, child) in items(val):
            setprop(val, ckey, walk(child, apply, ckey, val, path + [str(ckey)]))

    # Nodes are applied *after* their children.
    # For the root node, key and parent will be UNDEF.
    return apply(key, val, parent, path)


def merge(objs: List[Any] = None) -> Any:
    """
    Merge a list of values into each other. Later values have
    precedence.  Nodes override scalars. Node kinds (list or map)
    override each other, and do *not* merge.  The first element is
    modified.
    """

    # Handle edge cases.
    if not islist(objs):
        return objs
    if len(objs) == 0:
        return UNDEF
    if len(objs) == 1:
        return objs[0]
        
    # Merge a list of values.
    out = getprop(objs, 0, {})

    for i in range(1, len(objs)):
        obj = objs[i]

        if not isnode(obj):
            out = obj

        else:
            # Nodes win, also over nodes of a different kind
            if (not isnode(out) or (ismap(obj) and islist(out)) or (islist(obj) and ismap(out))):
                out = obj
            else:
                cur = [out]
                cI = 0
                
                def merger(key, val, parent, path):
                    if UNDEF == key:
                        return val

                    # Get the curent value at the current path in obj.
                    # NOTE: this is not exactly efficient, and should be optimised.
                    lenpath = len(path)
                    cI = lenpath - 1

                    # Ensure the cur list has at least cI elements
                    cur.extend([UNDEF]*(1+cI-len(cur)))
                        
                    if UNDEF == cur[cI]:
                        cur[cI] = getpath(path[:-1], out)

                        # Create node if needed
                        if not isnode(cur[cI]):
                            cur[cI] = [] if islist(parent) else {}

                    # Node child is just ahead of us on the stack, since
                    # `walk` traverses leaves before nodes.
                    if isnode(val) and not isempty(val):
                        cur.extend([UNDEF] * (2+cI+len(cur)))
                
                        setprop(cur[cI], key, cur[cI + 1])
                        cur[cI + 1] = UNDEF

                    else:
                        # Scalar child.
                        setprop(cur[cI], key, val)

                    return val

                walk(obj, merger)

    return out


def getpath(path, store, current=UNDEF, state=UNDEF):
    if isinstance(path, str):
        parts = path.split(S_DT)
    elif islist(path):
        parts = path[:]
    else:
        return UNDEF
        
    root = store
    val = store
    base = UNDEF if UNDEF == state else state.base
    
    # If path or store is UNDEF or empty, return store or store[state.base].
    if path is UNDEF or store is UNDEF or (1==len(parts) and parts[0] == S_MT):
        val = getprop(store, base, store)

    elif len(parts) > 0:
        pI = 0
            
        # Relative path uses `current` argument
        if parts[0] == S_MT:
            if len(parts) == 1:
                return getprop(store, base, store)
            pI = 1
            root = current

        part = parts[pI] if pI < len(parts) else UNDEF
        first = getprop(root, part)

        val = first
        if UNDEF == first and 0 == pI: 
            val = getprop(getprop(root, base), part)

        pI += 1
        
        while pI < len(parts) and UNDEF != val:
            part = parts[pI]
            val = getprop(val, part)
            pI += 1
            
    # If a custom handler is specified, apply it.
    if UNDEF != state and isfunc(state.handler):
        ref = pathify(path)
        val = state.handler(state, val, current, ref, store)

    return val


def inject(val, store, modify=UNDEF, current=UNDEF, state=UNDEF):
    """
    Inject values from `store` into `val` recursively, respecting backtick syntax.
    `modify` is an optional function(key, val, parent, state, current, store)
    that is called after each injection.
    """
    if state is UNDEF:
        # Create a root-level state
        parent = {S_DTOP: val}
        state = InjectState(
            mode = S_MVAL,
            full = False,
            keyI = 0,
            keys = [S_DTOP],
            key = S_DTOP,
            val = val,
            parent = parent,
            path = [S_DTOP],
            nodes = [parent],
            handler = _injecthandler,
            base = S_DTOP,
            modify = modify,
            meta = {},
            errs = getprop(store, S_DERRS, [])
        )

    # For local paths, we keep track of the current node in `current`.
    if current is UNDEF:
        current = {S_DTOP: store}
    else:
        parentkey = getprop(state.path, len(state.path)-2)
        current = current if UNDEF == parentkey else getprop(current, parentkey)

    # Descend into node
    if isnode(val):
        # Sort keys (transforms with `$...` go last).
        if ismap(val):
            normal_keys = [k for k in val.keys() if S_DS not in k]
            transform_keys = [k for k in val.keys() if S_DS in k]
            transform_keys.sort()
            nodekeys = normal_keys + transform_keys
        else:
            nodekeys = list(range(len(val)))

        nkI = 0
        while nkI < len(nodekeys):
            nodekey = str(nodekeys[nkI])

            childpath = state.path + [nodekey]
            childnodes = state.nodes + [val]
            childval = getprop(val, nodekey)

            # Phase 1: key-pre
            childstate = InjectState(
                mode = S_MKEYPRE,
                full = False,
                keyI = nkI,
                keys = nodekeys,
                key = nodekey,
                val = childval,
                parent = val,
                path = childpath,
                nodes = childnodes,
                handler = _injecthandler,
                base = state.base,
                errs = state.errs,
                meta = state.meta,
            )

            prekey = _injectstr(str(nodekey), store, current, childstate)

            # The injection may modify child processing.
            nkI = childstate.keyI

            if prekey is not UNDEF:
                # Phase 2: val
                child_val = getprop(val, prekey)
                childstate.mode = S_MVAL

                # Perform the val mode injection on the child value.
                # NOTE: return value is not used.
                inject(child_val, store, modify, current, childstate)

                # The injection may modify child processing.
                nkI = childstate.keyI
                
                # Phase 3: key-post
                childstate.mode = S_MKEYPOST
                _injectstr(nodekey, store, current, childstate)

                # The injection may modify child processing.
                nkI = childstate.keyI

            nkI = nkI+1
            
    elif isinstance(val, str):
        state.mode = S_MVAL
        val = _injectstr(val, store, current, state)
        setprop(state.parent, state.key, val)

    # Custom modification
    if UNDEF != modify:
        mkey = state.key
        mparent = state.parent
        mval = getprop(mparent, mkey)
        modify(
            mval,
            mkey,
            mparent,
            state,
            current,
            store
        )

    return getprop(state.parent, S_DTOP)


# Default injection handler (used by `inject`).
def _injecthandler(state, val, current, ref, store):
    out = val
    iscmd = isfunc(val) and (UNDEF == ref or (isinstance(ref, str) and ref.startswith(S_DS)))

    # Only call val function if it is a special command ($NAME format).
    if iscmd:
        out = val(state, val, current, store)

    # Update parent with value. Ensures references remain in node tree.
    else:
        if state.mode == S_MVAL and state.full:
            setprop(state.parent, state.key, val)

    return out


# -----------------------------------------------------------------------------
# Transform helper functions (these are injection handlers).


def transform_DELETE(state, val, current, store):
    """
    Injection handler to delete a key from a map/list.
    """
    setprop(state.parent, state.key, UNDEF)
    return UNDEF


def transform_COPY(state, val, current, store):
    """
    Injection handler to copy a value from source data under the same key.
    """
    mode = state.mode
    key = state.key
    parent = state.parent

    out = UNDEF
    if mode.startswith('key'):
        out = key
    else:
        out = getprop(current, key)
        setprop(parent, key, out)

    return out


def transform_KEY(state, val, current, store):
    """
    Injection handler to inject the parent's key (or a specified key).
    """
    mode = state.mode
    path = state.path
    parent = state.parent

    if mode != S_MVAL:
        return UNDEF

    keyspec = getprop(parent, S_DKEY)
    if keyspec is not UNDEF:
        setprop(parent, S_DKEY, UNDEF)
        return getprop(current, keyspec)

    meta = getprop(parent, S_DMETA)
    return getprop(meta, S_KEY, getprop(path, len(path) - 2))


def transform_META(state, val, current, store):
    """
    Injection handler that removes the `'$META'` key (after capturing if needed).
    """
    parent = state.parent
    setprop(parent, S_DMETA, UNDEF)
    return UNDEF


def transform_MERGE(state, val, current, store):
    """
    Injection handler to merge a list of objects onto the parent object.
    If the transform data is an empty string, merge the top-level store.
    """
    mode = state.mode
    key = state.key
    parent = state.parent

    if mode == S_MKEYPRE:
        return key

    if mode == S_MKEYPOST:
        args = getprop(parent, key)
        if args == S_MT:
            args = [store[S_DTOP]]
        elif not islist(args):
            args = [args]

        setprop(parent, key, UNDEF)

        # Merge them on top of parent
        mergelist = [parent] + args + [clone(parent)]
        merge(mergelist)
        return key

    return UNDEF


def transform_EACH(state, val, current, store):
    """
    Injection handler to convert the current node into a list by iterating over
    a source node. Format: ['`$EACH`','`source-path`', child-template]
    """
    mode = state.mode
    keys_ = state.keys
    path = state.path
    parent = state.parent
    nodes_ = state.nodes

    if keys_ is not UNDEF:
        # Only keep the transform item (first). Avoid further spurious keys.
        keys_[:] = keys_[:1]

    if mode != S_MVAL or path is UNDEF or nodes_ is UNDEF:
        return UNDEF

    # parent here is the array [ '$EACH', 'source-path', {... child ...} ]
    srcpath = parent[1] if len(parent) > 1 else UNDEF
    child_template = clone(parent[2]) if len(parent) > 2 else UNDEF

    # source data
    src = getpath(srcpath, store, current, state)
    
    # Create parallel data structures:
    # source entries :: child templates
    tcurrent = []
    tval = []

    tkey = path[-2] if len(path) >= 2 else UNDEF
    target = nodes_[-2] if len(nodes_) >= 2 else nodes_[-1]

    if isnode(src):
        if islist(src):
            tval = [clone(child_template) for _ in src]
        else:
            # Convert dict to a list of child templates
            tval = []
            for k, v in src.items():
                # Keep key in meta for usage by `$KEY`
                copy_child = clone(child_template)
                copy_child[S_DMETA] = {S_KEY: k}
                tval.append(copy_child)
        tcurrent = list(src.values()) if ismap(src) else src

    # Build parallel "current"
    tcurrent = {S_DTOP: tcurrent}

    # Inject to build substructure
    tval = inject(tval, store, state.modify, tcurrent)

    setprop(target, tkey, tval)
    return tval[0] if tval else UNDEF


def transform_PACK(state, val, current, store):
    """
    Injection handler to convert the current node into a dict by "packing"
    a source list or dict. Format: { '`$PACK`': [ 'source-path', {... child ...} ] }
    """
    mode = state.mode
    key = state.key
    path = state.path
    parent = state.parent
    nodes_ = state.nodes

    if (mode != S_MKEYPRE or not isinstance(key, str) or path is UNDEF or nodes_ is UNDEF):
        return UNDEF

    args = parent[key]
    if not args or not islist(args):
        return UNDEF

    srcpath = args[0] if len(args) > 0 else UNDEF
    child_template = clone(args[1]) if len(args) > 1 else UNDEF

    tkey = path[-2] if len(path) >= 2 else UNDEF
    target = nodes_[-2] if len(nodes_) >= 2 else nodes_[-1]

    # source data
    src = getpath(srcpath, store, current, state)

    # Convert dict -> list with meta keys or pass through if already list
    if islist(src):
        pass
    elif ismap(src):
        new_src = []
        for k, v in src.items():
            if ismap(v):
                # Keep KEY meta
                v_copy = clone(v)
                v_copy[S_DMETA] = {S_KEY: k}
                new_src.append(v_copy)
        src = new_src
    else:
        return UNDEF

    if src is UNDEF:
        return UNDEF

    # Child key from template
    childkey = getprop(child_template, S_DKEY)
    # Remove the transform key from template
    setprop(child_template, S_DKEY, UNDEF)

    # Build a new dict in parallel with the source
    tval = {}
    for elem in src:
        if childkey is not UNDEF:
            kn = getprop(elem, childkey)
        else:
            # fallback
            kn = getprop(elem, S_KEY)
        if kn is UNDEF:
            # Possibly from meta
            meta = getprop(elem, S_DMETA, {})
            kn = getprop(meta, S_KEY, UNDEF)

        if kn is not UNDEF:
            tval[kn] = clone(child_template)
            # Transfer meta if present
            tmeta = getprop(elem, S_DMETA)
            if tmeta is not UNDEF:
                tval[kn][S_DMETA] = tmeta

    # Build parallel "current"
    tcurrent = {}
    for elem in src:
        if childkey is not UNDEF:
            kn = getprop(elem, childkey)
        else:
            kn = getprop(elem, S_KEY)
        if kn is UNDEF:
            meta = getprop(elem, S_DMETA, {})
            kn = getprop(meta, S_KEY, UNDEF)
        if kn is not UNDEF:
            tcurrent[kn] = elem

    tcurrent = {S_DTOP: tcurrent}

    # Inject children
    tval = inject(tval, store, state.modify, tcurrent)
    setprop(target, tkey, tval)

    # Drop the transform
    return UNDEF


# Transform data using spec.
# Only operates on static JSON-like data.
# Arrays are treated as if they are objects with indices as keys.
def transform(
        data,
        spec,
        extra=UNDEF,
        modify=UNDEF
):
    extra_transforms = {}
    extra_data = {}

    if UNDEF != extra:
        for k, v in items(extra):
            if isinstance(k, str) and k.startswith(S_DS):
                extra_transforms[k] = v
            else:
                extra_data[k] = v

    # Combine extra data with user data
    data_clone = merge([clone(extra_data), clone(data)])

    # Top-level store used by inject
    store = {
        S_DTOP: data_clone,
        
        '$BT': lambda state, val, current, store: S_BT,
        '$DS': lambda state, val, current, store: S_DS,
        '$WHEN': lambda state, val, current, store: datetime.utcnow().isoformat(),

        
        '$DELETE': transform_DELETE,
        '$COPY': transform_COPY,
        '$KEY': transform_KEY,
        '$META': transform_META,
        '$MERGE': transform_MERGE,
        '$EACH': transform_EACH,
        '$PACK': transform_PACK,

        **extra_transforms,
    }

    out = inject(spec, store, modify, store)
    return out


def validate_STRING(state, _val, current, store):
    """
    A required string value. Rejects empty strings.
    """
    out = getprop(current, state.key)
    t = typify(out)

    if t == S_string:
        if out == S_MT:
            state.errs.append(f"Empty string at {pathify(state.path,1)}")
            return UNDEF
        else:
            return out
    else:
        state.errs.append(_invalidTypeMsg(state.path, S_string, t, out))
        return UNDEF


def validate_NUMBER(state, _val, current, store):
    """
    A required number value (int or float).
    """
    out = getprop(current, state.key)
    t = typify(out)

    if t != S_number:
        state.errs.append(_invalidTypeMsg(state.path, S_number, t, out))
        return UNDEF
    return out


def validate_BOOLEAN(state, _val, current, store):
    """
    A required boolean value.
    """
    out = getprop(current, state.key)
    t = typify(out)

    if t != S_boolean:
        state.errs.append(_invalidTypeMsg(state.path, S_boolean, t, out))
        return UNDEF
    return out


def validate_OBJECT(state, _val, current, store):
    """
    A required object (dict), contents not further validated by this step.
    """
    out = getprop(current, state.key)
    t = typify(out)

    if out is UNDEF or t != S_object:
        state.errs.append(_invalidTypeMsg(state.path, S_object, t, out))
        return UNDEF
    return out


def validate_ARRAY(state, _val, current, store):
    """
    A required list, contents not further validated by this step.
    """
    out = getprop(current, state.key)
    t = typify(out)

    if t != S_array:
        state.errs.append(_invalidTypeMsg(state.path, S_array, t, out))
        return UNDEF
    return out


def validate_FUNCTION(state, _val, current, store):
    """
    A required function (callable in Python).
    """
    out = getprop(current, state.key)
    t = typify(out)

    if t != S_function:
        state.errs.append(_invalidTypeMsg(state.path, S_function, t, out))
        return UNDEF
    return out


def validate_ANY(state, _val, current, store):
    """
    Allow any value.
    """
    return getprop(current, state.key)


def validate_CHILD(state, _val, current, store):
    mode = state.mode
    key = state.key
    parent = state.parent
    path = state.path
    keys = state.keys

    # Map syntax.
    if S_MKEYPRE == mode:
        childtm = getprop(parent, key)

        # The corresponding current object is found at path[-2].
        pkey = getprop(path, len(path)-2)
        tval = getprop(current, pkey)

        if UNDEF == tval:
            tval = {}
            
        elif not ismap(tval):
            msg = _invalidTypeMsg(path[:-1], S_object, typify(tval), tval)
            state.errs.append(msg)
            return UNDEF

        # For each key in tval, clone childtm
        ckeys = keysof(tval)
        for ckey in ckeys:
            setprop(parent, ckey, clone(childtm))
            # Extend state.keys so the injection/validation loop processes them
            keys.append(ckey)

        # Remove the `$CHILD` from final output
        setprop(parent, key, UNDEF)
        return UNDEF

    # List syntax.
    elif S_MVAL == mode:

        if not islist(parent):
            # $CHILD was not inside a list.
            state.errs.append("Invalid $CHILD as value")
            return UNDEF

        childtm = getprop(parent, 1)
        
        if UNDEF == current:
            # Empty list as default.
            del parent[:]
            return UNDEF

        if not islist(current):
            msg = _invalidTypeMsg(path[:-1], S_array, typify(current), current)
            state.errs.append(msg)
            state.keyI = len(parent)
            return current

    
        # Clone children abd reset state key index.
        # The inject child loop will now iterate over the cloned children,
        # validating them againt the current list values.
        for i in range(len(current)):
            parent[i] = clone(childtm)

        del parent[len(current):]
        state.keyI = 0
        out = getprop(current,0)
        return out
            
    return UNDEF


def validate_ONE(state, _val, current, store):
    """
    Match at least one of the specified shapes.
    Syntax: ['`$ONE`', alt0, alt1, ...]
    """
    mode = state.mode
    parent = state.parent
    path = state.path
    nodes = state.nodes

    if S_MVAL == mode:
        state.keyI = len(state.keys)

        tvals = parent[1:]

        for tval in tvals:
            terrs = []
            validate(current, tval, UNDEF, terrs)

            # The parent is the list itself. The "grandparent" is the next node up
            grandparent = nodes[-2] if len(nodes) >= 2 else UNDEF
            grandkey = path[-2] if len(path) >= 2 else UNDEF

            if isnode(grandparent):
                if 0 == len(terrs):
                    setprop(grandparent, grandkey, current)
                    return
                else:
                    setprop(grandparent, grandkey, UNDEF)

        valdesc = ", ".join(stringify(v) for v in tvals)
        valdesc = re.sub(r"`\$([A-Z]+)`", lambda m: m.group(1).lower(), valdesc)

        state.errs.append(_invalidTypeMsg(
            state.path[:-1],
            "one of " + valdesc,
            typify(current), current))

        
def _validation(
        pval,
        key,
        parent,
        state,
        current,
        _store
):
    if UNDEF == state:
        return

    cval = getprop(current, key)

    if UNDEF == cval or UNDEF == state:
        return

    ptype = typify(pval)

    if S_string == ptype and S_DS in str(pval):
        return

    ctype = typify(cval)

    if ptype != ctype and UNDEF != pval:
        state.errs.append(_invalidTypeMsg(state.path, ptype, ctype, cval))
        return

    if ismap(cval):
        if not ismap(pval):
            state.errs.append(_invalidTypeMsg(state.path, ptype, ctype, cval))
            return

        ckeys = keysof(cval)
        pkeys = keysof(pval)

        # Empty spec object {} means object can be open (any keys).
        if 0 < len(pkeys) and True != getprop(pval, '`$OPEN`'):
            badkeys = []
            for ckey in ckeys:
                if not haskey(pval, ckey):
                    badkeys.append(ckey)
            if 0 < len(badkeys):
                msg = f"Unexpected keys at {pathify(state.path,1)}: {', '.join(badkeys)}"
                state.errs.append(msg)
        else:
            # Object is open, so merge in extra keys.
            merge([pval, cval])
            if isnode(pval):
                setprop(pval,'`$OPEN`',UNDEF)

    elif islist(cval):
        if not islist(pval):
            state.errs.append(_invalidTypeMsg(state.path, ptype, ctype, cval))

    else:
        # Spec value was a default, copy over data
        setprop(parent, key, cval)

    return


# Validate a data structure against a shape specification.  The shape
# specification follows the "by example" principle.  Plain data in
# teh shape is treated as default values that also specify the
# required type.  Thus shape {a:1} validates {a:2}, since the types
# (number) match, but not {a:'A'}.  Shape {a;1} against data {}
# returns {a:1} as a=1 is the default value of the a key.  Special
# validation commands (in the same syntax as transform ) are also
# provided to specify required values.  Thus shape {a:'`$STRING`'}
# validates {a:'A'} but not {a:1}. Empty map or list means the node
# is open, and if missing an empty default is inserted.
def validate(data, spec, extra=UNDEF, collecterrs=UNDEF):
    errs = [] if UNDEF == collecterrs else collecterrs

    store = {
        "$ERRS": errs,

        "$DELETE": UNDEF,
        "$COPY": UNDEF,
        "$KEY": UNDEF,
        "$META": UNDEF,
        "$MERGE": UNDEF,
        "$EACH": UNDEF,
        "$PACK": UNDEF,

        "$STRING": validate_STRING,
        "$NUMBER": validate_NUMBER,
        "$BOOLEAN": validate_BOOLEAN,
        "$OBJECT": validate_OBJECT,
        "$ARRAY": validate_ARRAY,
        "$FUNCTION": validate_FUNCTION,
        "$ANY": validate_ANY,
        "$CHILD": validate_CHILD,
        "$ONE": validate_ONE,
    }

    if UNDEF != extra:
        store.update(extra)

    out = transform(data, spec, store, _validation)

    if 0 < len(errs) and UNDEF == collecterrs:
        raise ValueError("Invalid data: " + " | ".join(errs))

    return out



# Internal Utilities
# ==================


def _injectstr(val, store, current=UNDEF, state=UNDEF):
    full_re = re.compile(r'^`(\$[A-Z]+|[^`]+)[0-9]*`$')
    part_re = re.compile(r'`([^`]+)`')

    if not isinstance(val, str) or S_MT == val:
        return S_MT

    out = val
    
    m = full_re.match(val)
    
    if m:
        # Full string is an injection
        if UNDEF != state:
            state.full = True

        pathref = m.group(1)

        # Handle special escapes
        if 3 < len(pathref):
            pathref = pathref.replace(r'$BT', S_BT).replace(r'$DS', S_DS)

        out = getpath(pathref, store, current, state)

    else:
        
        # Check partial injections
        def partial(mobj):
            ref = mobj.group(1)

            if 3 < len(ref):
                ref = ref.replace(r'$BT', S_BT).replace(r'$DS', S_DS)

            if UNDEF != state:
                state.full = False

            found = getpath(ref, store, current, state)
            
            if UNDEF == found:
                return S_MT

            if isinstance(found, str):
                return found

            return json.dumps(found, separators=(',', ':'))

        out = part_re.sub(partial, val)

        if UNDEF != state and isfunc(state.handler):
            state.full = True
            out = state.handler(state, out, current, val, store)

    return out


def _invalidTypeMsg(path, expected_type, vt, v):
    vs = stringify(v)
    return (
        f"Expected {expected_type} at {pathify(path,1)}, "
        f"found {(vt+': ' + vs) if UNDEF != v else ''}"
    )

# from pprint import pformat
# print(pformat(vars(instance)))



