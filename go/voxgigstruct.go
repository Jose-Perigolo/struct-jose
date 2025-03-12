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
	
	// Types for validation
	S_STRING   = "`$STRING`"
	S_NUMBER   = "`$NUMBER`"
	S_BOOLEAN  = "`$BOOLEAN`"
)

// The standard undefined value for this language.
// NOTE: `nil` must be used directly.

// Keys are strings for maps, or integers for lists.
type PropKey any

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
	val any, // Injection value specification.
	current any, // Current source parent value.
	ref *string, // Original injection reference string.
	store any, // Current source root value.
) any

// Injection state used for recursive injection into JSON-like data structures.
type Injection struct {
	Mode    InjectMode       // Injection mode: key:pre, val, key:post.
	Full    bool             // Transform escape was full key name.
	KeyI    int              // Index of parent key in list of parent keys.
	Keys    []string         // List of parent keys.
	Key     string           // Current parent key.
	Val     any              // Current child value.
	Parent  any              // Current parent (in transform specification).
	Path    []string         // Path to current node.
	Nodes   []any            // Stack of ancestor nodes.
	Handler Injector         // Custom handler for injections.
	Errs    *ListRef[any]    // Error collector.
	Meta    map[string]any   // Custom meta data.
	Base    string           // Base key for data in store, if any.
	Modify  Modify           // Modify injection output.
}

// Apply a custom modification to injections.
type Modify func(
	val any, // Value.
	key any, // Value key, if any,
	parent any, // Parent node, if any.
	state *Injection, // Injection state, if any.
	current any, // Current value in store (matches path).
	store any, // Store, if any
)

// Function applied to each node and leaf when walking a node structure depth first.
type WalkApply func(
	// Map keys are strings, list keys are numbers, top key is nil
	key *string,
	val any,
	parent any,
	path []string,
) any

// Value is a node - defined, and a map (hash) or list (array).
func IsNode(val any) bool {
	if val == nil {
		return false
	}

	return IsMap(val) || IsList(val)
}

// Value is a defined map (hash) with string keys.
func IsMap(val any) bool {
	if val == nil {
		return false
	}
	_, ok := val.(map[string]any)
	return ok
}

// Value is a defined list (array) with integer keys (indexes).
func IsList(val any) bool {
	if val == nil {
		return false
	}
	rv := reflect.ValueOf(val)
	kind := rv.Kind()
	return kind == reflect.Slice || kind == reflect.Array
}

// Value is a defined string (non-empty) or integer key.
func IsKey(val any) bool {
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
func IsEmpty(val any) bool {
	if val == nil {
		return true
	}
	switch vv := val.(type) {
	case string:
		return vv == S_MT
	case []any:
		return len(vv) == 0
	case map[string]any:
		return len(vv) == 0
	}
	return false
}

// Value is a function.
func IsFunc(val any) bool {
	return reflect.ValueOf(val).Kind() == reflect.Func
}

// Safely get a property of a node. Nil arguments return nil.
// If the key is not found, return the alternative value, if any.
func GetProp(val any, key any, alts ...any) any {
	var out any
	var alt any

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

		v := val.(map[string]any)
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

		v, ok := val.([]any)

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
func KeysOf(val any) []string {
	if IsMap(val) {
		m := val.(map[string]any)

		keys := make([]string, 0, len(m))
		for k := range m {
			keys = append(keys, k)
		}

		sort.Strings(keys)

		return keys

	} else if IsList(val) {
		arr := val.([]any)
		keys := make([]string, len(arr))
		for i := range arr {
			keys[i] = _strKey(i)
		}
		return keys
	}

	return make([]string, 0)
}

// Value of property with name key in node val is defined.
func HasKey(val any, key any) bool {
	return nil != GetProp(val, key)
}

// List the sorted keys of a map or list as an array of tuples of the form [key, value].
func Items(val any) [][2]any {
	if IsMap(val) {
		m := val.(map[string]any)
		out := make([][2]any, 0, len(m))

		keys := make([]string, 0, len(m))
		for k := range m {
			keys = append(keys, k)
		}
		sort.Strings(keys)

		for _, k := range keys {
			out = append(out, [2]any{k, m[k]})
		}
		return out

	} else if IsList(val) {
		arr := val.([]any)
		out := make([][2]any, 0, len(arr))
		for i, v := range arr {
			out = append(out, [2]any{i, v})
		}
		return out
	}

	return make([][2]any, 0, 0)
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
func JoinUrl(parts []any) string {
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
func Stringify(val any, maxlen ...int) string {
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
func Pathify(val any, from ...int) string {
	var pathstr *string

	var path []any = nil

	if IsList(val) {
		list, ok := val.([]any)
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
			var filtered []any
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
func Clone(val any) any {
	return CloneFlags(val, nil)
}

func CloneFlags(val any, flags map[string]bool) any {
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
	case map[string]any:
		newMap := make(map[string]any, len(v))
		for key, value := range v {
			newMap[key] = CloneFlags(value, flags)
		}
		return newMap
	case []any:
		newSlice := make([]any, len(v))
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
func SetProp(parent any, key any, newval any) any {
	if !IsKey(key) {
		return parent
	}

	if IsMap(parent) {
		m := parent.(map[string]any)

		// Convert key to string
		ks := ""
		ks = _strKey(key)

		if newval == nil {
			delete(m, ks)
		} else {
			m[ks] = newval
		}

	} else if IsList(parent) {
		arr, genarr := parent.([]any)

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
			arr = make([]any, rv.Len())
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
			newarr := make([]any, 0, len(arr)+1)
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
	val any,
	apply WalkApply,
) any {
	return WalkDescend(val, apply, nil, nil, nil)
}

func WalkDescend(
	val any,
	apply WalkApply,
	key *string,
	parent any,
	path []string,
) any {

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
func Merge(val any) any {
	var out any = nil

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
	out = GetProp(list, 0, make(map[string]any))

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
				var cur []any = make([]any, 11)
				cI := 0
				cur[cI] = out

				merger := func(
					key *string,
					val any,
					parent any,
					path []string,
				) any {

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
							cur[cI] = make([]any, 0)
						} else {
							cur[cI] = make(map[string]any)
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
// dot (or the first element is "), the path is considered local, and
// resolved against the `current` argument, if defined.  Integer path
// parts are used as array indexes.  The state argument allows for
// custom handling when called from `inject` or `transform`.
func GetPath(path any, store any) any {
	return GetPathState(path, store, nil, nil)
}

func GetPathState(
	path any,
	store any,
	current any,
	state *Injection,
) any {
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
			parts = _resolveStrings(pp.([]any))
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
	store any,
	current any,
	state *Injection,
) any {
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
		case map[string]any, []any:
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
	val any,
	store any,
) any {
	return InjectDescend(val, store, nil, nil, nil)
}

func InjectDescend(
	val any,
	store any,
	modify Modify,
	current any,
	state *Injection,
) any {
	valType := _getType(val)

	// Create state if at root of injection.  The input value is placed
	// inside a virtual parent holder to simplify edge cases.
	if state == nil {
		parent := map[string]any{
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
			Nodes:   []any{parent},
			Handler: injectHandler,
			Base:    S_DTOP,
			Modify:  modify,
			Errs:    GetProp(store, S_DERRS, ListRefCreate[any]()).(*ListRef[any]),
			Meta:    make(map[string]any),
		}
	}

	// Resolve current node in store for local paths.
	if nil == current {
		current = map[string]any{
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
		nodekeys := append(normalKeys, transformKeys...)

		// Each child key-value pair is processed in three injection phases:
		// 1. state.mode='key:pre' - Key string is injected, returning a possibly altered key.
		// 2. state.mode='val' - The child value is injected.
		// 3. state.mode='key:post' - Key string is injected again, allowing child mutation.

		nkI := 0
		for nkI < len(nodekeys) {
			nodekey := nodekeys[nkI]

			childpath := append(state.Path, nodekey)
			childnodes := append(state.Nodes, val)
			childval := GetProp(val, nodekey)

			childstate := &Injection{
				Mode:    InjectModeKeyPre,
				Full:    false,
				KeyI:    nkI,
				Keys:    nodekeys,
				Key:     nodekey,
				Val:     childval,
				Parent:  val,
				Path:    childpath,
				Nodes:   childnodes,
				Handler: injectHandler,
				Base:    state.Base,
				Modify:  state.Modify,
				Errs:    state.Errs,
				Meta:    state.Meta,
			}

			// Peform the key:pre mode injection on the child key.
			preKey := _injectStr(nodekey, store, current, childstate)

			// The injection may modify child processing.
			nkI = childstate.KeyI
      nodekeys = childstate.Keys
      val = childstate.Parent
      
			if preKey != nil {
				childval = GetProp(val, preKey)
				childstate.Val = childval
				childstate.Mode = InjectModeVal

				// Perform the val mode injection on the child value.
				// NOTE: return value is not used.
				InjectDescend(childval, store, modify, current, childstate)

				// The injection may modify child processing.
				nkI = childstate.KeyI
        nodekeys = childstate.Keys
        val = childstate.Parent
        
				// Peform the key:post mode injection on the child key.
				childstate.Mode = InjectModeKeyPost
				_injectStr(nodekey, store, current, childstate)

				// The injection may modify child processing.
				nkI = childstate.KeyI
        nodekeys = childstate.Keys
        val = childstate.Parent
			}

      // fmt.Println("INJECT-CHILD-END", nkI, val, childstate)
      
			nkI = nkI + 1
		}

	} else if valType == S_string {

		// Inject paths into string scalars.
		state.Mode = InjectModeVal
		strVal, ok := val.(string)
		if ok {
			val = _injectStr(strVal, store, current, state)
			_setPropOfStateParent(state, val)
		}
	}

	// Custom modification
	if nil != modify {
    mkey := state.Key
    mparent := state.Parent
    mval := GetProp(mparent, mkey)
		modify(
			mval,
			mkey,
			mparent,
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
	val any,
	current any,
	ref *string,
	store any,
) any {

	iscmd := IsFunc(val) && (nil == ref || strings.HasPrefix(*ref, S_DS))

	if iscmd {
		fnih, ok := val.(Injector)

		if ok {
			val = fnih(state, val, current, ref, store)
		} else {

			// In Go, as a convenience, allow injection functions that have no arguments.
			fn0, ok := val.(func() any)
			if ok {
				val = fn0()
			}
		}
	} else if InjectModeVal == state.Mode && state.Full {
		// Update parent with value. Ensures references remain in node tree.
		_setPropOfStateParent(state, val)
	}

	return val
}

// The transform_* functions are special command inject handlers (see Injector).

// Delete a key from a map or list.
var Transform_DELETE Injector = func(
	state *Injection,
	val any,
	current any,
	ref *string,
	store any,
) any {
	// SetProp(state.Parent, state.Key, nil)
	_setPropOfStateParent(state, nil)
	return nil
}

// Copy value from source data.
var Transform_COPY Injector = func(
	state *Injection,
	val any,
	current any,
	ref *string,
	store any,
) any {
	var out any = state.Key

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
	val any,
	current any,
	ref *string,
	store any,
) any {
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
	val any,
	current any,
	ref *string,
	store any,
) any {
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
	val any,
	current any,
	ref *string,
	store any,
) any {
	if InjectModeKeyPre == state.Mode {
		return state.Key
	}

	if InjectModeKeyPost == state.Mode {
		args := GetProp(state.Parent, state.Key)
		if S_MT == args {
			args = []any{GetProp(store, S_DTOP)}
		} else if IsList(args) {
			// do nothing
		} else {
			// wrap in array
			args = []any{args}
		}

		// Remove the $MERGE command from a parent map.
		_setPropOfStateParent(state, nil)

		list, ok := args.([]any)
		if !ok {
			return state.Key
		}

		// Literals in the parent have precedence, but we still merge onto
		// the parent object, so that node tree references are not changed.
		mergeList := []any{state.Parent}
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
	val any,
	current any,
	ref *string,
	store any,
) any {

	// Remove arguments to avoid spurious processing.
	if state.Keys != nil {
		state.Keys = state.Keys[:1]
	}

	if InjectModeVal != state.Mode {
		return nil
	}

	// Get arguments: ['`$EACH`', 'source-path', child-template].
	parent := state.Parent
	arr, ok := parent.([]any)
	if !ok || len(arr) < 3 {
		return nil
	}
	srcpath := arr[1]
	child := Clone(arr[2])

	// Source data.
	src := GetPathState(srcpath, store, current, state)

	// Create parallel data structures:
	// source entries :: child templates
	var tcur any
	tcur = []any{}
	var tval any
	tval = []any{}

	// Create clones of the child template for each value of the current soruce.
	if IsList(src) {
		srcList := src.([]any)
		newlist := make([]any, len(srcList))
		for i := range srcList {
			newlist[i] = Clone(child)
			SetProp(tcur, i, srcList[i])
		}
		tval = newlist

	} else if IsMap(src) {
		items := Items(src)

		srcMap := src.(map[string]any)
		newlist := make([]any, 0, len(srcMap))

		for i, item := range items {
			k := item[0]
			v := item[1]
			cclone := Clone(child)

			// Make a note of the key for $KEY transforms.
			setp, ok := cclone.(map[string]any)
			if ok {
				setp[S_TMETA] = map[string]any{
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
	tcur = map[string]any{
		S_DTOP: tcur,
	}

	// Build the substructure.
	tval = InjectDescend(tval, store, state.Modify, tcur, nil)
	state.Parent = tval
	_updateStateNodeAncestors(state, tval)

	// Return the first element
	listVal, ok := tval.([]any)
	if ok && len(listVal) > 0 {
		return listVal[0]
	}

	return nil
}

// transform_PACK => `$PACK`
var Transform_PACK Injector = func(
	state *Injection,
	val any,
	current any,
	ref *string,
	store any,
) any {
	if state.Mode != InjectModeKeyPre || state.Key == "" || state.Path == nil || state.Nodes == nil {
		return nil
	}

	parentMap, ok := state.Parent.(map[string]any)
	if !ok {
		return nil
	}

	args, ok := parentMap[state.Key].([]any)
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
	var target any
	if len(state.Nodes) >= 2 {
		target = state.Nodes[len(state.Nodes)-2]
	} else {
		target = state.Nodes[len(state.Nodes)-1]
	}

	src := GetPathState(srcpath, store, current, state)
	// Convert map to list if needed
	var srclist []any

	if IsList(src) {
		srclist = src.([]any)
	} else if IsMap(src) {
		m := src.(map[string]any)
		tmp := make([]any, 0, len(m))
		for k, v := range m {
			// carry forward the KEY in TMeta
			vmeta := GetProp(v, S_TMETA)
			if vmeta == nil {
				vmeta = map[string]any{}
				SetProp(v, S_TMETA, vmeta)
			}
			vm := vmeta.(map[string]any)
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
	// remove S_TKEY so it doesn't interfere
	SetProp(child, S_TKEY, nil)

	tval := map[string]any{}
	tcurrent := map[string]any{}

	for _, item := range srclist {
		kname := GetProp(item, childKey)
		if kstr, ok := kname.(string); ok && kstr != "" {
			tval[kstr] = Clone(child)
			if _, ok2 := tval[kstr].(map[string]any); ok2 {
				SetProp(tval[kstr], S_TMETA, GetProp(item, S_TMETA))
			}
			tcurrent[kstr] = item
		}
	}

	tcur := map[string]any{
		S_DTOP: tcurrent,
	}

	tvalout := InjectDescend(tval, store, state.Modify, tcur, nil)

	SetProp(target, tkey, tvalout)

	return nil
}

// ---------------------------------------------------------------------
// Transform function: top-level

func Transform(
	data any, // source data
	spec any, // transform specification
) any {
	return TransformModify(data, spec, nil, nil)
}

func TransformModify(
	data any, // source data
	spec any, // transform specification
	extra any, // extra store
	modify Modify, // optional modify
) any {

	// Clone the spec so that the clone can be modified in place as the transform result.
	spec = Clone(spec)

	// Split extra transforms from extra data
	extraTransforms := map[string]any{}
	extraData := map[string]any{}

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
	dataClone := Merge([]any{
		Clone(extraData),
		Clone(data),
	})

	// The injection store with transform functions
	store := map[string]any{
		// Merged data is at $TOP
		S_DTOP: dataClone,

		// Handy escapes
		"$BT": func() any { return S_BT },
		"$DS": func() any { return S_DS },

		// Insert current date/time
		"$WHEN": func() any {
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


var validate_STRING Injector = func(
	state *Injection,
	_val any,
	current any,
	ref *string,
	store any,
) any {
	out := GetProp(current, state.Key)
	
	t := _typify(out)
	if S_string != t {
		msg := _invalidTypeMsg(state.Path, S_string, t, out)
		state.Errs.Append(msg)
		return nil
	}

	if S_MT == out.(string) {
		msg := "Empty string at " + Pathify(state.Path, 0)
		state.Errs.Append(msg)
		return nil
	}

	return out
}


var validate_NUMBER Injector = func(
	state *Injection,
	_val any,
	current any,
	ref *string,
	store any,
) any {
	out := GetProp(current, state.Key)
	
	t := _typify(out)
  if S_number != t {
		msg := _invalidTypeMsg(state.Path, S_number, t, out)
		state.Errs.Append(msg)
		return nil
	}

  return out
}


var validate_BOOLEAN Injector = func(
	state *Injection,
	_val any,
	current any,
	ref *string,
	store any,
) any {
	out := GetProp(current, state.Key)
	
	t := _typify(out)
	if S_boolean != t {
		msg := _invalidTypeMsg(state.Path, S_boolean, t, out)
		state.Errs.Append(msg)
		return nil
	}

	return out
}


var validate_OBJECT Injector = func(
	state *Injection,
	_val any,
	current any,
	ref *string,
	store any,
) any {
	out := GetProp(current, state.Key)
	
	t := _typify(out)
	if S_object != t {
		msg := _invalidTypeMsg(state.Path, S_object, t, out)
		state.Errs.Append(msg)
		return nil
	}
	
	return out
}


var validate_ARRAY Injector = func(
	state *Injection,
	_val any,
	current any,
	ref *string,
	store any,
) any {
	out := GetProp(current, state.Key)
	
	t := _typify(out)
	if S_array != t {
		msg := _invalidTypeMsg(state.Path, S_array, t, out)
		state.Errs.Append(msg)
		return nil
	}
	
	return out
}


var validate_FUNCTION Injector = func(
	state *Injection,
	_val any,
	current any,
	ref *string,
	store any,
) any {
	out := GetProp(current, state.Key)
	
	t := _typify(out)
	if S_function != t {
		msg := _invalidTypeMsg(state.Path, S_function, t, out)
		state.Errs.Append(msg)
		return nil
	}
	
	return out
}


var validate_ANY Injector = func(
	state *Injection,
	_val any,
	current any,
	ref *string,
	store any,
) any {
	return GetProp(current, state.Key)
}


var validate_CHILD Injector = func(
	state *Injection,
	_val any,
	current any,
	ref *string,
	store any,
) any {
	// Map syntax
	if state.Mode == S_MKEYPRE {
		child := GetProp(state.Parent, state.Key)

    pkey := GetProp(state.Path, len(state.Path)-2)
		tval := GetProp(current, pkey)

		if nil == tval {
			tval = map[string]any{}

		} else if !IsMap(tval) {
			state.Errs.Append(
				_invalidTypeMsg(
					state.Path[:len(state.Path)-1],
					S_object,
					_typify(tval),
					tval,
				))
			return nil
		}

		// For each key in tval, clone the child into parent
		ckeys := KeysOf(tval)
		for _, ckey := range ckeys {
			SetProp(state.Parent, ckey, Clone(child))
			state.Keys = append(state.Keys, ckey)
		}

		SetProp(state.Parent, state.Key, nil)

		return nil
	}

	// List syntax
  if state.Mode == S_MVAL {
    
		// We expect 'parent' to be a slice of any, like ["`$CHILD`", childTemplate].
		if !IsList(state.Parent) {
			state.Errs.Append("Invalid $CHILD as value")
			return nil
		}

    child := GetProp(state.Parent, 1)
    
		// If current is nil => empty list default
		if nil == current {
			state.Parent = []any{}
      _updateStateNodeAncestors(state, state.Parent)
			return nil
		}

		// If current is not a list => error
		if !IsList(current) {
			state.Errs.Append(
				_invalidTypeMsg(
					state.Path[:len(state.Path)-1],
					S_array,
					_typify(current),
					current,
				))
			state.KeyI = len(state.Parent.([]any))
			return current
		}

		// Otherwise, current is a list => clone child for each element in current
		rv := reflect.ValueOf(current)
		length := rv.Len()

		// Make a new slice to hold the child clones, sized to length
		newParent := make([]any, length)
		// For each element in 'current', set newParent[i] = clone(child)
		for i := 0; i < length; i++ {
			newParent[i] = Clone(child)
		}
		
		// Replace parent with the new slice
		state.Parent = newParent
		_updateStateNodeAncestors(state, state.Parent)

    out := GetProp(current, 0)
    return out
	}

	return nil
}


// Forward declaration for validate_ONE
var validate_ONE Injector

// Implementation will be set after ValidateCollect is defined
func init_validate_ONE() {
	validate_ONE = func(
		state *Injection,
		_val any,
		current any,
		ref *string,
		store any,
	) any {
		// Only operate in "val mode" (list mode).
		if state.Mode == S_MVAL {
			// Once we handle `$ONE`, we skip further iteration by setting KeyI to keys.length
			state.KeyI = len(state.Keys)
	
			// The parent is assumed to be a slice: ["`$ONE`", alt0, alt1, ...].
			parentSlice, ok := state.Parent.([]any)
			if !ok || len(parentSlice) < 2 {
				return nil
			}
	
			// The shape alternatives are everything after the first element.
			tvals := parentSlice[1:] // alt0, alt1, ...
	
			// Try each alternative shape
			for _, tval := range tvals {
				// Collect errors in a temporary slice
				var terrs = ListRefCreate[any]()
	
				// Attempt validation of `current` with shape `tval`
				_, err := ValidateCollect(current, tval, nil, terrs)
				if err == nil && len(terrs.List) == 0 {
					// The parent is the list we are inside.
					// We look up one level: that is `nodes[nodes.length - 2]`.
					grandparent := GetProp(state.Nodes, len(state.Nodes)-2)
          grandkey := GetProp(state.Path, len(state.Path)-2)
	
					if IsNode(grandparent) {

            if 0 == len(terrs.List) {
              SetProp(grandparent, grandkey, current)
              state.Parent = current
              // fmt.Println("ONE-GP", grandparent, grandkey)
              // fmt.Println("ONE-SC", current, state)

              return nil
            } else {
              SetProp(grandparent, grandkey, nil)
            }
					}
				}
			}

      mapped := make([]string, len(tvals))
      for i, v := range tvals {
        mapped[i] = Stringify(v)
      }

      joined := strings.Join(mapped, ", ")

      re := regexp.MustCompile("`\\$([A-Z]+)`")
      valdesc := re.ReplaceAllStringFunc(joined, func(match string) string {
        submatches := re.FindStringSubmatch(match)
        if len(submatches) == 2 {
          return strings.ToLower(submatches[1])
        }
        return match
      })
	
			actualType := _typify(current)
			msg := _invalidTypeMsg(
				state.Path[:len(state.Path)-1],
				"one of "+valdesc,
				actualType,
				current,
			)
			state.Errs.Append(msg)
		}

		return nil
	}
}


func validation(
	val any,
	key any,
	parent any,
	state *Injection,
	current any,
	_store any,
) {
	if state == nil {
		return
	}

	// Current val to verify.
	cval := GetProp(current, key)
	if cval == nil {
		return
	}

	pval := GetProp(parent, key)
	ptype := _typify(pval)

	// Delete any special commands remaining.
	if S_string == ptype && pval != nil {
		if strVal, ok := pval.(string); ok && strings.Contains(strVal, S_DS) {
			return
		}
	}

	ctype := _typify(cval)


  // fmt.Println("VALID", pval, ptype, cval, ctype)
  
	// Type mismatch.
	if ptype != ctype && pval != nil {
		state.Errs.Append(_invalidTypeMsg(state.Path, ptype, ctype, cval))
		return
	}

	if IsMap(cval) {
		if !IsMap(val) {
			var errType string
			if IsList(val) {
				errType = S_array
			} else {
				errType = ptype
			}
			state.Errs.Append(_invalidTypeMsg(state.Path, errType, ctype, cval))
			return
		}

		ckeys := KeysOf(cval)
		pkeys := KeysOf(pval)

		// Empty spec object {} means object can be open (any keys).
		if len(pkeys) > 0 && GetProp(pval, "`$OPEN`") != true {
			badkeys := []string{}
			for _, ckey := range ckeys {
				if !HasKey(val, ckey) {
					badkeys = append(badkeys, ckey)
				}
			}

			// Closed object, so reject extra keys not in shape.
			if len(badkeys) > 0 {
				state.Errs.Append("Unexpected keys at " + Pathify(state.Path, 1) +
					": " + strings.Join(badkeys, ", "))
			}
		} else {
			// Object is open, so merge in extra keys.
			Merge([]any{pval, cval})
			if IsNode(pval) {
				SetProp(pval, "`$OPEN`", nil)
			}
		}
	} else if IsList(cval) {
		if !IsList(val) {
			state.Errs.Append(_invalidTypeMsg(state.Path, ptype, ctype, cval))
		}
	} else {
		// Spec value was a default, copy over data
		SetProp(parent, key, cval)
	}

	return
}


func Validate(
	data any, // The input data
	spec any, // The shape specification
) (any, error) {
	return ValidateCollect(data, spec, nil, nil)
}

func ValidateCollect(
	data any,
	spec any,
	extra map[string]any,
	collecterrs *ListRef[any],
) (any, error) {

	if nil == collecterrs {
		collecterrs = ListRefCreate[any]()
	}
	
	// Initialize validate_ONE if not already initialized.
  // This avoids a circular reference error, validate_ONE calls ValidateCollect. 
	if validate_ONE == nil {
		init_validate_ONE()
	}

	store := map[string]any{
		"$ERRS": collecterrs,

		"$BT":     nil,
		"$DS":     nil,
		"$WHEN":   nil,
		"$DELETE": nil,
		"$COPY":   nil,
		"$KEY":    nil,
		"$META":   nil,
		"$MERGE":  nil,
		"$EACH":   nil,
		"$PACK":   nil,

		"$STRING":   validate_STRING,
		"$NUMBER":   validate_NUMBER,
		"$BOOLEAN":  validate_BOOLEAN,
		"$OBJECT":   validate_OBJECT,
		"$ARRAY":    validate_ARRAY,
		"$FUNCTION": validate_FUNCTION,
		"$ANY":      validate_ANY,
		"$CHILD":    validate_CHILD,
		"$ONE":      validate_ONE,
	}

	for k, fn := range extra {
		store[k] = fn
	}

	out := TransformModify(data, spec, store, validation)

	var err error

	if 0 < len(collecterrs.List) {
		err = fmt.Errorf("Invalid data: %s", _join(collecterrs.List, " | "))
	}

	return out, err
}


// Internal utilities
// ==================

type ListRef[T any] struct {
	List []T
}

func ListRefCreate[T any]() *ListRef[T] {
	return &ListRef[T]{
		List: make([]T, 0),
	}
}

func (l *ListRef[T]) Append(elem T) {
	l.List = append(l.List, elem)
}

func (l *ListRef[T]) Prepend(elem T) {
	l.List = append([]T{elem}, l.List...)
}


func _typify(value any) string {
	if value == nil {
		return "null"
	}

	t := reflect.TypeOf(value)

	switch t.Kind() {
	case reflect.Bool:
		return "boolean"

	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return "number"

	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64,
		reflect.Float32, reflect.Float64:
		return "number"

	case reflect.String:
		return "string"

	case reflect.Func:
		return "function"

	case reflect.Slice, reflect.Array:
		return "array"

	default:
		return "object"
	}
}

func _join(vals []any, sep string) string {
	strVals := make([]string, len(vals))
	for i, v := range vals {
		strVals[i] = fmt.Sprint(v)
	}
	return strings.Join(strVals, sep)
}


func _invalidTypeMsg(path []string, expected string, actual string, val any) string {
	vs := Stringify(val)
	valueStr := vs
	if val != nil {
		valueStr = actual + ": " + vs
	}
	
	return fmt.Sprintf(
		"Expected %s at %s, found %s",
		expected,
		Pathify(path, 1),
		valueStr,
	)
}


func _getType(v any) string {
	if nil == v {
		return "nil"
	}
	return reflect.TypeOf(v).String()
}

func _strKey(key any) string {
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

func _resolveStrings(input []any) []string {
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

func _listify(src any) []any {
	if list, ok := src.([]any); ok {
		return list
	}

	if src == nil {
		return nil
	}

	val := reflect.ValueOf(src)
	if val.Kind() == reflect.Slice {
		length := val.Len()
		result := make([]any, length)

		for i := 0; i < length; i++ {
			result[i] = val.Index(i).Interface()
		}
		return result
	}

	return nil
}

// toFloat64 helps unify numeric types for floor conversion.
func _toFloat64(val any) (float64, error) {
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
		// might overflow if > math.MaxFloat64, but for demonstration that's rare
		return float64(n), nil
	default:
		return 0, fmt.Errorf("not a numeric type")
	}
}

// _parseInt is a helper to convert a string to int safely.
func _parseInt(s string) (int, error) {
	// We'll do a very simple parse:
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

func _makeArrayType(values []any, target any) any {
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

func _stringifyValue(v any) string {
	switch vv := v.(type) {
	case string:
		return vv
	case float64, int, bool:
		return Stringify(v)
	default:
		return Stringify(v)
	}
}

func _setPropOfStateParent(state *Injection, val any) {
	parent := SetProp(state.Parent, state.Key, val)
	if IsList(parent) && len(parent.([]any)) != len(state.Parent.([]any)) {
		state.Parent = parent
		_updateStateNodeAncestors(state, parent)
	}
}

func _updateStateNodeAncestors(state *Injection, ac any) {
	aI := len(state.Nodes) - 1
	if -1 < aI {
		state.Nodes[aI] = ac
	}
	aI = aI - 1
	for -1 < aI {
		an := state.Nodes[aI]
		ak := state.Path[aI]
		ac = SetProp(an, ak, ac)
		if IsMap(ac) {
			aI = -1
		} else {
			aI = aI - 1
		}
	}
}

// DEBUG

func fdt(data any) string {
	return fdti(data, "")
}

func fdti(data any, indent string) string {
	result := ""

	if data == nil {
		return indent + "nil\n"
	}

	// Get a pointer for memory address
	memoryAddr := "0x???"
	val := reflect.ValueOf(data)
	
	// For non-pointer types that are addressable, get their pointer
	if val.Kind() != reflect.Ptr && val.CanAddr() {
		ptr := val.Addr()
		memoryAddr = fmt.Sprintf("0x%x", ptr.Pointer())
	} else if val.Kind() == reflect.Ptr {
		// For pointer types, use the pointer value directly
		memoryAddr = fmt.Sprintf("0x%x", val.Pointer())
	} else if val.Kind() == reflect.Map || val.Kind() == reflect.Slice {
		// For maps and slices, use the pointer to internal data
		memoryAddr = fmt.Sprintf("0x%x", val.Pointer())
	}

	switch v := data.(type) {
	case map[string]any:
		result += indent + fmt.Sprintf("{ @%s\n", memoryAddr)
		for key, value := range v {
			result += fmt.Sprintf("%s  \"%s\": %s", indent, key, fdti(value, indent+"  "))
		}
		result += indent + "}\n"

	case []any:
		result += indent + fmt.Sprintf("[ @%s\n", memoryAddr)
		for _, value := range v {
			result += fmt.Sprintf("%s  - %s", indent, fdti(value, indent+"  "))
		}
		result += indent + "]\n"

	default:
		// Check if it's a struct using reflection
		typ := val.Type()

		// Handle pointers by dereferencing
		isPtr := false
		if val.Kind() == reflect.Ptr {
			isPtr = true
			if val.IsNil() {
				return indent + "nil\n"
			}
			val = val.Elem()
			typ = val.Type()
		}

		if val.Kind() == reflect.Struct {
			structName := typ.Name()
			if isPtr {
				structName = "*" + structName
			}
			result += indent + fmt.Sprintf("struct %s @%s {\n", structName, memoryAddr)
			
			// Iterate over all fields of the struct
			for i := 0; i < val.NumField(); i++ {
				field := val.Field(i)
				fieldType := typ.Field(i)
				
				// Skip unexported fields (lowercase field names)
				if !fieldType.IsExported() {
					continue
				}
				
				fieldName := fieldType.Name
				fieldValue := field.Interface()
				
				result += fmt.Sprintf("%s  %s: %s", indent, fieldName, fdti(fieldValue, indent+"  "))
			}
			result += indent + "}\n"
		} else {
			// For non-struct types, just format value with its type
			result += fmt.Sprintf("%v (%s) @%s\n", v, reflect.TypeOf(v), memoryAddr)
		}
	}

	return result
}
