
type FullStore<T extends string> = {
  [K in T]: K extends `$${string}` ? FoundInjection : any;
};


function transform(
  data: any,
  spec: Record<string, any>,
  store: Record<string, any>,
  modify?: Function
) {
  const cd = clone((data || {}))
  const fullstore: FullStore<string> = {
    ...cd,
    $DATA: cd,

    $BT: '`',
    $WHEN: () => new Date().toISOString(),
    $DELETE: ((mode, mpath, key, val, parent, path, nodes, current, store) => {
      delete parent[key]
      return undefined
    }) as FoundInjection,
    $PRINT: ((...args) => console.log('PRINT', ...args)) as FoundInjection,

    // MOVE TO VAL and use nodes
    $MERGE: ((mode, mpath, key, val, parent, path, nodes, current, store) => {
      if ('key:pre' === mode) { return key }

      if ('key:post' === mode) {
        // console.log('MERGE', mode, key, val, 'p=', parent, path, nodes)
        delete parent[key]
        // Object.assign(parent, val[0])
        merge([parent, ...(Array.isArray(val) ? val : [val])])
        return key
      }

      return val
    }) as FoundInjection,

    $COPY: ((mode, mpath, key, val, parent, path, nodes, current, store) => {
      if (mode.startsWith('key')) { return key }
      // console.log('COPY',mode, mpath, key, val, parent, path, nodes, current)
      return null != current ? current[key] : undefined
    }) as FoundInjection,

    $EACH: ((mode, mpath, key, val, parent, path, nodes, current, store) => {
      if ('val' === mode) { return val }

      if ('key:pre' === mode) {
        const cleankey = key.replace(/`([^`]+)`/g, '')
        // console.log('EACH', key, cleankey, current[cleankey])
        const src = current[cleankey]

        if ('object' === typeof src) {
          if (Array.isArray(src)) {
            parent[key] = src.map(k =>
              clone(parent[key]))
          }
          else {
            parent[key] = Object.entries(src).map(n => ({
              ...clone(parent[key]),
              '`$META`': { KEY: n[0], VAL: n[1] }
            }))

            // TODO: can mutation be avoided?
            current[cleankey] = Object.values(src)
          }

          // console.log('PARENT', parent, current[cleankey])
        }
      }

      return ''
    }) as FoundInjection,

    $PACK: ((mode, mpath, key, val, parent, path, nodes, current, store) => {
      if ('val' === mode) { return val }

      if ('key:pre' === mode) {
        const cleankey = key.replace(/`([^`]+)`/g, '')
        const src = current[cleankey]

        const entry = clone(parent[key])

        parent[key] = src.reduce((a: any, n: any, i: number) =>
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

    $KEY: ((mode, mpath, key, val, parent, path, nodes, current, store) => {
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
      return null != meta ? meta.KEY : path[path.length - 2]
    }) as FoundInjection,

    $META: ((mode, mpath, key, val, parent, path, nodes, current, store) => {
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
  val: any,
  store: Record<string, any>,
  modify: Function | undefined,
  key?: string,
  parent?: any,
  path?: string[],
  nodes?: any[],
  current?: any
) {
  // console.log('INJECT', key, val, path, nodes)
  const valtype = typeof val

  current = null == key ? store : current
  current = (null == path || path.length < 2) ? current : current[path[path.length - 2]]

  if (null != val && 'object' === valtype) {
    // for(let origkey in val) {
    for (let origkey of Object.keys(val)) {

      let key = injection('key:pre', origkey, val[origkey], val,
        [...(path || []), origkey],
        [...(nodes || []), val],
        current, store)

      if ('string' === typeof key) {
        let child = val[key]

        inject(child, store, modify,
          key, val,
          [...(path || []), key],
          [...(nodes || []), val],
          current)
      }

      // console.log('KEY-POST', key, val, val[key])
      injection('key:post', key, val[key], val, path, nodes, current, store)
    }
  }

  else if ('string' === valtype) {
    // console.log('INJECT-STRING', key, val, path)
    // const newkey = injection('key', key, val, parent, path, nodes, current, store)
    const newkey = key
    const newval = injection('val', key, val, parent, path, nodes, current, store)

    if (modify) {
      modify(key, val, newkey, newval, parent, path, current, store)
    }
  }

  return val
}

type InjectionMode = 'key:pre' | 'key:post' | 'val'

type FoundInjection = (
  mode: InjectionMode,
  mpath: string,
  key: string,
  val: any,
  parent: any,
  path: string[],
  nodes: any[],
  current: any,
  store: Record<string, any>
) => any


function injection(
  mode: InjectionMode,
  key: string | Function | undefined,
  val: any,
  parent: any,
  path: string[] | undefined,
  nodes: any[] | undefined,
  current: any | undefined,
  store: Record<string, any>
) {
  // console.log('INJECTION', mode, key, val, path, 'C=', current)
  const find = (_full: string, mpath: string) => {
    let found = 'string' === typeof mpath ?
      mpath.startsWith('.') ?
        getpath(mpath.substring(1), current) :
        getpath(mpath, store) :
      undefined

    // console.log('FOUND', mpath, found, store)

    if ('function' === typeof found) {
      found = found(mode, mpath, key, val, parent, path, nodes, current, store)
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

  if ('function' === typeof key) {
    key(val, res, parent, store)
  }
  else if (null != parent) {
    if (iskeymode) {
      res = null == res ? orig : res

      if (key !== res) {
        // console.log('CKEY', key, res)
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

    // if('string' === typeof key) {
    if ('val' === mode && 'string' === typeof key) {
      parent[key] = res
    }
  }

  return res
}


function clone(val: any) {
  return undefined === val ? undefined : JSON.parse(JSON.stringify(val))
}


function merge(objs: any[]): any {
  let out: any = undefined
  if (1 === objs.length) {
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

            const valobj = null != val && 'object' === typeof val

            if (valobj && null != key) {
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


function getpath(path: string | string[], store: Record<string, any>, build?: boolean) {
  if (null == path || '' === path) {
    return store
  }

  const parts = Array.isArray(path) ? path : path.split('.')
  let val = undefined

  if (0 < parts.length) {
    val = store
    for (let pI = 0; pI < parts.length; pI++) {
      const part = parts[pI]
      let nval: any = val[part]
      if (undefined === nval) {
        if (build && pI < parts.length - 1) {
          // console.log('GPB', pI, part, parts, val)
          nval = val[part] = -1 < parseInt(parts[pI + 1]) ? [] : {}
        }
        else {
          val = undefined
          break
        }
      }
      val = nval
    }
  }

  return val

}


type WalkApply = (key: string | undefined, val: any, parent: any, path: string[]) => any

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
