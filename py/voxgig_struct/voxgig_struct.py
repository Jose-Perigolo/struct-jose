
from typing import *
import json
import re


def isnode(val: Any) -> bool:
    return ismap(val) or islist(val)


def ismap(val: Any) -> bool:
    return isinstance(val, dict)


def islist(val: Any) -> bool:
    return isinstance(val, list)


def iskey(key):
    return ((isinstance(key, str) and key != "")
            or isinstance(key, int))


def items(val: Any) -> list:
    if ismap(val):
        return [(i, n) for i, n in val.items()] 
    elif islist(val):
        return [(i, n) for i, n in enumerate(val)]
    else:
        return []

    
def getprop(val: Any, key: Any, alt: Any = None) -> Any:
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
    if iskey(key):
        if ismap(parent):
            if val is not None:
                parent[str(key)] = val
            else:
                try:
                    del parent[str(key)]
                except:
                    pass

        elif islist(parent):
            try:
                keyI = int(key)
            except ValError:
                keyI = None

            if keyI is not None and 0 <= keyI <= len(parent):
                if val is None and keyI < parent.length:
                    for pI in range(keyI, len(parent) - 1):
                        parent[pI] = parent[pI + 1]
                    parent.pop()

                elif keyI == len(parent):
                    parent.append(val)
                else:
                    parent[keyI] = val
    return parent


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
    # These arguments are the public interface.
    val,
    store,
    modify=None,

    # These arguments are for recursive calls.
    keyI=None,
    keys=None,
    key=None,
    parent=None,
    path=None,
    nodes=None,
    current=None
):
    # valtype = type(val)
    path = [] if path is None else path

    if keyI is None:
        key = '$TOP'
        path = []
        current = prop(store, '$DATA', store)
        nodes = []
        parent = {key: val}
    else:
        parentkey = path[-2] if len(path) > 1 else None
        current = prop(store, '$DATA', store) if current is None else current
        current = current if parentkey is None else current[parentkey]

    if isnode(val):
        if ismap(val):
            origkeys = sorted(
                [k for k in val.keys() if '$' not in k] +
                [k for k in val.keys() if '$' in k]
            )
        elif islist(val):
            origkeys = list(range(len(val)))

        print('ORIGKEYS', origkeys, val)
            
        for okI, origkey in enumerate(origkeys):
            prekey = injection(
                'key:pre',
                origkey,
                prop(val, origkey),
                val,
                path + [origkey],
                (nodes or []) + [val],
                current,
                store,
                okI,
                origkeys,
                modify
            )

            print('PREKEY', origkey, type(origkey), prekey, type(prekey), val, prop(val, prekey))
            
            # if isinstance(prekey, str):
            if prekey is not None:
                child = prop(val, prekey)
                childpath = path + [prekey]
                childnodes = (nodes or []) + [val]

                print('CHILD', child)
                
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
                prop(val, prekey),
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
                found = getpath(mpath, prop(store, '$DATA', store))

            # if found is None and prop(store,'$DATA') is not None:
            # found = getpath(mpath, store['$DATA'])

        if callable(found):
            found = found(
                mode, key, val, parent, path, nodes,
                current, store, keyI, keys, mpath, modify
            )

        print('FOUND', mpath, found)
            
        return found

    iskeymode = mode.startswith('key')
    if iskeymode and isinstance(key, int):
        return key
    
    orig = str(key if iskeymode else val)
    res = None

    m = re.match(r'^`([^`]+)`$', orig) if isinstance(orig, str) else None

    print('MATCH', mode, orig, type(orig), m)
    
    if m:
        res = find(m.group(0), m.group(1))
    elif isinstance(orig, str):
        res = re.sub(r'`([^`]+)`', lambda m: find(m.group(0), m.group(1)), orig)

    if parent is not None:
        if iskeymode:
            if key != res and isinstance(res, str):
                pval = prop(parent, key)
                if key is not None and pval is not None:
                    parent[int(res) if islist(parent) else res] = pval
                    if pval is not None:
                        del parent[int(key) if islist(parent) else key]
                key = res

        if mode == 'val' and isinstance(key, str):
            if res is None:
                if orig != '`$EACH`':
                    parent.pop(key, None)
            else:
                parent[int(key) if islist(parent) else key] = res

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
                            cur[cI] = [] if islist(parent) else {}

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
