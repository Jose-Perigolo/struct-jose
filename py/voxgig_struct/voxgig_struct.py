# Copyright (c) 2025 Voxgig Ltd. MIT LICENSE.
#
# Voxgig Struct
# =============
#
# Utility functions to manipulate in-memory JSON-like data structures.
# This Python version follows the same design and logic as the original
# TypeScript version, using "by-example" transformation of data.
#
# Main utilities
# - getpath: get the value at a key path deep inside an object.
# - merge: merge multiple nodes, overriding values in earlier nodes.
# - walk: walk a node tree, applying a function at each node and leaf.
# - inject: inject values from a data store into a new data structure.
# - transform: transform a data structure to an example structure.
# - validate: validate a data structure against a shape specification.
#
# Minor utilities
# - isnode, islist, ismap, iskey, isfunc: identify value kinds.
# - isempty: undefined values, or empty nodes.
# - keysof: sorted list of node keys (ascending).
# - haskey: true if key value is defined.
# - clone: create a copy of a JSON-like data structure.
# - items: list entries of a map or list as [key, value] pairs.
# - getprop: safely get a property value by key.
# - getelem: safely get a list element value by key/index.
# - setprop: safely set a property value by key.
# - size: get the size of a value (length for lists, strings; count for maps).
# - slice: return a part of a list or other value.
# - pad: pad a string to a specified length.
# - stringify: human-friendly string version of a value.
# - escre: escape a regular expresion string.
# - escurl: escape a url.
# - joinurl: join parts of a url, merging forward slashes.


from typing import *
from datetime import datetime
import urllib.parse
import json
import re
import math
import logging

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger('voxgig_struct')

# Mode value for inject step.
S_MKEYPRE =  'key:pre'
S_MKEYPOST =  'key:post'
S_MVAL =  'val'
S_MKEY =  'key'

# Special keys.
S_DKEY =  '`$KEY`'
S_DMETA =  '`$META`'
S_DTOP =  '$TOP'
S_DERRS =  '$ERRS'
S_DSPEC =  '$SPEC'

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
S_CN =  ':'
S_FS =  '/'
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
        self.prior = None

    def child(self, keyI: int, keys: List[str]) -> 'InjectState':
        """Create a child state object with the given key index and keys."""
        return InjectState(
            mode=self.mode,
            full=self.full,
            keyI=keyI,
            keys=keys,
            key=self.key,
            val=self.val,
            parent=self.parent,
            path=self.path,
            nodes=self.nodes,
            handler=self.handler,
            errs=self.errs,
            meta=self.meta,
            base=self.base,
            modify=self.modify
        )

    def setval(self, val: Any, ancestor: Optional[int] = None) -> Any:
        """Set the value in the parent node at the specified ancestor level."""
        if ancestor is None or ancestor < 2:
            return setprop(self.parent, self.key, val)
        else:
            return setprop(getelem(self.nodes, 0 - ancestor), getelem(self.path, 0 - ancestor), val)


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
    if isinstance(key, float):
        return True
    return False


def size(val: Any) -> int:
    """Determine the size of a value (length for lists/strings, count for maps)"""
    if islist(val):
        return len(val)
    elif ismap(val):
        return len(val.keys())
    
    if isinstance(val, str):
        return len(val)
    elif isinstance(val, (int, float)):
        return math.floor(val)
    elif isinstance(val, bool):
        return 1 if val else 0
    else:
        return 0


def slice(val: Any, start: int, end: int = UNDEF) -> Any:
    """Return a part of a list or other value"""
    if islist(val):
        vlen = size(val)
        if start is not None:
            if start < 0:
                end = vlen + start
                if end < 0:
                    end = 0
                start = 0
            elif end is not None:
                if end < 0:
                    end = vlen + end
                    if end < 0:
                        end = 0
                elif vlen < end:
                    end = len(val)
            else:
                end = len(val)

            if vlen < start:
                start = vlen

            if -1 < start and start <= end and end <= vlen:
                return val[start:end]

    return val


def pad(s: Any, padding: int = UNDEF, padchar: str = UNDEF) -> str:
    """Pad a string to a specified length"""
    s = stringify(s)
    padding = 44 if padding is UNDEF else padding
    padchar = ' ' if padchar is UNDEF else (padchar + ' ')[0]
    
    if padding > -1:
        return s.ljust(padding, padchar)
    else:
        return s.rjust(-padding, padchar)


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


def getelem(val: Any, key: Any, alt: Any = UNDEF) -> Any:
    """
    Get a list element. The key should be an integer, or a string
    that can parse to an integer only. Negative integers count from the end of the list.
    """
    out = UNDEF

    if UNDEF == val or UNDEF == key:
        return alt

    if islist(val):
        try:
            nkey = int(key)
            if isinstance(nkey, int) and str(key).strip('-').isdigit():
                if nkey < 0:
                    key = len(val) + nkey
                out = val[key] if 0 <= key < len(val) else UNDEF
        except (ValueError, IndexError):
            pass

    if UNDEF == out:
        return alt

    return out


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
        return alt
        
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
        return [(i, val[i]) for i in list(range(len(val)))]
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
        if i == 0:
            s = re.sub(r'/+$', '', s)
        else:
            s = re.sub(r'([^/])/{2,}', r'\1/', s)
            s = re.sub(r'^/+', '', s)
            s = re.sub(r'/+$', '', s)

        transformed.append(s)

    transformed = [s for s in transformed if s != ""]

    return "/".join(transformed)


def stringify(val: Any, maxlen: int = UNDEF):
    "Safely stringify a value for printing (NOT JSON!)."

    valstr = S_MT    

    if UNDEF == val:
        return valstr

    try:
        valstr = json.dumps(val, sort_keys=True, separators=(',', ':'))
    except Exception:
        valstr = str(val)
    
    valstr = valstr.replace('"', '')

    if maxlen is not UNDEF:
        json_len = len(valstr)
        valstr = valstr[:maxlen]
        
        if 3 < maxlen < json_len:
            valstr = valstr[:maxlen - 3] + '...'
    
    return valstr


def pathify(val: Any = UNDEF, startin: int = UNDEF, endin: int = UNDEF) -> str:
    pathstr = UNDEF
    
    # Convert input to a path array
    path = val if islist(val) else \
        [val] if iskey(val) else \
        UNDEF

    # [val] if isinstance(val, str) else \
        # [val] if isinstance(val, (int, float)) else \

    
    # Determine starting index and ending index
    start = 0 if startin is UNDEF else startin if -1 < startin else 0
    end = 0 if endin is UNDEF else endin if -1 < endin else 0

    if UNDEF != path and 0 <= start:
        path = path[start:len(path)-end]

        if 0 == len(path):
            pathstr = "<root>"
        else:
            # Filter path parts to include only valid keys
            filtered_path = [p for p in path if iskey(p)]
            
            # Map path parts: convert numbers to strings and remove any dots
            mapped_path = []
            for p in filtered_path:
                if isinstance(p, (int, float)):
                    mapped_path.append(S_MT + str(int(p)))
                else:
                    mapped_path.append(str(p).replace('.', S_MT))
            
            pathstr = S_DT.join(mapped_path)

    # Handle the case where we couldn't create a path
    if UNDEF == pathstr:
        pathstr = f"<unknown-path{S_MT if UNDEF == val else S_CN+stringify(val, 47)}>"

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
        elif hasattr(item, 'to_json'):
            return item.to_json()
        elif hasattr(item, '__dict__'):
            return item.__dict__ 
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
    logger.debug(f"setprop: Input - parent={type(parent).__name__}, key={key}, val={val}")
    logger.debug(f"setprop: Parent before - {parent}")

    if not iskey(key):
        logger.debug(f"setprop: Invalid key - {key}")
        return parent

    if ismap(parent):
        key = str(key)
        logger.debug(f"setprop: Map key after conversion - {key}")
        if UNDEF == val:
            logger.debug(f"setprop: Deleting key {key} from map")
            parent.pop(key, UNDEF)
        else:
            logger.debug(f"setprop: Setting map key {key} to {val}")
            parent[key] = val

    elif islist(parent):
        # Convert key to int
        try:
            key_i = int(key)
            logger.debug(f"setprop: List key converted to int - {key_i}")
        except ValueError:
            logger.debug(f"setprop: Invalid list key - {key}")
            return parent

        # Delete an element
        if UNDEF == val:
            if 0 <= key_i < len(parent):
                logger.debug(f"setprop: Deleting list element at index {key_i}")
                # Shift items left
                for pI in range(key_i, len(parent) - 1):
                    parent[pI] = parent[pI + 1]
                parent.pop()
        else:
            # Non-empty insert
            if key_i >= 0:
                if key_i >= len(parent):
                    # Append if out of range
                    logger.debug(f"setprop: Appending {val} to list")
                    parent.append(val)
                else:
                    logger.debug(f"setprop: Setting list index {key_i} to {val}")
                    parent[key_i] = val
            else:
                # Prepend if negative
                logger.debug(f"setprop: Prepending {val} to list")
                parent.insert(0, val)

    logger.debug(f"setprop: Parent after - {parent}")
    return parent


def walk(
        # These arguments are the public interface.
        val: Any,
        apply: Any,

        # These arguments are used for recursive state.
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
        obj = clone(objs[i])

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
    # Operate on a string array.
    if isinstance(path, str):
        parts = path.split(S_DT)
    elif islist(path):
        parts = path[:]
    else:
        return UNDEF
        
    root = store
    val = store
    base = UNDEF if UNDEF == state else state.base
    
    # An empty path (incl empty string) just finds the store.
    if path is UNDEF or store is UNDEF or (1 == len(parts) and parts[0] == S_MT):
        # The actual store data may be in a store sub property, defined by state.base.
        val = getprop(store, base, store)
    elif len(parts) > 0:
        pI = 0
            
        # Relative path uses `current` argument.
        if parts[0] == S_MT:
            pI = 1
            root = current

        part = parts[pI] if pI < len(parts) else UNDEF
        first = current if part == S_MT else getprop(root, part)

        # At top level, check state.base, if provided
        val = getprop(getprop(root, base), part) if UNDEF == first and 0 == pI else first

        # Move along the path, trying to descend into the store.
        pI += 1
        while UNDEF != val and pI < len(parts):
            part = parts[pI]
            if part != S_MT:
                val = getprop(val, parts[pI])
            pI += 1
            
    # State may provide a custom handler to modify found value.
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
            normal_keys.sort()
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

            # Create child state for key-pre phase
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


# Default inject handler for transforms. If the path resolves to a function,
# call the function passing the injection state. This is how transforms operate.
def _injecthandler(state, val, current, ref, store):
    out = val
    iscmd = isfunc(val) and (UNDEF == ref or (isinstance(ref, str) and ref.startswith(S_DS)))

    # Only call val function if it is a special command ($NAME format).
    if iscmd:
        out = val(state, val, current, ref, store)

    # Update parent with value. Ensures references remain in node tree.
    else:
        if state.mode == S_MVAL and state.full:
            state.setval(val)

    return out


# -----------------------------------------------------------------------------
# Transform helper functions (these are injection handlers).


def transform_DELETE(state, val, current, ref, store):
    """
    Injection handler to delete a key from a map/list.
    """
    state.setval(current, UNDEF)
    return UNDEF


def transform_COPY(state, val, current, ref, store):
    """
    Injection handler to copy a value from source data under the same key.
    """
    logger.debug(f"transform_COPY: Input - mode={state.mode}, key={state.key}")
    logger.debug(f"transform_COPY: Current - {current}")
    logger.debug(f"transform_COPY: Parent - {state.parent}")

    mode = state.mode
    key = state.key
    parent = state.parent

    out = UNDEF
    if mode.startswith('key'):
        logger.debug(f"transform_COPY: Key mode, returning key - {key}")
        out = key
    else:
        out = getprop(current, key)
        logger.debug(f"transform_COPY: Value mode, got value from current - {out}")
        state.setval(out)
        logger.debug(f"transform_COPY: Set value in parent using setval")

    logger.debug(f"transform_COPY: Returning - {out}")
    return out


def transform_KEY(state, val, current, ref, store):
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
        # Need to use setprop directly here since we're removing a specific key (S_DKEY)
        # not the current state's key
        setprop(parent, S_DKEY, UNDEF)
        return getprop(current, keyspec)

    meta = getprop(parent, S_DMETA)
    return getprop(meta, S_KEY, getprop(path, len(path) - 2))


def transform_META(state, val, current, ref, store):
    """
    Injection handler that removes the `'$META'` key (after capturing if needed).
    """
    parent = state.parent
    setprop(parent, S_DMETA, UNDEF)
    return UNDEF


def transform_MERGE(state, val, current, ref, store):
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

        state.setval(UNDEF)  # Using setval instead of setprop

        # Merge them on top of parent
        mergelist = [parent] + args + [clone(parent)]
        merge(mergelist)
        return key

    return UNDEF


def transform_EACH(state, val, current, ref, store):
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

    # Source data
    srcstore = getprop(store, state.base, store)
    src = getpath(srcpath, srcstore, current)
    
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

    _updateAncestors(state, target, tkey, tval)
    
    # Prevent callee from damaging first list entry (since we are in `val` mode).
    return tval[0] if tval else UNDEF


def transform_PACK(state, val, current, ref, store):
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
    srcstore = getprop(store, state.base, store)
    src = getpath(srcpath, srcstore, current)

    # Prepare source as a list
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

    # Build substructure
    tval = inject(tval, store, state.modify, tcurrent)
    
    _updateAncestors(state, target, tkey, tval)

    # Drop the transform key
    return UNDEF


def transform_REF(state, val, _current, _ref, store):
    """
    Reference original spec (enables recursive transformations)
    Format: ['`$REF`', '`spec-path`']
    """
    nodes = state.nodes
    modify = state.modify

    if state.mode != S_MVAL:
        return UNDEF

    # Get arguments: ['`$REF`', 'ref-path']
    refpath = getprop(state.parent, 1)
    state.keyI = len(state.keys)

    # Spec reference
    spec_func = getprop(store, S_DSPEC)
    if not callable(spec_func):
        return UNDEF
    spec = spec_func()
    ref = getpath(refpath, spec)

    # Check if ref has another $REF inside
    hasSubRef = False
    if isnode(ref):
        def check_subref(k, v, parent, path):
            nonlocal hasSubRef
            if v == '`$REF`':
                hasSubRef = True
            return v

        walk(ref, check_subref)

    tref = clone(ref)

    cpath = slice(state.path, 0, len(state.path)-3)
    tpath = slice(state.path, 0, len(state.path)-1)
    tcur = getpath(cpath, store)
    tval = getpath(tpath, store)
    rval = UNDEF

    if not hasSubRef or tval is not UNDEF:
        # Create child state for the next level
        child_state = state.child(0, [getelem(tpath, -1)])
        child_state.path = tpath
        child_state.nodes = slice(state.nodes, 0, len(state.nodes)-1)
        child_state.parent = getelem(nodes, -2)
        child_state.val = tref

        # Inject with child state
        inject(tref, store, modify, tcur, child_state)
        rval = child_state.val
    else:
        rval = UNDEF

    # Set the value in grandparent, using setval
    state.setval(rval, 2)
    
    # Handle lists by decrementing keyI
    if islist(state.parent) and state.prior:
        state.prior.keyI -= 1

    return val


# Transform data using spec.
# Only operates on static JSON-like data.
# Arrays are treated as if they are objects with indices as keys.
def transform(
        data,
        spec,
        extra=UNDEF,
        modify=UNDEF
):
    # Clone the spec so that the clone can be modified in place as the transform result.
    spec = clone(spec)

    extraTransforms = {}
    extraData = {} if UNDEF == extra else {}
    
    if UNDEF != extra:
        for k, v in items(extra):
            if isinstance(k, str) and k.startswith(S_DS):
                extraTransforms[k] = v
            else:
                extraData[k] = v

    # Combine extra data with user data
    data_clone = merge([
        clone(extraData) if not isempty(extraData) else UNDEF,
        clone(data)
    ])

    # Top-level store used by inject
    store = {
        # The inject function recognises this special location for the root of the source data.
        # NOTE: to escape data that contains "`$FOO`" keys at the top level,
        # place that data inside a holding map: { myholder: mydata }.
        S_DTOP: data_clone,
        
        # Escape backtick (this also works inside backticks).
        '$BT': lambda state, val, current, ref, store: S_BT,
        
        # Escape dollar sign (this also works inside backticks).
        '$DS': lambda state, val, current, ref, store: S_DS,
        
        # Insert current date and time as an ISO string.
        '$WHEN': lambda state, val, current, ref, store: datetime.utcnow().isoformat(),

        '$DELETE': transform_DELETE,
        '$COPY': transform_COPY,
        '$KEY': transform_KEY,
        '$META': transform_META,
        '$MERGE': transform_MERGE,
        '$EACH': transform_EACH,
        '$PACK': transform_PACK,
        '$REF': transform_REF,

        # Custom extra transforms, if any.
        **extraTransforms,
    }

    out = inject(spec, store, modify, store)
    return out


def validate_STRING(state, _val, current, _ref, store):
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
        state.errs.append(_invalidTypeMsg(state.path, S_string, t, out, 'V1010'))
        return UNDEF


def validate_NUMBER(state, _val, current, _ref, store):
    """
    A required number value (int or float).
    """
    out = getprop(current, state.key)
    t = typify(out)

    if t != S_number:
        state.errs.append(_invalidTypeMsg(state.path, S_number, t, out, 'V1020'))
        return UNDEF
    return out


def validate_BOOLEAN(state, _val, current, _ref, store):
    """
    A required boolean value.
    """
    out = getprop(current, state.key)
    t = typify(out)

    if t != S_boolean:
        state.errs.append(_invalidTypeMsg(state.path, S_boolean, t, out, 'V1030'))
        return UNDEF
    return out


def validate_OBJECT(state, _val, current, _ref, store):
    """
    A required object (dict), contents not further validated by this step.
    """
    out = getprop(current, state.key)
    t = typify(out)

    if out is UNDEF or t != S_object:
        state.errs.append(_invalidTypeMsg(state.path, S_object, t, out, 'V1040'))
        return UNDEF
    return out


def validate_ARRAY(state, _val, current, _ref, store):
    """
    A required list, contents not further validated by this step.
    """
    out = getprop(current, state.key)
    t = typify(out)

    if t != S_array:
        state.errs.append(_invalidTypeMsg(state.path, S_array, t, out, 'V1050'))
        return UNDEF
    return out


def validate_FUNCTION(state, _val, current, _ref, store):
    """
    A required function (callable in Python).
    """
    out = getprop(current, state.key)
    t = typify(out)

    if t != S_function:
        state.errs.append(_invalidTypeMsg(state.path, S_function, t, out, 'V1060'))
        return UNDEF
    return out


def validate_ANY(state, _val, current, _ref, store):
    """
    Allow any value.
    """
    return getprop(current, state.key)


def validate_CHILD(state, _val, current, _ref, store):
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
            msg = _invalidTypeMsg(path[:-1], S_object, typify(tval), tval, 'V0220')
            state.errs.append(msg)
            return UNDEF

        # For each key in tval, clone childtm
        ckeys = keysof(tval)
        for ckey in ckeys:
            # Create a temporary state for each child key
            child_state = state.child(0, [ckey])
            child_state.key = ckey
            child_state.setval(clone(childtm))
            # Extend state.keys so the injection/validation loop processes them
            keys.append(ckey)

        # Remove the `$CHILD` from final output
        state.setval(UNDEF)
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
            msg = _invalidTypeMsg(path[:-1], S_array, typify(current), current, 'V0230')
            state.errs.append(msg)
            state.keyI = len(parent)
            return current

    
        # Clone children and reset state key index.
        # The inject child loop will now iterate over the cloned children,
        # validating them against the current list values.
        for i in range(len(current)):
            parent[i] = clone(childtm)

        del parent[len(current):]
        state.keyI = 0
        out = getprop(current,0)
        return out
            
    return UNDEF


def validate_ONE(state, _val, current, _ref, store):
    """
    Match at least one of the specified shapes.
    Syntax: ['`$ONE`', alt0, alt1, ...]
    """
    mode = state.mode
    parent = state.parent
    path = state.path
    keyI = state.keyI
    nodes = state.nodes

    # Only operate in val mode, since parent is a list.
    if S_MVAL == mode:
        if not islist(parent) or 0 != keyI:
            state.errs.append('The $ONE validator at field ' +
                            pathify(state.path, 1, 1) +
                            ' must be the first element of an array.')
            return None
            
        state.keyI = len(state.keys)
        
        # Clean up structure, replacing [$ONE, ...] with current
        grandparent = state.setval(current, 2)
        
        state.path = state.path[:-1]
        state.key = state.path[-1]
        
        tvals = parent[1:]
        if 0 == len(tvals):
            state.errs.append('The $ONE validator at field ' +
                            pathify(state.path, 1, 1) +
                            ' must have at least one argument.')
            return None
            
        # See if we can find a match.
        for tval in tvals:
            # If match, then errs.length = 0
            terrs = []
            
            vstore = {**store}
            vstore[S_DTOP] = current
            vcurrent = validate(current, tval, vstore, terrs)
            
            # Update the value in the parent structure using a temporary state
            temp_state = state.child(0, [getelem(path, -2)])
            temp_state.key = getelem(path, -2)
            temp_state.setval(vcurrent)

            # Accept current value if there was a match
            if 0 == len(terrs):
                return None
                
        # There was no match.
        valdesc = ", ".join(stringify(v) for v in tvals)
        valdesc = re.sub(r"`\$([A-Z]+)`", lambda m: m.group(1).lower(), valdesc)
        
        # If we're validating against an array spec but got a non-array value,
        # add a more specific error message
        if islist(tvals[0]) and not islist(current):
            state.errs.append(_invalidTypeMsg(
                state.path,
                S_array,
                typify(current), current, 'V0210'))
        else:
            state.errs.append(_invalidTypeMsg(
                state.path,
                (1 < len(tvals) and "one of " or "") + valdesc,
                typify(current), current, 'V0210'))


def validate_EXACT(state, _val, current, _ref, _store):
    """
    Match exactly one of the specified values.
    Syntax: ['`$EXACT`', val0, val1, ...]
    """
    mode = state.mode
    parent = state.parent
    key = state.key
    keyI = state.keyI
    path = state.path
    nodes = state.nodes

    # Only operate in val mode, since parent is a list.
    if S_MVAL == mode:
        if not islist(parent) or 0 != keyI:
            state.errs.append('The $EXACT validator at field ' +
                pathify(state.path, 1, 1) +
                ' must be the first element of an array.')
            return None

        state.keyI = len(state.keys)

        # Clean up structure, replacing [$EXACT, ...] with current
        state.setval(current, 2)
        state.path = state.path[:-1]
        state.key = state.path[-1]

        tvals = parent[1:]
        if 0 == len(tvals):
            state.errs.append('The $EXACT validator at field ' +
                pathify(state.path, 1, 1) +
                ' must have at least one argument.')
            return None

        # See if we can find an exact value match.
        currentstr = None
        for tval in tvals:
            exactmatch = tval == current

            if not exactmatch and isnode(tval):
                currentstr = stringify(current) if currentstr is None else currentstr
                tvalstr = stringify(tval)
                exactmatch = tvalstr == currentstr

            if exactmatch:
                return None

        valdesc = ", ".join(stringify(v) for v in tvals)
        valdesc = re.sub(r"`\$([A-Z]+)`", lambda m: m.group(1).lower(), valdesc)

        state.errs.append(_invalidTypeMsg(
            state.path,
            ('' if 1 < len(state.path) else 'value ') +
            'exactly equal to ' + ('' if 1 == len(tvals) else 'one of ') + valdesc,
            typify(current), current, 'V0110'))
    else:
        state.setval(UNDEF)  # Using setval instead of setprop

        
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
        state.errs.append(_invalidTypeMsg(state.path, ptype, ctype, cval, 'V0010'))
        return

    if ismap(cval):
        if not ismap(pval):
            state.errs.append(_invalidTypeMsg(state.path, ptype, ctype, cval, 'V0020'))
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
                msg = f"Unexpected keys at field {pathify(state.path,1)}: {', '.join(badkeys)}"
                state.errs.append(msg)
        else:
            # Object is open, so merge in extra keys.
            merge([pval, cval])
            if isnode(pval):
                setprop(pval,'`$OPEN`',UNDEF)

    elif islist(cval):
        if not islist(pval):
            state.errs.append(_invalidTypeMsg(state.path, ptype, ctype, cval, 'V0030'))

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
        "$EXACT": validate_EXACT,
    }

    if UNDEF != extra:
        store.update(extra)

    # A special top level value to collect errors.
    # NOTE: collecterrs paramter always wins
    store["$ERRS"] = errs
        
    out = transform(data, spec, store, _validation)

    if 0 < len(errs) and UNDEF == collecterrs:
        raise ValueError("Invalid data: " + " | ".join(errs))

    return out



# Internal utilities
# ==================


# Set state.key property of state.parent node, ensuring reference consistency
# when needed by implementation language.
def _setparentprop(state, val):
    setprop(state.parent, state.key, val)
    
    
# Update all references to target in state.nodes.
def _updateAncestors(_state, target, tkey, tval):
    # SetProp is sufficient in Python as target reference remains consistent even for lists.
    setprop(target, tkey, tval)


# Inject values from a data store into a string. Not a public utility - used by
# `inject`.  Inject are marked with `path` where path is resolved
# with getpath against the store or current (if defined)
# arguments. See `getpath`.  Custom injection handling can be
# provided by state.handler (this is used for transform functions).
# The path can also have the special syntax $NAME999 where NAME is
# upper case letters only, and 999 is any digits, which are
# discarded. This syntax specifies the name of a transform, and
# optionally allows transforms to be ordered by alphanumeric sorting.
def _injectstr(val, store, current=UNDEF, state=UNDEF):
    # Can't inject into non-strings
    full_re = re.compile(r'^`(\$[A-Z]+|[^`]+)[0-9]*`$')
    part_re = re.compile(r'`([^`]+)`')

    if not isinstance(val, str) or S_MT == val:
        return S_MT

    out = val
    
    # Pattern examples: "`a.b.c`", "`$NAME`", "`$NAME1`"
    m = full_re.match(val)
    
    # Full string of the val is an injection.
    if m:
        if UNDEF != state:
            state.full = True

        pathref = m.group(1)

        # Special escapes inside injection.
        if 3 < len(pathref):
            pathref = pathref.replace(r'$BT', S_BT).replace(r'$DS', S_DS)

        # Get the extracted path reference.
        out = getpath(pathref, store, current, state)

    else:
        
        # Check for injections within the string.
        def partial(mobj):
            ref = mobj.group(1)

            # Special escapes inside injection.
            if 3 < len(ref):
                ref = ref.replace(r'$BT', S_BT).replace(r'$DS', S_DS)
                
            if UNDEF != state:
                state.full = False

            found = getpath(ref, store, current, state)
            
            # Ensure inject value is a string.
            if UNDEF == found:
                return S_MT
                
            if isinstance(found, str):
                return found

            return json.dumps(found, separators=(',', ':'))

        out = part_re.sub(partial, val)

        # Also call the state handler on the entire string, providing the
        # option for custom injection.
        if UNDEF != state and isfunc(state.handler):
            state.full = True
            out = state.handler(state, out, current, val, store)

    return out


def _invalidTypeMsg(path, needtype, vt, v, _whence=None):
    vs = 'no value' if UNDEF == v else stringify(v)
    return (
        'Expected ' +
        (f"field {pathify(path,1)} to be " if 1 < len(path) else '') +
        f"{needtype}, but found " +
        (f"{vt}: " if UNDEF != v else '') + vs +

        # Uncomment to help debug validation errors.
        # ' [' + str(_whence) + ']' +

        '.'
    )


# Create a StructUtils class with all utility functions as attributes
class StructUtility:
    def __init__(self):
        self.clone = clone
        self.escre = escre
        self.escurl = escurl
        self.getelem = getelem
        self.getpath = getpath
        self.getprop = getprop
        self.haskey = haskey
        self.inject = inject
        self.isempty = isempty
        self.isfunc = isfunc
        self.iskey = iskey
        self.islist = islist
        self.ismap = ismap
        self.isnode = isnode
        self.items = items
        self.joinurl = joinurl
        self.keysof = keysof
        self.merge = merge
        self.pad = pad
        self.pathify = pathify
        self.setprop = setprop
        self.size = size
        self.slice = slice
        self.stringify = stringify
        self.strkey = strkey
        self.transform = transform
        self.typify = typify
        self.validate = validate
        self.walk = walk
    

__all__ = [
    'InjectState',
    'StructUtility',
    'clone',
    'escre',
    'escurl',
    'getelem',
    'getpath',
    'getprop',
    'haskey',
    'inject',
    'isempty',
    'isfunc',
    'iskey',
    'islist',
    'ismap',
    'isnode',
    'items',
    'joinurl',
    'keysof',
    'merge',
    'pad',
    'pathify',
    'setprop',
    'size',
    'slice',
    'stringify',
    'strkey',
    'transform',
    'typify',
    'validate',
    'walk',
]

