
from typing import *
import json
import re


def isnode(val: Any) -> bool:
    return ismap(val) or islist(val)

def ismap(val: Any) -> bool:
    return isinstance(val, dict)

def islist(val: Any) -> bool:
    return isinstance(val, list)

def items(val: Any) -> list:
    if ismap(val):
        return [(i, n) for i, n in val.items()] 
    elif islist(val):
        return [(i, n) for i, n in enumerate(val)]
    else:
        return []

def clone(val: Any) -> Any:
    return None if val is None else copy.deepcopy(val)


def getpath(path: Union[str, list[str]], store: dict) -> Any:
    if path is None or store is None or path == '':
        return store

    if islist(path):
        parts = path
    elif isinstance(path, str):
        parts = path.split('.')
    else:
        parts = []

    val = None

    if 0 < len(parts):
        val = store
        for part in parts:
            if ismap(val):
                val = val.get(part)
            elif islist(val):
                try:
                    index = int(part)
                    val = val[index]
                except (ValueError, IndexError):
                    val = None
                    break
            else:
                val = None
                break

            if val is None:
                break

    return val


def inject(
    val,
    store,
    modify=None,
    keyI=None,
    keys=None,
    key=None,
    parent=None,
    path=None,
    nodes=None,
    current=None
):
    valtype = type(val)
    path = [] if path is None else path

    if keyI is None:
        key = '$TOP'
        path = []
        current = store.get('$DATA', store) if isinstance(store,dict) else store
        nodes = []
        parent = {key: val}
    else:
        parentkey = path[-2] if len(path) > 1 else None
        current = store.get('$DATA', store) if current is None else current
        current = current if parentkey is None else current[parentkey]

    if val is not None and (isinstance(val, dict) or isinstance(val, list)):
        if isinstance(val, dict):
            origkeys = sorted(
                [k for k in val.keys() if '$' not in k] +
                [k for k in val.keys() if '$' in k]
            )
        elif isinstance(val, list):
            origkeys = list(range(len(val)))  # List of indices for lists

        for okI, origkey in enumerate(origkeys):
            prekey = injection(
                'key:pre',
                origkey,
                val[origkey],
                val,
                path + [origkey],
                (nodes or []) + [val],
                current,
                store,
                okI,
                origkeys,
                modify
            )

            if isinstance(prekey, str):
                child = val[prekey]
                childpath = path + [prekey]
                childnodes = (nodes or []) + [val]

                inject(
                    child,
                    store,
                    modify,
                    okI,
                    origkeys,
                    prekey,
                    val,
                    childpath,
                    childnodes,
                    current
                )

            injection(
                'key:post',
                origkey if prekey is None else prekey,
                val.get(prekey),
                val,
                path,
                nodes,
                current,
                store,
                okI,
                origkeys,
                modify
            )

    elif isinstance(val, str):
        newval = injection(
            'val',
            key,
            val,
            parent,
            path,
            nodes,
            current,
            store,
            keyI,
            keys,
            modify
        )

        if modify:
            newval = modify(key, val, newval, parent, path, nodes, current, store, keyI, keys)

        val = newval

    return val


def injection(
    mode,
    key,
    val,
    parent,
    path,
    nodes,
    current,
    store,
    keyI,
    keys,
    modify
):
    def find(_full, mpath):
        mpath = re.sub(r'^\$[\d]+', '$', mpath)

        found = None
        if isinstance(mpath, str):
            if mpath.startswith('.'):
                found = getpath(mpath[1:], current)
            else:
                found = getpath(mpath, store)

        if found is None and store.get('$DATA') is not None:
            found = getpath(mpath, store['$DATA'])

        if callable(found):
            found = found(
                mode, key, val, parent, path, nodes,
                current, store, keyI, keys, mpath, modify
            )

        print('FOUND', mpath, found)
            
        return found

    iskeymode = mode.startswith('key')
    orig = key if iskeymode else val
    res = None

    m = re.match(r'^`([^`]+)`$', orig) if isinstance(orig, str) else None

    print('MATCH', orig, m)
    
    if m:
        res = find(m.group(0), m.group(1))
    elif isinstance(orig, str):
        res = re.sub(r'`([^`]+)`', lambda m: find(m.group(0), m.group(1)), orig)

    if parent is not None:
        if iskeymode:
            if key != res and isinstance(res, str):
                if isinstance(key, str):
                    parent[res] = parent[key]
                    del parent[key]
                key = res

        if mode == 'val' and isinstance(key, str):
            if res is None:
                if orig != '`$EACH`':
                    parent.pop(key, None)
            else:
                parent[key] = res

    return res



def merge(objs):
    if not isinstance(objs, list):
        return objs

    out = None

    if len(objs) == 1:
        return objs[0]
    elif len(objs) > 1:
        out = objs[0] or {}

        for obj in objs[1:]:
            if isnode(obj):
                cur = [out]

                def walker(key, val, parent, path):
                    if key is not None:
                        cI = len(path) - 1

                        if len(cur) <= cI:
                            cur.extend([None] * (1+cI-len(cur)))

                        if cur[cI] is None:
                            cur[cI] = getpath(path[:-1], out)
                        
                        if not isnode(cur[cI]):
                            cur[cI] = [] if isinstance(parent, list) else {}

                            # if( isinstance(cur[cI], list) and
                            if( islist(cur[cI]) and
                                isinstance(key, int) and
                                len(cur[cI]) <= key
                            ):
                                cur[cI].extend([None] * (1+key-len(cur[cI])))
                            
                        if isnode(val):
                            cur[cI][key] = cur[cI + 1]
                            cur[cI + 1] = None
                        else:
                            cur[cI][key] = val

                walk(obj, walker)

    return out


# Walk a data strcture depth first.
def walk(
    val: Any,
    apply: Callable[[Optional[Union[str, int]], Any, Optional[Any], List[str]], Any],
    key: Optional[Union[str, int]] = None,
    parent: Optional[Any] = None,
    path: Optional[List[str]] = None
) -> Any:
    if isnode(val):
        for ckey, child in items(val):
            val[ckey] = walk(child, apply, ckey, val, (path or []) + [str(ckey)])

    return apply(key, val, parent, path or [])
