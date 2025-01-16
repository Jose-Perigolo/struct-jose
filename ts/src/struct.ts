

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
    ...cd,

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
          val = data
        }
        merge([parent, ...(Array.isArray(val) ? val : [val])])
        return key
      }

      return val
    }) as FoundInjection,

    $COPY: ((mode, key, val, parent, path, nodes, current, store) => {
      if (mode.startsWith('key')) { return key }
      console.log('COPY', key, current == store ? 'STORE' : current)
      return null != current && null != key ? current[key] : undefined
    }) as FoundInjection,


    $EACH: ((mode, _key, _val, parent, path, nodes, _current, store, keyI, keys, _mpath, modify) => {
      if ('val' === mode) {

        // Remove arguments to avoid spurious processing
        if (keys) {
          keys.length = 1
        }

        const src = getpath(parent[1], store || {})

        if (null != path && null != nodes) {
          const tkey = path[path.length - 2]
          const pkey = path[path.length - 3]

          let target = nodes[path.length - 2]

          if ('object' === typeof src) {
            let tval

            if (Array.isArray(src)) {
              tval = src.map(() => clone(parent[2]))
            }
            else {
              tval = Object.entries(src).map(n => ({
                ...clone(parent[2]),
                '`$META`': { KEY: n[0] }
              }))
            }

            let tcurrent

            target[tkey] = tval
            tcurrent = { [tkey]: Object.values(src) }
            if (null != pkey) {
              tcurrent = { [pkey]: tcurrent }
            }

            console.log('EACH inject before',
              keyI,
              keys,
              pkey,
              tkey,
              tval,
              path.slice(0, path.length - 1).join('.'),
              // nodes[path.length - 3],
              tcurrent)

            tval = inject(
              tval,
              store,
              modify,
              keyI,
              keys,
              tkey,
              nodes[path.length - 3],
              path.slice(0, path.length - 1),
              nodes.slice(0, path.length - 1),
              tcurrent,
            )

            console.log('EACH inject after', tkey, tval, 'T=', target)

            // if (null != tkey) {
            target[tkey] = tval
            // }
            // else {
            //   tval.map((n: any, i: number) => (tcurrent as any)[i] = n)
            //   tcurrent.length = tval.length
            // }

            // console.log('CCC', tval, parent, tcurrent)
          }
          else {
            target[tkey] = []
          }
        }
      }

      return ''
    }) as FoundInjection,

    $PACK: ((mode, key, val, parent, _path, _nodes, current) => {
      if ('val' === mode) { return val }

      if ('key:pre' === mode && 'string' === typeof key) {
        const cleankey = key.replace(/`([^`]+)`/g, '')
        const src = current[cleankey]

        const entry = clone(parent[key])

        parent[key] = src.reduce((a: any, _n: any, i: number) =>
        (a[src[i][parent[key]['`$KEY`']]] = {
          ...clone(entry),
        }, a), {})

        // console.log('PACK', mode, key, path, src, parent[key])

        current[cleankey] = src.reduce((a: any, n: any, i: number) =>
          (a[src[i][entry['`$KEY`']]] = n, a), {})

        // console.log('PACK-CLEAN', mode, key, path, current[cleankey])
      }

      return ''
    }) as FoundInjection,

    $KEY: ((mode, _key, _val, parent, path) => {
      // console.log('KEY', mode, mpath, key, val, 'p=', parent, path, current)

      if ('key:pre' === mode) {
        // let k = current[path[path.length-1]][parent[key]]
        // nodes[nodes.length-1][k] = parent

        // delete nodes[nodes.length-1][path[path.length-1]]
        delete parent['`$KEY`']

        // console.log('KEY:PRE', parent)

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
  current?: any // Current store entry containing key
) {
  // console.log('INJECT', // 'k=', key,
  //  'v=', val,
  // 'p=', path, 'sk=', path?.[path.length - 2], 'n=', nodes, 's=', !!store, 'c=', current
  // )
  const valtype = typeof val
  path = null == path ? [] : path

  const parentkey = path[path.length - 2]

  // current = null == key || null == current ? store : current

  console.log('INJECT', path.join('.'), parentkey, key, 'c=', store === current ? 'STORE' : current)
  current = null == current ? store : current
  current = null == parentkey ? current : current[parentkey]

  const origkey = key

  if (null == key) {
    key = '$TOP'
    val = { [key]: val }
  }


  if (null != val && 'object' === valtype) {
    const origkeys = [
      ...Object.keys(val).filter(k => !k.includes('$')),
      ...Object.keys(val).filter(k => k.includes('$')).sort(),
    ]

    // for (let origkey of origkeys) {
    for (let okI = 0; okI < origkeys.length; okI++) {
      const origkey = origkeys[okI]
      console.log('ORIGKEY', origkey)

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

        inject(
          child,
          store,
          modify,
          okI,
          origkeys,
          prekey,
          val,
          [...(path || []), prekey],
          [...(nodes || []), val],
          current
        )
      }

      injection(
        'key:post',
        prekey,
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
    console.log('VAL-INJECTION', key, val, path.join('.'), 'pk=', parentkey,
      'c=', current == store ? 'STORE' : current)

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

    if (modify) {
      modify(key, val, newval, parent, path, nodes, current, store, keyI, keys)
    }
  }

  if (null == origkey) {
    val = val.$TOP
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
  if ('val' === mode) {
    console.log('INJECTION', mode, key, val, path?.join('.'), 'C=', current == store ? 'STORE' : current)
  }

  const find = (_full: string, mpath: string) => {
    mpath = mpath.replace(/^\$[\d]+/, '$')
    // console.log('FIND', mpath)

    let found: FoundInjection = 'string' === typeof mpath ?
      mpath.startsWith('.') ?
        getpath(mpath.substring(1), current) :
        getpath(mpath, store) :
      undefined

    // console.log('FOUND', mpath, found, store)

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

  // if ('function' === typeof key) {
  //   key(val, res, parent, store)
  // }
  // else
  if (null != parent) {
    if (iskeymode) {
      res = null == res ? orig : res

      if (key !== res) {
        if ('string' === typeof key) {
          parent[res] = parent[key]
          delete parent[key]
        }

        if ('string' === typeof res) {
          key = res
        }
        else {
          key = undefined
        }
      }
    }

    if ('val' === mode && 'string' === typeof key) {
      if (undefined === res) {
        delete parent[key]
      }
      else {
        parent[key] = res
      }
    }
  }

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
  transform,
  merge,
  walk,
  getpath,
  inject,
}
