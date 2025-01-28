/* Copyright (c) 2025 Voxgig Ltd. */

/* Voxgig Struct
 * =============
 *
 * Utility functions to manipulate in-memory JSON-like data
 * structures.  The general design principle is
 * "by-example". Transform specifications mirror the desired output.
 * This implementation is desgined for porting to multiple language.
 *
 * - isnode, islist, islist, iskey: identify value kinds
 * - clone: create a copy of a JSON-like data structure
 * - items: list entries of a map or list as [key, value] pairs
 * - getprop: safely get a property value by key
 * - setprop: safely set a property value by key
 * - getpath: get the value at a key path deep inside an object
 * - merge: merge multiple nodes, overriding values in earlier nodes.
 * - walk: walk a node tree, applying a function at each node and leaf.
 * - inject: inject values from a data store into a new data structure.
 * - transform: transform a data structure to an example structure.
 */


// Keys are strings for maps, or integers for lists.
type PropKey = string | number


// For each key in a node (map or list), perform value injections in
// three phases: on key value, before child, and then on key value again.
// This mode is passed via the InjectState.
type InjectMode = 'key:pre' | 'key:post' | 'val'


// Handle value injections using backtick escape sequences:
// - `a.b.c`: insert value at {a:{b:{c:1}}}
// - `$FOO`: apply transform FOO
type InjectHandler = (
  state: InjectState,
  val: any, // Injection value specification.
  current: any, // Current source parent value.
  store: any, // Current source root value.
) => any


// Injection state used for recursive injection into JSON-like data structures.
type InjectState = {
  mode: InjectMode,
  full: boolean,  // Transform escape was full key name.
  keyI: number,   // Index of parent key in list of parent keys.
  keys: string[], // List of parent keys.
  key: string,    // Current parent key.
  val: any,       // Current child value.
  parent: any,    // Current parent (in transform specification).
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


// Value is a node - defined, and a map (hash) or list (array).
function isnode(val: any) {
  return null != val && 'object' == typeof val
}


// Value is a defined map (hash) with string keys.
function ismap(val: any) {
  return null != val && 'object' == typeof val && !Array.isArray(val)
}


// Value is a defined list (array) with integer keys (indexes).
function islist(val: any) {
  return Array.isArray(val)
}


// Value is a defined string (non-empty) or integer key.
function iskey(key: any) {
  const keytype = typeof key
  return ('string' === keytype && '' !== key) || 'number' === keytype
}


// List the keys of a map or list as an array of tuples of the form [key, value].
function items(val: any) {
  return ismap(val) ? Object.entries(val) :
    islist(val) ? val.map((n: any, i: number) => [i, n]) :
      []
}


// Clone a JSON-like data structure.
function clone(val: any) {
  return undefined === val ? undefined : JSON.parse(JSON.stringify(val))
}


// Safely get a property of a node. Undefined arguments return undefined.
// If the key is not found, return the alternative value.
function getprop(val: any, key: any, alt?: any) {
  let out = undefined === val ? alt : undefined === key ? alt : val[key]
  return undefined == out ? alt : out
}


// Safely set a property. Undefined arguments and invalid keys are ignored.
// Returns the (possible modified) parent.
// If the value is undefined it the key will be deleted from the parent.
// If the parent is a list, and the key is negative, prepend the value.
// If the key is above the list size, append the value.
// If the value is undefined, remove the list element at index key, and shift the
// remaining elements down.  These rules avoids "holes" in the list.
function setprop<PARENT>(parent: PARENT, key: any, val: any): PARENT {
  if (!iskey(key)) {
    return parent
  }

  if (ismap(parent)) {
    if (undefined === val) {
      delete (parent as any)[key]
    }
    else {
      (parent as any)[key] = val
    }
  }
  else if (islist(parent)) {
    // Ensure key is an integer.
    let keyI = +key

    if (isNaN(keyI)) {
      return parent
    }

    keyI = Math.floor(keyI)

    // Delete list element at position keyI, shifting later elements down.
    if (undefined === val) {
      if (0 <= keyI && keyI < parent.length) {
        for (let pI = keyI; pI < parent.length - 1; pI++) {
          parent[pI] = parent[pI + 1]
        }
        parent.length = parent.length - 1
      }
    }

    // Set or append value at position keyI, or append if keyI out of bounds.
    else if (0 <= keyI) {
      parent[parent.length < keyI ? parent.length : keyI] = val
    }

    // Prepend value if keyI is negative
    else {
      parent.unshift(val)
    }
  }

  return parent
}


// Transform data using spec.
// Only operates on static JSON-like data.
// Arrays are treated as if they are objects with indices as keys.
function transform(
  data: any, // Source data to transform into new data (original not mutated)
  spec: any, // Transform specification; output follows this shape
  extra: any, // Additional store of data and transforms.
  modify?: Modify // Optionally modify individual values.
) {
  const extraTransforms: any = {}
  const extraData = null == extra ? {} : items(extra)
    .reduce((a: any, n: any[]) =>
      (n[0].startsWith('$') ? extraTransforms[n[0]] = n[1] : (a[n[0]] = n[1]), a), {})

  const dataClone = merge([
    clone(undefined === extraData ? {} : extraData),
    clone(undefined === data ? {} : data),
  ])

  // Define a top level store that provides transform operations.
  const store = {

    // Custom extra transforms, if any.
    ...extraTransforms,

    // The inject function recognises this special location for the root of the source data.
    // NOTE: to escape data that contains "`$FOO`" keys at the top level,
    // place that data inside a holding map: { myholder: mydata }.
    $TOP: dataClone,

    // Escape backtick (this also works inside backticks).
    $BT: () => '`',

    // Escape dollar sign (this also works inside backticks).
    $DS: () => '$',

    // Insert current date and time as an ISO string.
    $WHEN: () => new Date().toISOString(),


    // Delete a key from a map or list.
    $DELETE: (state: InjectState) => {
      const { key, parent } = state
      setprop(parent, key, undefined)
      return undefined
    },


    // Copy value from source data.
    $COPY: (state: InjectState, _val: any, current: any) => {
      const { mode, key, parent } = state

      let out
      if (mode.startsWith('key')) {
        out = key
      }
      else {
        out = getprop(current, key)
        setprop(parent, key, out)
      }

      return out
    },


    // As a value, inject the key of the parent node.
    // As a key, defined the name of the key property in the source object.
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


    // Store meta data about a node.
    $META: (state: InjectState) => {
      const { parent } = state
      setprop(parent, '`$META`', undefined)
      return undefined
    },


    // Merge a list of objects into the current object. 
    // Must be a key in an object. The value is merged over the current object.
    // If the value is an array, the elements are first merged using `merge`. 
    // If the value is the empty string, merge the top level store.
    // Format: { '`$MERGE`': '`source-path`' | ['`source-paths`', ...] }
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


    // Convert a node to a list.
    // Format: ['`$EACH`', '`source-path-of-node`', child-template]
    $EACH: (state: InjectState, _val: any, current: any, store: any) => {
      const { mode, keys, path, parent, nodes } = state

      // Remove arguments to avoid spurious processing.
      if (keys) {
        keys.length = 1
      }

      // Defensive context checks.
      if ('val' !== mode || null == path || null == nodes) {
        return undefined
      }

      // Get arguments.
      const srcpath = parent[1] // Path to source data.
      const child = clone(parent[2]) // Child template.

      // Source data
      const src = getpath(srcpath, store, current, state)

      // Create parallel data structures:
      // source entries :: child templates
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

            // Make a note of the key for $KEY transforms
            '`$META`': { KEY: n[0] }
          }))
        }

        tcurrent = Object.values(src)
      }

      // Parent structure.
      tcurrent = { $TOP: tcurrent }

      // Build the substructure.
      tval = inject(
        tval,
        store,
        modify,
        tcurrent,
      )

      setprop(target, tkey, tval)

      // Prevent callee from damaging first list entry (since we are in `val` mode).
      return tval[0]
    },


    // Convert a node to a map.
    // Format: { '`$PACK`':['`source-path`', child-template]}
    $PACK: (state: InjectState, _val: any, current: any, store: any) => {
      const { mode, key, path, parent, nodes } = state

      // Defensive context checks.
      if ('key:pre' !== mode || 'string' !== typeof key || null == path || null == nodes) {
        return undefined
      }

      // Get arguments.
      const args = parent[key]
      const srcpath = args[0] // Path to source data.
      const child = clone(args[1]) // Child template.

      // Find key and target node.
      const keyprop = child['`$KEY`']
      const tkey = path[path.length - 2]
      const target = nodes[path.length - 2] || nodes[path.length - 1]

      // Source data
      let src = getpath(srcpath, store, current, state)

      // Prepare source as a list.
      src = islist(src) ? src :
        ismap(src) ? Object.entries(src)
          .reduce((a: any[], n: any) =>
            (n[1]['`$META`'] = { KEY: n[0] }, a.push(n[1]), a), []) :
          undefined

      if (null == src) {
        return undefined
      }

      // Get key if specified.
      let childkey: PropKey | undefined = getprop(child, '`$KEY`')
      let keyname = undefined === childkey ? keyprop : childkey
      setprop(child, '`$KEY`', undefined)

      // Build parallel target object.
      let tval: any = {}
      tval = src.reduce((a: any, n: any) => {
        let kn = getprop(n, keyname)
        setprop(a, kn, clone(child))
        const nchild = getprop(a, kn)
        setprop(nchild, '`$META`', getprop(n, '`$META`'))
        return a
      }, tval)

      // Build parallel source object.
      let tcurrent: any = {}
      src.reduce((a: any, n: any) => {
        let kn = getprop(n, keyname)
        setprop(a, kn, n)
        return a
      }, tcurrent)

      tcurrent = { $TOP: tcurrent }

      // Build substructure.
      tval = inject(
        tval,
        store,
        modify,
        tcurrent,
      )

      setprop(target, tkey, tval)

      // Drop transform key.
      return undefined
    },
  }

  const out = inject(spec, store, modify, store)

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
  const m = val.match(/^`(\$[^`0-9]+|[^`]+)[0-9]*`$/)

  if (m) {
    if (state) {
      state.full = true
    }
    let ref = m[1]
    ref = 3 < ref.length ? ref.replace(/\$BT/g, '`').replace(/\$DS/g, '$') : ref

    // console.log('REF-A', ref)
    out = getpath(ref, store, current, state)
  }
  else {
    out = val.replace(/`([^`]+)`/g,
      (_m: string, ref: string) => {
        ref = 3 < ref.length ? ref.replace(/\$BT/g, '`').replace(/\$DS/g, '$') : ref
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
