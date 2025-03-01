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
	In     interface{} `json:"in,omitempty"`
	Out    interface{} `json:"out,omitempty"`
	Err    interface{} `json:"err,omitempty"`
	Thrown interface{} `json:"thrown,omitempty"`
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
func fixJSON(data interface{}) interface{} {
	return fixJSONFlags(data, map[string]bool{
		"null": true,
	})
}

func fixJSONFlags(data interface{}, flags map[string]bool) interface{} {
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
		fixedMap := make(map[string]interface{})
		for _, key := range v.MapKeys() {
			strKey, ok := key.Interface().(string)
			if ok {
				fixedMap[strKey] = fixJSONFlags(v.MapIndex(key).Interface(), flags)
			}
		}
		return fixedMap

	case reflect.Slice:
		length := v.Len()
		fixedSlice := make([]interface{}, length)
		for i := 0; i < length; i++ {
			fixedSlice[i] = fixJSONFlags(v.Index(i).Interface(), flags)
		}
		return fixedSlice

	case reflect.Array:
		length := v.Len()
		fixedSlice := make([]interface{}, length)
		for i := 0; i < length; i++ {
			fixedSlice[i] = fixJSONFlags(v.Index(i).Interface(), flags)
		}
		return fixedSlice

	default:
		return data
	}
}

func nullModifier(
	key interface{},
	val interface{},
	parent interface{},
	state *voxgigstruct.Injection,
	current interface{},
	store interface{},
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

func toJSONString(data interface{}) string {
	jsonBytes, err := json.Marshal(data)
	if err != nil {
		return "" // Return empty string if marshalling fails
	}
	return string(jsonBytes)
}

// RunTestSet executes a set of test entries by calling 'apply'
// on each "in" value and comparing to "out".
// If a mismatch occurs, the test fails.

func runTestSet(t *testing.T, tests SubTest, apply func(interface{}) interface{}) {
	runTestSetFlags(t, tests, apply, map[string]bool{
		"null": true,
	})
}

func runTestSetFlags(t *testing.T, tests SubTest, apply func(interface{}) interface{}, flags map[string]bool) {
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

// walkPath mimics the TS function walkpath,
// appending path info to any string values.
func walkPath(k *string, val interface{}, parent interface{}, path []string) interface{} {
	if str, ok := val.(string); ok {
		return str + "~" + strings.Join(path, ".") // fmt.Sprint(path)
	}
	return val
}



type TestProvider struct{}

func (p *TestProvider) Test(opts map[string]interface{}) (runner.Client, error) {
	return &testClient{}, nil
}

type testClient struct{}

func (c *testClient) Utility() (runner.Utility) {
  return &testUtility{}
}

type testUtility struct{}

func (c *testUtility) Struct() *runner.StructUtility {
  return &runner.StructUtility{
    Clone: voxgigstruct.Clone,
    GetPath: voxgigstruct.GetPath,
    Inject: voxgigstruct.Inject,
    Items: voxgigstruct.Items,
    Stringify: voxgigstruct.Stringify,
    Walk: voxgigstruct.Walk,
  }
}




// TestStructFunctions runs the entire suite of tests
// replicating the original TS test logic.
func TestStruct(t *testing.T) {

  store := make(map[string]interface{})
  provider := &TestProvider{}
  runner, err := runner.Runner("struct", store, "../build/test/test.json", provider)
	if err != nil {
		t.Fatalf("Failed to create runner: %v", err)
	}

  fmt.Printf("RUNNER: %+v\n", runner)
  
	// Adjust path to your JSON test file.
	testSpec, err := LoadTestSpec("../build/test/test.json")
	if err != nil {
		t.Fatalf("Failed to load test spec: %v", err)
	}

	// =========================
	// minor tests
	// =========================

	// minor-exists
	t.Run("minor-exists", func(t *testing.T) {
		// In TS, we tested typeof clone, etc.
		// Here, we approximate by ensuring the library provides them.
		checks := map[string]interface{}{
			"clone":     voxgigstruct.Clone,
			"escre":     voxgigstruct.EscRe,
			"escurl":    voxgigstruct.EscUrl,
			"getprop":   voxgigstruct.GetProp,
			"isempty":   voxgigstruct.IsEmpty,
			"iskey":     voxgigstruct.IsKey,
			"islist":    voxgigstruct.IsList,
			"ismap":     voxgigstruct.IsMap,
			"isnode":    voxgigstruct.IsNode,
			"items":     voxgigstruct.Items,
			"setprop":   voxgigstruct.SetProp,
			"stringify": voxgigstruct.Stringify,
		}
		for name, fn := range checks {
			if fnVal := reflect.ValueOf(fn); fnVal.Kind() != reflect.Func {
				t.Errorf("%s should be a function, but got %s", name, fnVal.Kind().String())
			}
		}
	})

	// minor-clone
	t.Run("minor-clone", func(t *testing.T) {
		subtest := testSpec["minor"]["clone"]
		runTestSet(t, subtest, func(v interface{}) interface{} {
			return voxgigstruct.Clone(v)
		})
	})

	// minor-isnode
	t.Run("minor-isnode", func(t *testing.T) {
		subtest := testSpec["minor"]["isnode"]
		runTestSet(t, subtest, func(v interface{}) interface{} {
			return voxgigstruct.IsNode(v)
		})
	})

	// minor-ismap
	t.Run("minor-ismap", func(t *testing.T) {
		subtest := testSpec["minor"]["ismap"]
		runTestSet(t, subtest, func(v interface{}) interface{} {
			return voxgigstruct.IsMap(v)
		})
	})

	// minor-islist
	t.Run("minor-islist", func(t *testing.T) {
		subtest := testSpec["minor"]["islist"]
		runTestSet(t, subtest, func(v interface{}) interface{} {
			return voxgigstruct.IsList(v)
		})
	})

	// minor-iskey
	t.Run("minor-iskey", func(t *testing.T) {
		subtest := testSpec["minor"]["iskey"]
		runTestSet(t, subtest, func(v interface{}) interface{} {
			return voxgigstruct.IsKey(v)
		})
	})

	// minor-isempty
	t.Run("minor-isempty", func(t *testing.T) {
		subtest := testSpec["minor"]["isempty"]
		runTestSet(t, subtest, func(v interface{}) interface{} {
			if "__NULL__" == v {
				return voxgigstruct.IsEmpty(nil)
			}
			return voxgigstruct.IsEmpty(v)
		})
	})

	// minor-escre
	t.Run("minor-escre", func(t *testing.T) {
		subtest := testSpec["minor"]["escre"]
		runTestSet(t, subtest, func(in interface{}) interface{} {
			return voxgigstruct.EscRe(fmt.Sprint(in))
		})
	})

	// minor-escurl
	t.Run("minor-escurl", func(t *testing.T) {
		subtest := testSpec["minor"]["escurl"]
		runTestSet(t, subtest, func(in interface{}) interface{} {
			return strings.ReplaceAll(voxgigstruct.EscUrl(fmt.Sprint(in)), "+", "%20")
		})
	})

	// minor-stringify
	t.Run("minor-stringify", func(t *testing.T) {
		subtest := testSpec["minor"]["stringify"]
		runTestSet(t, subtest, func(v interface{}) interface{} {
			// The TS code used: null == vin.max ? stringify(vin.val) : stringify(vin.val, vin.max)
			// We'll do similarly in Go.
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			val := m["val"]
			max, hasMax := m["max"]
			if !hasMax || max == nil {
				return voxgigstruct.Stringify(val)
			} else {
				return voxgigstruct.Stringify(val, int(max.(int)))
			}
		})
	})

	// minor-items
	t.Run("minor-items", func(t *testing.T) {
		subtest := testSpec["minor"]["items"]
		runTestSet(t, subtest, func(v interface{}) interface{} {
			return voxgigstruct.Items(v)
		})
	})

	// minor-getprop
	t.Run("minor-getprop", func(t *testing.T) {
		subtest := testSpec["minor"]["getprop"]
		runTestSet(t, subtest, func(v interface{}) interface{} {
			// The TS code used: null == vin.alt ? getprop(vin.val, vin.key) : getprop(vin.val, vin.key, vin.alt)
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			store := m["val"]
			key := m["key"]
			alt, hasAlt := m["alt"]
			if !hasAlt || alt == nil {
				return voxgigstruct.GetProp(store, key)
			}
			return voxgigstruct.GetProp(store, key, alt)
		})
	})

	// minor-setprop
	t.Run("minor-setprop", func(t *testing.T) {
		subtest := testSpec["minor"]["setprop"]
		runTestSet(t, subtest, func(v interface{}) interface{} {
			// The TS code used: setprop(vin.parent, vin.key, vin.val)
			// We'll do similarly.
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			parent := m["parent"]
			key := m["key"]
			val := m["val"]
			return voxgigstruct.SetProp(parent, key, val)
		})
	})

	// =========================
	// walk tests
	// =========================

	// walk-exists
	t.Run("walk-exists", func(t *testing.T) {
		// Just check that walk is a function in voxgigstruct.
		fnVal := reflect.ValueOf(voxgigstruct.Walk)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("walk should be a function, but got %s", fnVal.Kind().String())
		}
	})

	// walk-basic
	t.Run("walk-basic", func(t *testing.T) {
		subtest := testSpec["walk"]["basic"]
		runTestSet(t, subtest, func(v interface{}) interface{} {
			if "__NULL__" == v {
				v = nil
			}
			return voxgigstruct.Walk(v, walkPath, nil, nil, nil)
		})
	})

	// =========================
	// merge tests
	// =========================

	// merge-exists
	t.Run("merge-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Merge)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("merge should be a function, but got %s", fnVal.Kind().String())
		}
	})

	// merge-basic
	t.Run("merge-basic", func(t *testing.T) {
		test := testSpec["merge"]["basic"]
		// The TS code calls merge(test.in) -> deepEqual(...) with test.out.
		// We can do a single check because it's not a set, it's one.
		inVal := test.In
		outVal := test.Out
		result := voxgigstruct.Merge(inVal)
		if !reflect.DeepEqual(result, outVal) {
			t.Errorf("Expected: %v, Got: %v", outVal, result)
		}
	})

	// merge-cases, merge-array
	t.Run("merge-cases", func(t *testing.T) {
		runTestSet(t, testSpec["merge"]["cases"], func(in interface{}) interface{} {
			return voxgigstruct.Merge(in)
		})
	})

	t.Run("merge-array", func(t *testing.T) {
		runTestSet(t, testSpec["merge"]["array"], func(in interface{}) interface{} {
			return voxgigstruct.Merge(in)
		})
	})

	// =========================
	// getpath tests
	// =========================

	// getpath-exists
	t.Run("getpath-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.GetPath)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("getpath should be a function, but got %s", fnVal.Kind().String())
		}
	})

	// getpath-basic
	t.Run("getpath-basic", func(t *testing.T) {
		runTestSet(t, testSpec["getpath"]["basic"], func(v interface{}) interface{} {
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			path := m["path"]
			store := m["store"]

			return voxgigstruct.GetPath(path, store)
		})
	})

	// getpath-current
	t.Run("getpath-current", func(t *testing.T) {
		runTestSet(t, testSpec["getpath"]["current"], func(v interface{}) interface{} {
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			path := m["path"]
			store := m["store"]
			current := m["current"]
			return voxgigstruct.GetPathState(path, store, current, nil)
		})
	})

	// getpath-state
	t.Run("getpath-state", func(t *testing.T) {
		step := 0

		runTestSet(t, testSpec["getpath"]["state"], func(v interface{}) interface{} {
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			path := m["path"]
			store := m["store"]
			current := m["current"]

			// We'll define a custom state in Go.
			state := &voxgigstruct.Injection{
				Handler: func(s *voxgigstruct.Injection, val interface{}, cur interface{}, st interface{}) interface{} {
					// out := fmt.Sprintf("%d:%v", s.Step, val)
					// s.Step++
					out := fmt.Sprintf("%d:%v", step, val)
					step++
					return out
				},
				// Step:   0,
				Mode:   "val",
				Full:   false,
				KeyI:   0,
				Keys:   []string{"$TOP"},
				Key:    "$TOP",
				Val:    "",
				Parent: nil,
				Path:   []string{"$TOP"},
				Nodes:  make([]interface{}, 1),
				Base:   "$TOP",
			}

			return voxgigstruct.GetPathState(path, store, current, state)
		})
	})

	// =========================
	// inject tests
	// =========================

	// inject-exists
	t.Run("inject-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Inject)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("inject should be a function, but got %s", fnVal.Kind().String())
		}
	})

	// inject-basic
	t.Run("inject-basic", func(t *testing.T) {
		subtest := testSpec["inject"]["basic"]
		// TS code: deepEqual(inject(test.in.val, test.in.store), test.out)
		inVal := subtest.In.(map[string]interface{})
		val, store := inVal["val"], inVal["store"]
		outVal := subtest.Out
		result := voxgigstruct.Inject(val, store)
		if !reflect.DeepEqual(result, outVal) {
			t.Errorf("Expected: %v, Got: %v", outVal, result)
		}
	})

	// inject-string
	t.Run("inject-string", func(t *testing.T) {
		runTestSet(t, testSpec["inject"]["string"], func(v interface{}) interface{} {
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			val := m["val"]
			store := m["store"]
			current := m["current"]

			return voxgigstruct.InjectState(val, store, nullModifier, current, nil)
		})
	})

	// inject-deep
	t.Run("inject-deep", func(t *testing.T) {
		runTestSet(t, testSpec["inject"]["deep"], func(v interface{}) interface{} {
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			val := m["val"]
			store := m["store"]
			return voxgigstruct.Inject(val, store)
		})
	})

	// =========================
	// transform tests
	// =========================

	// transform-exists
	t.Run("transform-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Transform)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("transform should be a function, but got %s", fnVal.Kind().String())
		}
	})

	// transform-basic
	t.Run("transform-basic", func(t *testing.T) {
		subtest := testSpec["transform"]["basic"]
		inVal := subtest.In.(map[string]interface{})
		data := inVal["data"]
		spec := inVal["spec"]
		outVal := subtest.Out
		result := voxgigstruct.Transform(data, spec)
		if !reflect.DeepEqual(result, outVal) {
			t.Errorf("Expected: %v, Got: %v", outVal, result)
		}
	})

	// transform-paths
	t.Run("transform-paths", func(t *testing.T) {
		runTestSet(t, testSpec["transform"]["paths"], func(v interface{}) interface{} {
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})

	// transform-cmds
	t.Run("transform-cmds", func(t *testing.T) {
		runTestSet(t, testSpec["transform"]["cmds"], func(v interface{}) interface{} {
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})

	// transform-each
	t.Run("transform-each", func(t *testing.T) {
		runTestSet(t, testSpec["transform"]["each"], func(v interface{}) interface{} {
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})

	// transform-pack
	t.Run("transform-pack", func(t *testing.T) {
		runTestSet(t, testSpec["transform"]["pack"], func(v interface{}) interface{} {
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})

	// transform-modify
	t.Run("transform-modify", func(t *testing.T) {
		runTestSet(t, testSpec["transform"]["modify"], func(v interface{}) interface{} {
			m, ok := v.(map[string]interface{})
			if !ok {
				return nil
			}
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.TransformModify(data, spec, nil, func(
				key interface{},
				val interface{},
				parent interface{},
				state *voxgigstruct.Injection,
				current interface{},
				store interface{},
			) {
				if key != nil && parent != nil {
					if strval, ok := val.(string); ok {
						// mimic the TS logic: val = parent[key] = '@' + val
						newVal := "@" + strval
						// In Go, we need reflection or map/array checks to assign.
						// We'll assume the parent is a map, keyed by 'key'.
						if pm, isMap := parent.(map[string]interface{}); isMap {
							pm[fmt.Sprint(key)] = newVal
						}
					}
				}
			})
		})
	})

	// transform-extra
	t.Run("transform-extra", func(t *testing.T) {
		data := map[string]interface{}{"a": 1}
		spec := map[string]interface{}{
			"x": "`a`",
			"b": "`$COPY`",
			"c": "`$UPPER`",
		}

		upper := voxgigstruct.InjectHandler(func(
			s *voxgigstruct.Injection,
			val interface{},
			current interface{},
			store interface{},
		) interface{} {
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

		extra := map[string]interface{}{
			"b":      2,
			"$UPPER": upper,
		}

		output := map[string]interface{}{
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
}
