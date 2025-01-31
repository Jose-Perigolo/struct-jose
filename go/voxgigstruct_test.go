
// go test
// go test -v -run=TestStruct/foo

package voxgigstruct_test

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/voxgig/struct"
)

// We assume your TypeScript test file references a JSON file:
//
//	../../build/test/test.json
//
// Adjust the path to where your "test.json" actually resides.
func loadTestSpec(t *testing.T) map[string]interface{} {
	t.Helper()

	path := filepath.Join("..", "build", "test", "test.json")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("Cannot read test.json: %v", err)
	}

	// var testSpec map[string]interface{}
	var testSpec interface{}
	err = json.Unmarshal(data, &testSpec)
	if err != nil {
		t.Fatalf("Invalid JSON in test.json: %v", err)
	}

	testSpec = fixJSON(testSpec)

	testSpecMap, _ := testSpec.(map[string]interface{})
	
	return testSpecMap
}

// testEntry matches each item in the "set" array within test.json.
//
// Each test entry in TS looks like:
//
//	{
//	  in:  ...,
//	  out: ...,
//	  err: ...,
//	  thrown: ...
//	}
type testEntry struct {
	In     interface{} `json:"in"`
	Out    interface{} `json:"out"`
	Err    interface{} `json:"err"`
	Thrown string      `json:"thrown"`
}

// testSetBlock is the minimal structure we expect for { set: testEntry[] }
type testSetBlock struct {
	Set []testEntry `json:"set"`
}

// testSet replicates the TS logic:
//
//	for (let entry of tests.set) {
//	  try { deepEqual(apply(entry.in), entry.out) }
//	  catch(err) { ... }
//	}
func testSet(t *testing.T, block interface{}, apply func(interface{}) interface{}) {
	t.Helper()

	// Unmarshal block into our testSetBlock struct
	blk, ok := block.(map[string]interface{})
	if !ok {
		t.Fatalf("testSet expected map[string]interface{}, got %T", block)
	}

	var tsb testSetBlock
	bb, _ := json.Marshal(blk)
	_ = json.Unmarshal(bb, &tsb)

	for _, entry := range tsb.Set {
		func(e testEntry) {
			// We run each entry as a subtest for clarity.
			inStr, _ := json.Marshal(e.In)
			t.Run(fmt.Sprintf("in=%s", inStr), func(t *testing.T) {
				defer func() {
					// Catch panic if apply(...) panics
					if r := recover(); r != nil {
						errStr := fmt.Sprintf("%v", r)
						handleTestEntryError(t, &e, errStr)
					}
				}()

				// Call the function
				result := apply(e.In)
				fmt.Println("BBB-RES", formatDataWithTypes(result,""))
				fmt.Println("CCC-OUT", formatDataWithTypes(e.Out,""))
				
				// Compare with expected e.Out
				if !reflect.DeepEqual(result, e.Out) {
					// If there's an expected "err" text, or boolean "true"
					if e.Err != nil {
						errText, isString := e.Err.(string)
						if isString && strings.Contains(fmt.Sprint(result), errText) {
							// That counts as success
							return
						}
						if bVal, isBool := e.Err.(bool); isBool && bVal {
							// Also success
							return
						}
						// Otherwise, we record the mismatch
						e.Thrown = fmt.Sprintf("result=%v, want=%v", result, e.Out)
						t.Fatalf("test entry mismatch (with 'err' present): %v", e)
					} else {
						// No err expected => must match exactly
						t.Fatalf("\nGOT=%v\nWANT=%v", formatDataWithTypes(result,""), formatDataWithTypes(e.Out,""))
					}
				}
			})
		}(entry)
	}
}

// handleTestEntryError is used when a panic (or error-like string) occurs
// so we can mimic the TS logic that checks `entry.err`.
func handleTestEntryError(t *testing.T, entry *testEntry, errStr string) {
	if entry.Err != nil {
		// If "true === entry_err" or (err.message.includes(entry_err))
		if bVal, ok := entry.Err.(bool); ok && bVal {
			// accepted
			return
		}
		if sVal, ok := entry.Err.(string); ok {
			if strings.Contains(errStr, sVal) {
				// accepted
				return
			}
		}
		entry.Thrown = errStr
		t.Fatalf("unexpected error/panic: %v", entry)
	} else {
		panic(errStr)
	}
}




func formatDataWithTypes(data interface{}, indent string) string {
	result := ""

	switch v := data.(type) {
	case map[string]interface{}:
		result += indent + "{\n"
		for key, value := range v {
			result += fmt.Sprintf("%s  \"%s\": %s", indent, key, formatDataWithTypes(value, indent+"  "))
		}
		result += indent + "}\n"

	case []interface{}:
		result += indent + "[\n"
		for _, value := range v {
			result += fmt.Sprintf("%s  - %s", indent, formatDataWithTypes(value, indent+"  "))
		}
		result += indent + "]\n"

	default:
		// Format value with its type
		result += fmt.Sprintf("%v (%s)\n", v, reflect.TypeOf(v))
	}

	return result
}


func fixJSON(data any) any {
	switch v := data.(type) {
	case map[string]interface{}:
		// Recursively process each key-value pair in a map
		for key, value := range v {
			v[key] = fixJSON(value)
		}
		return v

	case []interface{}:
		// Recursively process each element in a slice
		for i, value := range v {
			v[i] = fixJSON(value)
		}
		return v

	case float64:
		// Convert float64 to int if it has no decimal part
		if v == float64(int(v)) {
			return int(v)
		}
		return v

	default:
		// Return the value unchanged if it's not a float64
		return v
	}
}

// walkPath replicates the TS function:
//
//	function walkpath(_key, val, _parent, path) {
//	  return ('string' === typeof val) ? val + '~' + path.join('.') : val
//	}
func walkPath(key *string, val interface{}, parent interface{}, path []string) interface{} {
	str, isString := val.(string)
	if isString {
		return str + "~" + strings.Join(path, ".")
	}
	return val
}

// Now we define the actual test functions, mirroring your TS `describe(...) / test(...)` blocks.

func TestStruct(t *testing.T) {
	testSpec := loadTestSpec(t)

	// The TS code: describe('struct', () => { ... })

	// "minor" tests use testSpec["minor"], which should be a map with sub-blocks.
	minor, ok := testSpec["minor"].(map[string]interface{})
	if !ok {
		t.Fatal("testSpec.minor is missing or not an object")
	}

	// ~~~~~~~~~~~~~ "minor-exists" ~~~~~~~~~~~~~
	// In TS: test('minor-exists', () => { equal('function', typeof clone) ... })
	// In Go, we just confirm the symbols exist by calling them once.
	t.Run("minor-exists", func(t *testing.T) {
		// if voxgigstruct.Clone == nil ||
		//   voxgigstruct.EscRe == nil ||
		//   voxgigstruct.EscUrl == nil ||
		//   voxgigstruct.GetProp == nil ||
		//   voxgigstruct.IsEmpty == nil ||
		//   voxgigstruct.IsKey == nil ||
		//   voxgigstruct.IsList == nil ||
		//   voxgigstruct.IsMap == nil ||
		//   voxgigstruct.IsNode == nil ||
		//   voxgigstruct.Items == nil ||
		//   voxgigstruct.SetProp == nil ||
		//   voxgigstruct.Stringify == nil {
		//   t.Fatal("One or more functions are nil!")
		// }
	})

	// ~~~~~~~~~~~~~ "minor-clone" ~~~~~~~~~~~~~
	t.Run("minor-clone", func(t *testing.T) {
		data := minor["clone"]
		testSet(t, data, func(in interface{}) interface{} {
			return voxgigstruct.Clone(in)
		})
	})

	t.Run("minor-isnode", func(t *testing.T) {
		data := minor["isnode"]
		testSet(t, data, func(in interface{}) interface{} {
			return voxgigstruct.IsNode(in)
		})
	})

	t.Run("minor-ismap", func(t *testing.T) {
		data := minor["ismap"]
		testSet(t, data, func(in interface{}) interface{} {
			return voxgigstruct.IsMap(in)
		})
	})

	t.Run("minor-islist", func(t *testing.T) {
		data := minor["islist"]
		testSet(t, data, func(in interface{}) interface{} {
			return voxgigstruct.IsList(in)
		})
	})

	t.Run("minor-iskey", func(t *testing.T) {
		data := minor["iskey"]
		testSet(t, data, func(in interface{}) interface{} {
			return voxgigstruct.IsKey(in)
		})
	})

	t.Run("minor-isempty", func(t *testing.T) {
		data := minor["isempty"]
		testSet(t, data, func(in interface{}) interface{} {
			return voxgigstruct.IsEmpty(in)
		})
	})

	t.Run("minor-escre", func(t *testing.T) {
		data := minor["escre"]
		testSet(t, data, func(in interface{}) interface{} {
			return voxgigstruct.EscRe(fmt.Sprint(in))
		})
	})

	t.Run("minor-escurl", func(t *testing.T) {
		data := minor["escurl"]
		testSet(t, data, func(in interface{}) interface{} {
			return strings.ReplaceAll(voxgigstruct.EscUrl(fmt.Sprint(in)), "+", "%20")
		})
	})

	t.Run("minor-stringify", func(t *testing.T) {
		data := minor["stringify"]
		testSet(t, data, func(vin interface{}) interface{} {
			// Based on TS code:
			// test_set(clone(TESTSPEC.minor.stringify), (vin: any) =>
			//   null == vin.max ? stringify(vin.val) : stringify(vin.val, vin.max))

			// We expect vin to be an object { val: ..., max: ... }
			vm, _ := vin.(map[string]interface{})
			val := vm["val"]
			max, hasMax := vm["max"]

			if !hasMax || max == nil {
				return voxgigstruct.Stringify(val)
			}
			// max is presumably a float64 => cast to int
			return voxgigstruct.Stringify(val, int(max.(float64)))
		})
	})

	t.Run("minor-items", func(t *testing.T) {
		data := minor["items"]

		testSet(t, data, func(in interface{}) interface{} {
			fmt.Println("AAA-IN", formatDataWithTypes(in,""))
			return voxgigstruct.Items(in)
		})
	})

	t.Run("minor-getprop", func(t *testing.T) {
		data := minor["getprop"]
		testSet(t, data, func(vin interface{}) interface{} {
			vm, _ := vin.(map[string]interface{})
			val := vm["val"]
			key := vm["key"]
			alt := vm["alt"]
			if alt == nil {
				return voxgigstruct.GetProp(val, key)
			}
			return voxgigstruct.GetProp(val, key, alt)
		})
	})

	t.Run("minor-setprop", func(t *testing.T) {
		data := minor["setprop"]
		testSet(t, data, func(vin interface{}) interface{} {
			vm, _ := vin.(map[string]interface{})
			parent := vm["parent"]
			key := vm["key"]
			val := vm["val"]

			// SetProp mutates the parent, so for the TS "clone" approach, we want
			// a local copy. We'll do a JSON clone to avoid partial mutation.
			parentCopy := voxgigstruct.Clone(parent)

			out := voxgigstruct.SetProp(parentCopy, key, val)
			// Return the entire parent structure so we can compare
			return out
		})
	})

	// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	// walk tests
	walkData, _ := testSpec["walk"].(map[string]interface{})
	if walkData == nil {
		t.Error("No 'walk' section in test.json")
	} else {
		t.Run("walk-exists", func(t *testing.T) {
			// In TS: test('walk-exists', () => { equal('function', typeof merge) })
			// We'll just check merge != nil
			// if voxgigstruct.Merge == nil {
			// 	t.Fatal("voxgigstruct.Merge is nil")
			// }
		})

		t.Run("walk-basic", func(t *testing.T) {
			data := walkData["basic"]
			testSet(t, data, func(in interface{}) interface{} {
				// TS: test_set(..., (vin:any) => walk(vin, walkpath))
				// We'll define a local function that calls your walk function:
				return voxgigstruct.Walk(in, walkPath, nil, nil, nil)
			})
		})
	}

	// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	// merge tests
	mergeData, _ := testSpec["merge"].(map[string]interface{})
	if mergeData == nil {
		t.Error("No 'merge' section in test.json")
	} else {
		t.Run("merge-exists", func(t *testing.T) {
			// if voxgigstruct.Merge == nil {
			// 	t.Fatal("voxgigstruct.Merge is nil")
			// }
		})

		t.Run("merge-basic", func(t *testing.T) {
			testBlock := mergeData["basic"]
			vm, ok := testBlock.(map[string]interface{})
			if !ok {
				t.Fatal("merge.basic is not an object")
			}
			inVal := vm["in"]
			outVal := vm["out"]

			// Do the merge
			got := voxgigstruct.Merge(inVal.([]interface{}))
			if !reflect.DeepEqual(got, outVal) {
				t.Errorf("merge-basic: got %#v, want %#v", got, outVal)
			}
		})

		t.Run("merge-cases", func(t *testing.T) {
			data := mergeData["cases"]
			testSet(t, data, func(in interface{}) interface{} {
				// The TS code does: merge(in)
				// Typically `in` is an array of objects
				// but to be safe, do a type-check
				arr, _ := in.([]interface{})
				return voxgigstruct.Merge(arr)
			})
		})

		t.Run("merge-array", func(t *testing.T) {
			data := mergeData["array"]
			testSet(t, data, func(in interface{}) interface{} {
				arr, _ := in.([]interface{})
				return voxgigstruct.Merge(arr)
			})
		})
	}

	// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	// getpath tests
	getpathData, _ := testSpec["getpath"].(map[string]interface{})
	if getpathData == nil {
		t.Error("No 'getpath' section in test.json")
	} else {
		t.Run("getpath-exists", func(t *testing.T) {
			// if voxgigstruct.GetPath == nil {
			// 	t.Fatal("voxgigstruct.GetPath is nil")
			// }
		})

		t.Run("getpath-basic", func(t *testing.T) {
			data := getpathData["basic"]
			testSet(t, data, func(in interface{}) interface{} {
				vm, _ := in.(map[string]interface{})
				path := vm["path"]
				store := vm["store"]
				return voxgigstruct.GetPath(path, store, nil, nil)
			})
		})

		t.Run("getpath-current", func(t *testing.T) {
			data := getpathData["current"]
			testSet(t, data, func(in interface{}) interface{} {
				vm, _ := in.(map[string]interface{})
				path := vm["path"]
				store := vm["store"]
				cur := vm["current"]
				return voxgigstruct.GetPath(path, store, cur, nil)
			})
		})

		t.Run("getpath-state", func(t *testing.T) {
			data := getpathData["state"]
			testSet(t, data, func(in interface{}) interface{} {
				// Create a custom state that increments step each time
				state := &voxgigstruct.InjectState{
					Handler: func(st *voxgigstruct.InjectState, val interface{}, _cur interface{}, _store interface{}) interface{} {
						// TS code: let out = state.step + ':' + val; state.step++
						// return out
						// stepI := st.Mode // we'll store step in st.Val or something
						// but the TS code does `state.step++`
						// We'll keep an integer in st.KeyI or something:
						out := fmt.Sprintf("%d:%v", st.KeyI, val)
						st.KeyI++
						return out
					},
					Mode:   voxgigstruct.InjectModeVal,
					Full:   false,
					KeyI:   0,
					Keys:   []string{"$TOP"},
					Key:    "$TOP",
					Val:    "",
					Parent: map[string]interface{}{},
					Path:   []string{"$TOP"},
					Nodes:  []interface{}{map[string]interface{}{}},
					Base:   "$TOP",
				}

				vm, _ := in.(map[string]interface{})
				path := vm["path"]
				store := vm["store"]
				cur := vm["current"]
				return voxgigstruct.GetPath(path, store, cur, state)
			})
		})
	}

	// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	// inject tests
	injectData, _ := testSpec["inject"].(map[string]interface{})
	if injectData == nil {
		t.Error("No 'inject' section in test.json")
	} else {
		t.Run("inject-exists", func(t *testing.T) {
			// if voxgigstruct.Inject == nil {
			// 	t.Fatal("voxgigstruct.Inject is nil")
			// }
		})

		t.Run("inject-basic", func(t *testing.T) {
			testBlk := injectData["basic"]
			vm, _ := testBlk.(map[string]interface{})
			inVal := vm["in"].(map[string]interface{})
			valVal := inVal["val"]
			storeVal := inVal["store"]
			outVal := vm["out"]

			got := voxgigstruct.Inject(valVal, storeVal, nil, nil, nil)
			if !reflect.DeepEqual(got, outVal) {
				t.Errorf("inject-basic mismatch:\n got=%v\nout=%v\n", got, outVal)
			}
		})

		t.Run("inject-string", func(t *testing.T) {
			data := injectData["string"]
			testSet(t, data, func(in interface{}) interface{} {
				vm, _ := in.(map[string]interface{})
				val := vm["val"]
				store := vm["store"]
				// TS: inject(vin.val, vin.store, vin.current)
				// The signature in Go is: Inject(val, store, modify, current, state)
				cur := vm["current"]
				return voxgigstruct.Inject(val, store, nil, cur, nil)
			})
		})

		t.Run("inject-deep", func(t *testing.T) {
			data := injectData["deep"]
			testSet(t, data, func(in interface{}) interface{} {
				vm, _ := in.(map[string]interface{})
				val := vm["val"]
				store := vm["store"]
				return voxgigstruct.Inject(val, store, nil, nil, nil)
			})
		})
	}

	// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
	// transform tests
	transformData, _ := testSpec["transform"].(map[string]interface{})
	if transformData == nil {
		t.Error("No 'transform' section in test.json")
	} else {
		t.Run("transform-exists", func(t *testing.T) {
			// if voxgigstruct.Transform == nil {
			// 	t.Fatal("voxgigstruct.Transform is nil")
			// }
		})

		t.Run("transform-basic", func(t *testing.T) {
			dat := transformData["basic"]
			vm, _ := dat.(map[string]interface{})
			inVal := vm["in"].(map[string]interface{})
			dataVal := inVal["data"]
			specVal := inVal["spec"]
			storeVal := inVal["store"]
			outVal := vm["out"]
			got := voxgigstruct.Transform(dataVal, specVal, storeVal, nil)
			if !reflect.DeepEqual(got, outVal) {
				t.Errorf("transform-basic mismatch:\n got=%v\nout=%v\n", got, outVal)
			}
		})

		t.Run("transform-paths", func(t *testing.T) {
			data := transformData["paths"]
			testSet(t, data, func(in interface{}) interface{} {
				vm, _ := in.(map[string]interface{})
				dat := vm["data"]
				spec := vm["spec"]
				str := vm["store"]
				return voxgigstruct.Transform(dat, spec, str, nil)
			})
		})

		t.Run("transform-cmds", func(t *testing.T) {
			data := transformData["cmds"]
			testSet(t, data, func(in interface{}) interface{} {
				vm, _ := in.(map[string]interface{})
				dat := vm["data"]
				spec := vm["spec"]
				str := vm["store"]
				return voxgigstruct.Transform(dat, spec, str, nil)
			})
		})

		t.Run("transform-each", func(t *testing.T) {
			data := transformData["each"]
			testSet(t, data, func(in interface{}) interface{} {
				vm, _ := in.(map[string]interface{})
				dat := vm["data"]
				spec := vm["spec"]
				str := vm["store"]
				return voxgigstruct.Transform(dat, spec, str, nil)
			})
		})

		t.Run("transform-pack", func(t *testing.T) {
			data := transformData["pack"]
			testSet(t, data, func(in interface{}) interface{} {
				vm, _ := in.(map[string]interface{})
				dat := vm["data"]
				spec := vm["spec"]
				str := vm["store"]
				return voxgigstruct.Transform(dat, spec, str, nil)
			})
		})

		t.Run("transform-modify", func(t *testing.T) {
			data := transformData["modify"]
			testSet(t, data, func(in interface{}) interface{} {
				vm, _ := in.(map[string]interface{})
				dat := vm["data"]
				spec := vm["spec"]
				str := vm["store"]
				return voxgigstruct.Transform(dat, spec, str,
					func(key interface{}, val interface{}, parent interface{},
						state *voxgigstruct.InjectState, current interface{}, store interface{}) {
						// TS code snippet:
						// (key: any, val: any, parent: any) => {
						//    if (null != key && null != parent && 'string' === typeof val) {
						//      val = parent[key] = '@' + val
						//    }
						// }
						if key != nil && parent != nil {
							if s, isStr := val.(string); isStr {
								voxgigstruct.SetProp(parent, key, "@"+s)
							}
						}
					})
			})
		})

		t.Run("transform-extra", func(t *testing.T) {
			// TS code:
			// deepEqual(transform({ a: 1 }, { x: '`a`', b: '`$COPY`', c: '`$UPPER`' },
			// {
			//   b: 2, $UPPER: (state: any) => {
			//     ...
			//   }
			// }), { x: 1, b: 2, c: 'C' })
			got := voxgigstruct.Transform(
				map[string]interface{}{"a": 1},
				map[string]interface{}{
					"x": "`a`",
					"b": "`$COPY`",
					"c": "`$UPPER`",
				},
				map[string]interface{}{
					"b": 2,
					"$UPPER": func(st *voxgigstruct.InjectState, val interface{}, cur interface{}, store interface{}) interface{} {
						// replicate TS: return (''+getprop(path, path.length-1)).toUpperCase()
						// We'll do st.Path's last element => uppercase
						if len(st.Path) > 0 {
							last := st.Path[len(st.Path)-1]
							return strings.ToUpper(last)
						}
						return val
					},
				},
				nil,
			)
			want := map[string]interface{}{
				"x": float64(1), // note: 1 in JSON => float64 in Go
				"b": float64(2),
				"c": "C",
			}
			if !reflect.DeepEqual(got, want) {
				t.Errorf("transform-extra mismatch:\n got=%#v\nwant=%#v", got, want)
			}
		})
	}
}
