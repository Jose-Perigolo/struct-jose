package voxgigstruct

import (
	"encoding/json"
	"fmt"
	"net/url"
	"reflect"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// ---------------------------------------------------------------------
// String constants (mirroring the TypeScript S object).

const (
	MKEYPRE  = "key:pre"
	MKEYPOST = "key:post"
	MVAL     = "val"

	TKEY  = "`$KEY`"
	TMETA = "`$META`"

	KEY  = "KEY"
	DTOP = "$TOP"

	OBJECT   = "object"
	NUMBER   = "number"
	STRING   = "string"
	FUNCTION = "function"
	EMPTY    = ""
	BASE     = "Base"

	BT = "`"
	DS = "$"
	DT = "."
)

// ---------------------------------------------------------------------
// Basic type aliases to replicate the TS definitions.

// PropKey can be either string or number in the original TypeScript.
// In Go, we simply treat it as an empty interface and do runtime checks.
type PropKey interface{}

// InjectMode is "key:pre" | "key:post" | "val".
type InjectMode string

const (
	InjectModeKeyPre  InjectMode = MKEYPRE
	InjectModeKeyPost InjectMode = MKEYPOST
	InjectModeVal     InjectMode = MVAL
)

// Injection replicates the recursive state used during injection.
type Injection struct {
	Mode    InjectMode
	Full    bool
	KeyI    int
	Keys    []string
	Key     string
	Val     interface{}
	Parent  interface{}
	Path    []string
	Nodes   []interface{}
	Handler InjectHandler
	Base    string
	Modify  Modify
}

// InjectHandler corresponds to the TypeScript signature:
// (state, val, current, store) => any
type InjectHandler func(
	state *Injection,
	val interface{},
	current interface{},
	store interface{},
) interface{}

// Modify corresponds to the TS type that customizes injection output.
type Modify func(
	key interface{},
	val interface{},
	parent interface{},
	state *Injection,
	current interface{},
	store interface{},
)

// WalkApply replicates the function applied at each node in walk().
type WalkApply func(
	key *string,
	val interface{},
	parent interface{},
	path []string,
) interface{}

func strKey(key interface{}) string {
	switch v := key.(type) {
	case string:
		return v
	case int:
		return strconv.Itoa(v)
	case int64:
		return strconv.FormatInt(v, 10)
	case float64:
		return strconv.FormatFloat(v, 'f', -1, 64)
	case float32:
		return strconv.FormatFloat(float64(v), 'f', -1, 32)
	default:
		return fmt.Sprintf("%v", v)
	}
}

func resolveStrings(input []interface{}) []string {
	var result []string

	for _, v := range input {
		if str, ok := v.(string); ok {
			result = append(result, str)
		} else {
			result = append(result, strKey(v))
		}
	}

	return result
}


func listify(src interface{}) []interface{} {
	if list, ok := src.([]interface{}); ok {
		return list
	}

	if src == nil {
		return nil
	}

	val := reflect.ValueOf(src)
	if val.Kind() == reflect.Slice {
		length := val.Len()
		result := make([]interface{}, length)

		for i := 0; i < length; i++ {
			result[i] = val.Index(i).Interface()
		}
		return result
	}

	return nil
}


// ---------------------------------------------------------------------
// Utility checks

// IsNode checks if val is non-nil and is an object/map or array.
func IsNode(val interface{}) bool {
	if val == nil {
		return false
	}
	// In JS: typeof val == 'object'
	// In Go, we approximate by checking if it's either map[...]... or []...
	switch val.(type) {
	case map[string]interface{}, []interface{}:
		return true
	default:
		return false
	}
}

// IsMap checks if val is a non-nil map (JS object).
func IsMap(val interface{}) bool {
	if val == nil {
		return false
	}
	_, ok := val.(map[string]interface{})
	return ok
}

// IsList checks if val is a non-nil slice (JS array).
func IsList(val interface{}) bool {
	if val == nil {
		return false
	}
	_, ok := val.([]interface{})
	return ok
}

// IsKey checks if key is a non-empty string or an integer.
func IsKey(key interface{}) bool {
	switch k := key.(type) {
	case string:
		return k != EMPTY
	case int, float64, int8, int16, int32, int64:
		return true
	case uint8, uint16, uint32, uint64, uint, float32:
		return true
	default:
		return false
	}
}

// IsEmpty replicates the TS function checking for “empty” values:
//   - nil
//   - ""
//   - false
//   - 0
//   - empty array
//   - empty object
func IsEmpty(val interface{}) bool {
	if val == nil {
		return true
	}
	switch vv := val.(type) {
	case bool:
		return vv == false
	case string:
		return vv == EMPTY
	case float64:
		// JSON decoding of numeric 0 becomes float64(0)
		return vv == 0
	case int:
		return vv == 0
	case []interface{}:
		return len(vv) == 0
	case map[string]interface{}:
		return len(vv) == 0
	}
	return false
}

// ---------------------------------------------------------------------
// Misc string utilities

// Stringify attempts to JSON-stringify `val`, then remove quotes, for debug printing.
// If maxlen is provided, the string is truncated.
func Stringify(val interface{}, maxlen ...int) string {
  // if nil == val {
  //   return "null"
  // }

  b, err := json.Marshal(val)
	if err != nil {
		// fallback
		return ""
	}
	jsonStr := string(b)

	// Remove double quotes from the edges if they exist.
	jsonStr = strings.ReplaceAll(jsonStr, `"`, "")

	if len(maxlen) > 0 && maxlen[0] > 0 {
		ml := maxlen[0]
		if len(jsonStr) > ml {
			// ensure space for "..."
			if ml >= 3 {
				jsonStr = jsonStr[:ml-3] + "..."
			} else {
				// fallback
				jsonStr = jsonStr[:ml]
			}
		}
	}

	return jsonStr
}

// EscRe escapes a string for use in a regular expression.
func EscRe(s string) string {
	if s == "" {
		return ""
	}
	// In TS, /[.*+?^${}()|[\]\\]/g => \\$&
	re := regexp.MustCompile(`[.*+?^${}()|\[\]\\]`)
	return re.ReplaceAllString(s, `\${0}`)
}

// EscUrl escapes a string for safe inclusion in a URL.
func EscUrl(s string) string {
	return url.QueryEscape(s)
}

// ---------------------------------------------------------------------
// Items lists the key/value pairs (like Object.entries).


func Keys(val interface{}) []string {
	if IsMap(val) {
		m := val.(map[string]interface{})

		keys := make([]string, 0, len(m))
		for k := range m {
			keys = append(keys, k)
		}

		sort.Strings(keys)

    return keys
    
	} else if IsList(val) {
    arr := val.([]interface{})
    keys := make([]string, len(arr))
    for i := range arr {
      keys[i] = strKey(i)
    }
    return keys
	}

	return make([]string, 0)
}

func SortedKeys(val interface{}, ckey string) []string {
  type pair struct {
    k string
    c string
  }

  if IsMap(val) {
		m := val.(map[string]interface{})

		pairs := make([]pair, 0, len(m))
		for k, v := range m {
			pairs = append(pairs, pair{k:k,c:strKey(GetProp(v,ckey))})
		}

    sort.Slice(pairs, func(i, j int) bool {
      return pairs[i].c < pairs[j].c
    })

    keys := make([]string, len(pairs))
    for i, pair := range pairs {
      keys[i] = pair.k
    }

    return keys
    
	} else if IsList(val) {
    arr := val.([]interface{})
    keys := make([]string, len(arr))
    for i := range arr {
      keys[i] = strKey(i)
    }
    return keys
	}

	return make([]string, 0)
}


func Items(val interface{}) [][2]interface{} {
	if IsMap(val) {
		m := val.(map[string]interface{})
		out := make([][2]interface{}, 0, len(m))

		// Step 1: Extract and sort keys
		keys := make([]string, 0, len(m))
		for k := range m {
			keys = append(keys, k)
		}
		sort.Strings(keys) // Ensures deterministic order

		// Step 2: Iterate over sorted keys
		for _, k := range keys {
			out = append(out, [2]interface{}{k, m[k]})
		}
		return out
	} else if IsList(val) {
		arr := val.([]interface{})
		out := make([][2]interface{}, 0, len(arr))
		for i, v := range arr {
			out = append(out, [2]interface{}{i, v})
		}
		return out
	}
	return nil
}

// ---------------------------------------------------------------------
// Clone a JSON-like data structure using JSON round-trips.

func Clone(val interface{}) interface{} {
	switch v := val.(type) {
	case map[string]interface{}:
		// Clone a map
		newMap := make(map[string]interface{}, len(v))
		for key, value := range v {
			newMap[key] = Clone(value)
		}
		return newMap
	case []interface{}:
		// Clone a list
		newSlice := make([]interface{}, len(v))
		for i, value := range v {
			newSlice[i] = Clone(value)
		}
		return newSlice
	default:
		// Primitive types (string, number, bool, nil) are immutable, so return as-is
		return v
	}

  // if val == nil {
	// 	return nil
	// }
	// b, err := json.Marshal(val)
	// if err != nil {
	// 	return nil
	// }
	// var out interface{}
	// _ = json.Unmarshal(b, &out)
	// return out
}

// ---------------------------------------------------------------------
// GetProp: safely get val[key], or alt if missing.

func GetProp(val interface{}, key interface{}, alt ...interface{}) interface{} {
	var out interface{}

	if len(alt) > 0 {
		out = alt[0]
	}

	if val == nil || key == nil {
		return out
	}

	switch v := val.(type) {
	case map[string]interface{}:
		ks, ok := key.(string)
		if !ok {
			// ks = fmt.Sprintf("%v", key)
			ks = strKey(key)
		}

		res, has := v[ks]
		if has {
			out = res
		}
	case []interface{}:
		ki, ok := key.(int)
		if !ok {
			// might be float64 from JSON
			switch kf := key.(type) {
			case float64:
				ki = int(kf)

			case string:
				ki = -1
				ski, err := strconv.Atoi(key.(string))
				if nil == err {
					ki = ski
				}
			}
		}
		if 0 <= ki && ki < len(v) {
			out = v[ki]
		}

	default:
		valRef := reflect.ValueOf(val)
		if valRef.Kind() == reflect.Ptr {
			valRef = valRef.Elem()
		}

		if valRef.Kind() == reflect.Struct {
			ks, ok := key.(string)
			if !ok {
				ks = strKey(key)
			}

			field := valRef.FieldByName(ks)
			if field.IsValid() {
				out = field.Interface()
			}
		}
	}

	return out
}

// ---------------------------------------------------------------------
// SetProp: safely set val[key] = newval (or delete if newval==nil).

func SetProp(parent interface{}, key interface{}, newval interface{}) interface{} {
	if !IsKey(key) {
		return parent
	}

	if IsMap(parent) {
		m := parent.(map[string]interface{})

		// Convert key to string
		ks := ""
		// ks = fmt.Sprintf("%v", key)
		ks = strKey(key)

		if newval == nil {
			delete(m, ks)
		} else {
			m[ks] = newval
		}
	} else if IsList(parent) {
		arr := parent.([]interface{})

		// Convert key to integer
		var ki int
		switch k := key.(type) {
		case int:
			ki = k
		case float64:
			ki = int(k)
		case string:
			// try to parse
			// e.g. "0", "10", etc.
			// not strictly TS behavior, but an approximation
			// var err error
			// attempt parse
			// ignoring error means zero if parse fails
			// to keep consistent with the TS code
			// you may want to handle errors more strictly
			kiParsed, e := parseInt(k)
			if e == nil {
				ki = kiParsed
			} else {
				// no-op, can't set
				return parent
			}
		default:
			return parent
		}

		// If newval == nil, remove element [shift down].
		if newval == nil {
			if ki >= 0 && ki < len(arr) {
				copy(arr[ki:], arr[ki+1:])
				arr = arr[:len(arr)-1]
			}
			return arr
		}

		// If ki >= 0, set or append
		if ki >= 0 {
			if ki >= len(arr) {
				arr = append(arr, newval)
			} else {
				arr[ki] = newval
			}
			return arr
		}

		// If ki < 0, prepend
		if ki < 0 {
			// prepend
			newarr := make([]interface{}, 0, len(arr)+1)
			newarr = append(newarr, newval)
			newarr = append(newarr, arr...)
			return newarr
		}
	}
	return parent
}

// parseInt is a helper to convert a string to int safely.
func parseInt(s string) (int, error) {
	// We’ll do a very simple parse:
	var x int
	var sign int = 1
	for i, c := range s {
		if c == '-' && i == 0 {
			sign = -1
			continue
		}
		if c < '0' || c > '9' {
			return 0, &ParseIntError{s}
		}
		x = 10*x + int(c-'0')
	}
	return x * sign, nil
}

type ParseIntError struct{ input string }

func (e *ParseIntError) Error() string {
	return "cannot parse int from: " + e.input
}

// ---------------------------------------------------------------------
// Walk: Depth-first traversal applying a function to each node.

func Walk(
	val interface{},
	apply WalkApply,
	key *string,
	parent interface{},
	path []string,
) interface{} {

	if IsNode(val) {
		for _, kv := range Items(val) {
			ckey := kv[0]
			child := kv[1]
			ckeyStr := strKey(ckey)
			newChild := Walk(child, apply, &ckeyStr, val, append(path, ckeyStr))
			val = SetProp(val, ckey, newChild)
		}


		if nil != parent && nil != key {
			_ = SetProp(parent, *key, val)
		}
	}

	val = apply(key, val, parent, path)

	return val
}

// ---------------------------------------------------------------------
// Merge: merges an array of nodes from left to right; later override earlier.

func Merge(src interface{}) interface{} {
	if !IsList(src) {
    return src
  }
  
	var out interface{}

  objs := listify(src)
  
	if len(objs) == 0 {
		out = nil

	} else if len(objs) == 1 {
		out = objs[0]

	} else {
		out = objs[0]

		// Merge the rest onto the first
		for i := 1; i < len(objs); i++ {
      obj := objs[i]
      
			if !IsNode(obj) {

				// Nodes win.
				out = obj

			} else {
				// Nodes win, also over nodes of a different kind.
				if !IsNode(out) ||
					(IsMap(obj) && IsList(out)) ||
					(IsList(obj) && IsMap(out)) {

					out = obj

				} else {

					var cur []interface{} = make([]interface{}, 11)
					cI := 0
          cur[cI] = out
          
					Walk(obj, func(
						key *string,
						val interface{},
						parent interface{},
						path []string,
					) interface{} {

						if nil == key {
							return val
						}

						lenpath := len(path)
						cI = lenpath - 1

						if nil == cur[cI] {
							cur[cI] = GetPath(path[:lenpath-1], out)
						}

						if nil == cur[cI] {
							if IsList(parent) {
								cur[cI] = make([]interface{}, 0)
							} else {
								cur[cI] = make(map[string]interface{})
							}
						}

						if IsNode(val) {
						  cur[cI] = SetProp(cur[cI], *key, cur[cI+1])
						  cur[cI+1] = nil

						} else {
						  cur[cI] = SetProp(cur[cI], *key, val)
						}

						return val

					}, nil, nil, nil)

          out = cur[0]
        }
			}
		}
	}
  
	return out
}

// getNodeByPath gets or creates a node in `root` by following `path`.
func getNodeByPath(root interface{}, path []string) interface{} {
	curr := root
	for _, part := range path {
		next := GetProp(curr, part)
		if !IsNode(next) {
			// create empty node
			// if the part was an integer in string form, assume list
			if _, err := parseInt(part); err == nil {
				next = []interface{}{}
			} else {
				next = map[string]interface{}{}
			}
			SetProp(curr, part, next)
		}
		curr = next
	}
	return curr
}

// ---------------------------------------------------------------------
// GetPath: retrieve nested values by path. Path can be string with '.' or []string.

func GetPath(path interface{}, store interface{}) interface{} {
	return GetPathState(path, store, nil, nil)
}

func GetPathState(path interface{}, store interface{}, current interface{}, state *Injection) interface{} {
	var parts []string

  val := store
  root := store

	switch pp := path.(type) {
	case []string:
		parts = pp

	case string:
		if pp == "" {
			parts = []string{EMPTY}
		} else {
			parts = strings.Split(pp, DT)
		}
  default:
    if IsList(path) {
      parts = resolveStrings(pp.([]interface{}))
    } else {
      return nil
    }    
	}

	if nil == path || nil == store || (1 == len(parts) && EMPTY == parts[0]) {
		val = GetProp(store, GetProp(state, BASE), store)

	} else if 0 < len(parts) {

    
		pI := 0

		if parts[0] == EMPTY {
      pI = 1
			root = current
		}

    var part *string
		if pI < len(parts) {
			part = &parts[pI]
    }

    first := GetProp(root, *part)

    val = first
    if pI == 0 && first == nil  {
      val = GetProp(GetProp(root, (GetProp(state, BASE))), *part)
    }
      
    pI++
    for nil != val && pI < len(parts) {
      val = GetProp(val, parts[pI])
      pI++
		}
	}

	if state != nil && state.Handler != nil {
    val = state.Handler(state, val, current, store)
	}

	return val
}

func getType(v interface{}) string {
  if nil == v {
    return "nil"
  }
  return reflect.TypeOf(v).String()
}

// ---------------------------------------------------------------------
// injectStr: internal function that handles backtick injections in strings.

func injectStr(val string, store interface{}, current interface{}, state *Injection) interface{} {
	if val == "" {
		return ""
	}

	// Full-string injection: matches /^`(\$[A-Z]+|[^`]+)[0-9]*`$/
	// e.g. `a.b.c` or `$FOO` or `$FOO123`
	// The RegEx is somewhat simplified here:
	fullRe := regexp.MustCompile("^`([^`]+)[0-9]*`$")
	matches := fullRe.FindStringSubmatch(val)
	if matches != nil {
		// full injection
		if state != nil {
			state.Full = true
		}
		ref := matches[1]

		// Special escapes
		if len(ref) > 3 {
			ref = strings.ReplaceAll(ref, "$BT", BT)
			ref = strings.ReplaceAll(ref, "$DS", DS)
		}
		out := GetPathState(ref, store, current, state)
    // fmt.Println("INJECTSTR", val, out)
    
    return out
	}

	// Partial injection
	// e.g. "Hello `name`, you owe `amount` dollars"
	partialRe := regexp.MustCompile("`([^`]+)`")
	out := partialRe.ReplaceAllStringFunc(val, func(m string) string {
		inner := strings.Trim(m, "`")
		if len(inner) > 3 {
			inner = strings.ReplaceAll(inner, "$BT", BT)
			inner = strings.ReplaceAll(inner, "$DS", DS)
		}
		if state != nil {
			state.Full = false
		}
		found := GetPathState(inner, store, current, state)

    if found == nil {
			return ""
		}
		switch fv := found.(type) {
		case map[string]interface{}, []interface{}:
			// for partial injection, JSON-stringify
			b, _ := json.Marshal(fv)
			return string(b)
		default:
			return stringifyValue(found)
		}
	})

	// Also call the handler on the entire resulting string (with state.Full = true).
	if state != nil && state.Handler != nil {
		state.Full = true
		strVal := state.Handler(state, out, current, store)
		return strVal
	}
	return out
}

func stringifyValue(v interface{}) string {
	switch vv := v.(type) {
	case string:
		return vv
	case float64, int, bool:
		return Stringify(v)
	default:
		return Stringify(v)
	}
}

// ---------------------------------------------------------------------
// Inject: recursively inject store paths into a JSON-like structure.

func Inject(
	val interface{},
	store interface{},
) interface{} {
  return InjectState(val, store, nil, nil, nil)
}

func InjectState(
	val interface{},
	store interface{},
	modify Modify,
	current interface{},
	state *Injection,
) interface{} {
	valType := getType(val)

	// Create state if at the root
	if state == nil {
		parent := map[string]interface{}{
			DTOP: val,
		}
		state = &Injection{
			Mode:    InjectModeVal,
			Full:    false,
			KeyI:    0,
			Keys:    []string{DTOP},
			Key:     DTOP,
			Val:     val,
			Parent:  parent,
			Path:    []string{DTOP},
			Nodes:   []interface{}{parent},
			Handler: injectHandler,
			Base:    DTOP,
			Modify:  modify,
		}
	}

	if current == nil {
		current = map[string]interface{}{
			DTOP: store,
		}
	} else {
		if len(state.Path) > 1 {
			parentKey := state.Path[len(state.Path)-2]
			current = GetProp(current, parentKey)
		}
	}

	// Descend into node
	if IsNode(val) {

    childkeys := Keys(val)

    var normalKeys []string
    var transformKeys []string
    for _, k := range childkeys {
      // If k includes `$`, treat it as a transform key
      if strings.Contains(k, DS) {
        transformKeys = append(transformKeys, k)
      } else {
        normalKeys = append(normalKeys, k)
      }
    }

    // Sort transform keys so they run in alphanumeric order
    sort.Strings(transformKeys)
    origKeys := append(normalKeys, transformKeys...)

    for okI, origKey := range origKeys {
      childPath := append(state.Path, origKey)
      childNodes := append(state.Nodes, val)

      // 1) mode = "key:pre"
      childState := &Injection{
        Mode:    InjectModeKeyPre,
        Full:    false,
        KeyI:    okI,
        Keys:    origKeys,
        Key:     origKey,
        Val:     val,
        Parent:  val,
        Path:    childPath,
        Nodes:   childNodes,
        Handler: injectHandler,
        Base:    state.Base,
        Modify:  state.Modify,
      }
      preKey := injectStr(origKey, store, current, childState)

      if preKey != nil {
        // 2) mode = "val"
        childVal := GetProp(val, origKey)
        childState.Mode = InjectModeVal
        InjectState(childVal, store, modify, current, childState)
        
        // 3) mode = "key:post"
        childState.Mode = InjectModeKeyPost
        injectStr(origKey, store, current, childState)
      }
    }
	} else if valType == STRING {
		state.Mode = InjectModeVal
		strVal, ok := val.(string)
		if ok {
			newVal := injectStr(strVal, store, current, state)
			SetProp(state.Parent, state.Key, newVal)
			val = newVal
		}
	}

	// Custom modification
	if modify != nil {
		modify(state.Key, val, state.Parent, state, current, store)
	}

	// Return possibly updated root
	return GetProp(state.Parent, DTOP)
}

// ---------------------------------------------------------------------
// Default inject handler for transforms.

var injectHandler InjectHandler = func(
	state *Injection,
	val interface{},
	current interface{},
	store interface{},
) interface{} {

  isfunc := false
  if nil != val {
    isfunc = reflect.TypeOf(val).Kind() == reflect.Func
  }

	if isfunc {
		// If val is a "function" transform, call it.
		// In Go, we store them as a special variable or a typed value.
		// For simplicity, we’ll do a type assertion check:

    fn, ok := val.(InjectHandler)

    if ok {
			out := fn(state, val, current, store)
      val = out
		}
	}

	// If we are in "val" mode and the entire injection was a "full" match,
	// set the parent's key
	if state.Mode == InjectModeVal && state.Full {
		SetProp(state.Parent, state.Key, val)
	}

	return val
}

// ---------------------------------------------------------------------
// Transform handlers

// transform_DELETE => `$DELETE`
var Transform_DELETE InjectHandler = func(
	state *Injection,
	val interface{},
	current interface{},
	store interface{},
) interface{} {
	SetProp(state.Parent, state.Key, nil)
	return nil
}

// transform_COPY => `$COPY`
var Transform_COPY InjectHandler = func(
	state *Injection,
	val interface{},
	current interface{},
	store interface{},
) interface{} {
	if strings.HasPrefix(string(state.Mode), "key") {
		return state.Key
	} else {
		out := GetProp(current, state.Key)

		SetProp(state.Parent, state.Key, out)
		return out
	}
}

// transform_KEY => `$KEY`
var Transform_KEY InjectHandler = func(
	state *Injection,
	val interface{},
	current interface{},
	store interface{},
) interface{} {
	if state.Mode != InjectModeVal {
		return nil
	}

	// If there's a `"$KEY"` property, that indicates the "name" of the key
	keyspec := GetProp(state.Parent, TKEY)
	if keyspec != nil {
		// remove the TKEY property
		SetProp(state.Parent, TKEY, nil)
		return GetProp(current, keyspec)
	}

	// If no TKEY property, fallback to the parent's stored key in TMETA => KEY
	tmeta := GetProp(state.Parent, TMETA)
	pkey := GetProp(tmeta, KEY)
	if pkey != nil {
		return pkey
	}

	// fallback to the second-last path element
	ppath := state.Path
	if len(ppath) >= 2 {
		return ppath[len(ppath)-2]
	}

	return nil
}

// transform_META => `$META`
var Transform_META InjectHandler = func(
	state *Injection,
	val interface{},
	current interface{},
	store interface{},
) interface{} {
	SetProp(state.Parent, TMETA, nil)
	return nil
}

// transform_MERGE => `$MERGE`
var Transform_MERGE InjectHandler = func(
	state *Injection,
	val interface{},
	current interface{},
	store interface{},
) interface{} {
	if state.Mode == InjectModeKeyPre {
		return state.Key
	}
	if state.Mode == InjectModeKeyPost {
		args := GetProp(state.Parent, state.Key)
		if args == EMPTY {
			args = []interface{}{GetProp(store, DTOP)}
		} else if IsList(args) {
			// do nothing
		} else {
			// wrap in array
			args = []interface{}{args}
		}
		list, ok := args.([]interface{})
		if !ok {
			return state.Key
		}

		// Remove the transform key
		SetProp(state.Parent, state.Key, nil)

		// Merge parent + ...args + clone(parent)
		mergeList := []interface{}{state.Parent}
		mergeList = append(mergeList, list...)
		mergeList = append(mergeList, Clone(state.Parent))

		_ = Merge(mergeList)
	}
	return state.Key
}

// transform_EACH => `$EACH`
var Transform_EACH InjectHandler = func(
	state *Injection,
	val interface{},
	current interface{},
	store interface{},
) interface{} {
	// Keep only the first key in the parent
	if state.Keys != nil {
		state.Keys = state.Keys[:1]
	}

	// Defensive checks
	if state.Mode != InjectModeVal || state.Path == nil || state.Nodes == nil {
		return nil
	}

	// Format: ['`$EACH`', 'source-path', child-template]
	parent := state.Parent
	arr, ok := parent.([]interface{})
	if !ok || len(arr) < 3 {
		return nil
	}
	srcpath := arr[1]
	child := Clone(arr[2])

	// Source data
	src := GetPathState(srcpath, store, current, state)

	// Build parallel data structures
	var tval interface{}
	tval = []interface{}{}
	var tcur interface{}
	tcur = []interface{}{}
  
	// If src is a list, map each item
	if IsList(src) {
		srcList := src.([]interface{})
		newlist := make([]interface{}, len(srcList))
		for i := range srcList {
			newlist[i] = Clone(child)
      SetProp(tcur, i, srcList[i])
		}
		tval = newlist
	} else if IsMap(src) {

    items := Items(src)

    // If src is a map, create a list of child clones, storing the KEY in TMeta
		srcMap := src.(map[string]interface{})
		newlist := make([]interface{}, 0, len(srcMap))
    // i := 0
		// for k, v := range srcMap {
    for i, item := range items {
      k := item[0]
      v := item[1]
      
			cclone := Clone(child)
			// record the key in TMeta => KEY
			setp, ok := cclone.(map[string]interface{})
			if ok {
				setp[TMETA] = map[string]interface{}{
					KEY: k,
				}
			}
			newlist = append(newlist, cclone)
			// _ = v // we just want the same length

      tcur = SetProp(tcur, i, v)
      i++
		}
		tval = newlist
	}

	// Build parallel `current` for injection
	tcur = map[string]interface{}{
		DTOP: tcur,
	}

	// Perform sub-injection
	tval = InjectState(tval, store, state.Modify, tcur, nil)

	// set the result in the node (the parent’s parent)
	if len(state.Path) >= 2 {
		tkey := state.Path[len(state.Path)-2]
		target := state.Nodes[len(state.Path)-2]
		SetProp(target, tkey, tval)
	}

	// Return the first element
	listVal, ok := tval.([]interface{})
	if ok && len(listVal) > 0 {
		return listVal[0]
	}
	return nil
}

// transform_PACK => `$PACK`
var Transform_PACK InjectHandler = func(
	state *Injection,
	val interface{},
	current interface{},
	store interface{},
) interface{} {
	if state.Mode != InjectModeKeyPre || state.Key == "" || state.Path == nil || state.Nodes == nil {
		return nil
	}

	parentMap, ok := state.Parent.(map[string]interface{})
	if !ok {
		return nil
	}

	args, ok := parentMap[state.Key].([]interface{})
	if !ok || len(args) < 2 {
		return nil
	}

	srcpath := args[0]
	child := Clone(args[1])
	keyprop := GetProp(child, TKEY)

	tkey := ""
	if len(state.Path) >= 2 {
		tkey = state.Path[len(state.Path)-2]
	}
	var target interface{}
	if len(state.Nodes) >= 2 {
		target = state.Nodes[len(state.Nodes)-2]
	} else {
		target = state.Nodes[len(state.Nodes)-1]
	}

	src := GetPathState(srcpath, store, current, state)
	// Convert map to list if needed
	var srclist []interface{}

	if IsList(src) {
		srclist = src.([]interface{})
	} else if IsMap(src) {
		m := src.(map[string]interface{})
		tmp := make([]interface{}, 0, len(m))
		for k, v := range m {
			// carry forward the KEY in TMeta
			vmeta := GetProp(v, TMETA)
			if vmeta == nil {
				vmeta = map[string]interface{}{}
				SetProp(v, TMETA, vmeta)
			}
			vm := vmeta.(map[string]interface{})
			vm[KEY] = k
			tmp = append(tmp, v)
		}
		srclist = tmp
	} else {
		// no valid source
		return nil
	}

	// Build a parallel map from srclist
	// each item => clone(child)
	childKey := keyprop
	if childKey == nil {
		childKey = keyprop
	}
	// remove TKEY so it doesn’t interfere
	SetProp(child, TKEY, nil)

	tval := map[string]interface{}{}
	tcurrent := map[string]interface{}{}

	for _, item := range srclist {
		kname := GetProp(item, childKey)
		if kstr, ok := kname.(string); ok && kstr != "" {
			tval[kstr] = Clone(child)
			if _, ok2 := tval[kstr].(map[string]interface{}); ok2 {
				SetProp(tval[kstr], TMETA, GetProp(item, TMETA))
			}
			tcurrent[kstr] = item
		}
	}

	tcur := map[string]interface{}{
		DTOP: tcurrent,
	}

	tvalout := InjectState(tval, store, state.Modify, tcur, nil)

	SetProp(target, tkey, tvalout)

	return nil
}

// ---------------------------------------------------------------------
// Transform function: top-level

func Transform(
	data interface{}, // source data
	spec interface{}, // transform specification
) interface{} {
  return TransformModify(data, spec, nil, nil)
}


func TransformModify(
	data interface{}, // source data
	spec interface{}, // transform specification
	extra interface{}, // extra store
	modify Modify, // optional modify
) interface{} {
	// Split extra transforms from extra data
	extraTransforms := map[string]interface{}{}
	extraData := map[string]interface{}{}

	if extra != nil {
		pairs := Items(extra)
		for _, kv := range pairs {
			k, _ := kv[0].(string)
			v := kv[1]
			if strings.HasPrefix(k, DS) {
				extraTransforms[k] = v
			} else {
				extraData[k] = v
			}
		}
	}

	// Merge extraData + data
	dataClone := Merge([]interface{}{
		Clone(extraData),
		Clone(data),
	})

	// The injection store with transform functions
	store := map[string]interface{}{
		// Merged data is at $TOP
		DTOP: dataClone,

		// Handy escapes
		"$BT": func() interface{} { return BT },
		"$DS": func() interface{} { return DS },

		// Insert current date/time
		"$WHEN": func() interface{} {
			return time.Now().UTC().Format(time.RFC3339)
		},

		// Built-in transform functions
		"$DELETE": Transform_DELETE,
		"$COPY":   Transform_COPY,
		"$KEY":    Transform_KEY,
		"$META":   Transform_META,
		"$MERGE":  Transform_MERGE,
		"$EACH":   Transform_EACH,
		"$PACK":   Transform_PACK,
	}

	// Add any extra transforms
	for k, v := range extraTransforms {
		store[k] = v
	}

	out := InjectState(spec, store, modify, store, nil)
	return out
}

// DEBUG

func fdt(data interface{}) string {
	return fdti(data, "")
}

func fdti(data interface{}, indent string) string {
	result := ""

	switch v := data.(type) {
	case map[string]interface{}:
		result += indent + "{\n"
		for key, value := range v {
			result += fmt.Sprintf("%s  \"%s\": %s", indent, key, fdti(value, indent+"  "))
		}
		result += indent + "}\n"

	case []interface{}:
		result += indent + "[\n"
		for _, value := range v {
			result += fmt.Sprintf("%s  - %s", indent, fdti(value, indent+"  "))
		}
		result += indent + "]\n"

	default:
		// Format value with its type
		result += fmt.Sprintf("%v (%s)\n", v, reflect.TypeOf(v))
	}

	return result
}
