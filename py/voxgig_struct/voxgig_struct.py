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



  # Mode value for inject step.
S_MKEYPRE =  'key:pre'
S_MKEYPOST =  'key:post'
S_MVAL =  'val'
S_MKEY =  'key',

  # Special keys.
S_DKEY =  '`$KEY`'
S_DTOP =  '$TOP'
S_DERRS =  '$ERRS'
S_DMETA =  '`$META`',

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


def clone(val: Any = UNDEF):
    """
    // Clone a JSON-like data structure.
    // NOTE: function value references are copied, *not* cloned.
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

    json_str = json.dumps(transformed)

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
    """
    Get a value deep inside 'store' using a path (string or list).
    - If path is a dotted string, split on '.'.
    - If path begins with '.', treat it as relative to 'current' (if given).
    - If the path is empty, just return store (or store[state.base] if set).
    - state.handler can modify the found value (for injections).
    """

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
        val = state.handler(state, val, current, pathify(path), store)

    return val


def _injectstr(val, store, current=UNDEF, state=UNDEF):
    """
    Internal helper. Inject store values into a string with backtick syntax:
    - Full injection if it matches ^`([^`]+)`$
    - Partial injection for occurrences of `path` inside the string.
    """
    if not isinstance(val, str):
        return S_MT

    if val == "":
        return ""
    
    pattern_full = re.compile(r'^`(\$[A-Z]+|[^`]+)[0-9]*`$')
    pattern_part = re.compile(r'`([^`]+)`')

    m = pattern_full.match(val)
    # print("INJECTSTR-M", val, m)
    
    if m:
        # Full string is an injection
        if state is not UNDEF:
            state.full = True
        ref = m.group(1)

        # Handle special escapes
        if len(ref) > 3:
            ref = ref.replace(r'$BT', S_BT).replace(r'$DS', S_DS)

        out = getpath(ref, store, current, state)
        # print('INJECTSTR-P', val, out)
        
    else:
        # Check partial injections
        def replace_injection(mobj):
            ref_local = mobj.group(1)
            if len(ref_local) > 3:
                ref_local = ref_local.replace(r'$BT', S_BT).replace(r'$DS', S_DS)
            if state is not UNDEF:
                state.full = False
            found = getpath(ref_local, store, current, state)
            if found is UNDEF:
                return S_MT
            if isinstance(found, (dict, list)):
                import json
                return json.dumps(found, separators=(',', ':'))
            if type(found) is bool:
                if True == found:
                    return "true"
                if False == found:
                    return "false"
            return str(found)

        out = pattern_part.sub(replace_injection, val)

        # Also call handler on entire string
        if state is not UNDEF and isfunc(state.handler):
            state.full = True
            out = state.handler(state, out, current, val, store)

    return out


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
        parentkey = state.path[-2] if len(state.path) > 1 else UNDEF
        if parentkey is not UNDEF:
            current = getprop(current, parentkey, current)

    # Descend into node
    if isnode(val):
        # Sort keys (transforms with `$...` go last).
        if ismap(val):
            normal_keys = [k for k in val.keys() if S_DS not in k]
            transform_keys = [k for k in val.keys() if S_DS in k]
            transform_keys.sort()
            origkeys = normal_keys + transform_keys
        else:
            origkeys = list(range(len(val)))

        okI = 0
        while okI < len(origkeys):
            origkey = origkeys[okI]

            childpath = state.path + [str(origkey)]
            childnodes = state.nodes + [val]

            # Phase 1: key-pre
            childstate = InjectState(
                mode = S_MKEYPRE,
                full = False,
                keyI = okI,
                keys = origkeys,
                key = str(origkey),
                val = val,
                parent = val,
                path = childpath,
                nodes = childnodes,
                handler = _injecthandler,
                base = state.base,
                meta = state.meta,
                errs = state.errs,
            )

            prekey = _injectstr(str(origkey), store, current, childstate)

            # The injection may modify child processing.
            okI = childstate.keyI

            if prekey is not UNDEF:
                # Phase 2: val
                child_val = getprop(val, prekey)
                childstate.mode = S_MVAL

                # Perform the val mode injection on the child value.
                # NOTE: return value is not used.
                inject(child_val, store, modify, current, childstate)

                # The injection may modify child processing.
                okI = childstate.keyI
                
                # Phase 3: key-post
                childstate.mode = S_MKEYPOST
                _injectstr(str(origkey), store, current, childstate)

                # The injection may modify child processing.
                okI = childstate.keyI

            okI = okI+1
            
    elif isinstance(val, str):
        state.mode = S_MVAL
        newval = _injectstr(val, store, current, state)
        setprop(state.parent, state.key, newval)
        val = newval

    # Custom modification
    if UNDEF != modify:
        modify(val, state.key, state.parent, state, current, store)

    return getprop(state.parent, S_DTOP)


# Default injection handler (used by `inject`).
def _injecthandler(state, val, current, ref, store):
    """
    Default injection handler. If val is a callable, call it.
    Otherwise, if this is a 'full' injection in 'val' mode, set val in parent.
    """
    if isfunc(val) and (UNDEF == ref or (isinstance(ref, str) and ref.startswith(S_DS))):
        return val(state, val, current, store)
    else:
        if state.mode == S_MVAL and state.full:
            setprop(state.parent, state.key, val)
        return val


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


# -----------------------------------------------------------------------------
# Main transform function


def transform(data, spec, extra=UNDEF, modify=UNDEF):
    """
    Transform `data` into a new data structure defined by `spec`.
    Additional transforms or data can be provided in `extra`.
    """
    # Separate out custom transforms from data.
    extra_transforms = {}
    extra_data = {}

    if extra is not UNDEF:
        for k, v in items(extra):
            if isinstance(k, str) and k.startswith(S_DS):
                extra_transforms[k] = v
            else:
                extra_data[k] = v

    # Combine extra data with user data
    data_clone = merge([clone(extra_data), clone(data)])

    # Top-level store used by inject
    store = {
        # Custom transforms
        **extra_transforms,
        # Original data
        S_DTOP: data_clone,
        # Escape helpers
        '$BT': lambda state, val, current, store: S_BT,
        '$DS': lambda state, val, current, store: S_DS,
        # Current date/time
        '$WHEN': lambda state, val, current, store: datetime.utcnow().isoformat(),
        # Built-in transform handlers
        '$DELETE': transform_DELETE,
        '$COPY': transform_COPY,
        '$KEY': transform_KEY,
        '$META': transform_META,
        '$MERGE': transform_MERGE,
        '$EACH': transform_EACH,
        '$PACK': transform_PACK,
    }

    out = inject(spec, store, modify, store)
    return out


def _invalidTypeMsg(path, expected_type, vt, v):
    vs = stringify(v)
    return (
        f"Expected {expected_type} at {pathify(path)}, "
        f"found {(vt+': ' + vs) if UNDEF != v else ''}"
    )


def pathify(val: Any = UNDEF, from_index: int = UNDEF) -> str:
    """
    Build a human friendly path string from a value.
    
    Args:
        val: Value to convert to a path. Can be a list, string, or number.
        from_index: Optional starting index for list values (defaults to 0)
        
    Returns:
        A string representing the path in dot notation
    """
    path = None
    
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
        start = from_index if from_index >= 0 else 0
    
    # Process the path if we have one
    if path is not None and start >= 0:
        if len(path) <= start:
            start = len(path)
            
        sliced = path[start:]
        
        if len(sliced) == 0:
            return "<root>"
        else:
            # Filter out non-string/non-number elements and special system paths
            filtered = []
            for p in sliced:
                # Skip system paths like $TOP
                if isinstance(p, str) and p.startswith("$"):
                    continue
                    
                if isinstance(p, str) or isinstance(p, (int, float)):
                    filtered.append(p)
            
            # Return root if all elements were filtered out
            if len(filtered) == 0:
                return "<root>"
                
            # Map each element to a string, removing dots
            mapped = []
            for p in filtered:
                if isinstance(p, str):
                    mapped.append(p.replace(S_DT, S_MT))
                else:
                    mapped.append(str(int(p)))
            
            return S_DT.join(mapped)
    
    # Handle the case where we couldn't create a path
    if val is UNDEF:
        return "<unknown-path>"
    else:
        return f"<unknown-path:{stringify(val, 33)}>"


# _pathify function has been removed in favor of the public pathify function


# Internal functions have been removed in favor of the public typify function


def validate_STRING(state, _val, current, store):
    """
    A required string value. Rejects empty strings.
    """
    out = getprop(current, state.key)
    t = typify(out)

    if t == S_string:
        if out == S_MT:
            state.errs.append(f"Empty string at {pathify(state.path)}")
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
    """
    Specify child values for a map or list.
      - Map syntax: {'`$CHILD`': child_template}
      - List syntax: ['`$CHILD`', child_template ]
    """
    mode = state.mode
    key = state.key
    parent = state.parent
    path = state.path
    keys = state.keys

    if mode == S_MKEYPRE:
        # => Map syntax
        child_template = getprop(parent, key)

        # The corresponding current object is found at path[-2].
        pkey = path[-2] if len(path) >= 2 else UNDEF
        tval = getprop(current, pkey)

        if UNDEF == tval:
            # Default to empty dict
            tval = {}
        elif not ismap(tval):
            msg = _invalidTypeMsg(path[:-1], S_object, typify(tval), tval)
            state.errs.append(msg)
            return UNDEF

        # For each key in tval, clone child_template
        ckeys = keysof(tval)
        for ckey in ckeys:
            setprop(parent, ckey, clone(child_template))
            # Extend state.keys so the injection/validation loop processes them
            keys.append(ckey)

        # Remove the `$CHILD` from final output
        setprop(parent, key, UNDEF)
        return UNDEF

    elif mode == S_MVAL:
        # => List syntax
        if not islist(parent):
            state.errs.append("Invalid $CHILD as value")
            return UNDEF

        if len(parent) > 1:
            child_template = parent[1]
        else:
            child_template = UNDEF

        # if current is UNDEF => empty list as default
        if current is UNDEF:
            del parent[:]
            return UNDEF

        if not islist(current):
            # Not a list => error
            msg = _invalidTypeMsg(path[:-1], S_array, typify(current), current)
            state.errs.append(msg)
            state.keyI = len(parent)
            return current

        else:
            # Clone the child template for each element
            for i in range(len(current)):
                parent[i] = clone(child_template)
            # Adjust the length of the parent to match current
            del parent[len(current):]
            # Reset the injection pointer
            state.keyI = 0
            # Return the first item for further injection
            return getprop(current,0)

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

    if mode == S_MVAL:
        # Skip normal injection for all the alt shapes
        state.keyI = len(state.keys)

        # The shapes are after the first element (the `'$ONE'` command).
        tvals = parent[1:]

        for tval in tvals:
            terrs = []
            validate(current, tval, UNDEF, terrs)

            # The parent is the list itself. The "grandparent" is the next node up
            if len(nodes) >= 2:
                grandparent = nodes[-2]
            else:
                grandparent = UNDEF
            if len(path) >= 2:
                grandkey = path[-2]
            else:
                grandkey = UNDEF

            if isnode(grandparent) and UNDEF != grandkey:
                if len(terrs) == 0:
                    # Accept this data
                    setprop(grandparent, grandkey, current)
                    return
                else:
                    # Unset the value so no spurious error remains
                    setprop(grandparent, grandkey, UNDEF)

        valdesc = ", ".join(stringify(v) for v in tvals)
        valdesc = re.sub(r"`\$([A-Z]+)`", lambda m: m.group(1).lower(), valdesc)

        state.errs.append(
            _invalidTypeMsg(
                state.path[:-1],
                "one of " + valdesc,
                typify(current),
                current
            )
        )

        
def _validation(val, key, parent, state, current, _store):
    """
    Generic validation callback that runs *after* any special commands ($STRING, etc.).
    If there's a type mismatch, we record errors, etc.
    This mirrors the final block in your TS code's 'validation' function.
    """
    if state is UNDEF or key is UNDEF:
        return UNDEF

    cval = getprop(current, key)
    if UNDEF == cval:
        return UNDEF

    pval = getprop(parent, key)
    t = typify(pval)
    ct = typify(cval)

    # If pval is a leftover transform command (like '`$STRING`'), skip it.
    if t == S_string and S_DS in str(pval):
        return UNDEF

    # Type mismatch
    if t != ct and pval is not UNDEF:
        state.errs.append(_invalidTypeMsg(state.path, t, ct, cval))
        return UNDEF

    # If cval is a dict:
    elif ismap(cval):
        if not ismap(val):
            # The spec is not a dict => mismatch
            # If val is a list => we say "expected array"
            st = S_array if islist(val) else typify(val)
            state.errs.append(_invalidTypeMsg(state.path, st, ct, cval))
            return UNDEF

        ckeys = keysof(cval)
        pkeys = keysof(pval)

        # If spec object has keys and doesn't have `$OPEN` => it's a "closed" object
        if pkeys and not (pval.get("`$OPEN`") is True):
            badkeys = []
            for ckey in ckeys:
                if not haskey(val, ckey):
                    badkeys.append(ckey)
            if badkeys:
                msg = f"Unexpected keys at {pathify(state.path)}: {', '.join(badkeys)}"
                state.errs.append(msg)
        else:
            # It's open => merge in extra keys from data
            merge([pval, cval])
            if isnode(pval):
                pval.pop("`$OPEN`", UNDEF)

    # If cval is a list
    elif islist(cval):
        if not islist(val):
            state.errs.append(_invalidTypeMsg(state.path, t, ct, cval))

    else:
        # Spec value was a default => copy data
        setprop(parent, key, cval)

    return UNDEF


def validate(data, spec, extra=UNDEF, collecterrs=UNDEF):
    """
    Validate a data structure against a shape specification.

    - data: Source data (won't be mutated)
    - spec: Shape specification
    - extra: Additional custom checks (dict of $COMMAND -> function)
    - collecterrs: if provided, is a list to accumulate errors instead of throwing.

    Returns: validated data structure with defaults/changes applied.
    Raises:  ValueError if invalid (unless collecterrs is provided).
    """
    errs = collecterrs if collecterrs is not UNDEF else []
    
    # The store merges your built-in validators with any custom ones
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

    out = transform(data, spec, store, modify=_validation)

    if errs and UNDEF == collecterrs:
        raise ValueError("Invalid data: " + "\n".join(errs))

    return out
