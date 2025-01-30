# Copyright (c) 2025 Voxgig Ltd.
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
import json
import re


S = {
    'MKEYPRE': 'key:pre',
    'MKEYPOST': 'key:post',
    'MVAL': 'val',
    'MKEY': 'key',

    'TKEY': '`$KEY`',
    'TMETA': '`$META`',

    'KEY': 'KEY',

    'DTOP': '$TOP',

    'object': 'object',
    'number': 'number',
    'string': 'string',
    'function': 'function',
    'empty': '',
    'base': 'base',

    'BT': '`',
    'DS': '$',
    'DT': '.',
}


def isnode(val: Any):
    """
    Return True if val is a non-None dict or list (JSON-like node).
    """
    return val is not None and isinstance(val, (dict, list))


def ismap(val: Any):
    """
    Return True if val is a non-None dict (map).
    """
    return val is not None and isinstance(val, dict)


def islist(val: Any):
    """
    Return True if val is a list.
    """
    return isinstance(val, list)


def iskey(key: Any):
    """
    Return True if key is a non-empty string or a number (int).
    """
    if isinstance(key, str):
        return len(key) > 0
    # Exclude bool (which is a subclass of int)
    if isinstance(key, bool):
        return False
    if isinstance(key, int):
        return True
    return False


def items(val: Any):
    """
    List the keys of a map or list as an array of [key, value] tuples.
    """
    if ismap(val):
        return list(val.items())
    elif islist(val):
        return list(enumerate(val))
    else:
        return []


def clone(val: Any):
    """
    Clone a JSON-like data structure using a deep copy (via JSON).
    """
    import json
    if val is None:
        return None
    return json.loads(json.dumps(val))


def getprop(val: Any, key: Any, alt: Any = None) -> Any:
    """
    Safely get a property from a dictionary or list. Return `alt` if not found or invalid.
    """
    if not isnode(val) or not iskey(key):
        return alt
    
    if ismap(val):
        return val.get(str(key), alt)
    
    if islist(val):
        try:
            key = int(key)
        except (ValueError, TypeError):
            return alt

        if 0 <= key < len(val):
            return val[key]
        else:
            return alt

    return alt


def setprop(parent: Any, key: Any, val: Any):
    """
    Safely set a property on a dictionary or list.
    - If `val` is None, delete the key from parent.
    - For lists, negative key -> prepend.
    - For lists, key > len(list) -> append.
    - For lists, None value -> remove and shift down.
    """
    if not iskey(key):
        return parent

    if ismap(parent):
        key = str(key)
        if val is None:
            parent.pop(key, None)
        else:
            parent[key] = val

    elif islist(parent):
        # Convert key to int
        try:
            key_i = int(key)
        except ValueError:
            return parent

        # Delete an element
        if val is None:
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
        key: Any = None,
        parent: Any = None,
        path: Any = None
):
    """
    Walk a data structure depth-first, calling apply at each node (after children).
    """
    if path is None:
        path = []
    if isnode(val):
        for (ckey, child) in items(val):
            setprop(val, ckey, walk(child, apply, ckey, val, path + [str(ckey)]))

    # Nodes are applied *after* their children.
    # For the root node, key and parent will be None.
    return apply(key, val, parent, path)


def merge(objs: List[Any]):
    """
    Merge a list of values into each other (first is mutated).
    Later values have precedence. Node types override scalars.
    Kinds also override each other (dict vs list).
    """
    if not islist(objs):
        return objs
    if len(objs) == 0:
        return None
    if len(objs) == 1:
        return objs[0]
        
    out = getprop(objs, 0, {})

    # Merge remaining
    for i in range(1, len(objs)):
        obj = objs[i]
        if isnode(obj):

            # Nodes win, also over nodes of a different kind
            if (not isnode(out) or (ismap(obj) and islist(out)) or (islist(obj) and ismap(out))):
                out = obj
            else:
                cur = [out]
                
                def merge_apply(key, val, parent, path):
                    if key is not None:
                        # cI is the current depth index within path
                        cI = len(path) - 1

                        # Ensure the cur list has at least cI elements
                        cur.extend([None]*(1+cI-len(cur)))
                        
                        # If we haven't set cur[cI] yet, get it from out along the path
                        if cur[cI] is None:
                            cur[cI] = getpath(path[:-1], out)

                        # Create node if needed
                        if not isnode(cur[cI]):
                            cur[cI] = [] if islist(parent) else {}

                        # Node child is just ahead of us on the stack.
                        if isnode(val):
                            # Ensure the cur list has at least cI+1 elements
                            cur.extend([None] * (2+cI+len(cur)))
                
                            setprop(cur[cI], key, cur[cI + 1])
                            cur[cI + 1] = None

                        else:
                            # Scalar child.
                            setprop(cur[cI], key, val)

                    return val

                walk(obj, merge_apply)
        else:
            # Nodes win.
            out = obj

    return out


def getpath(path, store, current=None, state=None):
    """
    Get a value deep inside 'store' using a path (string or list).
    - If path is a dotted string, split on '.'.
    - If path begins with '.', treat it as relative to 'current' (if given).
    - If the path is empty, just return store (or store[state.base] if set).
    - state.handler can modify the found value (for injections).
    """
    # If path or store is None or empty, return store or store[state.base].
    if path is None or store is None or path == S['empty']:
        if state is not None:
            base = getprop(state, S['base'])
            if base is not None:
                return getprop(store, base, store)
        return store

    if isinstance(path, str):
        parts = path.split(S['DT'])
    else:
        parts = path[:]  # assume list of keys

    val = store
    if len(parts) > 0:
        p_idx = 0
        # Relative path -> first part is '' => use current
        if parts[0] == S['empty']:
            if len(parts) == 1:
                if state is not None:
                    base = getprop(state, S['base'])
                    if base is not None:
                        return getprop(store, base, store)
                return store
            p_idx = 1
            val = current

        if val is None:
            return None

        # Attempt to descend
        while p_idx < len(parts) and val is not None:
            part = parts[p_idx]
            val = getprop(val, part)
            p_idx += 1

    # If a custom handler is specified, apply it.
    if state is not None and callable(getprop(state, 'handler')):
        handler = getprop(state, 'handler')
        val = handler(state, val, current, store)

    return val


def _injectstr(val, store, current=None, state=None):
    """
    Internal helper. Inject store values into a string with backtick syntax:
    - Full injection if it matches ^`([^`]+)`$
    - Partial injection for occurrences of `path` inside the string.
    """
    if not isinstance(val, str):
        return S['empty']

    import re

    pattern_full = re.compile(r'^`(\$[A-Z]+|[^`]+)[0-9]*`$')
    pattern_part = re.compile(r'`([^`]+)`')

    m = pattern_full.match(val)
    if m:
        # Full string is an injection
        if state is not None:
            state['full'] = True
        ref = m.group(1)

        # Handle special escapes
        if len(ref) > 3:
            ref = ref.replace(r'$BT', S['BT']).replace(r'$DS', S['DS'])

        out = getpath(ref, store, current, state)
    else:
        # Check partial injections
        def replace_injection(mobj):
            ref_local = mobj.group(1)
            if len(ref_local) > 3:
                ref_local = ref_local.replace(r'$BT', S['BT']).replace(r'$DS', S['DS'])
            if state is not None:
                state['full'] = False
            found = getpath(ref_local, store, current, state)
            if found is None:
                return S['empty']
            if isinstance(found, (dict, list)):
                import json
                return json.dumps(found)
            return str(found)

        out = pattern_part.sub(replace_injection, val)

        # Also call handler on entire string
        if state is not None and callable(getprop(state, 'handler')):
            state['full'] = True
            handler = getprop(state, 'handler')
            out = handler(state, out, current, store)

    return out


def inject(val, store, modify=None, current=None, state=None):
    """
    Inject values from `store` into `val` recursively, respecting backtick syntax.
    `modify` is an optional function(key, val, parent, state, current, store)
    that is called after each injection.
    """
    if state is None:
        # Create a root-level state
        parent = {S['DTOP']: val}
        state = {
            'mode': S['MVAL'],
            'full': False,
            'keyI': 0,
            'keys': [S['DTOP']],
            'key': S['DTOP'],
            'val': val,
            'parent': parent,
            'path': [S['DTOP']],
            'nodes': [parent],
            'handler': _injecthandler,
            'base': S['DTOP'],
            'modify': modify
        }

    # For local paths, we keep track of the current node in `current`.
    if current is None:
        current = {S['DTOP']: store}
    else:
        parentkey = state['path'][-2] if len(state['path']) > 1 else None
        if parentkey is not None:
            current = getprop(current, parentkey, current)

    # Descend into node
    if isnode(val):
        # Sort keys (transforms with `$...` go last).
        if ismap(val):
            normal_keys = [k for k in val.keys() if S['DS'] not in k]
            transform_keys = [k for k in val.keys() if S['DS'] in k]
            transform_keys.sort()
            origkeys = normal_keys + transform_keys
        else:
            origkeys = list(range(len(val)))

        for okI, origkey in enumerate(origkeys):
            childpath = state['path'] + [str(origkey)]
            childnodes = state['nodes'] + [val]

            # Phase 1: key-pre
            child_state = {
                'mode': S['MKEYPRE'],
                'full': False,
                'keyI': okI,
                'keys': origkeys,
                'key': str(origkey),
                'val': val,
                'parent': val,
                'path': childpath,
                'nodes': childnodes,
                'handler': _injecthandler,
                'base': state.get('base'),
            }

            prekey = _injectstr(str(origkey), store, current, child_state)
            if prekey is not None:
                # Phase 2: val
                child_val = getprop(val, prekey)
                child_state['mode'] = S['MVAL']
                inject(child_val, store, modify, current, child_state)

                # Phase 3: key-post
                child_state['mode'] = S['MKEYPOST']
                _injectstr(str(origkey), store, current, child_state)

    elif isinstance(val, str):
        state['mode'] = S['MVAL']
        newval = _injectstr(val, store, current, state)
        setprop(state['parent'], state['key'], newval)
        val = newval

    # Custom modification
    if modify is not None:
        modify(state['key'], val, state['parent'], state, current, store)

    return state['parent'].get(S['DTOP'], None)


# Default injection handler (used by `inject`).
def _injecthandler(state, val, current, store):
    """
    Default injection handler. If val is a callable, call it.
    Otherwise, if this is a 'full' injection in 'val' mode, set val in parent.
    """
    if callable(val):
        return val(state, val, current, store)
    else:
        if state['mode'] == S['MVAL'] and state['full']:
            setprop(state['parent'], state['key'], val)
        return val


# -----------------------------------------------------------------------------
# Transform helper functions (these are injection handlers).


def transform_DELETE(state, val, current, store):
    """
    Injection handler to delete a key from a map/list.
    """
    setprop(state['parent'], state['key'], None)
    return None


def transform_COPY(state, val, current, store):
    """
    Injection handler to copy a value from source data under the same key.
    """
    mode = state['mode']
    key = state['key']
    parent = state['parent']

    out = None
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
    mode = state['mode']
    path = state['path']
    parent = state['parent']

    if mode != S['MVAL']:
        return None

    keyspec = getprop(parent, S['TKEY'])
    if keyspec is not None:
        setprop(parent, S['TKEY'], None)
        return getprop(current, keyspec)

    meta = getprop(parent, S['TMETA'])
    return getprop(meta, S['KEY'], getprop(path, len(path) - 2))


def transform_META(state, val, current, store):
    """
    Injection handler that removes the `'$META'` key (after capturing if needed).
    """
    parent = state['parent']
    setprop(parent, S['TMETA'], None)
    return None


def transform_MERGE(state, val, current, store):
    """
    Injection handler to merge a list of objects onto the parent object.
    If the transform data is an empty string, merge the top-level store.
    """
    mode = state['mode']
    key = state['key']
    parent = state['parent']

    if mode == S['MKEYPRE']:
        return key

    if mode == S['MKEYPOST']:
        args = getprop(parent, key)
        if args == S['empty']:
            args = [store[S['DTOP']]]
        elif not islist(args):
            args = [args]

        setprop(parent, key, None)

        # Merge them on top of parent
        mergelist = [parent] + args + [clone(parent)]
        merge(mergelist)
        return key

    return None


def transform_EACH(state, val, current, store):
    """
    Injection handler to convert the current node into a list by iterating over
    a source node. Format: ['`$EACH`','`source-path`', child-template]
    """
    mode = state['mode']
    keys_ = state.get('keys')
    path = state['path']
    parent = state['parent']
    nodes_ = state['nodes']

    if keys_ is not None:
        # Only keep the transform item (first). Avoid further spurious keys.
        keys_[:] = keys_[:1]

    if mode != S['MVAL'] or path is None or nodes_ is None:
        return None

    # parent here is the array [ '$EACH', 'source-path', {... child ...} ]
    srcpath = parent[1] if len(parent) > 1 else None
    child_template = clone(parent[2]) if len(parent) > 2 else None

    # source data
    src = getpath(srcpath, store, current, state)

    # The key in the parent's parent
    tkey = path[-2] if len(path) >= 2 else None
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
                copy_child[S['TMETA']] = {S['KEY']: k}
                tval.append(copy_child)
        tcurrent = list(src.values()) if ismap(src) else src
    else:
        # Not a node, do nothing
        return None

    # Build parallel "current"
    tcurrent = {S['DTOP']: tcurrent}

    # Inject to build substructure
    tval = inject(tval, store, state.get('modify'), tcurrent)

    setprop(target, tkey, tval)
    return tval[0] if tval else None


def transform_PACK(state, val, current, store):
    """
    Injection handler to convert the current node into a dict by "packing"
    a source list or dict. Format: { '`$PACK`': [ 'source-path', {... child ...} ] }
    """
    mode = state['mode']
    key = state['key']
    path = state['path']
    parent = state['parent']
    nodes_ = state['nodes']

    if (mode != S['MKEYPRE'] or not isinstance(key, str) or path is None or nodes_ is None):
        return None

    args = parent[key]
    if not args or not islist(args):
        return None

    srcpath = args[0] if len(args) > 0 else None
    child_template = clone(args[1]) if len(args) > 1 else None

    tkey = path[-2] if len(path) >= 2 else None
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
                v_copy[S['TMETA']] = {S['KEY']: k}
                new_src.append(v_copy)
        src = new_src
    else:
        return None

    if src is None:
        return None

    # Child key from template
    childkey = getprop(child_template, S['TKEY'])
    # Remove the transform key from template
    setprop(child_template, S['TKEY'], None)

    # Build a new dict in parallel with the source
    tval = {}
    for elem in src:
        if childkey is not None:
            kn = getprop(elem, childkey)
        else:
            # fallback
            kn = getprop(elem, S['TKEY'])
        if kn is None:
            # Possibly from meta
            meta = getprop(elem, S['TMETA'], {})
            kn = getprop(meta, S['KEY'], None)

        if kn is not None:
            tval[kn] = clone(child_template)
            # Transfer meta if present
            tmeta = getprop(elem, S['TMETA'])
            if tmeta is not None:
                tval[kn][S['TMETA']] = tmeta

    # Build parallel "current"
    tcurrent = {}
    for elem in src:
        if childkey is not None:
            kn = getprop(elem, childkey)
        else:
            kn = getprop(elem, S['TKEY'])
        if kn is None:
            meta = getprop(elem, S['TMETA'], {})
            kn = getprop(meta, S['KEY'], None)
        if kn is not None:
            tcurrent[kn] = elem

    tcurrent = {S['DTOP']: tcurrent}

    # Inject children
    tval = inject(tval, store, state.get('modify'), tcurrent)
    setprop(target, tkey, tval)

    # Drop the transform
    return None


# -----------------------------------------------------------------------------
# Main transform function


def transform(data, spec, extra=None, modify=None):
    """
    Transform `data` into a new data structure defined by `spec`.
    Additional transforms or data can be provided in `extra`.
    """
    # Separate out custom transforms from data.
    extra_transforms = {}
    extra_data = {}

    if extra is not None:
        for k, v in items(extra):
            if isinstance(k, str) and k.startswith(S['DS']):
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
        S['DTOP']: data_clone,
        # Escape helpers
        '$BT': lambda: S['BT'],
        '$DS': lambda: S['DS'],
        # Current date/time
        '$WHEN': lambda: __import__('datetime').datetime.utcnow().isoformat(),
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


# -----------------------------------------------------------------------------
# If you want to expose the functions from this module, you can list them here:

__all__ = [
    'isnode',
    'ismap',
    'islist',
    'iskey',
    'items',
    'clone',
    'getprop',
    'setprop',
    'walk',
    'merge',
    'getpath',
    'inject',
    'transform',
]
