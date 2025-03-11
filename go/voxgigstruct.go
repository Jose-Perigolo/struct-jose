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

package voxgigstruct

import (
	"encoding/json"
	"fmt"
	"math"
	"net/url"
	"reflect"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// String constants are explicitly defined.

const (
	// Mode value for inject step.
	S_MKEYPRE  = "key:pre"
	S_MKEYPOST = "key:post"
	S_MVAL     = "val"
	S_MKEY     = "key"

	// Special keys.
	S_TKEY  = "`$KEY`"
	S_TMETA = "`$META`"
	S_DTOP  = "$TOP"
	S_DERRS = "$ERRS"

	// General strings.
	S_array    = "array"
	S_base     = "base"
	S_boolean  = "boolean"
	S_function = "function"
	S_number   = "number"
	S_object   = "object"
	S_string   = "string"
	S_null     = "null"
	S_key      = "key"
	S_parent   = "parent"
	S_MT       = ""
	S_BT       = "`"
	S_DS       = "$"
	S_DT       = "."
	S_CN       = ":"
	S_KEY      = "KEY"
)

// The standard undefined value for this language.
// NOTE: `nil` must be used directly.

// Keys are strings for maps, or integers for lists.
type PropKey interface{}

// For each key in a node (map or list), perform value injections in
// three phases: on key value, before child, and then on key value again.
// This mode is passed via the Injection structure.
type InjectMode string

const (
	InjectModeKeyPre  InjectMode = S_MKEYPRE
	InjectModeKeyPost InjectMode = S_MKEYPOST
	InjectModeVal     InjectMode = S_MVAL
)

// Handle value injections using backtick escape sequences:
// - `a.b.c`: insert value at {a:{b:{c:1}}}
// - `$FOO`: apply transform FOO
type Injector func(
	state *Injection, // Injection state.
	val interface{}, // Injection value specification.
	current interface{}, // Current source parent value.
	ref *string, // Original injection reference string.
	store interface{}, // Current source root value.
) interface{}

// Injection state used for recursive injection into JSON-like data structures.
type Injection struct {
	Mode    InjectMode             // Injection mode: key:pre, val, key:post.
	Full    bool                   // Transform escape was full key name.
	KeyI    int                    // Index of parent key in list of parent keys.
	Keys    []string               // List of parent keys.
	Key     string                 // Current parent key.
	Val     interface{}            // Current child value.
	Parent  interface{}            // Current parent (in transform specification).
	Path    []string               // Path to current node.
	Nodes   []interface{}          // Stack of ancestor nodes.
	Handler Injector               // Custom handler for injections.
	Errs    []interface{}          // Error collector.
	Meta    map[string]interface{} // Custom meta data.
	Base    string                 // Base key for data in store, if any.
	Modify  Modify                 // Modify injection output.
}

// Apply a custom modification to injections.
type Modify func(
	val interface{}, // Value.
	key interface{}, // Value key, if any,
	parent interface{}, // Parent node, if any.
	state *Injection, // Injection state, if any.
	current interface{}, // Current value in store (matches path).
	store interface{}, // Store, if any
)

// Function applied to each node and leaf when walking a node structure depth first.
type WalkApply func(
	// Map keys are strings, list keys are numbers, top key is nil
	key *string,
	val interface{},
	parent interface{},
	path []string,
) interface{}

// Value is a node - defined, and a map (hash) or list (array).
func IsNode(val interface{}) bool {
	if val == nil {
		return false
	}

	return IsMap(val) || IsList(val)
}

// Value is a defined map (hash) with string keys.
func IsMap(val interface{}) bool {
	if val == nil {
		return false
	}
	_, ok := val.(map[string]interface{})
	return ok
}

// Value is a defined list (array) with integer keys (indexes).
func IsList(val interface{}) bool {
	if val == nil {
		return false
	}
	rv := reflect.ValueOf(val)
	kind := rv.Kind()
	return kind == reflect.Slice || kind == reflect.Array
}

// Value is a defined string (non-empty) or integer key.
func IsKey(val interface{}) bool {
	switch k := val.(type) {
	case string:
		return k != S_MT
	case int, float64, int8, int16, int32, int64:
		return true
	case uint8, uint16, uint32, uint64, uint, float32:
		return true
	default:
		return false
	}
}

// Check for an "empty" value - nil, empty string, array, object.
func IsEmpty(val interface{}) bool {
	if val == nil {
		return true
	}
	switch vv := val.(type) {
	case string:
		return vv == S_MT
	case []interface{}:
		return len(vv) == 0
	case map[string]interface{}:
		return len(vv) == 0
	}
	return false
}

// Value is a function.
func IsFunc(val interface{}) bool {
	return reflect.ValueOf(val).Kind() == reflect.Func
}

// Safely get a property of a node. Nil arguments return nil.
// If the key is not found, return the alternative value, if any.
func GetProp(val interface{}, key interface{}, alts ...interface{}) interface{} {
	var out interface{}
	var alt interface{}

	if len(alts) > 0 {
		alt = alts[0]
	}

	if nil == val || nil == key {
		return alt
	}

	if IsMap(val) {
		ks, ok := key.(string)
		if !ok {
			ks = _strKey(key)
		}

		v := val.(map[string]interface{})
		res, has := v[ks]
		if has {
			out = res
		}

	} else if IsList(val) {
		ki, ok := key.(int)
		if !ok {
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

		v, ok := val.([]interface{})

		if !ok {
			rv := reflect.ValueOf(val)
			if rv.Kind() == reflect.Slice && 0 <= ki && ki < rv.Len() {
				out = rv.Index(ki).Interface()
			}

		} else {
			if 0 <= ki && ki < len(v) {
				out = v[ki]
			}
		}

	} else {
		valRef := reflect.ValueOf(val)
		if valRef.Kind() == reflect.Ptr {
			valRef = valRef.Elem()
		}

		if valRef.Kind() == reflect.Struct {
			ks, ok := key.(string)
			if !ok {
				ks = _strKey(key)
			}

			field := valRef.FieldByName(ks)
			if field.IsValid() {
				out = field.Interface()
			}
		}
	}

	if nil == out {
		return alt
	}

	return out
}

// Sorted keys of a map, or indexes of a list.
func KeysOf(val interface{}) []string {
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
			keys[i] = _strKey(i)
		}
		return keys
	}

	return make([]string, 0)
}

// Value of property with name key in node val is defined.
func HasKey(val interface{}, key interface{}) bool {
	return nil != GetProp(val, key)
}

// List the sorted keys of a map or list as an array of tuples of the form [key, value].
func Items(val interface{}) [][2]interface{} {
	if IsMap(val) {
		m := val.(map[string]interface{})
		out := make([][2]interface{}, 0, len(m))

		keys := make([]string, 0, len(m))
		for k := range m {
			keys = append(keys, k)
		}
		sort.Strings(keys)

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

	return make([][2]interface{}, 0, 0)
}

// Escape regular expression.
func EscRe(s string) string {
	if s == "" {
		return ""
	}
	re := regexp.MustCompile(`[.*+?^${}()|\[\]\\]`)
	return re.ReplaceAllString(s, `\${0}`)
}

// Escape URLs.
func EscUrl(s string) string {
	return url.QueryEscape(s)
}

var (
	reNonSlashSlash = regexp.MustCompile(`([^/])/+`)
	reTrailingSlash = regexp.MustCompile(`/+$`)
	reLeadingSlash  = regexp.MustCompile(`^/+`)
)

// Concatenate url part strings, merging forward slashes as needed.
func JoinUrl(parts []interface{}) string {
	var filtered []string
	for _, p := range parts {
		if "" != p && nil != p {
			ps, ok := p.(string)
			if !ok {
				ps = Stringify(p)
			}
			filtered = append(filtered, ps)
		}
	}

	for i, s := range filtered {
		s = reNonSlashSlash.ReplaceAllString(s, `$1/`)

		if i == 0 {
			s = reTrailingSlash.ReplaceAllString(s, "")
		} else {
			s = reLeadingSlash.ReplaceAllString(s, "")
			s = reTrailingSlash.ReplaceAllString(s, "")
		}
		filtered[i] = s
	}

	finalParts := filtered[:0]
	for _, s := range filtered {
		if s != "" {
			finalParts = append(finalParts, s)
		}
	}

	return strings.Join(finalParts, "/")
}

// Safely stringify a value for humans (NOT JSON!).
func Stringify(val interface{}, maxlen ...int) string {
	if nil == val {
		return S_MT
	}

	b, err := json.Marshal(val)
	if err != nil {
		return ""
	}
	jsonStr := string(b)

	jsonStr = strings.ReplaceAll(jsonStr, `"`, "")

	if len(maxlen) > 0 && maxlen[0] > 0 {
		ml := maxlen[0]
		if len(jsonStr) > ml {
			if ml >= 3 {
				jsonStr = jsonStr[:ml-3] + "..."
			} else {
				jsonStr = jsonStr[:ml]
			}
		}
	}

	return jsonStr
}

// Build a human friendly path string.
func Pathify(val interface{}, from ...int) string {
	var pathstr *string

	var path []interface{} = nil

	if IsList(val) {
		list, ok := val.([]interface{})
		if !ok {
			list = _listify(val)
		}
		path = list
	} else {
		str, ok := val.(string)
		if ok {
			path = append(path, str)
		} else {
			num, err := _toFloat64(val)
			if nil == err {
				path = append(path, strconv.FormatInt(int64(math.Floor(num)), 10))
			}
		}
	}

	var start int
	if 0 == len(from) {
		start = 0

	} else {
		start = from[0]
		if start < 0 {
			start = 0
		}
	}

	if nil != path && 0 <= start {
		if len(path) < start {
			start = len(path)
		}

		sliced := path[start:]
		if len(sliced) == 0 {
			root := "<root>"
			pathstr = &root

		} else {
			var filtered []interface{}
			for _, p := range sliced {
				switch x := p.(type) {
				case string:
					filtered = append(filtered, x)
				case int, int8, int16, int32, int64,
					float32, float64, uint, uint8, uint16, uint32, uint64:
					filtered = append(filtered, x)
				}
			}

			var mapped []string
			for _, p := range filtered {
				switch x := p.(type) {
				case string:
					replaced := strings.ReplaceAll(x, S_DT, S_MT)
					mapped = append(mapped, replaced)
				default:
					numVal, err := _toFloat64(x)
					if err == nil {
						mapped = append(mapped, S_MT+strconv.FormatInt(int64(math.Floor(numVal)), 10))
					}
				}
			}

			joined := strings.Join(mapped, S_DT)
			pathstr = &joined
		}
	}

	if nil == pathstr {
		var sb strings.Builder
		sb.WriteString("<unknown-path")
		if val == nil {
			sb.WriteString(S_MT)
		} else {
			sb.WriteString(S_CN)
			sb.WriteString(Stringify(val, 33))
		}
		sb.WriteString(">")
		updesc := sb.String()
		pathstr = &updesc
	}

	return *pathstr
}

// Clone a JSON-like data structure.
// NOTE: function value references are copied, *not* cloned.
func Clone(val interface{}) interface{} {
	return CloneFlags(val, nil)
}

func CloneFlags(val interface{}, flags map[string]bool) interface{} {
	if val == nil {
		return nil
	}

	if nil == flags {
		flags = map[string]bool{}
	}

	if _, ok := flags["func"]; !ok {
		flags["func"] = true
	}

	typ := reflect.TypeOf(val)
	if typ.Kind() == reflect.Func {
		if flags["func"] {
			return val
		}
		return nil
	}

	switch v := val.(type) {
	case map[string]interface{}:
		newMap := make(map[string]interface{}, len(v))
		for key, value := range v {
			newMap[key] = CloneFlags(value, flags)
		}
		return newMap
	case []interface{}:
		newSlice := make([]interface{}, len(v))
		for i, value := range v {
			newSlice[i] = CloneFlags(value, flags)
		}
		return newSlice
	default:
		return v
	}
}

// Safely set a property. Undefined arguments and invalid keys are ignored.
// Returns the (possibly modified) parent.
// If the value is undefined the key will be deleted from the parent.
// If the parent is a list, and the key is negative, prepend the value.
// NOTE: If the key is above the list size, append the value; below, prepend.
// If the value is undefined, remove the list element at index key, and shift the
// remaining elements down.  These rules avoid "holes" in the list.
func SetProp(parent interface{}, key interface{}, newval interface{}) interface{} {
	if !IsKey(key) {
		return parent
	}

	if IsMap(parent) {
		m := parent.(map[string]interface{})

		// Convert key to string
		ks := ""
		ks = _strKey(key)

		if newval == nil {
			delete(m, ks)
		} else {
			m[ks] = newval
		}

	} else if IsList(parent) {
		arr, genarr := parent.([]interface{})

		// Convert key to integer
		var ki int
		switch k := key.(type) {
		case int:
			ki = k
		case float64:
			ki = int(k)
		case string:
			kiParsed, e := _parseInt(k)
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

		if !genarr {
			rv := reflect.ValueOf(parent)
			arr = make([]interface{}, rv.Len())
			for i := 0; i < rv.Len(); i++ {
				arr[i] = rv.Index(i).Interface()
			}
		}

		if newval == nil {
			if ki >= 0 && ki < len(arr) {
				copy(arr[ki:], arr[ki+1:])
				arr = arr[:len(arr)-1]
			}

			if !genarr {
				return _makeArrayType(arr, parent)
			} else {

				return arr
			}
		}

		// If ki >= 0, set or append
		if ki >= 0 {
			if ki >= len(arr) {
				arr = append(arr, newval)
			} else {
				arr[ki] = newval
			}

			if !genarr {
				return _makeArrayType(arr, parent)
			} else {
				return arr
			}
		}

		// If ki < 0, prepend
		if ki < 0 {
			// prepend
			newarr := make([]interface{}, 0, len(arr)+1)
			newarr = append(newarr, newval)
			newarr = append(newarr, arr...)
			if !genarr {
				return _makeArrayType(newarr, parent)
			} else {
				return newarr
			}
		}
	}

	return parent
}

// Walk a data structure depth first, applying a function to each value.
func Walk(
	val interface{},
	apply WalkApply,
) interface{} {
	return WalkDescend(val, apply, nil, nil, nil)
}

func WalkDescend(
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
			ckeyStr := _strKey(ckey)
			newChild := WalkDescend(child, apply, &ckeyStr, val, append(path, ckeyStr))
			val = SetProp(val, ckey, newChild)
		}

		if nil != parent && nil != key {
			SetProp(parent, *key, val)
		}
	}

	// Nodes are applied *after* their children.
	// For the root node, key and parent will be undefined.
	val = apply(key, val, parent, path)

	return val
}

// Merge a list of values into each other. Later values have
// precedence.  Nodes override scalars. Node kinds (list or map)
// override each other, and do *not* merge.  The first element is
// modified.
func Merge(val interface{}) interface{} {
	var out interface{} = nil

	if !IsList(val) {
		return val
	}

	list := _listify(val)
	lenlist := len(list)

	if 0 == lenlist {
		return nil
	}

	if 1 == lenlist {
		return list[0]
	}

	// Merge a list of values.
	out = GetProp(list, 0, make(map[string]interface{}))

	for i := 1; i < lenlist; i++ {
		obj := list[i]

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
				// Node stack. walking down the current obj.
				var cur []interface{} = make([]interface{}, 11)
				cI := 0
				cur[cI] = out

				merger := func(
					key *string,
					val interface{},
					parent interface{},
					path []string,
				) interface{} {

					if nil == key {
						return val
					}

					// Get the curent value at the current path in obj.
					// NOTE: this is not exactly efficient, and should be optimised.
					lenpath := len(path)
					cI = lenpath - 1
					if nil == cur[cI] {
						cur[cI] = GetPath(path[:lenpath-1], out)
					}

					// Create node if needed.
					if nil == cur[cI] {
						if IsList(parent) {
							cur[cI] = make([]interface{}, 0)
						} else {
							cur[cI] = make(map[string]interface{})
						}
					}

					// Node child is just ahead of us on the stack, since
					// `walk` traverses leaves before nodes.
					if IsNode(val) && !IsEmpty(val) {
						cur[cI] = SetProp(cur[cI], *key, cur[cI+1])
						cur[cI+1] = nil

					} else {
						cur[cI] = SetProp(cur[cI], *key, val)
					}

					return val
				}

				// Walk overriding node, creating paths in output as needed.
				Walk(obj, merger)

				out = cur[0]
			}
		}
	}

	return out
}

// Get a value deep inside a node using a key path.  For example the
// path `a.b` gets the value 1 from {a:{b:1}}.  The path can specified
// as a dotted string, or a string array.  If the path starts with a
// dot (or the first element is ”), the path is considered local, and
// resolved against the `current` argument, if defined.  Integer path
// parts are used as array indexes.  The state argument allows for
// custom handling when called from `inject` or `transform`.
func GetPath(path interface{}, store interface{}) interface{} {
	return GetPathState(path, store, nil, nil)
}

func GetPathState(
	path interface{},
	store interface{},
	current interface{},
	state *Injection,
) interface{} {
	var parts []string

	val := store
	root := store

	// Operate on a string array.
	switch pp := path.(type) {
	case []string:
		parts = pp

	case string:
		if pp == "" {
			parts = []string{S_MT}
		} else {
			parts = strings.Split(pp, S_DT)
		}
	default:
		if IsList(path) {
			parts = _resolveStrings(pp.([]interface{}))
		} else {
			return nil
		}
	}

	var base *string = nil
	if nil != state {
		base = &state.Base
	}

	// An empty path (incl empty string) just finds the store.
	if nil == path || nil == store || (1 == len(parts) && S_MT == parts[0]) {
		// The actual store data may be in a store sub property, defined by state.base.
		val = GetProp(store, base, store)

	} else if 0 < len(parts) {

		pI := 0

		// Relative path uses `current` argument.
		if parts[0] == S_MT {
			pI = 1
			root = current
		}

		var part *string
		if pI < len(parts) {
			part = &parts[pI]
		}

		first := GetProp(root, *part)

		// At top level, check state.base, if provided
		val = first
		if nil == first && 0 == pI {
			val = GetProp(GetProp(root, base), *part)
		}

		// Move along the path, trying to descend into the store.
		pI++
		for nil != val && pI < len(parts) {
			val = GetProp(val, parts[pI])
			pI++
		}
	}

	if nil != state && state.Handler != nil {
		ref := Pathify(path)
		val = state.Handler(state, val, current, &ref, store)
	}

	return val
}

// Inject store values into a string. Not a public utility - used by
// `inject`.  Inject are marked with `path` where path is resolved
// with getpath against the store or current (if defined)
// arguments. See `getpath`.  Custom injection handling can be
// provided by state.handler (this is used for transform functions).
// The path can also have the special syntax $NAME999 where NAME is
// upper case letters only, and 999 is any digits, which are
// discarded. This syntax specifies the name of a transform, and
// optionally allows transforms to be ordered by alphanumeric sorting.
func _injectStr(
	val string,
	store interface{},
	current interface{},
	state *Injection,
) interface{} {
	if val == S_MT {
		return S_MT
	}

	// Pattern examples: "`a.b.c`", "`$NAME`", "`$NAME1`"
	// fullRe := regexp.MustCompile("^`([^`]+)[0-9]*`$")
	fullRe := regexp.MustCompile("^`(\\$[A-Z]+|[^`]+)[0-9]*`$")
	matches := fullRe.FindStringSubmatch(val)

	// Full string of the val is an injection.
	if matches != nil {
		if nil != state {
			state.Full = true
		}
		pathref := matches[1]

		// Special escapes inside injection.
		if len(pathref) > 3 {
			pathref = strings.ReplaceAll(pathref, "$BT", S_BT)
			pathref = strings.ReplaceAll(pathref, "$DS", S_DS)
		}

		// Get the extracted path reference.
		out := GetPathState(pathref, store, current, state)

		return out
	}

	// Check for injections within the string.
	partialRe := regexp.MustCompile("`([^`]+)`")
	out := partialRe.ReplaceAllStringFunc(val, func(m string) string {
		ref := strings.Trim(m, "`")

		// Special escapes inside injection.
		if 3 < len(ref) {
			ref = strings.ReplaceAll(ref, "$BT", S_BT)
			ref = strings.ReplaceAll(ref, "$DS", S_DS)
		}
		if nil != state {
			state.Full = false
		}
		found := GetPathState(ref, store, current, state)

		if nil == found {
			return S_MT
		}
		switch fv := found.(type) {
		case map[string]interface{}, []interface{}:
			b, _ := json.Marshal(fv)
			return string(b)
		default:
			return _stringifyValue(found)
		}
	})

	// Also call the state handler on the entire string, providing the
	// option for custom injection.
	if nil != state && IsFunc(state.Handler) {
		state.Full = true
		out = state.Handler(state, out, current, &val, store).(string)
	}

	return out
}

// Inject values from a data store into a node recursively, resolving
// paths against the store, or current if they are local. THe modify
// argument allows custom modification of the result.  The state
// (InjectState) argument is used to maintain recursive state.
func Inject(
	val interface{},
	store interface{},
) interface{} {
	return InjectDescend(val, store, nil, nil, nil)
}

func InjectDescend(
	val interface{},
	store interface{},
	modify Modify,
	current interface{},
	state *Injection,
) interface{} {
	valType := _getType(val)

	// Create state if at root of injection.  The input value is placed
	// inside a virtual parent holder to simplify edge cases.
	if state == nil {
		parent := map[string]interface{}{
			S_DTOP: val,
		}

		// Set up state assuming we are starting in the virtual parent.
		state = &Injection{
			Mode:    InjectModeVal,
			Full:    false,
			KeyI:    0,
			Keys:    []string{S_DTOP},
			Key:     S_DTOP,
			Val:     val,
			Parent:  parent,
			Path:    []string{S_DTOP},
			Nodes:   []interface{}{parent},
			Handler: injectHandler,
			Base:    S_DTOP,
			Modify:  modify,
			Errs:    GetProp(store, S_DERRS, make([]interface{}, 0)).([]interface{}),
			Meta:    make(map[string]interface{}),
		}
	}

	// Resolve current node in store for local paths.
	if nil == current {
		current = map[string]interface{}{
			S_DTOP: store,
		}
	} else {
		if len(state.Path) > 1 {
			parentKey := state.Path[len(state.Path)-2]
			current = GetProp(current, parentKey)
		}
	}

	// Descend into node
	if IsNode(val) {
		childkeys := KeysOf(val)

		// Keys are sorted alphanumerically to ensure determinism.
		// Injection transforms ($FOO) are processed *after* other keys.
		// NOTE: the optional digits suffix of the transform can thus be
		// used to order the transforms.
		var normalKeys []string
		var transformKeys []string
		for _, k := range childkeys {
			if strings.Contains(k, S_DS) {
				transformKeys = append(transformKeys, k)
			} else {
				normalKeys = append(normalKeys, k)
			}
		}

		sort.Strings(transformKeys)
		origKeys := append(normalKeys, transformKeys...)

		// Each child key-value pair is processed in three injection phases:
		// 1. state.mode='key:pre' - Key string is injected, returning a possibly altered key.
		// 2. state.mode='val' - The child value is injected.
		// 3. state.mode='key:post' - Key string is injected again, allowing child mutation.

		// for okI, origKey := range origKeys {
		okI := 0
		for okI < len(origKeys) {
			origKey := origKeys[okI]

			childPath := append(state.Path, origKey)
			childNodes := append(state.Nodes, val)
			childVal := GetProp(val, origKey)

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

			// Peform the key:pre mode injection on the child key.
			preKey := _injectStr(origKey, store, current, childState)

			// The injection may modify child processing.
			okI = childState.KeyI

			if preKey != nil {
				childVal = GetProp(val, preKey)
				childState.Val = childVal
				childState.Mode = InjectModeVal

				// Perform the val mode injection on the child value.
				// NOTE: return value is not used.
				InjectDescend(childVal, store, modify, current, childState)

				// The injection may modify child processing.
				okI = childState.KeyI

				// Peform the key:post mode injection on the child key.
				childState.Mode = InjectModeKeyPost
				_injectStr(origKey, store, current, childState)

				// The injection may modify child processing.
				okI = childState.KeyI
			}

			okI = okI + 1
		}

	} else if valType == S_string {

		// Inject paths into string scalars.
		state.Mode = InjectModeVal
		strVal, ok := val.(string)
		if ok {
			val = _injectStr(strVal, store, current, state)
			// fmt.Println("INJECT-STR-A", state.Key, val, state.Parent)
			_setPropOfStateParent(state, val)
			// fmt.Println("INJECT-STR-B", state.Key, val, state.Parent, state.Nodes)

			// parent := SetProp(state.Parent, state.Key, val)

			// // Lists are not mutable, so update grandparent reference.
			// if IsList(parent) {
			// 	_updateGrandParent(state, parent)
			// }
		}
	}

	// Custom modification
	if nil != modify {
		modify(
			val,
			state.Key,
			state.Parent,
			state,
			current,
			store,
		)
	}

	// Original val reference may no longer be correct.
	// This return value is only used as the top level result.
	return GetProp(state.Parent, S_DTOP)
}

// Default inject handler for transforms. If the path resolves to a function,
// call the function passing the injection state. This is how transforms operate.
var injectHandler Injector = func(
	state *Injection,
	val interface{},
	current interface{},
	ref *string,
	store interface{},
) interface{} {

	iscmd := IsFunc(val) && (nil == ref || strings.HasPrefix(*ref, S_DS))

	if iscmd {
		fnih, ok := val.(Injector)

		if ok {
			val = fnih(state, val, current, ref, store)
		} else {

			// In Go, as a convenience, allow injection functions that have no arguments.
			fn0, ok := val.(func() interface{})
			if ok {
				val = fn0()
			}
		}
	} else if InjectModeVal == state.Mode && state.Full {
		// Update parent with value. Ensures references remain in node tree.
		_setPropOfStateParent(state, val)

		// parent := SetProp(state.Parent, state.Key, val)

		// // Lists are not mutable, so update grandparent reference.
		// if IsList(parent) {
		//   _updateGrandParent(state, parent)
		// }

	}

	// fmt.Println("IH", state.Mode, state.Key, val)
	return val
}

// The transform_* functions are special command inject handlers (see Injector).

// Delete a key from a map or list.
var Transform_DELETE Injector = func(
	state *Injection,
	val interface{},
	current interface{},
	ref *string,
	store interface{},
) interface{} {
	// SetProp(state.Parent, state.Key, nil)
	_setPropOfStateParent(state, nil)
	return nil
}

// Copy value from source data.
var Transform_COPY Injector = func(
	state *Injection,
	val interface{},
	current interface{},
	ref *string,
	store interface{},
) interface{} {
	var out interface{} = state.Key

	if !strings.HasPrefix(string(state.Mode), "key") {
		out = GetProp(current, state.Key)
		// SetProp(state.Parent, state.Key, out)
		_setPropOfStateParent(state, out)
	}

	return out
}

// As a value, inject the key of the parent node.
// As a key, defined the name of the key property in the source object.
var Transform_KEY Injector = func(
	state *Injection,
	val interface{},
	current interface{},
	ref *string,
	store interface{},
) interface{} {
	if state.Mode != InjectModeVal {
		return nil
	}

	// Key is defined by $KEY meta property.
	keyspec := GetProp(state.Parent, S_TKEY)
	if keyspec != nil {
		SetProp(state.Parent, S_TKEY, nil)
		return GetProp(current, keyspec)
	}

	// Key is defined within general purpose $META object.
	tmeta := GetProp(state.Parent, S_TMETA)
	pkey := GetProp(tmeta, S_KEY)
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

// Store meta data about a node.  Does nothing itself, just used by
// other injectors, and is removed when called.
var Transform_META Injector = func(
	state *Injection,
	val interface{},
	current interface{},
	ref *string,
	store interface{},
) interface{} {
	SetProp(state.Parent, S_TMETA, nil)
	return nil
}

// Merge a list of objects into the current object.
// Must be a key in an object. The value is merged over the current object.
// If the value is an array, the elements are first merged using `merge`.
// If the value is the empty string, merge the top level store.
// Format: { '`$MERGE`': '`source-path`' | ['`source-paths`', ...] }
var Transform_MERGE Injector = func(
	state *Injection,
	val interface{},
	current interface{},
	ref *string,
	store interface{},
) interface{} {
	if InjectModeKeyPre == state.Mode {
		return state.Key
	}

	if InjectModeKeyPost == state.Mode {
		args := GetProp(state.Parent, state.Key)
		if S_MT == args {
			args = []interface{}{GetProp(store, S_DTOP)}
		} else if IsList(args) {
			// do nothing
		} else {
			// wrap in array
			args = []interface{}{args}
		}

		// Remove the $MERGE command from a parent map.
		// SetProp(state.Parent, state.Key, nil)
		_setPropOfStateParent(state, nil)
		// fmt.Print("MERGE", fdt(state.Parent), fdt(state.Nodes))

		list, ok := args.([]interface{})
		if !ok {
			return state.Key
		}

		// Literals in the parent have precedence, but we still merge onto
		// the parent object, so that node tree references are not changed.
		mergeList := []interface{}{state.Parent}
		mergeList = append(mergeList, list...)
		mergeList = append(mergeList, Clone(state.Parent))

		Merge(mergeList)

		return state.Key
	}

	// Ensures $MERGE is removed from parent list.
	return nil
}

// Convert a node to a list.
// Format: ['`$EACH`', '`source-path-of-node`', child-template]
var Transform_EACH Injector = func(
	state *Injection,
	val interface{},
	current interface{},
	ref *string,
	store interface{},
) interface{} {

	// Remove arguments to avoid spurious processing.
	if state.Keys != nil {
		state.Keys = state.Keys[:1]
	}

	if InjectModeVal != state.Mode {
		return nil
	}

	// Get arguments: ['`$EACH`', 'source-path', child-template].
	parent := state.Parent
	arr, ok := parent.([]interface{})
	if !ok || len(arr) < 3 {
		return nil
	}
	srcpath := arr[1]
	child := Clone(arr[2])

	// Source data.
	src := GetPathState(srcpath, store, current, state)

	// Create parallel data structures:
	// source entries :: child templates
	var tcur interface{}
	tcur = []interface{}{}
	var tval interface{}
	tval = []interface{}{}

	// Create clones of the child template for each value of the current soruce.
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

		srcMap := src.(map[string]interface{})
		newlist := make([]interface{}, 0, len(srcMap))

		for i, item := range items {
			k := item[0]
			v := item[1]
			cclone := Clone(child)

			// Make a note of the key for $KEY transforms.
			setp, ok := cclone.(map[string]interface{})
			if ok {
				setp[S_TMETA] = map[string]interface{}{
					S_KEY: k,
				}
			}
			newlist = append(newlist, cclone)

			tcur = SetProp(tcur, i, v)
			i++
		}
		tval = newlist
	}

	// Parent structure.
	tcur = map[string]interface{}{
		S_DTOP: tcur,
	}

	// Build the substructure.
	tval = InjectDescend(tval, store, state.Modify, tcur, nil)
	// fmt.Println("EACH-TVAL", tval)

	// set the result in the node (the parent’s parent)
	// if len(state.Path) >= 2 {
	// 	tkey := state.Path[len(state.Path)-2]
	// 	target := state.Nodes[len(state.Path)-2]
	//   fmt.Println("EACH-SP", tkey, target, "S=", state.Key, state.Parent, state.Nodes)
	// 	SetProp(target, tkey, tval)
	// }

	// _setPropOfStateParent(state, tval)
	state.Parent = tval
	_updateStateNodeAncestors(state, tval)
	// fmt.Println("EACH-SP", tval, "S=", state.Key, state.Parent, state.Nodes)

	// Return the first element
	listVal, ok := tval.([]interface{})
	if ok && len(listVal) > 0 {
		return listVal[0]
	}

	return nil
}

// transform_PACK => `$PACK`
var Transform_PACK Injector = func(
	state *Injection,
	val interface{},
	current interface{},
	ref *string,
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
	keyprop := GetProp(child, S_TKEY)

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
			vmeta := GetProp(v, S_TMETA)
			if vmeta == nil {
				vmeta = map[string]interface{}{}
				SetProp(v, S_TMETA, vmeta)
			}
			vm := vmeta.(map[string]interface{})
			vm[S_KEY] = k
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
	// remove S_TKEY so it doesn’t interfere
	SetProp(child, S_TKEY, nil)

	tval := map[string]interface{}{}
	tcurrent := map[string]interface{}{}

	for _, item := range srclist {
		kname := GetProp(item, childKey)
		if kstr, ok := kname.(string); ok && kstr != "" {
			tval[kstr] = Clone(child)
			if _, ok2 := tval[kstr].(map[string]interface{}); ok2 {
				SetProp(tval[kstr], S_TMETA, GetProp(item, S_TMETA))
			}
			tcurrent[kstr] = item
		}
	}

	tcur := map[string]interface{}{
		S_DTOP: tcurrent,
	}

	tvalout := InjectDescend(tval, store, state.Modify, tcur, nil)

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

	// Clone the spec so that the clone can be modified in place as the transform result.
	spec = Clone(spec)

	// Split extra transforms from extra data
	extraTransforms := map[string]interface{}{}
	extraData := map[string]interface{}{}

	if extra != nil {
		pairs := Items(extra)
		for _, kv := range pairs {
			k, _ := kv[0].(string)
			v := kv[1]
			if strings.HasPrefix(k, S_DS) {
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
		S_DTOP: dataClone,

		// Handy escapes
		"$BT": func() interface{} { return S_BT },
		"$DS": func() interface{} { return S_DS },

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

	out := InjectDescend(spec, store, modify, store, nil)

	return out
}

func invalidTypeMsg(path []string, expected string, actual string, val interface{}) string {
	return fmt.Sprintf(
		"Expected %s at %s, found %s: %s",
		expected,
		Pathify(path, 1),
		actual,
		val,
	)
}

func validate_STRING(state *Injection, _val, current interface{}) interface{} {
	out := GetProp(current, state.Key)

	str, ok := out.(string)
	if !ok {
		state.Errs = append(state.Errs, invalidTypeMsg(state.Path, S_string, fmt.Sprintf("%T", out), out))
		return nil
	}

	// Reject empty
	if str == S_MT {
		state.Errs = append(state.Errs, "Empty string at "+Pathify(state.Path, 0))
		return nil
	}

	return str
}

func validate_NUMBER(state *Injection, _val, current interface{}) interface{} {
	out := GetProp(current, state.Key)

	switch n := out.(type) {
	case int, float64:
		return n
	default:
		state.Errs = append(state.Errs, invalidTypeMsg(state.Path, S_number, fmt.Sprintf("%T", out), out))
		return nil
	}
}

func validate_BOOLEAN(state *Injection, _val, current interface{}) interface{} {
	out := GetProp(current, state.Key)

	b, ok := out.(bool)
	if !ok {
		state.Errs = append(state.Errs, invalidTypeMsg(state.Path, S_boolean, fmt.Sprintf("%T", out), out))
		return nil
	}

	return b
}

func validate_OBJECT(state *Injection, _val, current interface{}) interface{} {
	out := GetProp(current, state.Key)
	if !IsMap(out) {
		// We also check that out != nil
		state.Errs = append(state.Errs, invalidTypeMsg(state.Path, S_object, fmt.Sprintf("%T", out), out))
		return nil
	}
	return out
}

func validate_ARRAY(state *Injection, _val, current interface{}) interface{} {
	out := GetProp(current, state.Key)
	if !IsList(out) {
		state.Errs = append(state.Errs, invalidTypeMsg(state.Path, S_array, fmt.Sprintf("%T", out), out))
		return nil
	}
	return out
}

func validate_FUNCTION(state *Injection, _val, current interface{}) interface{} {
	out := GetProp(current, state.Key)
	if reflect.TypeOf(out).Kind() != reflect.Func {
		state.Errs = append(state.Errs, invalidTypeMsg(state.Path, S_function, fmt.Sprintf("%T", out), out))
		return nil
	}
	return out
}

func validate_ANY(state *Injection, _val, current interface{}) interface{} {
	return GetProp(current, state.Key)
}

func validate_CHILD(state *Injection, _val, current interface{}) interface{} {
	return nil
}

func validate_ONE(state *Injection, _val, current interface{}) interface{} {
	return nil
}

func validation(
	val interface{},
	key interface{},
	parent interface{},
	state *Injection,
	current interface{},
	_store interface{},
) {

	if state == nil {
		return
	}

	cval := GetProp(current, key)
	if cval == nil {
		return
	}

	pval := GetProp(parent, key)
	// If the spec had a transform command leftover, remove it
	if s, ok := pval.(string); ok && strings.Contains(s, S_DS) {
		return
	}

	if pval != nil && reflect.TypeOf(pval) != reflect.TypeOf(cval) {
		state.Errs = append(state.Errs, invalidTypeMsg(state.Path, fmt.Sprintf("%T", pval), fmt.Sprintf("%T", cval), cval))
		return
	}

	if IsMap(cval) && !IsMap(val) {
		ex := S_object
		if IsList(val) {
			ex = S_array
		}
		state.Errs = append(state.Errs, invalidTypeMsg(state.Path, ex, fmt.Sprintf("%T", cval), cval))
		return
	}

	if IsList(cval) && !IsList(val) {
		state.Errs = append(state.Errs, invalidTypeMsg(state.Path, fmt.Sprintf("%T", val), fmt.Sprintf("%T", cval), cval))
		return
	}

	SetProp(parent, key, cval)
  
	return
}


func Validate(
	data interface{}, // The input data
	spec interface{}, // The shape specification
) interface{} {
  return ValidateCollect(data,spec,nil,nil)
}

func ValidateCollect(
	data interface{}, // The input data
	spec interface{}, // The shape specification
	extra interface{}, // Additional custom checks
	collecterrs []string, // If you provide an existing slice of errs
) interface{} {

  
	errs := collecterrs

	commands := map[string]interface{}{
    "$ERRS": errs,

    "$STRING":   validate_STRING,
		"$NUMBER":   validate_NUMBER,
		"$BOOLEAN":  validate_BOOLEAN,
		"$OBJECT":   validate_OBJECT,
		"$ARRAY":    validate_ARRAY,
		"$FUNCTION": validate_FUNCTION,
		"$ANY":      validate_ANY,
		"$CHILD":    validate_CHILD,
		"$ONE":      validate_ONE,
		// ...
	}

	if extraMap, ok := extra.(map[string]func(*Injection, interface{}, interface{}) interface{}); ok {
		for k, fn := range extraMap {
			commands[k] = fn
		}
	}

	out := TransformModify(data, spec, commands, validation)

	if len(collecterrs) == 0 && len(errs) > 0 {
		panic(fmt.Sprintf("Invalid data:\n%s", strings.Join(errs, "\n")))
	}
  
	return out
}

// Internal utilities
// ==================

func _getType(v interface{}) string {
	if nil == v {
		return "nil"
	}
	return reflect.TypeOf(v).String()
}

func _strKey(key interface{}) string {
	if nil == key {
		return S_MT
	}

	switch v := key.(type) {
	case string:
		return v
	case *string:
		if nil != v {
			return *v
		}
		return S_MT
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

func _resolveStrings(input []interface{}) []string {
	var result []string

	for _, v := range input {
		if str, ok := v.(string); ok {
			result = append(result, str)
		} else {
			result = append(result, _strKey(v))
		}
	}

	return result
}

func _listify(src interface{}) []interface{} {
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

// toFloat64 helps unify numeric types for floor conversion.
func _toFloat64(val interface{}) (float64, error) {
	switch n := val.(type) {
	case float64:
		return n, nil
	case float32:
		return float64(n), nil
	case int:
		return float64(n), nil
	case int8:
		return float64(n), nil
	case int16:
		return float64(n), nil
	case int32:
		return float64(n), nil
	case int64:
		return float64(n), nil
	case uint:
		return float64(n), nil
	case uint8:
		return float64(n), nil
	case uint16:
		return float64(n), nil
	case uint32:
		return float64(n), nil
	case uint64:
		// might overflow if > math.MaxFloat64, but for demonstration that’s rare
		return float64(n), nil
	default:
		return 0, fmt.Errorf("not a numeric type")
	}
}

// _parseInt is a helper to convert a string to int safely.
func _parseInt(s string) (int, error) {
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

func _makeArrayType(values []interface{}, target interface{}) interface{} {
	targetElem := reflect.TypeOf(target).Elem()
	out := reflect.MakeSlice(reflect.SliceOf(targetElem), len(values), len(values))

	for i, v := range values {
		elemVal := reflect.ValueOf(v)
		if !elemVal.Type().ConvertibleTo(targetElem) {
			return values
		}

		out.Index(i).Set(elemVal.Convert(targetElem))
	}

	return out.Interface()
}

func _stringifyValue(v interface{}) string {
	switch vv := v.(type) {
	case string:
		return vv
	case float64, int, bool:
		return Stringify(v)
	default:
		return Stringify(v)
	}
}

func _setPropOfStateParent(state *Injection, val interface{}) {
	parent := SetProp(state.Parent, state.Key, val)
	if IsList(parent) && len(parent.([]interface{})) != len(state.Parent.([]interface{})) {
		state.Parent = parent
		// fmt.Println("SPP", state.Key, val, state.Parent, state.Nodes)
		_updateStateNodeAncestors(state, parent)
	}
}

func _updateStateNodeAncestors(state *Injection, ac interface{}) {
	aI := len(state.Nodes) - 1
	if -1 < aI {
		state.Nodes[aI] = ac
	}
	aI = aI - 1
	for -1 < aI {
		an := state.Nodes[aI]
		ak := state.Path[aI]
		// fmt.Println("USNA", aI, ac, ak, an)
		ac = SetProp(an, ak, ac)
		if IsMap(ac) {
			aI = -1
		} else {
			aI = aI - 1
		}
	}
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
