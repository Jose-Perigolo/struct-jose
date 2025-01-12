


def merge(objs):
    """
    Merges a list of objects deeply, handling nested structures.

    :param objs: List of objects to merge
    :return: A merged object
    """
    out = None

    if len(objs) == 1:
        return objs[0]
    
    elif len(objs) > 1:
        out = objs[0] or {}

        for obj_index in range(1, len(objs)):
            obj = objs[obj_index]

            if obj is not None and isinstance(obj, dict):
                current = [out]
                current_index = 0

                def walker(key, val, parent, path):
                    nonlocal current, current_index

                    if key is not None:
                        current_index = len(path) - 1
                        
                        # Ensure current has enough elements
                        while len(current) <= current_index:
                            current.append(None)

                        # Get or build the path
                        current[current_index] = (
                            current[current_index] or
                            getpath(path[:-1], out)
                        )

                        if current[current_index] is None or not isinstance(current[current_index], dict):
                            current[current_index] = [] if isinstance(parent, list) else {}

                        is_val_object = val is not None and isinstance(val, dict)

                        if is_val_object and key is not None:
                            current[current_index][key] = current[current_index + 1]
                            while len(current) <= current_index + 1:
                                current.append(None)
                            current[current_index + 1] = None
                        else:
                            current[current_index][key] = val

                    return val

                walk(obj, walker)

    return out


def getpath(path, store, build=False):
    """
    Retrieves or builds a nested path in a dictionary or list.

    :param path: List or dot-separated string representing the path
    :param store: The dictionary or list to traverse
    :param build: Whether to build missing parts of the path
    :return: The value at the path or None
    """
    if path is None or path == '':
        return store

    parts = path if isinstance(path, list) else path.split('.')
    val = store

    for index, part in enumerate(parts):
        nval = val.get(part) if isinstance(val, dict) else None

        if nval is None:
            if build and index < len(parts) - 1:
                nval = val[part] = [] if parts[index + 1].isdigit() else {}
            else:
                return None

        val = nval

    return val


def walk(val, apply, key=None, parent=None, path=None):
    """
    Walks through a dictionary or list and applies a function at each node.

    :param val: The current value
    :param apply: Function to apply (key, value, parent, path)
    :param key: The current key
    :param parent: The parent container
    :param path: The path to the current value
    :return: The result of the apply function
    """
    valtype = type(val)

    if val is not None and isinstance(val, (dict, list)):
        for k, v in (val.items() if isinstance(val, dict) else enumerate(val)):
            val[k] = walk(v, apply, k, val, (path or []) + [str(k)])

    return apply(key, val, parent, path or [])
