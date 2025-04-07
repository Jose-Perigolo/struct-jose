/* Copyright (c) 2025 Voxgig Ltd. MIT LICENSE. */

/* Voxgig Struct
 * =============
 *
 * Utility functions to manipulate in-memory JSON-like data
 * structures. These structures assumed to be composed of nested
 * "nodes", where a node is a list or map, and has named or indexed
 * fields.  The general design principle is "by-example". Transform
 * specifications mirror the desired output.  This implementation is
 * designed for porting to multiple language, and to be tolerant of
 * undefined values.
 *
 * Main utilities
 * - getpath: get the value at a key path deep inside an object.
 * - merge: merge multiple nodes, overriding values in earlier nodes.
 * - walk: walk a node tree, applying a function at each node and leaf.
 * - inject: inject values from a data store into a new data structure.
 * - transform: transform a data structure to an example structure.
 * - validate: valiate a data structure against a shape specification.
 *
 * Minor utilities
 * - isnode, islist, ismap, iskey, isfunc: identify value kinds.
 * - isempty: undefined values, or empty nodes.
 * - keysof: sorted list of node keys (ascending).
 * - haskey: true if key value is defined.
 * - clone: create a copy of a JSON-like data structure.
 * - items: list entries of a map or list as [key, value] pairs.
 * - getprop: safely get a property value by key.
 * - setprop: safely set a property value by key.
 * - stringify: human-friendly string version of a value.
 * - escre: escape a regular expresion string.
 * - escurl: escape a url.
 * - joinurl: join parts of a url, merging forward slashes.
 *
 * This set of functions and supporting utilities is designed to work
 * uniformly across many languages, meaning that some code that may be
 * functionally redundant in specific languages is still retained to
 * keep the code human comparable.
 *
 * NOTE: In this code JSON nulls are in general *not* considered the
 * same as the undefined value in the given language. However most
 * JSON parsers do use the undefined value to represent JSON
 * null. This is ambiguous as JSON null is a separate value, not an
 * undefined value. You should convert such values to a special value
 * to represent JSON null, if this ambiguity creates issues
 * (thankfully in most APIs, JSON nulls are not used). For example,
 * the unit tests use the string "__NULL__" where necessary.
 *
 */


// String constants are explicitly defined.

// Mode value for inject step.
const S_MKEYPRE = 'key:pre'
const S_MKEYPOST = 'key:post'
const S_MVAL = 'val'
const S_MKEY = 'key'

// Special keys.
const S_DKEY = '`$KEY`'
const S_DMETA = '`$META`'
const S_DTOP = '$TOP'
const S_DERRS = '$ERRS'

// General strings.
const S_array = 'array'
const S_base = 'base'
const S_boolean = 'boolean'
const S_function = 'function'
const S_number = 'number'
const S_object = 'object'
const S_string = 'string'
const S_null = 'null'
const S_MT = ''
const S_BT = '`'
const S_DS = '$'
const S_DT = '.'
const S_CN = ':'
const S_KEY = 'KEY'


// The standard undefined value for this language.
const UNDEF = undefined


// Value is a node - defined, and a map (hash) or list (array).
function isnode(val) {
  return null != val && S_object == typeof val
}


// Value is a defined map (hash) with string keys.
function ismap(val) {
  return null != val && S_object == typeof val && !Array.isArray(val)
}


// Value is a defined list (array) with integer keys (indexes).
function islist(val) {
  return Array.isArray(val)
}


// Value is a defined string (non-empty) or integer key.
function iskey(key) {
  const keytype = typeof key
  return (S_string === keytype && S_MT !== key) || S_number === keytype
}


// Check for an "empty" value - undefined, empty string, array, object.
function isempty(val) {
  return null == val || S_MT === val ||
    (Array.isArray(val) && 0 === val.length) ||
    (S_object === typeof val && 0 === Object.keys(val).length)
}


// Value is a function.
function isfunc(val) {
  return S_function === typeof val
}


// Determine the type of a value as a string.
// Returns one of: 'null', 'string', 'number', 'boolean', 'function', 'array', 'object'
// Normalizes and simplifies JavaScript's type system for consistency.
function typify(value) {
  if (value === null || value === undefined) {
    return S_null
  }

  const type = typeof value

  if (Array.isArray(value)) {
    return S_array
  }

  if (type === 'object') {
    return S_object
  }

  return type
}


// Safely get a property of a node. Undefined arguments return undefined.
// If the key is not found, return the alternative value, if any.
function getprop(val, key, alt) {
  let out = alt

  if (UNDEF === val || UNDEF === key) {
    return alt
  }

  if (isnode(val)) {
    out = val[key]
  }

  if (UNDEF === out) {
    return alt
  }

  return out
}


// Convert different types of keys to string representation.
// String keys are returned as is.
// Number keys are converted to strings.
// Floats are truncated to integers.
// Booleans, objects, arrays, null, undefined all return empty string.
function strkey(key = UNDEF) {
  if (UNDEF === key) {
    return S_MT
  }

  if (typeof key === S_string) {
    return key
  }

  if (typeof key === S_boolean) {
    return S_MT
  }

  if (typeof key === S_number) {
    return key % 1 === 0 ? String(key) : String(Math.floor(key))
  }

  return S_MT
}


// Sorted keys of a map, or indexes of a list.
function keysof(val) {
  return !isnode(val) ? [] :
    ismap(val) ? Object.keys(val).sort() : val.map((_n, i) => '' + i)
}


// Value of property with name key in node val is defined.
function haskey(val, key) {
  return UNDEF !== getprop(val, key)
}


// List the sorted keys of a map or list as an array of tuples of the form [key, value].
// NOTE: Unlike keysof, list indexes are returned as numbers.
function items(val) {
  return keysof(val).map(k => [k, val[k]])
}


// Escape regular expression.
function escre(s) {
  s = null == s ? S_MT : s
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}


// Escape URLs.
function escurl(s) {
  s = null == s ? S_MT : s
  return encodeURIComponent(s)
}


// Concatenate url part strings, merging forward slashes as needed.
function joinurl(sarr) {
  return sarr
    .filter(s => null != s && '' !== s)
    .map((s, i) => 0 === i ? s.replace(/([^\/])\/+/, '$1/').replace(/\/+$/, '') :
      s.replace(/([^\/])\/+/, '$1/').replace(/^\/+/, '').replace(/\/+$/, ''))
    .filter(s => '' !== s)
    .join('/')
}


// Safely stringify a value for humans (NOT JSON!).
function stringify(val, maxlen) {
  let str = S_MT

  if (UNDEF === val) {
    return str
  }

  try {
    str = JSON.stringify(val, function(_key, val) {
      if (
        val !== null &&
        typeof val === "object" &&
        !Array.isArray(val)
      ) {
        const sortedObj = {}
        for (const k of Object.keys(val).sort()) {
          sortedObj[k] = val[k]
        }
        return sortedObj
      }
      return val
    })
  }
  catch (err) {
    str = S_MT + val
  }

  str = S_string !== typeof str ? S_MT + str : str
  str = str.replace(/"/g, '')

  if (null != maxlen) {
    let js = str.substring(0, maxlen)
    str = maxlen < str.length ? (js.substring(0, maxlen - 3) + '...') : str
  }

  return str
}


// Build a human friendly path string.
function pathify(val, startin, endin) {
  let pathstr = UNDEF

  let path = islist(val) ? val :
    S_string == typeof val ? [val] :
      S_number == typeof val ? [val] :
        UNDEF

  const start = null == startin ? 0 : -1 < startin ? startin : 0
  const end = null == endin ? 0 : -1 < endin ? endin : 0

  if (UNDEF != path && 0 <= start) {
    path = path.slice(start, path.length - end)
    if (0 === path.length) {
      pathstr = '<root>'
    }
    else {
      pathstr = path
        // .filter((p, t) => (t = typeof p, S_string === t || S_number === t))
        .filter((p) => iskey(p))
        .map((p) =>
          'number' === typeof p ? S_MT + Math.floor(p) :
            p.replace(/\./g, S_MT))
        .join(S_DT)
    }
  }

  if (UNDEF === pathstr) {
    pathstr = '<unknown-path' + (UNDEF === val ? S_MT : S_CN + stringify(val, 47)) + '>'
  }

  return pathstr
}


// Clone a JSON-like data structure.
// NOTE: function value references are copied, *not* cloned.
function clone(val) {
  const refs = []
  const replacer = (_k, v) => S_function === typeof v ?
    (refs.push(v), '`$FUNCTION:' + (refs.length - 1) + '`') : v
  const reviver = (_k, v, m) => S_string === typeof v ?
    (m = v.match(/^`\$FUNCTION:([0-9]+)`$/), m ? refs[m[1]] : v) : v
  return UNDEF === val ? UNDEF : JSON.parse(JSON.stringify(val, replacer), reviver)
}


// Safely set a property. Undefined arguments and invalid keys are ignored.
// Returns the (possibly modified) parent.
// If the value is undefined the key will be deleted from the parent.
// If the parent is a list, and the key is negative, prepend the value.
// NOTE: If the key is above the list size, append the value; below, prepend.
// If the value is undefined, remove the list element at index key, and shift the
// remaining elements down.  These rules avoid "holes" in the list.
function setprop(parent, key, val) {
  if (!iskey(key)) {
    return parent
  }

  if (ismap(parent)) {
    key = S_MT + key
    if (UNDEF === val) {
      delete parent[key]
    }
    else {
      parent[key] = val
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
    if (UNDEF === val) {
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


// Walk a data structure depth first, applying a function to each value.
function walk(
  // These arguments are the public interface.
  val,
  apply,

  // These areguments are used for recursive state.
  key,
  parent,
  path
) {
  if (isnode(val)) {
    for (let [ckey, child] of items(val)) {
      setprop(val, ckey, walk(child, apply, ckey, val, [...(path || []), S_MT + ckey]))
    }
  }

  // Nodes are applied *after* their children.
  // For the root node, key and parent will be undefined.
  return apply(key, val, parent, path || [])
}


// Merge a list of values into each other. Later values have
// precedence.  Nodes override scalars. Node kinds (list or map)
// override each other, and do *not* merge.  The first element is
// modified.
function merge(val) {
  let out = UNDEF

  // Handle edge cases.
  if (!islist(val)) {
    return val
  }

  const list = val
  const lenlist = list.length

  if (0 === lenlist) {
    return UNDEF
  }
  else if (1 === lenlist) {
    return list[0]
  }

  // Merge a list of values.
  out = getprop(list, 0, {})

  for (let oI = 1; oI < lenlist; oI++) {
    let obj = list[oI]

    if (!isnode(obj)) {
      // Nodes win.
      out = obj
    }
    else {
      // Nodes win, also over nodes of a different kind.
      if (!isnode(out) || (ismap(obj) && islist(out)) || (islist(obj) && ismap(out))) {
        out = obj
      }
      else {
        // Node stack. walking down the current obj.
        let cur = [out]
        let cI = 0

        function merger(
          key,
          val,
          parent,
          path
        ) {
          if (null == key) {
            return val
          }

          // Get the curent value at the current path in obj.
          // NOTE: this is not exactly efficient, and should be optimised.
          let lenpath = path.length
          cI = lenpath - 1
          if (UNDEF === cur[cI]) {
            cur[cI] = getpath(path.slice(0, lenpath - 1), out)
          }

          // Create node if needed.
          if (!isnode(cur[cI])) {
            cur[cI] = islist(parent) ? [] : {}
          }

          // Node child is just ahead of us on the stack, since
          // `walk` traverses leaves before nodes.
          if (isnode(val) && !isempty(val)) {
            setprop(cur[cI], key, cur[cI + 1])
            cur[cI + 1] = UNDEF
          }

          // Scalar child.
          else {
            setprop(cur[cI], key, val)
          }

          return val
        }

        // Walk overriding node, creating paths in output as needed.
        walk(obj, merger)
      }
    }
  }

  return out
}


// Get a value deep inside a node using a key path.  For example the
// path `a.b` gets the value 1 from {a:{b:1}}.  The path can specified
// as a dotted string, or a string array.  If the path starts with a
// dot (or the first element is ''), the path is considered local, and
// resolved against the `current` argument, if defined.  Integer path
// parts are used as array indexes.  The state argument allows for
// custom handling when called from `inject` or `transform`.
function getpath(path, store, current, state) {

  // Operate on a string array.
  const parts = islist(path) ? path : S_string === typeof path ? path.split(S_DT) : UNDEF

  if (UNDEF === parts) {
    return UNDEF
  }

  let root = store
  let val = store
  const base = getprop(state, S_base)

  // An empty path (incl empty string) just finds the store.
  if (null == path || null == store || (1 === parts.length && S_MT === parts[0])) {
    // The actual store data may be in a store sub property, defined by state.base.
    val = getprop(store, base, store)
  }
  else if (0 < parts.length) {
    let pI = 0

    // Relative path uses `current` argument.
    if (S_MT === parts[0]) {
      pI = 1
      root = current
    }

    let part = pI < parts.length ? parts[pI] : UNDEF
    let first = getprop(root, part)

    // At top level, check state.base, if provided
    val = (UNDEF === first && 0 === pI) ?
      getprop(getprop(root, base), part) :
      first

    // Move along the path, trying to descend into the store.
    for (pI++; UNDEF !== val && pI < parts.length; pI++) {
      val = getprop(val, parts[pI])
    }
  }

  // State may provide a custom handler to modify found value.
  if (null != state && isfunc(state.handler)) {
    const ref = pathify(path)
    val = state.handler(state, val, current, ref, store)
  }

  return val
}


// Inject values from a data store into a node recursively, resolving
// paths against the store, or current if they are local. THe modify
// argument allows custom modification of the result.  The state
// (InjectState) argument is used to maintain recursive state.
function inject(
  val,
  store,
  modify,
  current,
  state
) {
  const valtype = typeof val

  // Create state if at root of injection.  The input value is placed
  // inside a virtual parent holder to simplify edge cases.
  if (UNDEF === state) {
    const parent = { [S_DTOP]: val }

    // Set up state assuming we are starting in the virtual parent.
    state = {
      mode: S_MVAL,
      full: false,
      keyI: 0,
      keys: [S_DTOP],
      key: S_DTOP,
      val,
      parent,
      path: [S_DTOP],
      nodes: [parent],
      handler: _injecthandler,
      base: S_DTOP,
      modify,
      errs: getprop(store, S_DERRS, []),
      meta: {},
    }
  }

  // Resolve current node in store for local paths.
  if (UNDEF === current) {
    current = { $TOP: store }
  }
  else {
    const parentkey = getprop(state.path, state.path.length - 2)
    current = null == parentkey ? current : getprop(current, parentkey)
  }

  // Descend into node.
  if (isnode(val)) {

    // Keys are sorted alphanumerically to ensure determinism.
    // Injection transforms ($FOO) are processed *after* other keys.
    // NOTE: the optional digits suffix of the transform can thus be
    // used to order the transforms.
    let nodekeys = ismap(val) ? [
      ...Object.keys(val).filter(k => !k.includes(S_DS)).sort(),
      ...Object.keys(val).filter(k => k.includes(S_DS)).sort(),
    ] : val.map((_n, i) => i)

    // Each child key-value pair is processed in three injection phases:
    // 1. state.mode='key:pre' - Key string is injected, returning a possibly altered key.
    // 2. state.mode='val' - The child value is injected.
    // 3. state.mode='key:post' - Key string is injected again, allowing child mutation.
    for (let nkI = 0; nkI < nodekeys.length; nkI++) {
      const nodekey = S_MT + nodekeys[nkI]

      // let child = parent[nodekey]
      let childpath = [...(state.path || []), nodekey]
      let childnodes = [...(state.nodes || []), val]
      let childval = getprop(val, nodekey)

      const childstate = {
        mode: S_MKEYPRE,
        full: false,
        keyI: nkI,
        keys: nodekeys,
        key: nodekey,
        val: childval,
        parent: val,
        path: childpath,
        nodes: childnodes,
        handler: _injecthandler,
        base: state.base,
        errs: state.errs,
        meta: state.meta,
      }

      // Peform the key:pre mode injection on the child key.
      const prekey = _injectstr(nodekey, store, current, childstate)

      // The injection may modify child processing.
      nkI = childstate.keyI
      nodekeys = childstate.keys

      // Prevent further processing by returning an undefined prekey
      if (UNDEF !== prekey) {
        childstate.val = childval = getprop(val, prekey)
        childstate.mode = S_MVAL

        // Perform the val mode injection on the child value.
        // NOTE: return value is not used.
        inject(childval, store, modify, current, childstate)

        // The injection may modify child processing.
        nkI = childstate.keyI
        nodekeys = childstate.keys

        // Peform the key:post mode injection on the child key.
        childstate.mode = S_MKEYPOST
        _injectstr(nodekey, store, current, childstate)

        // The injection may modify child processing.
        nkI = childstate.keyI
        nodekeys = childstate.keys
      }
    }
  }

  // Inject paths into string scalars.
  else if (S_string === valtype) {
    state.mode = S_MVAL
    val = _injectstr(val, store, current, state)

    setprop(state.parent, state.key, val)
  }

  // Custom modification.
  if (modify) {
    let mkey = state.key
    let mparent = state.parent
    let mval = getprop(mparent, mkey)
    modify(
      mval,
      mkey,
      mparent,
      state,
      current,
      store
    )
  }

  // Original val reference may no longer be correct.
  // This return value is only used as the top level result.
  return getprop(state.parent, S_DTOP)
}


// The transform_* functions are special command inject handlers (see Injector).

// Delete a key from a map or list.
const transform_DELETE = (state) => {
  _setparentprop(state, UNDEF)
  return UNDEF
}


// Copy value from source data.
const transform_COPY = (state, _val, current) => {
  const { mode, key } = state

  let out = key
  if (!mode.startsWith(S_MKEY)) {
    out = getprop(current, key)
    _setparentprop(state, out)
  }

  return out
}


// As a value, inject the key of the parent node.
// As a key, defined the name of the key property in the source object.
const transform_KEY = (state, _val, current) => {
  const { mode, path, parent } = state

  // Do nothing in val mode.
  if (S_MVAL !== mode) {
    return UNDEF
  }

  // Key is defined by $KEY meta property.
  const keyspec = getprop(parent, S_DKEY)
  if (UNDEF !== keyspec) {
    setprop(parent, S_DKEY, UNDEF)
    return getprop(current, keyspec)
  }

  // Key is defined within general purpose $META object.
  return getprop(getprop(parent, S_DMETA), S_KEY, getprop(path, path.length - 2))
}


// Store meta data about a node.  Does nothing itself, just used by
// other injectors, and is removed when called.
const transform_META = (state) => {
  const { parent } = state
  setprop(parent, S_DMETA, UNDEF)
  return UNDEF
}


// Merge a list of objects into the current object. 
// Must be a key in an object. The value is merged over the current object.
// If the value is an array, the elements are first merged using `merge`. 
// If the value is the empty string, merge the top level store.
// Format: { '`$MERGE`': '`source-path`' | ['`source-paths`', ...] }
const transform_MERGE = (
  state, _val, current
) => {
  const { mode, key, parent } = state

  if (S_MKEYPRE === mode) { return key }

  // Operate after child values have been transformed.
  if (S_MKEYPOST === mode) {

    let args = getprop(parent, key)
    args = S_MT === args ? [current.$TOP] : Array.isArray(args) ? args : [args]

    // Remove the $MERGE command from a parent map.
    _setparentprop(state, UNDEF)

    // Literals in the parent have precedence, but we still merge onto
    // the parent object, so that node tree references are not changed.
    const mergelist = [parent, ...args, clone(parent)]

    merge(mergelist)

    return key
  }

  // Ensures $MERGE is removed from parent list.
  return UNDEF
}


// Convert a node to a list.
// Format: ['`$EACH`', '`source-path-of-node`', child-template]
const transform_EACH = (
  state,
  _val,
  current,
  _ref,
  store
) => {
  const { mode, keys, path, parent, nodes } = state

  // Remove arguments to avoid spurious processing.
  if (null != state.keys) {
    state.keys.length = 1
  }

  if (S_MVAL !== state.mode) {
    return UNDEF
  }

  // Get arguments: ['`$EACH`', 'source-path', child-template].
  const srcpath = getprop(state.parent, 1)
  const child = clone(getprop(state.parent, 2))

  // Source data.
  // const src = getpath(srcpath, store, current, state)
  const srcstore = getprop(store, state.base, store)
  const src = getpath(srcpath, srcstore, current)

  // Create parallel data structures:
  // source entries :: child templates
  let tcur = []
  let tval = []

  const tkey = state.path[state.path.length - 2]
  const target = state.nodes[state.path.length - 2] || state.nodes[state.path.length - 1]

  // Create clones of the child template for each value of the current soruce.
  if (islist(src)) {
    tval = src.map(() => clone(child))
  }
  else if (ismap(src)) {
    tval = Object.entries(src).map(n => ({
      ...clone(child),

      // Make a note of the key for $KEY transforms.
      [S_DMETA]: { KEY: n[0] }
    }))
  }

  tcur = null == src ? UNDEF : Object.values(src)

  // Parent structure.
  tcur = { $TOP: tcur }

  // Build the substructure.
  tval = inject(tval, store, state.modify, tcur)

  _updateAncestors(state, target, tkey, tval)

  // Prevent callee from damaging first list entry (since we are in `val` mode).
  return tval[0]
}



// Convert a node to a map.
// Format: { '`$PACK`':['`source-path`', child-template]}
const transform_PACK = (
  state,
  _val,
  current,
  ref,
  store
) => {
  const { mode, key, path, parent, nodes } = state

  // Defensive context checks.
  if (S_MKEYPRE !== mode || S_string !== typeof key || null == path || null == nodes) {
    return UNDEF
  }

  // Get arguments.
  const args = parent[key]
  const srcpath = args[0] // Path to source data.
  const child = clone(args[1]) // Child template.

  // Find key and target node.
  const keyprop = child[S_DKEY]
  const tkey = path[path.length - 2]
  const target = nodes[path.length - 2] || nodes[path.length - 1]

  // Source data
  // const srcstore = getprop(store, getprop(state, S_base), store)
  const srcstore = getprop(store, state.base, store)
  let src = getpath(srcpath, srcstore, current)
  // let src = getpath(srcpath, store, current, state)

  // Prepare source as a list.
  src = islist(src) ? src :
    ismap(src) ? Object.entries(src)
      .reduce((a, n) =>
        (n[1][S_DMETA] = { KEY: n[0] }, a.push(n[1]), a), []) :
      UNDEF

  if (null == src) {
    return UNDEF
  }

  // Get key if specified.
  let childkey = getprop(child, S_DKEY)
  let keyname = UNDEF === childkey ? keyprop : childkey
  setprop(child, S_DKEY, UNDEF)

  // Build parallel target object.
  let tval = {}
  tval = src.reduce((a, n) => {
    let kn = getprop(n, keyname)
    setprop(a, kn, clone(child))
    const nchild = getprop(a, kn)
    setprop(nchild, S_DMETA, getprop(n, S_DMETA))
    return a
  }, tval)

  // Build parallel source object.
  let tcurrent = {}
  src.reduce((a, n) => {
    let kn = getprop(n, keyname)
    setprop(a, kn, n)
    return a
  }, tcurrent)

  tcurrent = { $TOP: tcurrent }

  // Build substructure.
  tval = inject(
    tval,
    store,
    state.modify,
    tcurrent,
  )

  _updateAncestors(state, target, tkey, tval)

  // Drop transform key.
  return UNDEF
}


// Transform data using spec.
// Only operates on static JSON-like data.
// Arrays are treated as if they are objects with indices as keys.
function transform(
  data, // Source data to transform into new data (original not mutated)
  spec, // Transform specification; output follows this shape
  extra, // Additional store of data and transforms.
  modify // Optionally modify individual values.
) {
  // Clone the spec so that the clone can be modified in place as the transform result.
  spec = clone(spec)

  const extraTransforms = {}
  const extraData = null == extra ? {} : items(extra)
    .reduce((a, n) =>
      (n[0].startsWith(S_DS) ? extraTransforms[n[0]] = n[1] : (a[n[0]] = n[1]), a), {})

  const dataClone = merge([
    clone(UNDEF === extraData ? {} : extraData),
    clone(UNDEF === data ? {} : data),
  ])

  // Define a top level store that provides transform operations.
  const store = {

    // The inject function recognises this special location for the root of the source data.
    // NOTE: to escape data that contains "`$FOO`" keys at the top level,
    // place that data inside a holding map: { myholder: mydata }.
    $TOP: dataClone,

    // Escape backtick (this also works inside backticks).
    $BT: () => S_BT,

    // Escape dollar sign (this also works inside backticks).
    $DS: () => S_DS,

    // Insert current date and time as an ISO string.
    $WHEN: () => new Date().toISOString(),

    $DELETE: transform_DELETE,
    $COPY: transform_COPY,
    $KEY: transform_KEY,
    $META: transform_META,
    $MERGE: transform_MERGE,
    $EACH: transform_EACH,
    $PACK: transform_PACK,

    // Custom extra transforms, if any.
    ...extraTransforms,
  }

  const out = inject(spec, store, modify, store)
  return out
}


// A required string value. NOTE: Rejects empty strings.
const validate_STRING = (state, _val, current) => {
  let out = getprop(current, state.key)

  const t = typify(out)
  if (S_string !== t) {
    let msg = _invalidTypeMsg(state.path, S_string, t, out)
    state.errs.push(msg)
    return UNDEF
  }

  if (S_MT === out) {
    let msg = 'Empty string at ' + pathify(state.path, 1)
    state.errs.push(msg)
    return UNDEF
  }

  return out
}


// A required number value (int or float).
const validate_NUMBER = (state, _val, current) => {
  let out = getprop(current, state.key)

  const t = typify(out)
  if (S_number !== t) {
    state.errs.push(_invalidTypeMsg(state.path, S_number, t, out))
    return UNDEF
  }

  return out
}


// A required boolean value.
const validate_BOOLEAN = (state, _val, current) => {
  let out = getprop(current, state.key)

  const t = typify(out)
  if (S_boolean !== t) {
    state.errs.push(_invalidTypeMsg(state.path, S_boolean, t, out))
    return UNDEF
  }

  return out
}


// A required object (map) value (contents not validated).
const validate_OBJECT = (state, _val, current) => {
  let out = getprop(current, state.key)

  const t = typify(out)
  if (t !== S_object) {
    state.errs.push(_invalidTypeMsg(state.path, S_object, t, out))
    return UNDEF
  }

  return out
}


// A required array (list) value (contents not validated).
const validate_ARRAY = (state, _val, current) => {
  let out = getprop(current, state.key)

  const t = typify(out)
  if (t !== S_array) {
    state.errs.push(_invalidTypeMsg(state.path, S_array, t, out))
    return UNDEF
  }

  return out
}


// A required function value.
const validate_FUNCTION = (state, _val, current) => {
  let out = getprop(current, state.key)

  const t = typify(out)
  if (S_function !== t) {
    state.errs.push(_invalidTypeMsg(state.path, S_function, t, out))
    return UNDEF
  }

  return out
}


// Allow any value.
const validate_ANY = (state, _val, current) => {
  return getprop(current, state.key)
}



// Specify child values for map or list.
// Map syntax: {'`$CHILD`': child-template }
// List syntax: ['`$CHILD`', child-template ]
const validate_CHILD = (state, _val, current) => {
  const { mode, key, parent, keys, path } = state

  // Setup data structures for validation by cloning child template.

  // Map syntax.
  if (S_MKEYPRE === mode) {
    const childtm = getprop(parent, key)

    // Get corresponding current object.
    const pkey = getprop(path, path.length - 2)
    let tval = getprop(current, pkey)

    if (UNDEF == tval) {
      tval = {}
    }
    else if (!ismap(tval)) {
      state.errs.push(_invalidTypeMsg(
        state.path.slice(0, state.path.length - 1), S_object, typify(tval), tval))
      return UNDEF
    }

    const ckeys = keysof(tval)
    for (let ckey of ckeys) {
      setprop(parent, ckey, clone(childtm))

      // NOTE: modifying state! This extends the child value loop in inject.
      keys.push(ckey)
    }

    // Remove $CHILD to cleanup ouput.
    _setparentprop(state, UNDEF)
    return UNDEF
  }

  // List syntax.
  if (S_MVAL === mode) {

    if (!islist(parent)) {
      // $CHILD was not inside a list.
      state.errs.push('Invalid $CHILD as value')
      return UNDEF
    }

    const childtm = getprop(parent, 1)

    if (UNDEF === current) {
      // Empty list as default.
      parent.length = 0
      return UNDEF
    }

    if (!islist(current)) {
      const msg = _invalidTypeMsg(
        state.path.slice(0, state.path.length - 1), S_array, typify(current), current)
      state.errs.push(msg)
      state.keyI = parent.length
      return current
    }

    // Clone children abd reset state key index.
    // The inject child loop will now iterate over the cloned children,
    // validating them againt the current list values.
    current.map((_n, i) => parent[i] = clone(childtm))
    parent.length = current.length
    state.keyI = 0
    const out = getprop(current, 0)
    return out
  }

  return UNDEF
}


// Match at least one of the specified shapes.
// Syntax: ['`$ONE`', alt0, alt1, ...]okI
const validate_ONE = (
  state,
  _val,
  current,
  _ref,
  store,
) => {
  const { mode, parent, path, keyI, nodes } = state

  // Only operate in val mode, since parent is a list.
  if (S_MVAL === mode) {
    if (!islist(parent) || 0 !== keyI) {
      state.errs.push('The $ONE validator at field ' +
        pathify(state.path, 1, 1) +
        ' must be the first element of an array.')
      return
    }

    state.keyI = state.keys.length

    const grandparent = nodes[nodes.length - 2]
    const grandkey = path[path.length - 2]

    // Clean up structure, replacing [$ONE, ...] with current
    setprop(grandparent, grandkey, current)
    state.path = state.path.slice(0, state.path.length - 1)
    state.key = state.path[state.path.length - 1]

    let tvals = parent.slice(1)
    if (0 === tvals.length) {
      state.errs.push('The $ONE validator at field ' +
        pathify(state.path, 1, 1) +
        ' must have at least one argument.')
      return
    }

    // See if we can find a match.
    for (let tval of tvals) {

      // If match, then errs.length = 0
      let terrs = []
      validate(current, tval, store, terrs)

      // Accept current value if there was a match
      if (0 === terrs.length) {
        return
      }
    }

    // There was no match.

    const valdesc = tvals
      .map((v) => stringify(v))
      .join(', ')
      .replace(/`\$([A-Z]+)`/g, (_m, p1) => p1.toLowerCase())

    state.errs.push(_invalidTypeMsg(
      state.path,
      (1 < tvals.length ? 'one of ' : '') + valdesc,
      typify(current), current, 'V0210'))
  }
}


// Match exactly one of the specified shapes.
// Syntax: ['`$EXACT`', val0, val1, ...]
const validate_EXACT = (
  state,
  _val,
  current,
  _ref,
  _store
) => {
  const { mode, parent, key, keyI, path, nodes } = state

  // Only operate in val mode, since parent is a list.
  if (S_MVAL === mode) {
    if (!islist(parent) || 0 !== keyI) {
      state.errs.push('The $EXACT validator at field ' +
        pathify(state.path, 1, 1) +
        ' must be the first element of an array.')
      return
    }

    state.keyI = state.keys.length

    const grandparent = nodes[nodes.length - 2]
    const grandkey = path[path.length - 2]

    // Clean up structure, replacing [$EXACT, ...] with current
    setprop(grandparent, grandkey, current)
    state.path = state.path.slice(0, state.path.length - 1)
    state.key = state.path[state.path.length - 1]

    let tvals = parent.slice(1)
    if (0 === tvals.length) {
      state.errs.push('The $EXACT validator at field ' +
        pathify(state.path, 1, 1) +
        ' must have at least one argument.')
      return
    }

    // See if we can find an exact value match.
    let currentstr = undefined
    for (let tval of tvals) {
      // console.log('TVAL', tval, stringify(tval), stringify(current))
      let exactmatch = tval === current

      if (!exactmatch && isnode(tval)) {
        currentstr = undefined === currentstr ? stringify(current) : currentstr
        const tvalstr = stringify(tval)
        exactmatch = tvalstr === currentstr
      }

      if (exactmatch) {
        return
      }
    }

    const valdesc = tvals
      .map((v) => stringify(v))
      .join(', ')
      .replace(/`\$([A-Z]+)`/g, (_m, p1) => p1.toLowerCase())

    state.errs.push(_invalidTypeMsg(
      state.path,
      (1 < state.path.length ? '' : 'value ') +
      'exactly equal to ' + (1 === tvals.length ? '' : 'one of ') + valdesc,
      typify(current), current, 'V0110'))
  }
  else {
    setprop(parent, key, UNDEF)
  }
}


// This is the "modify" argument to inject. Use this to perform
// generic validation. Runs *after* any special commands.
const _validation = (
  pval,
  key,
  parent,
  state,
  current,
  _store
) => {

  if (UNDEF === state) {
    return
  }

  // Current val to verify.
  const cval = getprop(current, key)

  if (UNDEF === cval || UNDEF === state) {
    return
  }

  // const pval = getprop(parent, key)
  const ptype = typify(pval)

  // Delete any special commands remaining.
  if (S_string === ptype && pval.includes(S_DS)) {
    return
  }

  const ctype = typify(cval)

  // Type mismatch.
  if (ptype !== ctype && UNDEF !== pval) {
    state.errs.push(_invalidTypeMsg(state.path, ptype, ctype, cval, 'V0010'))
    return
  }

  if (ismap(cval)) {
    if (!ismap(pval)) {
      state.errs.push(_invalidTypeMsg(state.path, ptype, ctype, cval, 'V0020'))
      return
    }

    const ckeys = keysof(cval)
    const pkeys = keysof(pval)

    // Empty spec object {} means object can be open (any keys).
    if (0 < pkeys.length && true !== getprop(pval, '`$OPEN`')) {
      const badkeys = []
      for (let ckey of ckeys) {
        if (!haskey(pval, ckey)) {
          badkeys.push(ckey)
        }
      }

      // Closed object, so reject extra keys not in shape.
      if (0 < badkeys.length) {
        const msg =
          'Unexpected keys at field ' + pathify(state.path, 1) + ': ' + badkeys.join(', ')
        state.errs.push(msg)
      }
    }
    else {
      // Object is open, so merge in extra keys.
      merge([pval, cval])
      if (isnode(pval)) {
        setprop(pval, '`$OPEN`', UNDEF)
      }
    }
  }
  else if (islist(cval)) {
    if (!islist(pval)) {
      state.errs.push(_invalidTypeMsg(state.path, ptype, ctype, cval, 'V0030'))
    }
  }
  else {
    // Spec value was a default, copy over data
    setprop(parent, key, cval)
  }

  return
}



// Validate a data structure against a shape specification.  The shape
// specification follows the "by example" principle.  Plain data in
// teh shape is treated as default values that also specify the
// required type.  Thus shape {a:1} validates {a:2}, since the types
// (number) match, but not {a:'A'}.  Shape {a;1} against data {}
// returns {a:1} as a=1 is the default value of the a key.  Special
// validation commands (in the same syntax as transform ) are also
// provided to specify required values.  Thus shape {a:'`$STRING`'}
// validates {a:'A'} but not {a:1}. Empty map or list means the node
// is open, and if missing an empty default is inserted.
function validate(
  data, // Source data to transform into new data (original not mutated)
  spec, // Transform specification; output follows this shape

  extra, // Additional custom checks

  // Optionally modify individual values.
  collecterrs,
) {
  const errs = null == collecterrs ? [] : collecterrs

  const store = {
    // Remove the transform commands.
    $DELETE: null,
    $COPY: null,
    $KEY: null,
    $META: null,
    $MERGE: null,
    $EACH: null,
    $PACK: null,

    $STRING: validate_STRING,
    $NUMBER: validate_NUMBER,
    $BOOLEAN: validate_BOOLEAN,
    $OBJECT: validate_OBJECT,
    $ARRAY: validate_ARRAY,
    $FUNCTION: validate_FUNCTION,
    $ANY: validate_ANY,
    $CHILD: validate_CHILD,
    $ONE: validate_ONE,
    $EXACT: validate_EXACT,

    ...(extra || {}),

    // A special top level value to collect errors.
    $ERRS: errs,
  }

  const out = transform(data, spec, store, _validation)

  const generr = (0 < errs.length && null == collecterrs)
  if (generr) {
    throw new Error('Invalid data: ' + errs.join(' | '))
  }

  return out
}


// Internal utilities
// ==================


// Set state.key property of state.parent node, ensuring reference consistency
// when needed by implementation language.
function _setparentprop(state, val) {
  setprop(state.parent, state.key, val)
}


// Update all references to target in state.nodes.
function _updateAncestors(_state, target, tkey, tval) {
  // SetProp is sufficient in JavaScript as target reference remains consistent even for lists.
  setprop(target, tkey, tval)
}


// Build a type validation error message.
function _invalidTypeMsg(path, needtype, vt, v, _whence) {
  let vs = null == v ? 'no value' : stringify(v)

  return 'Expected ' +
    (1 < path.length ? ('field ' + pathify(path, 1) + ' to be ') : '') +
    needtype + ', but found ' +
    (null != v ? vt + ': ' : '') + vs +

    // Uncomment to help debug validation errors.
    // (null == _whence ? '' : ' [' + _whence + ']') +

    '.'
}


// Default inject handler for transforms. If the path resolves to a function,
// call the function passing the injection state. This is how transforms operate.
const _injecthandler = (
  state,
  val,
  current,
  ref,
  store
) => {
  let out = val
  const iscmd = isfunc(val) && (UNDEF === ref || ref.startsWith(S_DS))

  // Only call val function if it is a special command ($NAME format).
  if (iscmd) {
    out = val(state, val, current, ref, store)
  }

  // Update parent with value. Ensures references remain in node tree.
  else if (S_MVAL === state.mode && state.full) {
    // setprop(state.parent, state.key, val)
    _setparentprop(state, val)
  }

  return out
}


// Inject values from a data store into a string. Not a public utility - used by
// `inject`.  Inject are marked with `path` where path is resolved
// with getpath against the store or current (if defined)
// arguments. See `getpath`.  Custom injection handling can be
// provided by state.handler (this is used for transform functions).
// The path can also have the special syntax $NAME999 where NAME is
// upper case letters only, and 999 is any digits, which are
// discarded. This syntax specifies the name of a transform, and
// optionally allows transforms to be ordered by alphanumeric sorting.
function _injectstr(
  val,
  store,
  current,
  state
) {
  // Can't inject into non-strings
  if (S_string !== typeof val || S_MT === val) {
    return S_MT
  }

  let out = val

  // Pattern examples: "`a.b.c`", "`$NAME`", "`$NAME1`"
  const m = val.match(/^`(\$[A-Z]+|[^`]+)[0-9]*`$/)

  // Full string of the val is an injection.
  if (m) {
    if (null != state) {
      state.full = true
    }
    let pathref = m[1]

    // Special escapes inside injection.
    pathref =
      3 < pathref.length ? pathref.replace(/\$BT/g, S_BT).replace(/\$DS/g, S_DS) : pathref

    // Get the extracted path reference.
    out = getpath(pathref, store, current, state)
  }

  else {
    // Check for injections within the string.
    const partial = (_m, ref) => {
      // Special escapes inside injection.
      ref = 3 < ref.length ? ref.replace(/\$BT/g, S_BT).replace(/\$DS/g, S_DS) : ref
      if (state) {
        state.full = false
      }
      const found = getpath(ref, store, current, state)

      // Ensure inject value is a string.
      return UNDEF === found ? S_MT : S_string === typeof found ? found : JSON.stringify(found)
      // S_object === typeof found ? JSON.stringify(found) :
      // found
    }

    out = val.replace(/`([^`]+)`/g, partial)

    // Also call the state handler on the entire string, providing the
    // option for custom injection.
    if (null != state && isfunc(state.handler)) {
      state.full = true
      out = state.handler(state, out, current, val, store)
    }
  }

  return out
}


module.exports = {
  clone,
  escre,
  escurl,
  getpath,
  getprop,
  haskey,
  inject,
  isempty,
  isfunc,
  iskey,
  islist,
  ismap,
  isnode,
  items,
  joinurl,
  keysof,
  merge,
  pathify,
  setprop,
  strkey,
  stringify,
  transform,
  typify,
  validate,
  walk,
}

