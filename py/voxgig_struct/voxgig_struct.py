


def merge(objs):
    # print("objs ", repr(objs))

    if not isinstance(objs, list):
        return objs

    out = None

    if len(objs) == 1:
        return objs[0]
    elif len(objs) > 1:
        out = objs[0] or {}

        for obj in objs[1:]:
            if obj is not None and isinstance(obj, (dict, list)):
                cur = [out]

                def walker(key, val, parent, path):
                    # print("WALK", repr(key), repr(val), repr(cur))

                    if key is not None:
                        cI = len(path) - 1

                        if len(cur) <= cI:
                            cur.extend([None] * (1+cI-len(cur)))

                        if cur[cI] is None:
                            cur[cI] = getpath(path[:-1], out)
                        
                        if cur[cI] is None or not isinstance(cur[cI], (dict, list)):
                            cur[cI] = [] if isinstance(parent, list) else {}

                        if( isinstance(cur[cI], list) and
                            isinstance(key, int) and
                            len(cur[cI]) <= key
                           ):
                            cur[cI].extend([None] * (1+key-len(cur[cI])))
                            
                        if val is not None and isinstance(val, (dict,list)):
                            cur[cI][key] = cur[cI + 1]
                            cur[cI + 1] = None
                        else:
                            cur[cI][key] = val

                walk(obj, walker)

    return out


def getpath(path, store):
    if path is None or store is None or path == '':
        return store

    parts = path if isinstance(path, list) else path.split('.')
    val = None

    if len(parts) > 0:
        val = store
        for part in parts:
            if isinstance(val, dict):
                val = val.get(part)
            elif isinstance(val, list):
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


# Walk a data strcture depth first.
def walk(val, apply, key=None, parent=None, path=None):
    valtype = type(val)

    if val is not None and isinstance(val, (dict, list)):
        for k, v in (val.items() if isinstance(val, dict) else enumerate(val)):
            val[k] = walk(v, apply, k, val, (path or []) + [str(k)])

    return apply(key, val, parent, path or [])
