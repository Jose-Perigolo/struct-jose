// go test
// go test -v -run=TestStruct/foo

package voxgigstruct_test

import (
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"strings"
	"testing"

	"github.com/voxgig/struct"
	"github.com/voxgig/struct/testutil"
)

// TestEntry represents a single test case
// in/out values and potential error info
// from the original TS code.
type TestEntry struct {
	In     any `json:"in,omitempty"`
	Out    any `json:"out,omitempty"`
	Err    any `json:"err,omitempty"`
	Thrown any `json:"thrown,omitempty"`
}

type TestSet []TestEntry

type SubTest struct {
	TestEntry
	Set TestSet `json:"set"`
}

type TestGroup map[string]SubTest

type FullTest map[string]TestGroup

// Since json.Unmarshal uses nil for null, assume
// user will represent null in another way with a defined value.
func fixJSON(data any) any {
	return fixJSONFlags(data, map[string]bool{
		"null": true,
	})
}

func fixJSONFlags(data any, flags map[string]bool) any {
	if nil == data && flags["null"] {
		return "__NULL__"
	}

	v := reflect.ValueOf(data)

	switch v.Kind() {

	case reflect.Float64:
		if v.Float() == float64(int(v.Float())) {
			return int(v.Float())
		}
		return data

	case reflect.Map:
		fixedMap := make(map[string]any)
		for _, key := range v.MapKeys() {
			strKey, ok := key.Interface().(string)
			if ok {
				fixedMap[strKey] = fixJSONFlags(v.MapIndex(key).Interface(), flags)
			}
		}
		return fixedMap

	case reflect.Slice:
		length := v.Len()
		fixedSlice := make([]any, length)
		for i := 0; i < length; i++ {
			fixedSlice[i] = fixJSONFlags(v.Index(i).Interface(), flags)
		}
		return fixedSlice

	case reflect.Array:
		length := v.Len()
		fixedSlice := make([]any, length)
		for i := 0; i < length; i++ {
			fixedSlice[i] = fixJSONFlags(v.Index(i).Interface(), flags)
		}
		return fixedSlice

	default:
		return data
	}
}

func nullModifier(
	val any,
	key any,
	parent any,
	state *voxgigstruct.Injection,
	current any,
	store any,
) {
	switch v := val.(type) {
	case string:
		if "__NULL__" == v {
			_ = voxgigstruct.SetProp(parent, key, nil)
		} else {
			_ = voxgigstruct.SetProp(parent, key,
				strings.ReplaceAll(v, "__NULL__", "null"))
		}
	}
}

func fdt(data any) string {
	return fdti(data, "")
}

func fdti(data any, indent string) string {
	result := ""

	switch v := data.(type) {
	case map[string]any:
		result += indent + "{\n"
		for key, value := range v {
			result += fmt.Sprintf("%s  \"%s\": %s", indent, key, fdti(value, indent+"  "))
		}
		result += indent + "}\n"

	case []any:
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

func toJSONString(data any) string {
	jsonBytes, err := json.Marshal(data)
	if err != nil {
		return "" // Return empty string if marshalling fails
	}
	return string(jsonBytes)
}

// RunTestSet executes a set of test entries by calling 'apply'
// on each "in" value and comparing to "out".
// If a mismatch occurs, the test fails.

func runTestSet(t *testing.T, tests SubTest, apply func(any) any) {
	runTestSetFlags(t, tests, apply, map[string]bool{
		"null": true,
	})
}

func runTestSetFlags(t *testing.T, tests SubTest, apply func(any) any, flags map[string]bool) {
	for _, entry := range tests.Set {
		input := fixJSONFlags(entry.In, flags)
		output := fixJSONFlags(entry.Out, flags)
		result := fixJSONFlags(apply(input), flags)

		// fmt.Println("RUNTESTSET", "\nINPUT", fdt(input), "\nRESULT", fdt(result), "\nOUTPUT", fdt(output))

		if !reflect.DeepEqual(result, output) {
			t.Errorf("Expected: %s, \nGot: %s \nExpected JSON: %s \nGot JSON: %s",
				fdt(output), fdt(result), toJSONString(output), toJSONString(result))
		}
	}
}

// LoadTestSpec reads and unmarshals the JSON file into FullTest.
func LoadTestSpec(filename string) (FullTest, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	var testSpec FullTest
	if err := json.Unmarshal(data, &testSpec); err != nil {
		return nil, err
	}

	return testSpec, nil
}

type TestProvider struct{}

func (p *TestProvider) Test(opts map[string]any) (runner.Client, error) {
	return &testClient{}, nil
}

type testClient struct{}

func (c *testClient) Utility() runner.Utility {
	return &testUtility{}
}

type testUtility struct{}

func (c *testUtility) Struct() *runner.StructUtility {
	return &runner.StructUtility{
		IsNode:     voxgigstruct.IsNode,
		Clone:      voxgigstruct.Clone,
		CloneFlags: voxgigstruct.CloneFlags,
		GetPath:    voxgigstruct.GetPath,
		Inject:     voxgigstruct.Inject,
		Items:      voxgigstruct.Items,
		Stringify:  voxgigstruct.Stringify,
		Walk:       voxgigstruct.Walk,
	}
}

// NOTE: tests are in order of increasing dependence.
func TestStruct(t *testing.T) {

	store := make(map[string]any)
	provider := &TestProvider{}

	runnerMap, err := runner.Runner("struct", store, "../build/test/test.json", provider)
	if err != nil {
		t.Fatalf("Failed to create runner: %v", err)
	}

	var spec map[string]any = runnerMap.Spec
	var runset runner.RunSet = runnerMap.RunSet
	var runsetFlags runner.RunSetFlags = runnerMap.RunSetFlags

	var minor = spec["minor"].(map[string]any)
	var walk = spec["walk"].(map[string]any)
	var merge = spec["merge"].(map[string]any)
	var getpath = spec["getpath"].(map[string]any)
	var inject = spec["inject"].(map[string]any)
	var transform = spec["transform"].(map[string]any)
	var validate = spec["validate"].(map[string]any)

	// minor tests
	// ===========

	t.Run("minor-exists", func(t *testing.T) {
		checks := map[string]any{
			"clone":   voxgigstruct.Clone,
			"escre":   voxgigstruct.EscRe,
			"escurl":  voxgigstruct.EscUrl,
			"getprop": voxgigstruct.GetProp,
			"haskey":  voxgigstruct.HasKey,

			"isempty": voxgigstruct.IsEmpty,
			"isfunc":  voxgigstruct.IsFunc,
			"iskey":   voxgigstruct.IsKey,
			"islist":  voxgigstruct.IsList,
			"ismap":   voxgigstruct.IsMap,

			"isnode":  voxgigstruct.IsNode,
			"items":   voxgigstruct.Items,
			"joinurl": voxgigstruct.JoinUrl,
			"keysof":  voxgigstruct.KeysOf,
			"setprop": voxgigstruct.SetProp,

			"stringify": voxgigstruct.Stringify,
		}
		for name, fn := range checks {
			if fnVal := reflect.ValueOf(fn); fnVal.Kind() != reflect.Func {
				t.Errorf("%s should be a function, but got %s", name, fnVal.Kind().String())
			}
		}
	})

	t.Run("minor-isnode", func(t *testing.T) {
		runset(t, minor["isnode"], voxgigstruct.IsNode)
	})

	t.Run("minor-ismap", func(t *testing.T) {
		runset(t, minor["ismap"], voxgigstruct.IsMap)
	})

	t.Run("minor-islist", func(t *testing.T) {
		runset(t, minor["islist"], voxgigstruct.IsList)
	})

	t.Run("minor-iskey", func(t *testing.T) {
		runsetFlags(t, minor["iskey"], map[string]bool{"json_null": false}, voxgigstruct.IsKey)
	})

	t.Run("minor-isempty", func(t *testing.T) {
		runsetFlags(t, minor["isempty"], map[string]bool{"json_null": false}, voxgigstruct.IsEmpty)
	})

	t.Run("minor-isfunc", func(t *testing.T) {
		runset(t, minor["isfunc"], voxgigstruct.IsFunc)

		f0 := func() any {
			return nil
		}

		if !voxgigstruct.IsFunc(f0) {
			t.Errorf("IsFunc failed on function f0")
		}

		if !voxgigstruct.IsFunc(func() any { return nil }) {
			t.Errorf("IsFunc failed on anonymous function")
		}
	})

	t.Run("minor-clone", func(t *testing.T) {
		runsetFlags(
			t,
			minor["clone"],
			map[string]bool{"json_null": false},
			voxgigstruct.Clone,
		)
	})

	t.Run("minor-escre", func(t *testing.T) {
		runset(t, minor["escre"], voxgigstruct.EscRe)
	})

	t.Run("minor-escurl", func(t *testing.T) {
		runset(t, minor["escurl"], func(in string) string {
			return strings.ReplaceAll(voxgigstruct.EscUrl(fmt.Sprint(in)), "+", "%20")
		})
	})

	t.Run("minor-stringify", func(t *testing.T) {
		runset(t, minor["stringify"], func(v any) any {
			m := v.(map[string]any)
			val := m["val"]

			if "__NULL__" == val {
				val = "null"
			}

			max, hasMax := m["max"]
			if !hasMax || nil == max {
				return voxgigstruct.Stringify(val)
			} else {
				return voxgigstruct.Stringify(val, int(max.(int)))
			}
		})
	})

	t.Run("minor-pathify", func(t *testing.T) {
		runsetFlags(
			t,
			minor["pathify"],
			map[string]bool{"json_null": true},
			func(v any) any {
				m := v.(map[string]any)
				path := m["path"]
				from, hasFrom := m["from"]

				// NOTE: JSON null is not really nil, so special handling needed since
				// the JSON parser does give us nil for null!
				if "__NULL__" == m["path"] {
					path = nil
				}

				pathstr := ""

				if !hasFrom || nil == from {
					pathstr = voxgigstruct.Pathify(path)
				} else {
					pathstr = voxgigstruct.Pathify(path, int(from.(int)))
				}

				if "__NULL__" == m["path"] {
					pathstr = strings.ReplaceAll(pathstr, ">", ":null>")
				}

				pathstr = strings.ReplaceAll(pathstr, "__NULL__.", "")

				return pathstr
			},
		)
	})

	t.Run("minor-items", func(t *testing.T) {
		runset(t, minor["items"], voxgigstruct.Items)
	})

	t.Run("minor-getprop", func(t *testing.T) {
		runsetFlags(
			t,
			minor["getprop"],
			map[string]bool{"json_null": false},
			func(v any) any {
				m := v.(map[string]any)
				store := m["val"]
				key := m["key"]
				alt, hasAlt := m["alt"]
				if !hasAlt || alt == nil {
					return voxgigstruct.GetProp(store, key)
				}
				return voxgigstruct.GetProp(store, key, alt)
			},
		)
	})

	t.Run("minor-edge-getprop", func(t *testing.T) {
		strarr := []string{"a", "b", "c", "d", "e"}
		expectedA := "c"

		result0 := voxgigstruct.GetProp(strarr, 2)
		if !reflect.DeepEqual(expectedA, result0) {
			t.Errorf("Expected: %v, Got: %v", expectedA, result0)
		}

		result1 := voxgigstruct.GetProp(strarr, "2")
		if !reflect.DeepEqual(expectedA, result1) {
			t.Errorf("Expected: %v, Got: %v", expectedA, result1)
		}

		intarr := []int{2, 3, 5, 7, 11}
		expectedB := 5

		result2 := voxgigstruct.GetProp(intarr, 2)
		if !reflect.DeepEqual(expectedB, result2) {
			t.Errorf("Expected: %v, Got: %v", expectedB, result2)
		}

		result3 := voxgigstruct.GetProp(intarr, "2")
		if !reflect.DeepEqual(expectedB, result3) {
			t.Errorf("Expected: %v, Got: %v", expectedB, result2)
		}
	})

	t.Run("minor-setprop", func(t *testing.T) {
		runsetFlags(
			t,
			minor["setprop"],
			map[string]bool{"json_null": true},
			func(v any) any {
				m := v.(map[string]any)
				parent := m["parent"]
				key := m["key"]
				val := m["val"]
				res := voxgigstruct.SetProp(parent, key, val)
				return res
			})
	})

	t.Run("minor-edge-setprop", func(t *testing.T) {
		strarr0 := []string{"a", "b", "c", "d", "e"}
		strarr1 := []string{"a", "b", "c", "d", "e"}

		expected0 := []string{"a", "b", "C", "d", "e"}
		gotstrarr := voxgigstruct.SetProp(strarr0, 2, "C").([]string)
		if !reflect.DeepEqual(gotstrarr, expected0) {
			t.Errorf("Expected: %v, Got: %v", expected0, gotstrarr)
		}

		expected1 := []string{"a", "b", "CC", "d", "e"}
		gotstrarr = voxgigstruct.SetProp(strarr1, "2", "CC").([]string)
		if !reflect.DeepEqual(gotstrarr, expected1) {
			t.Errorf("Expected: %v, Got: %v", expected0, gotstrarr)
		}

		intarr0 := []int{2, 3, 5, 7, 11}
		intarr1 := []int{2, 3, 5, 7, 11}

		expected2 := []int{2, 3, 55, 7, 11}
		gotintarr := voxgigstruct.SetProp(intarr0, 2, 55).([]int)
		if !reflect.DeepEqual(gotintarr, expected2) {
			t.Errorf("Expected: %v, Got: %v", expected2, gotintarr)
		}

		expected3 := []int{2, 3, 555, 7, 11}
		gotintarr = voxgigstruct.SetProp(intarr1, "2", 555).([]int)
		if !reflect.DeepEqual(gotintarr, expected3) {
			t.Errorf("Expected: %v, Got: %v", expected3, gotintarr)
		}
	})

	t.Run("minor-haskey", func(t *testing.T) {
		runset(t, minor["haskey"], voxgigstruct.HasKey)
	})

	t.Run("minor-keysof", func(t *testing.T) {
		runset(t, minor["keysof"], voxgigstruct.KeysOf)
	})

	t.Run("minor-joinurl", func(t *testing.T) {
		runsetFlags(t, minor["joinurl"], map[string]bool{"json_null": false}, voxgigstruct.JoinUrl)
	})

	// walk tests
	// ==========

	t.Run("walk-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Walk)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("walk should be a function, but got %s", fnVal.Kind().String())
		}
	})

	t.Run("walk-log", func(t *testing.T) {
		test := voxgigstruct.Clone(walk["log"]).(map[string]any)

		var log []any

		walklog := func(k *string, v any, p any, t []string) any {
			var ks string
			if nil == k {
				ks = ""
			} else {
				ks = *k
			}
			entry := "k=" + voxgigstruct.Stringify(ks) +
				", v=" + voxgigstruct.Stringify(v) +
				", p=" + voxgigstruct.Stringify(p) +
				", t=" + voxgigstruct.Pathify(t)
			log = append(log, entry)
			return v
		}

		voxgigstruct.Walk(test["in"], walklog)

		if !reflect.DeepEqual(log, test["out"]) {
			t.Errorf("log mismatch:\n got:  %v\n want: %v\n", log, test["out"])
		}
	})

	t.Run("walk-basic", func(t *testing.T) {
		walkpath := func(k *string, val any, parent any, path []string) any {
			if str, ok := val.(string); ok {
				return str + "~" + strings.Join(path, ".")
			}
			return val
		}

		runset(t, walk["basic"], func(v any) any {
			if "__NULL__" == v {
				v = nil
			}
			return voxgigstruct.Walk(v, walkpath)
		})
	})

	// merge tests
	// ===========

	t.Run("merge-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Merge)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("merge should be a function, but got %s", fnVal.Kind().String())
		}
	})

	t.Run("merge-basic", func(t *testing.T) {
		test := merge["basic"].(map[string]any)
		inVal := test["in"]
		outVal := test["out"]
		result := voxgigstruct.Merge(inVal)
		if !reflect.DeepEqual(result, outVal) {
			t.Errorf("Expected: %v, Got: %v", outVal, result)
		}
	})

	t.Run("merge-cases", func(t *testing.T) {
		runset(t, merge["cases"], voxgigstruct.Merge)
	})

	t.Run("merge-array", func(t *testing.T) {
		runset(t, merge["array"], voxgigstruct.Merge)
	})

	// getpath tests
	// =============

	t.Run("getpath-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.GetPath)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("getpath should be a function, but got %s", fnVal.Kind().String())
		}
	})

	t.Run("getpath-basic", func(t *testing.T) {
		runset(t, getpath["basic"], func(v any) any {
			m := v.(map[string]any)
			path := m["path"]
			store := m["store"]

			return voxgigstruct.GetPath(path, store)
		})
	})

	t.Run("getpath-current", func(t *testing.T) {
		runset(t, getpath["current"], func(v any) any {
			m := v.(map[string]any)
			path := m["path"]
			store := m["store"]
			current := m["current"]
			return voxgigstruct.GetPathState(path, store, current, nil)
		})
	})

	t.Run("getpath-state", func(t *testing.T) {
		state := &voxgigstruct.Injection{
			Handler: func(
				s *voxgigstruct.Injection,
				val any,
				cur any,
				ref *string,
				st any,
			) any {
				out := voxgigstruct.Stringify(s.Meta["step"]) + ":" + voxgigstruct.Stringify(val)
				s.Meta["step"] = 1 + s.Meta["step"].(int)
				return out
			},
			Mode:   "val",
			Full:   false,
			KeyI:   0,
			Keys:   []string{"$TOP"},
			Key:    "$TOP",
			Val:    "",
			Parent: nil,
			Path:   []string{"$TOP"},
			Nodes:  make([]any, 1),
			Base:   "$TOP",
			Errs:   voxgigstruct.ListRefCreate[any](),
			Meta:   map[string]any{"step": 0},
		}

		runset(t, getpath["state"], func(v any) any {
			m := v.(map[string]any)
			path := m["path"]
			store := m["store"]
			current := m["current"]

			return voxgigstruct.GetPathState(path, store, current, state)
		})
	})

	// inject tests
	// ============

	// inject-exists
	t.Run("inject-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Inject)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("inject should be a function, but got %s", fnVal.Kind().String())
		}
	})

	t.Run("inject-basic", func(t *testing.T) {
		subtest := inject["basic"].(map[string]any)
		inVal := subtest["in"].(map[string]any)
		val, store := inVal["val"], inVal["store"]
		outVal := subtest["out"]
		result := voxgigstruct.Inject(val, store)
		if !reflect.DeepEqual(result, outVal) {
			t.Errorf("Expected: %v, Got: %v", outVal, result)
		}
	})

	// inject-string
	t.Run("inject-string", func(t *testing.T) {
		runset(t, inject["string"], func(v any) any {
			m := v.(map[string]any)
			val := m["val"]
			store := m["store"]
			current := m["current"]

			return voxgigstruct.InjectDescend(val, store, nullModifier, current, nil)
		})
	})

	t.Run("inject-deep", func(t *testing.T) {
		runset(t, inject["deep"], func(v any) any {
			m := v.(map[string]any)
			val := m["val"]
			store := m["store"]
			return voxgigstruct.Inject(val, store)
		})
	})

	// transform tests
	// ===============

	t.Run("transform-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Transform)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("transform should be a function, but got %s", fnVal.Kind().String())
		}
	})

	t.Run("transform-basic", func(t *testing.T) {
		subtest := transform["basic"].(map[string]any)
		inVal := subtest["in"].(map[string]any)
		data := inVal["data"]
		spec := inVal["spec"]
		outVal := subtest["out"]
		result := voxgigstruct.Transform(data, spec)
		if !reflect.DeepEqual(result, outVal) {
			t.Errorf("Expected: %v, Got: %v", outVal, result)
		}
	})

	t.Run("transform-paths", func(t *testing.T) {
		runset(t, transform["paths"], func(v any) any {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})

	t.Run("transform-cmds", func(t *testing.T) {
		runset(t, transform["cmds"], func(v any) any {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})

	t.Run("transform-each", func(t *testing.T) {
		runset(t, transform["each"], func(v any) any {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})

	t.Run("transform-pack", func(t *testing.T) {
		runset(t, transform["pack"], func(v any) any {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})

	t.Run("transform-modify", func(t *testing.T) {
		runset(t, transform["modify"], func(v any) any {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.TransformModify(data, spec, nil, func(
				val any,
				key any,
				parent any,
				state *voxgigstruct.Injection,
				current any,
				store any,
			) {
				if key != nil && parent != nil {
					if strval, ok := val.(string); ok {
						newVal := "@" + strval
						if pm, isMap := parent.(map[string]any); isMap {
							pm[fmt.Sprint(key)] = newVal
						}
					}
				}
			})
		})
	})

	t.Run("transform-extra", func(t *testing.T) {
		data := map[string]any{"a": 1}
		spec := map[string]any{
			"x": "`a`",
			"b": "`$COPY`",
			"c": "`$UPPER`",
		}

		upper := voxgigstruct.Injector(func(
			s *voxgigstruct.Injection,
			val any,
			current any,
			ref *string,
			store any,
		) any {
			p := s.Path
			if len(p) == 0 {
				return ""
			}
			last := p[len(p)-1]
			// uppercase the last letter
			if len(last) > 0 {
				return string(last[0]-32) + last[1:]
			}

			return last
		})

		extra := map[string]any{
			"b":      2,
			"$UPPER": upper,
		}

		output := map[string]any{
			"x": 1,
			"b": 2,
			"c": "C",
		}

		result := voxgigstruct.TransformModify(data, spec, extra, nil)
		if !reflect.DeepEqual(result, output) {
			t.Errorf("Expected: %s, \nGot: %s \nExpected JSON: %s \nGot JSON: %s",
				fdt(output), fdt(result), toJSONString(output), toJSONString(result))
		}
	})

	// validate tests
	// ===============

	t.Run("validate-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Validate)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("validate should be a function, but got %s", fnVal.Kind().String())
		}
	})

	t.Run("validate-basic", func(t *testing.T) {
		runset(t, validate["basic"], func(v any) (any, error) {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Validate(data, spec)
			// out, err := voxgigstruct.Validate(data, spec)
			// if nil != err {
			//   t.Error(err)
			// }
			// return out
		})
	})

	t.Run("validate-node", func(t *testing.T) {
		runset(t, validate["node"], func(v any) (any, error) {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			out, err := voxgigstruct.Validate(data, spec)
			
			// Return both the output and error so the test framework can handle error checking
			return out, err
		})
	})

	t.Run("validate-custom", func(t *testing.T) {
		errs := voxgigstruct.ListRefCreate[any]() // make([]any,0)

		integerCheck := voxgigstruct.Injector(func(
			state *voxgigstruct.Injection,
			val any,
			current any,
			ref *string,
			store any,
		) any {
			out := voxgigstruct.GetProp(current, state.Key)
			switch x := out.(type) {
			case int:
				return x
			default:
				msg := fmt.Sprintf("Not an integer at %s: %v",
					voxgigstruct.Pathify(state.Path,1), out)
        state.Errs.Append(msg)
				return out
			}
		})

		extra := map[string]any{
			"$INTEGER": integerCheck,
		}

		schema := map[string]any{
			"a": "`$INTEGER`",
		}

		out, err := voxgigstruct.ValidateCollect(
			map[string]any{"a": 1},
			schema,
			extra,
			errs,
		)
		if nil != err {
			t.Error(err)
		}

		expected0 := map[string]any{"a": 1}
		if !reflect.DeepEqual(out, expected0) {
			t.Errorf("Expected: %v, Got: %v", expected0, out)
		}
		errs0 := []any{}
		if !reflect.DeepEqual(errs.List, errs0) {
			t.Errorf("Expected Error: %v, Got: %v", errs0, errs.List)
		}

		out, err = voxgigstruct.ValidateCollect(
			map[string]any{"a": "A"},
			schema,
			extra,
			errs,
		)
    
    // fmt.Println("QQQ", out, err)

    expectedErr := "Invalid data: Not an integer at a: A"
		if !reflect.DeepEqual(expectedErr, err.Error()) {
      t.Errorf("Expected: %v, Got: %v", expectedErr, err.Error())
		}
    
		expected1 := map[string]any{"a": "A"}
		if !reflect.DeepEqual(out, expected1) {
			t.Errorf("Expected: %v, Got: %v", expected1, out)
		}
		errs1 := []any{"Not an integer at a: A"}
		if !reflect.DeepEqual(errs.List, errs1) {
			t.Errorf("Expected Error: %v, Got: %v", errs1, errs.List)
		}

	})

}
