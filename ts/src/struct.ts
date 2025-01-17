

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




function transform(
  data: any,
  spec: any,
  store: any,
  modify?: ModifyInjection
) {
  const cd = clone((data || {}))
  const fullstore: FullStore<string> = {
    // ...cd,

    $DATA: cd,

    $BT: '`',

    $WHEN: () => new Date().toISOString(),

    $DELETE: ((_mode, key, _val, parent) => {
      if (null != key) {
        delete parent[key]
      }
      return undefined
    }) as FoundInjection,

    $PRINT: ((...args) => console.log('PRINT', ...args)) as FoundInjection,

    $MERGE: ((mode, key, val, parent) => {
      if ('key:pre' === mode) { return key }

      if ('key:post' === mode) {
        // console.log('MERGE', mode, key, val, 'p=', parent, path, nodes)
        if (null != key) {
          delete parent[key]
        }
        if ('' === val) {
          val = cd
        }

        // console.log('MERGE', val)

        merge([parent, ...(Array.isArray(val) ? val : [val])])
        return key
      }

      return val
    }) as FoundInjection,

    $COPY: ((mode, key, val, parent, path, nodes, current, store) => {
      if (mode.startsWith('key')) { return key }
      // console.log('COPY', key, current == store ? 'STORE' : current)
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

      // console.log('EACH', keys, parent)

      // EACH Arguments: [EACH, sercpath, child]
      const srcpath = parent[1] // Path to source data
      const child = clone(parent[2]) // Child spec

      const src = null != store ?
        null != store.$DATA ? getpath(srcpath, store.$DATA) :
          getpath(srcpath, store) :
        undefined

      // console.log('SRC', src, 'PATH', path.join('.'))
      // console.log('NODES', nodes)

      let tcurrent: any = []
      let tval: any = []

      const tkey = path[path.length - 2]
      const pkey = path[path.length - 3]
      const target = nodes[path.length - 2] || nodes[path.length - 1]

      if ('object' === typeof src) {
        // if (null != path && null != nodes) {

        // console.log('TARGET', pkey, tkey, target)

        // if ('object' === typeof src) {

        if (Array.isArray(src)) {
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

      // console.log('TVAL', tval, tcurrent)

      if (null != tkey) {
        tcurrent = { [tkey]: tcurrent }
        target[tkey] = tval
      }

      if (null != pkey) {
        tcurrent = { [pkey]: tcurrent }
      }

      // console.log('EACH inject before',
      // keyI,
      //   keys,
      //   pkey,
      //   tkey,
      //   tval,
      //   path.slice(0, path.length - 1).join('.'),
      //   // nodes[path.length - 3],
      //   tcurrent)

      // console.log('TCUR', tcurrent)

      tval = inject(
        tval,
        store,
        modify,
        -1, // keyI,
        undefined, // keys,
        tkey,
        nodes[path.length - 3],
        path.slice(0, path.length - 1),
        nodes.slice(0, path.length - 1),
        tcurrent,
      )

      // console.log('TVAL-B', tkey, tval)

      if (null != tkey) {
        target[tkey] = tval
      }
      else {
        // console.log('TARGET-A', target)
        tval.map((n: any, i: number) => (target as any)[i] = n)
        // console.log('TARGET-B', target)

        target.length = tval.length
        // console.log('TARGET-C', target)
      }

      // console.log('DONE', mode, tkey, target, nodes)


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

      // const pkey = 4 < path.length ? path[path.length - 3] : undefined
      const pkey = path[path.length - 3]
      // console.log('****** PACK', tkey, pkey, 'p=', path.join('.'))

      const target = nodes[path.length - 2] || nodes[path.length - 1]
      // console.log('NODES', nodes)
      // const target = nodes[path.length - 1]

      let src = null != store ?
        null != store.$DATA ? getpath(srcpath, store.$DATA) :
          getpath(srcpath, store) :
        undefined

      // console.log('PACK ARGS', key, path, target)
      // console.log('PACK', path.join('.'), srcpath, 's=', src)

      // TODO: also accept objects
      src = Array.isArray(src) ? src :
        'object' === typeof src ? Object.entries(src)
          .reduce((a: any[], n: any) =>
            (n[1]['`$META`'] = { KEY: n[0] }, a.push(n[1]), a), []) :
          undefined

      if (null == src) {
        return undefined
      }

      // if (Array.isArray(src)) {

      // console.log('SRC', src)

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

      // console.log('T', tval, tcurrent)

      if (null != tkey) {
        tcurrent = { [tkey]: tcurrent }
      }

      if (null != pkey) {
        tcurrent = { [pkey]: tcurrent }
      }


      // console.log('PACK TARGET', tkey, tval, path, tcurrent)

      // console.log('PACK INJECT', path.join('.'), tval, tcurrent)
      tval = inject(
        tval,
        store,
        modify,
        -1, // keyI,
        undefined, // keys,
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
      // console.log('META',mode,key,val,parent,path)
      delete parent['`$META`']
      return undefined
    }) as FoundInjection,

    ...(store || {})
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
  const mark = ('' + Math.random()).substring(2, 8)
  // console.log('INJECT-START', mark, path?.join('.'), keyI, val, nodes)

  //  'v=', val,
  // 'p=', path, 'sk=', path?.[path.length - 2], 'n=', nodes, 's=', !!store, 'c=', current
  // )
  const valtype = typeof val
  path = null == path ? [] : path

  // if (null == key) {
  // if (null == current) {
  if (null == keyI) {
    key = '$TOP'
    path = []
    current = (null != store.$DATA ? store.$DATA : store)
    nodes = []
  }
  else {

    // const parentkey = 2 < path.length ? path[path.length - 2] : undefined
    const parentkey = path[path.length - 2]

    // console.log('INJECT', path.join('.'), parentkey, key, 'c=', store === current ? 'STORE' : current)
    current = null == current ? (null != store.$DATA ? store.$DATA : store) : current
    current = null == parentkey ? current : current[parentkey]

  }

  // console.log('INJECT-NODES', mark, path?.join('.'), nodes)

  // const origkey = key

  if (null != val && 'object' === valtype) {
    // console.log('INJECT-KEYS-A', mark, path?.join('.'), val, nodes)

    const origkeys = [
      ...Object.keys(val).filter(k => !k.includes('$')),
      ...Object.keys(val).filter(k => k.includes('$')).sort(),
    ]

    // for (let origkey of origkeys) {
    for (let okI = 0; okI < origkeys.length; okI++) {
      const origkey = origkeys[okI]
      // console.log('ORIGKEY', origkey, typeof origkey)

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

      // console.log('PREKEY', prekey, typeof prekey, 'ok=', origkey)

      // console.log('INJECT-KEYS-B', mark, path?.join('.'), val, nodes)

      if ('string' === typeof prekey) {
        let child = val[prekey]
        let childpath = [...(path || []), prekey]
        let childnodes = [...(nodes || []), val]
        // console.log('CHILD', path?.join('.'), child, prekey, current, childpath.join('.'), childnodes)
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

        // console.log('INJECT-KEYS-C', mark, path?.join('.'), val, nodes)
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

    // console.log('INJECT-KEYS-D', mark, path?.join('.'), val, nodes)
  }

  else if ('string' === valtype) {
    // console.log('VAL-INJECTION', key, val, path.join('.'), 'pk=', parentkey,
    // 'c=', current == store ? 'STORE' : current)

    // console.log('INJECT-VAL-A', mark, val, nodes)
    const newval = injection(
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
    // console.log('INJECT-VAL-B', mark, val, nodes)

    if (modify) {
      modify(key, val, newval, parent, path, nodes, current, store, keyI, keys)
    }
  }

  // console.log('INJECT-END', mark, path?.join('.'), val, nodes)

  return val
}




function injection(
  mode: InjectionMode,
  key: string | undefined,
  // key: string,
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
  if ('val' === mode) {
    // console.log('INJECTION', mode, key, val, path?.join('.'), 'C=', current == store ? 'STORE' : current)
  }

  const find = (_full: string, mpath: string) => {
    mpath = mpath.replace(/^\$[\d]+/, '$')

    let found: FoundInjection = 'string' === typeof mpath ?
      mpath.startsWith('.') ?
        getpath(mpath.substring(1), current) :
        (getpath(mpath, store)) :
      undefined

    found =
      (undefined === found && null != store.$DATA) ? getpath(mpath, store.$DATA) : found

    // console.log('FINDER', mpath, found)

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


  // console.log('ORIG', orig)


  const m = orig.match(/^`([^`]+)`$/)
  // console.log('M', mode, key, m)

  if (m) {
    res = find(m[0], m[1])
  }
  else {
    res = orig.replace(/`([^`]+)`/g, find)
  }

  // console.log('FIND', mode, key, val, 'f=', orig, res, 'p=', parent)

  // console.log('RES-SET', mode, orig, key, typeof key, res, parent)

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

  // console.log('RES-END', mode, orig, key, typeof key, res, parent)
  return res
}


function clone(val: any) {
  return undefined === val ? undefined : JSON.parse(JSON.stringify(val))
}


function merge(objs: any[]): any {
  let out: any = undefined
  if (null == objs || !Array.isArray(objs)) {
    return objs
  }
  else if (1 === objs.length) {
    return objs[0]
  }
  else if (1 < objs.length) {
    out = objs[0] || {}
    for (let oI = 1; oI < objs.length; oI++) {
      let obj = objs[oI]
      if (null != obj && 'object' === typeof obj) {
        let cur = [out]
        let cI = 0
        walk(obj, (key, val, parent, path) => {
          if (null != key) {
            cI = path.length - 1
            cur[cI] = cur[cI] || getpath(path.slice(0, path.length - 1), out)

            if (null == cur[cI] || 'object' !== typeof cur[cI]) {
              cur[cI] = (Array.isArray(parent) ? [] : {})
            }

            if (null != val && 'object' === typeof val) {
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

  const parts = Array.isArray(path) ? path : path.split('.')
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
  const valtype = typeof val

  if (null != val && 'object' === valtype) {
    for (let k in val) {
      val[k] = walk(val[k], apply, k, val, [...(path || []), k])
    }
  }

  return apply(key, val, parent, path || [])
}



export {
  getpath,
  inject,
  merge,
  transform,
  walk,
}
