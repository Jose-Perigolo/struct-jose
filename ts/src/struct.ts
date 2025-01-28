
type PropKey = string | number

type InjectMode = 'key:pre' | 'key:post' | 'val'

type InjectHandler = (
  state: InjectState,
  val: any,
  current: any,
  store: any,
) => any

type InjectState = {
  mode: InjectMode,
  full: boolean,
  keyI: number,
  keys: string[],
  key: string,
  val: any,
  parent: any,
  path: string[],
  nodes: any[],
  handler: InjectHandler,
  base?: string
}

type Modify = (
  key: string | number,
  val: any,
  parent: any,
  state: InjectState,
  current: any,
  store: any,
) => void


type FullStore<T extends string> = {
  [K in T]: K extends `$${string}` ? InjectHandler : any
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

function iskey(key: any) {
  const keytype = typeof key
  return ('string' === keytype && '' !== key) || 'number' === keytype
}

function items(val: any) {
  return ismap(val) ? Object.entries(val) :
    islist(val) ? val.map((n: any, i: number) => [i, n]) :
      []
}

function getprop(val: any, key: any, alt?: any) {
  let out = undefined === val ? alt : undefined === key ? alt : val[key]
  return undefined == out ? alt : out
}

function setprop<PARENT>(parent: PARENT, key: any, val: any): PARENT {
  if (iskey(key)) {
    if (ismap(parent)) {
      if (undefined === val) {
        delete (parent as any)[key]
      }
      else {
        (parent as any)[key] = val
      }
    }
    else if (islist(parent)) {
      const keyI = +key
      if (undefined === val) {
        if (0 <= keyI && keyI < parent.length) {
          for (let pI = keyI; pI < parent.length - 1; pI++) {
            parent[pI] = parent[pI + 1]
          }
          parent.length = parent.length - 1
        }
      }
      else if (0 <= keyI) {
        parent[parent.length < keyI ? parent.length : keyI] = val
      }
      else {
        parent.unshift(val)
      }
    }
  }
  return parent
}


function clone(val: any) {
  return undefined === val ? undefined : JSON.parse(JSON.stringify(val))
}


// Transform data using spec.
// Only operates on static JSONifiable data.
// Array are treated as if they are objects with indices as keys.
function transform(
  data: any, // Source data to transform into new data (original not mutated)
  spec: any, // Transform specification; output follows this shape
  extra: any, // Additional store of data
  modify?: Modify // Optionally modify individual values.
) {
  const dataClone = merge([
    clone(undefined === extra ? {} : extra),
    clone(undefined === data ? {} : data),
  ])

  // if (ismap(dataClone)) {
  //   for (let [k, n] of items(dataClone)) {
  //     if ('string' === typeof k && k.startsWith('$')) {
  //       dataClone['$' + k] = n
  //       delete dataClone[k]
  //     }
  //   }
  // }

  // Define a top level store that provides transform operations.
  // const fullstore: FullStore<string> = {

  const store = {

    $TOP: dataClone,

    // Escape backtick,
    $BT: () => '`',

    // Escape dollar sign,
    $DS: () => '$',

    // Insert current date and time as an ISO string.
    $WHEN: () => new Date().toISOString(),

    // Delete a key-value pair.
    $DELETE: (state: InjectState) => {
      const { key, parent } = state
      if (null != key) {
        // delete parent[key]
        setprop(parent, key, undefined)
      }
      return undefined
    },


    $COPY: (state: InjectState, _val: any, current: any) => {
      const { mode, key, parent } = state

      let out
      if (mode.startsWith('key')) {
        out = key
      }
      else {
        // console.log('KEY', current)
        out = null != current && null != key ? current[key] : undefined

        setprop(parent, key, out)
      }

      return out
    },


    $KEY: (state: InjectState, _val: any, current: any) => {
      const { mode, path, parent } = state

      if ('val' !== mode) {
        return undefined
      }

      const keyspec = getprop(parent, '`$KEY`')
      if (undefined !== keyspec) {
        setprop(parent, '`$KEY`', undefined)
        return getprop(current, keyspec)
      }

      return getprop(getprop(parent, '`$META`'), 'KEY', getprop(path, path.length - 2))
    },


    $META: (state: InjectState) => {
      const { parent } = state
      setprop(parent, '`$META`', undefined)
      return undefined
    },


    // Merge a list of objects into the current object. 
    // Must be a key in an object. The value is merged over the current object.
    // If the value is an array, the elements are first merged using `merge`. 
    // If the value is the empty string, merge the top level store.
    $MERGE: (state: InjectState) => {
      const { mode, key, parent } = state

      if ('key:pre' === mode) { return key }

      // Operate after child values have been transformed.
      if ('key:post' === mode) {

        let args = getprop(parent, key)
        args = '' === args ? [dataClone] : Array.isArray(args) ? args : [args]

        merge([parent, ...args])
        setprop(parent, key, undefined)

        return key
      }

      return undefined
    },


    $EACH: (state: InjectState, val: any, current: any, store: any) => {
      const { mode, keys, path, parent, nodes } = state

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

      const src = getpath(srcpath, store, current, state)

      let tcurrent: any = []
      let tval: any = []

      const tkey = path[path.length - 2]
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

      tcurrent = { $TOP: tcurrent }

      tval = inject(
        tval,
        store,
        modify,
        tcurrent,
      )

      setprop(target, tkey, tval)

      return tval[0]

      // const list: any[] = getprop(target, tkey)
      // tval.map((n: any, i: number) => list[i] = n)
      // list.length = tval.length

      // return list[0]
    },


    $PACK: (state: InjectState, _val: any, current: any, store: any) => {
      const { mode, key, path, parent, nodes } = state

      // Defensive context checks.
      if ('key:pre' !== mode || 'string' !== typeof key || null == path || null == nodes) {
        return undefined
      }

      const args = parent[key]
      const srcpath = args[0]
      const child = clone(args[1])

      const keyprop = child['`$KEY`']
      const tkey = path[path.length - 2]
      const target = nodes[path.length - 2] || nodes[path.length - 1]

      let src = getpath(srcpath, store, current, state)

      // console.log('SRC', JSON.stringify(srcpath), src)

      src = islist(src) ? src :
        ismap(src) ? Object.entries(src)
          .reduce((a: any[], n: any) =>
            (n[1]['`$META`'] = { KEY: n[0] }, a.push(n[1]), a), []) :
          undefined

      if (null == src) {
        return undefined
      }

      let childkey: PropKey | undefined = getprop(child, '`$KEY`')
      let keyname = undefined === childkey ? keyprop : childkey
      setprop(child, '`$KEY`', undefined)

      let tval: any = {}
      tval = src.reduce((a: any, n: any) => {
        let kn = getprop(n, keyname)
        setprop(a, kn, clone(child))
        const nchild = getprop(a, kn)
        setprop(nchild, '`$META`', getprop(n, '`$META`'))
        return a
      }, tval)

      let tcurrent: any = {}
      src.reduce((a: any, n: any) => {
        let kn = getprop(n, keyname)
        setprop(a, kn, n)
        return a
      }, tcurrent)

      tcurrent = { $TOP: tcurrent }


      tval = inject(
        tval,
        store,
        modify,
        tcurrent,
      )

      // console.log('TCURRENT', tcurrent)
      // console.log('TVAL', tval)
      // console.log('TARGET', tkey, target)

      setprop(target, tkey, tval)

      // console.log('TARGET2', tkey, target)
      // console.log('NODES')
      // console.dir(state.nodes, { depth: null })

      // const map: any = getprop(target, key)
      // Object.assign(map, tval)

      return undefined
    },
  }

  const out = inject(spec, store, modify, store)

  // console.log('TRANSFORM', out, '\n')
  return out
}


const injecthandler: InjectHandler = (state: any, val: any, current: any, store: any): any => {
  let out = val

  if ('function' === typeof val) {
    out = val(state, val, current, store)
  }
  else if ('val' === state.mode && state.full) {
    setprop(state.parent, state.key, val)
  }

  return out
}


function inject(
  val: any,
  store: any,
  modify?: Modify,
  current?: any,
  state?: InjectState,
) {
  const mark = 'M' + ('' + Math.random()).substring(2, 6)
  const valtype = typeof val

  if (undefined === state) {
    const parent = { '$TOP': val }
    state = {
      mode: 'val',
      full: false,
      keyI: 0,
      keys: ['$TOP'],
      key: '$TOP',
      val,
      parent,
      path: ['$TOP'],
      nodes: [parent],
      handler: injecthandler,
      base: '$TOP'
    }
  }

  if (undefined === current) {
    current = { $TOP: store }
  }
  else {
    const parentkey = state.path[state.path.length - 2]
    // console.log('PARENTKEY', parentkey, state.path)
    current = null == parentkey ? current : getprop(current, parentkey)
  }

  // console.log('INJECT-START', current)
  // console.dir(state, { depth: null })

  if (isnode(val)) {
    // val.mark = mark
  }
  // console.log('INJECT-START', mark, state.key, val)
  // console.dir(state.nodes, { depth: null })

  if (isnode(val)) {
    const origkeys = ismap(val) ? [
      ...Object.keys(val).filter(k => !k.includes('$')),
      ...Object.keys(val).filter(k => k.includes('$')).sort(),
    ] : val.map((_n: any, i: number) => i)


    // console.log('ORIGKEYS', origkeys, current)

    for (let okI = 0; okI < origkeys.length; okI++) {
      const origkey = '' + origkeys[okI]

      let childpath = [...(state.path || []), origkey]
      let childnodes = [...(state.nodes || []), val]

      const childstate: InjectState = {
        mode: 'key:pre',
        full: false,
        keyI: okI,
        keys: origkeys,
        key: origkey,
        val,
        parent: val,
        path: childpath,
        nodes: childnodes,
        handler: injecthandler,
        base: state.base,
      }

      const prekey = injectstr(origkey, store, current, childstate)

      if (null != prekey) {

        let child = val[prekey]
        childstate.mode = 'val'

        inject(
          child,
          store,
          modify,
          current,
          childstate,
        )

        // console.log('INJECT-CHILD-VAL', mark, prekey, child, state)

        childstate.mode = 'key:post'
        injectstr(origkey, store, current, childstate)
      }
    }
  }

  else if ('string' === valtype) {
    state.mode = 'val'
    const newval = injectstr(val, store, current, state)
    val = newval

    setprop(state.parent, state.key, newval)
  }

  if (modify) {
    modify(
      state.key,
      val,
      state.parent,
      state,
      current,
      store
    )
  }

  // console.log('INJECT-OUT', val, state)

  // return val
  return state.parent.$TOP
}


function injectstr(val: string, store: any, current?: any, state?: any): any {
  if ('string' !== typeof val) {
    return ''
  }

  let out: any = val
  const m = val.match(/^`([^`]+)`$/)

  if (m) {
    if (state) {
      state.full = true
    }
    const ref = m[1] // .replace(/^$[0-9]+/, '$')
    out = getpath(ref, store, current, state)
  }
  else {
    out = val.replace(/`([^`]+)`/g,
      (_m: string, ref: string) => {
        // const ref = p1.replace(/^$[0-9]+/, '$')
        if (state) {
          state.full = false
        }
        const found = getpath(ref, store, current, state)
        return undefined == found ? '' :
          'object' === typeof found ? JSON.stringify(found) :
            found
      })

    if (state.handler) {
      state.full = true
      out = state.handler(state, out, current, store)
    }
  }

  return out
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
        if ((ismap(obj) && islist(out)) || (islist(obj) && ismap(out))) {
          out = obj
        }
        let cur = [out]
        let cI = 0
        walk(obj, (key, val, parent, path) => {
          if (null != key) {
            cI = path.length - 1
            if (undefined === cur[cI]) {
              cur[cI] = getpath(path.slice(0, path.length - 1), out)
            }

            if (!isnode(cur[cI])) {
              cur[cI] = islist(parent) ? [] : {}
            }

            if (isnode(val)) {
              setprop(cur[cI], key, cur[cI + 1])
              cur[cI + 1] = undefined
            }
            else {
              setprop(cur[cI], key, val)
            }
          }

          return val
        })
      }
      else {
        out = obj
      }
    }
  }
  return out
}


function getpath(path: string | string[], store: any, current?: any, state?: InjectState) {
  if (null == path || null == store || '' === path) {
    return getprop(store, getprop(state, 'base'), store)
  }

  const parts = islist(path) ? path : 'string' === typeof path ? path.split('.') : []
  let val = store

  if (0 < parts.length) {
    let pI = 0
    if ('' === parts[0]) {
      if (1 === parts.length) {
        return getprop(store, getprop(state, 'base'), store)
      }
      pI = 1
      val = current
    }
    /*
    else if (1 === parts.length && 'string' === typeof parts[0]) {
      const m = parts[0].match(/^\$[0-9]+(.+)/)
      if (m) {
        pI = 1
        const data = store
        val = getprop(data, '$' + m[1])
      }
      else {
        val = store
      }
      }

    else if (undefined !== state && undefined !== state.base) {
      let baseval = getprop(store, state.base)
      val = undefined === baseval ? store : baseval
    }
    else {
      val = store
    }
    */

    for (; pI < parts.length; pI++) {
      const part = parts[pI]
      let newval: any = getprop(val, part)
      if (undefined === newval && 0 === pI && undefined !== state && undefined !== state.base) {
        newval = getprop(getprop(val, state.base), part)
      }

      if (undefined === newval) {
        // if (0 === pI && null != val && 'function' === typeof val.$DATA) {
        if (0 === pI && null != val) {
          const data = val // .$DATA()
          newval = getprop(data, part)
        }

        val = newval
        if (undefined == val) {
          break
        }
      }
      else {
        val = newval
      }
    }
  }

  if (null != state && 'function' === typeof state.handler) {
    let newval = state.handler(state, val, current, store)
    val = newval
  }

  return val
}


type WalkApply = (key: string | undefined, val: any, parent: any, path: string[]) => any

// Walk a data strcture depth first.
function walk(val: any, apply: WalkApply, key?: string, parent?: any, path?: string[]): any {
  if (isnode(val)) {
    for (let [ckey, child] of items(val)) {
      setprop(val, ckey, walk(child, apply, ckey, val, [...(path || []), ckey]))
    }
  }

  return apply(key, val, parent, path || [])
}



export {
  clone,
  isnode,
  ismap,
  islist,
  iskey,
  items,
  getprop,
  setprop,

  getpath,
  inject,
  merge,
  transform,
  walk,
}
