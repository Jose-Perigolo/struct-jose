

type InjectionMode = 'key:pre' | 'key:post' | 'val'

type FoundInjection = (
  mode: InjectionMode,
  key: string | undefined,
  val: any,
  parent: any,
  path: string[] | undefined,
  nodes: any[] | undefined,
  current: any,
  store: Record<string, any> | undefined,
  keyI: number | undefined,
  keys: string[] | undefined,
  mpath: string | undefined,
  modify: ModifyInjection | undefined
) => any


type ModifyInjection = (
  key: string | undefined,
  val: any,
  newval: any,
  parent: any,
  path: string[] | undefined,
  nodes: any[] | undefined,
  current: any,
  store: any,
  keyI: number | undefined,
  keys: string[] | undefined,
) => void

type FullStore<T extends string> = {
  [K in T]: K extends `$${string}` ? FoundInjection : any;
};



// Transform data using spec.
// Only operates on static JSONifiable data.
// Array are treated as if they are objects with indices as keys.
function transform(
  data: any, // Source data to transform into new data (original not mutated)
  spec: any, // Transform specification; output follows this shape
  extra: any, // Additional store of data
  modify?: ModifyInjection // Optionally modify individual values.
) {
  const dataClone = merge([clone(extra || {}), clone(data || {})])

  // Define a top level store that provides transform operations.
  const fullstore: FullStore<string> = {

    // Source data.
    $DATA: dataClone,

    // Escape backtick,
    $BT: '`',

    // Insert current date and time as an ISO string.
    $WHEN: () => new Date().toISOString(),

    // Delete a key-value pair.
    $DELETE: ((_mode, key, _val, parent) => {
      if (null != key) {
        delete parent[key]
      }
      return undefined
    }) as FoundInjection,


    // Merge a list of objects into the current object. 
    // Must be a key in an object. The value is merged over the current object.
    // If the value is an array, the elements are first merged using `merge`. 
    // If the value is the empty string, merge the top level store.
    $MERGE: ((mode, key, val, parent) => {
      if ('key:pre' === mode) { return key }

      // Operate after child values have been transformed.
      if ('key:post' === mode) {

        // Remove self from parent.
        if (null != key) {
          delete parent[key]
        }

        if ('' === val) {
          val = dataClone
        }

        merge([parent, ...(Array.isArray(val) ? val : [val])])

        return key
      }

      return undefined
    }) as FoundInjection,

    $COPY: ((mode, key, val, parent, path, nodes, current, store) => {
      if (mode.startsWith('key')) { return key }
      return null != current && null != key ? current[key] : undefined
    }) as FoundInjection,


    $EACH: ((mode, _key, _val, parent, path, nodes, _current, store, keyI, keys, _mpath, modify) => {
      // Remove arguments to avoid spurious processing.
      if (keys) {
        keys.length = 1
      }

      // Defensive context checks.
      if ('val' !== mode || null == path || null == nodes) {
        return undefined
      }

      const srcpath = parent[1] // Path to source data
      const child = clone(parent[2]) // Child spec

      const src = null != store ?
        null != store.$DATA ? getpath(srcpath, store.$DATA) :
          getpath(srcpath, store) :
        undefined

      let tcurrent: any = []
      let tval: any = []

      const tkey = path[path.length - 2]
      const pkey = path[path.length - 3]
      const target = nodes[path.length - 2] || nodes[path.length - 1]

      if (isnode(src)) {

        if (islist(src)) {
          tval = src.map(() => clone(child))
        }
        else {
          tval = Object.entries(src).map(n => ({
            ...clone(child),
            '`$META`': { KEY: n[0] }
          }))
        }

        tcurrent = Object.values(src)
      }

      if (null != tkey) {
        tcurrent = { [tkey]: tcurrent }
        target[tkey] = tval
      }

      if (null != pkey) {
        tcurrent = { [pkey]: tcurrent }
      }

      tval = inject(
        tval,
        store,
        modify,
        -1,
        undefined,
        tkey,
        nodes[path.length - 3],
        path.slice(0, path.length - 1),
        nodes.slice(0, path.length - 1),
        tcurrent,
      )

      if (null != tkey) {
        target[tkey] = tval
      }
      else {
        tval.map((n: any, i: number) => (target as any)[i] = n)
        target.length = tval.length
      }

      return undefined
    }) as FoundInjection,


    $PACK: ((mode, key, val, parent, path, nodes, _current, store, keyI, keys, _mpath, modify) => {

      if ('key:pre' !== mode || 'string' !== typeof key || null == path || null == nodes) {
        return undefined
      }

      const args = parent[key]
      const srcpath = args[0]
      const child = clone(args[1])

      const keyprop = child['`$KEY`']
      const tkey = path[path.length - 2]
      const pkey = path[path.length - 3]
      const target = nodes[path.length - 2] || nodes[path.length - 1]

      let src = null != store ?
        null != store.$DATA ? getpath(srcpath, store.$DATA) :
          getpath(srcpath, store) :
        undefined

      src = islist(src) ? src :
        ismap(src) ? Object.entries(src)
          .reduce((a: any[], n: any) =>
            (n[1]['`$META`'] = { KEY: n[0] }, a.push(n[1]), a), []) :
          undefined

      if (null == src) {
        return undefined
      }

      let tval = src.reduce((a: any, n: any) => {
        let kn = null == child['`$KEY`'] ? n[keyprop] : n[child['`$KEY`']]
        a[kn] = {
          ...clone(child),
        }

        if (null != n['`$META`']) {
          a[kn]['`$META`'] = n['`$META`']
        }

        return a
      }, {})

      let tcurrent = src.reduce((a: any, n: any) => {
        let kn = null == child['`$KEY`'] ? n[keyprop] : n[child['`$KEY`']]
        a[kn] = n
        return a
      }, {})

      if (null != tkey) {
        tcurrent = { [tkey]: tcurrent }
      }

      if (null != pkey) {
        tcurrent = { [pkey]: tcurrent }
      }

      tval = inject(
        tval,
        store,
        modify,
        -1,
        undefined,
        tkey,
        nodes[path.length - 3],
        path.slice(0, path.length - 1),
        nodes.slice(0, path.length - 1),
        tcurrent,
      )

      // console.log('PACK TARGET', tkey, target, tval)
      if (null != tkey) {
        target[tkey] = tval
      }
      else {
        delete target[key]
        Object.assign(target, tval)
      }

      return undefined
    }) as FoundInjection,


    $KEY: ((mode, _key, _val, parent, path) => {
      if ('key:pre' === mode) {
        delete parent['`$KEY`']
        return undefined
      }
      else if ('key:post' === mode) {
        return undefined
      }

      const meta = parent['`$META`']
      return null != meta ? meta.KEY : null != path ? path[path.length - 2] : undefined
    }) as FoundInjection,

    $META: ((_mode, _key, _val, parent) => {
      delete parent['`$META`']
      return undefined
    }) as FoundInjection,
  }

  const out = inject(spec, fullstore, modify)
  return out
}


function inject(
  //  These arguments are the public interface.
  val: any,
  store: any,
  modify?: ModifyInjection | undefined,

  // These arguments are for recursive calls.
  keyI?: number,
  keys?: string[],
  key?: string,
  parent?: any,
  path?: string[],
  nodes?: any[],
  current?: any // Current store node
) {
  const valtype = typeof val
  path = null == path ? [] : path

  if (null == keyI) {
    key = '$TOP'
    path = []
    current = (null != store.$DATA ? store.$DATA : store)
    nodes = []
    parent = { [key]: val }
  }
  else {
    const parentkey = path[path.length - 2]

    current = null == current ? (null != store.$DATA ? store.$DATA : store) : current
    current = null == parentkey ? current : current[parentkey]
  }

  if (isnode(val)) {
    const origkeys = [
      ...Object.keys(val).filter(k => !k.includes('$')),
      ...Object.keys(val).filter(k => k.includes('$')).sort(),
    ]

    for (let okI = 0; okI < origkeys.length; okI++) {
      const origkey = origkeys[okI]

      let prekey = injection(
        'key:pre',
        origkey,
        val[origkey],
        val,
        [...(path || []), origkey],
        [...(nodes || []), val],
        current,
        store,
        okI,
        origkeys,
        modify
      )

      if ('string' === typeof prekey) {
        let child = val[prekey]
        let childpath = [...(path || []), prekey]
        let childnodes = [...(nodes || []), val]

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
      }

      injection(
        'key:post',
        undefined == prekey ? origkey : prekey,
        val[prekey],
        val,
        path,
        nodes,
        current,
        store,
        okI,
        origkeys,
        modify
      )
    }
  }

  else if ('string' === valtype) {
    let newval = injection(
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

    if (modify) {
      newval = modify(key, val, newval, parent, path, nodes, current, store, keyI, keys)
    }

    val = newval
  }

  return val
}


function injection(
  mode: InjectionMode,
  key: string | undefined,
  val: any,
  parent: any,
  path: string[] | undefined,
  nodes: any[] | undefined,
  current: any | undefined,
  store: any | undefined,
  keyI: number | undefined,
  keys: string[] | undefined,
  modify: ModifyInjection | undefined
) {
  const find = (_full: string, mpath: string) => {
    mpath = mpath.replace(/^\$[\d]+/, '$')

    let found: FoundInjection = 'string' === typeof mpath ?
      mpath.startsWith('.') ?
        getpath(mpath.substring(1), current) :
        (getpath(mpath, store)) :
      undefined

    found =
      (undefined === found && null != store.$DATA) ? getpath(mpath, store.$DATA) : found

    if ('function' === typeof found) {
      found = found(
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
        mpath,
        modify
      )
    }

    return found
  }

  const iskeymode = mode.startsWith('key')
  const orig = iskeymode ? key : val
  let res

  const m = orig.match(/^`([^`]+)`$/)

  if (m) {
    res = find(m[0], m[1])
  }
  else {
    res = orig.replace(/`([^`]+)`/g, find)
  }

  if (null != parent) {
    if (iskeymode) {
      //res = null == res ? orig : res

      if (key !== res && 'string' === typeof res) {
        if ('string' === typeof key) {
          parent[res] = parent[key]
          delete parent[key]
        }

        key = res
      }
    }

    if ('val' === mode && 'string' === typeof key) {
      if (undefined === res) {
        if (orig !== '`$EACH`') {
          delete parent[key]
        }
      }
      else {
        parent[key] = res
      }
    }
  }

  return res
}


function isnode(val: any) {
  return null != val && 'object' == typeof val
}

function ismap(val: any) {
  return null != val && 'object' == typeof val && !Array.isArray(val)
}

function islist(val: any) {
  return Array.isArray(val)
}

function items(val: any) {
  return ismap(val) ? Object.entries(val) :
    islist(val) ? val.map((n: any, i: number) => [i, n]) :
      []
}

function clone(val: any) {
  return undefined === val ? undefined : JSON.parse(JSON.stringify(val))
}


function merge(objs: any[]): any {
  let out: any = undefined

  if (!islist(objs)) {
    return objs
  }
  else if (1 === objs.length) {
    return objs[0]
  }
  else if (1 < objs.length) {
    out = objs[0] || {}
    for (let oI = 1; oI < objs.length; oI++) {
      let obj = objs[oI]

      if (isnode(obj)) {
        let cur = [out]
        let cI = 0
        walk(obj, (key, val, parent, path) => {
          if (null != key) {
            cI = path.length - 1
            cur[cI] = cur[cI] || getpath(path.slice(0, path.length - 1), out)

            if (null == cur[cI] || 'object' !== typeof cur[cI]) {
              cur[cI] = islist(parent) ? [] : {}
            }

            if (isnode(val)) {
              cur[cI][key] = cur[cI + 1]
              cur[cI + 1] = undefined
            }
            else {
              cur[cI][key] = val
            }
          }

          return val
        })
      }
    }
  }
  return out
}


function getpath(path: string | string[], store: Record<string, any>) {
  if (null == path || null == store || '' === path) {
    return store
  }

  const parts = islist(path) ? path : 'string' === typeof path ? path.split('.') : []
  let val = undefined

  if (0 < parts.length) {
    val = store
    for (let pI = 0; pI < parts.length; pI++) {
      const part = parts[pI]
      val = val[part]
      if (null == val) {
        break
      }
    }
  }

  return val
}


type WalkApply = (key: string | undefined, val: any, parent: any, path: string[]) => any

// Walk a data strcture depth first.
function walk(val: any, apply: WalkApply, key?: string, parent?: any, path?: string[]): any {
  if (isnode(val)) {
    for (let [ckey, child] of items(val)) {
      val[ckey] = walk(child, apply, ckey, val, [...(path || []), ckey])
    }
  }

  return apply(key, val, parent, path || [])
}



export {
  clone,
  isnode,
  ismap,
  islist,
  items,

  getpath,
  inject,
  merge,
  transform,
  walk,
}
