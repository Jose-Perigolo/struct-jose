package runner

import (
	"fmt"

	"github.com/voxgig/struct"

	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"strings"
	"testing"
)

type Provider interface {
	Test(opts map[string]interface{}) (Client, error)
}

type Client interface {
	Utility() Utility
}

type Utility interface {
	Struct() *StructUtility
}

type StructUtility struct {
	Clone      func(val interface{}) interface{}
	CloneFlags func(val interface{}, flags map[string]bool) interface{}
	GetPath    func(path interface{}, store interface{}) interface{}
	Inject     func(val interface{}, store interface{}) interface{}
	Items      func(val interface{}) [][2]interface{} // each element => [key, value]
	Stringify  func(val interface{}, maxlen ...int) string
	Walk       func(
		val interface{},
		apply voxgigstruct.WalkApply,
		key *string,
		parent interface{},
		path []string,
	) interface{}
}

type RunSet func(
	t *testing.T,
	testspec interface{},
	testsubject interface{},
)

type RunSetFlags func(
	t *testing.T,
	testspec interface{},
  flags map[string]bool,
	testsubject interface{},
)

type RunPack struct {
	Spec   map[string]interface{}
	RunSet RunSet
  RunSetFlags RunSetFlags
}


type TestPack struct {
	Client  Client
	Subject Subject
	Utility Utility
}

type Subject func(args ...interface{}) (interface{}, error)


func Runner(
	name string,
	store interface{},
	testfile string,
	provider Provider,
) (*RunPack, error) {
	client, err := provider.Test(nil)
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve client: %w", err)
	}

	utility := client.Utility()
	structUtil := utility.Struct()

	spec := resolveSpec(name, testfile)
	clients, err := resolveClients(spec, store, provider, structUtil)
	if err != nil {
		return nil, err
	}

	subject, err := resolveSubject(name, structUtil)
	if err != nil {
		return nil, err
	}

	var runsetFlags RunSetFlags = func(
		t *testing.T,
		testspec interface{},
    flags map[string]bool,
		testsubject interface{},
	) {
    if nil == flags {
      flags = map[string]bool{}
    }

    if _, ok := flags["json_null"]; !ok {
      flags["json_null"] = true
    }

    jsonFlags := map[string]bool{
      "null": flags["json_null"],
    }
    
		if testsubject != nil {
			subject = subjectify(testsubject)
		}

		var testspecmap = fixJSONFlags(testspec.(map[string]interface{}), jsonFlags).(map[string]interface{})

		set, ok := testspecmap["set"].([]interface{})
		if !ok {
			fmt.Printf("No test set in %v", name)
			return
		}

		for _, entryVal := range set {
			entry := entryVal.(map[string]interface{})

			testpack, err := resolveTestPack(name, entry, subject, client, clients)
			if err != nil {
				fmt.Print("TESTPACK FAIL", err)
				return
			}

			args := resolveArgs(entry, testpack)

			res, err := testpack.Subject(args...)

      res = fixJSONFlags(res, jsonFlags)
      
			entry["res"] = res
			entry["thrown"] = err

			if nil == err {
				checkResult(t, entry, res, structUtil)
			} else {
				handleError(t, entry, err, structUtil)
			}
		}
	}

	var runset RunSet = func(
		t *testing.T,
		testspec interface{},
		testsubject interface{},
	) {
    runsetFlags(t, testspec, nil, testsubject)
  }
  
	return &RunPack{
		Spec:   spec,
		RunSet: runset,
    RunSetFlags: runsetFlags,
	}, nil
}


func checkResult(
	t *testing.T,
	entry map[string]interface{},
	res interface{},
	structUtils *StructUtility,
) {

	if entry["match"] == nil || entry["out"] != nil {
		var cleanRes interface{}
		if res != nil {
			flags := map[string]bool{"func": false}
			cleanRes = structUtils.CloneFlags(res, flags)
		} else {
			cleanRes = res
		}

		// fmt.Println("CR", cleanRes, entry["out"], "DE", reflect.DeepEqual(cleanRes, entry["out"]))

		if !reflect.DeepEqual(cleanRes, entry["out"]) {
			t.Error(outFail(entry, cleanRes, entry["out"]))
			return
		}
	}

	if entry["match"] != nil {
		pass, err := MatchNode(
			entry["match"],
			map[string]interface{}{
				"in":  entry["in"],
				"out": entry["res"],
				"ctx": entry["ctx"],
			},
			structUtils,
		)
		if err != nil {
			t.Error(fmt.Sprintf("match error: %v", err))
			return
		}
		if !pass {
			t.Error(fmt.Sprintf("match fail: %v", err))
			return
		}
	}
}

func outFail(entry interface{}, res interface{}, out interface{}) string {
	return fmt.Sprintf("Entry:\n%s\nExpected:\n%s\nGot:\n%s\n",
		inspect(entry), inspect(out), inspect(res))
}

func inspect(val interface{}) string {
	return inspectIndent(val, "")
}

func inspectIndent(val interface{}, indent string) string {
	result := ""

	switch v := val.(type) {
	case map[string]interface{}:
		result += indent + "{\n"
		for key, value := range v {
			result += fmt.Sprintf("%s  \"%s\": %s", indent, key, inspectIndent(value, indent+"  "))
		}
		result += indent + "}\n"

	case []interface{}:
		result += indent + "[\n"
		for _, value := range v {
			result += fmt.Sprintf("%s  - %s", indent, inspectIndent(value, indent+"  "))
		}
		result += indent + "]\n"

	default:
		result += fmt.Sprintf("%v (%s)\n", v, reflect.TypeOf(v))
	}

	return result
}

func handleError(
	t *testing.T,
	entry map[string]interface{},
	testerr error,
	structUtils *StructUtility,
) {
	entryErr := entry["err"]

	if nil == entryErr {
		t.Error(fmt.Sprintf("%s\n\nENTRY: %s", testerr.Error(), structUtils.Stringify(entry)))
		return
	}

	boolErr, hasBoolErr := entryErr.(bool)
	if hasBoolErr && !boolErr {
		t.Error(fmt.Sprintf("%s\n\nENTRY: %s", testerr.Error(), structUtils.Stringify(entry)))
		return
	}

	matchErr, err := MatchNode(entryErr, testerr.Error(), structUtils)

	if boolErr || matchErr {
		if entry["match"] != nil {
			matchErr, err := MatchNode(
				entry["match"],
				map[string]interface{}{
					"in":  entry["in"],
					"out": entry["res"],
					"ctx": entry["ctx"],
					"err": err.Error(),
				},
				structUtils,
			)

			if !matchErr {
				t.Error(fmt.Sprintf("match failed: %v", matchErr))
			}

			if nil != err {
				t.Error(fmt.Sprintf("match failed: %v", err))
			}
		}
	}

	// If we didn't match, then fail with an error message.
	t.Error(fmt.Sprintf("ERROR MATCH: [%s] <=> [%s]",
		structUtils.Stringify(entryErr),
		err.Error(),
	))
}

func resolveArgs(entry map[string]interface{}, testpack TestPack) []interface{} {
	structUtils := testpack.Utility.Struct()

	var args []interface{}
	if inVal, ok := entry["in"]; ok {
		args = []interface{}{structUtils.Clone(inVal)}
	} else {
		args = []interface{}{}
	}

	if ctx, exists := entry["ctx"]; exists && ctx != nil {
		args = []interface{}{ctx}
	} else if rawArgs, exists := entry["args"]; exists && rawArgs != nil {
		if slice, ok := rawArgs.([]interface{}); ok {
			args = slice
		}
	}

	if entry["ctx"] != nil || entry["args"] != nil {
		if len(args) > 0 {
			first := args[0]
			if firstMap, ok := first.(map[string]interface{}); ok && first != nil {
				clonedFirst := structUtils.Clone(firstMap)
				args[0] = clonedFirst
				entry["ctx"] = clonedFirst
				if m, ok := clonedFirst.(map[string]interface{}); ok {
					m["client"] = testpack.Client
					m["utility"] = testpack.Utility
				}
			}
		}
	}

	return args
}

func resolveTestPack(
	name string,
	entry interface{},
	testsubject interface{},
	client Client,
	clients map[string]Client,
) (TestPack, error) {

	subject, ok := testsubject.(Subject)
	if !ok {
		panic("QQQ")
	}

	pack := TestPack{
		Client:  client,
		Subject: subject,
		Utility: client.Utility(),
	}

	var err error

	if e, ok := entry.(map[string]interface{}); ok {
		if rawClient, exists := e["client"]; exists {
			if clientKey, ok := rawClient.(string); ok {
				if cl, found := clients[clientKey]; found {
					pack.Client = cl
					pack.Utility = cl.Utility()
					pack.Subject, err = resolveSubject(name, pack.Utility.Struct())
				}
			}
		}
	}

	return pack, err
}

func resolveSpec(
  name string,
  testfile string,
) map[string]interface{} {

	data, err := os.ReadFile(filepath.Join(".", testfile))
	if err != nil {
		panic(err)
	}

	var alltests map[string]interface{}
	if err := json.Unmarshal(data, &alltests); err != nil {
		panic(err)
	}

	var spec map[string]interface{}

	// Check if there's a "primary" key that is a map, and if it has our 'name'
	if primaryRaw, hasPrimary := alltests["primary"]; hasPrimary {
		if primaryMap, ok := primaryRaw.(map[string]interface{}); ok {
			if found, ok := primaryMap[name]; ok {
				spec = found.(map[string]interface{})
			}
		}
	}

	if spec == nil {
		if found, ok := alltests[name]; ok {
			spec = found.(map[string]interface{})
		}
	}

	if spec == nil {
		spec = alltests
	}

	return spec
}

func resolveClients(
	spec map[string]interface{},
	store interface{},
	provider Provider,
	structUtil *StructUtility,
) (map[string]Client, error) {
	clients := make(map[string]Client)

	defRaw, hasDef := spec["DEF"]
	if !hasDef {
		return clients, nil
	}

	defMap, ok := defRaw.(map[string]interface{})
	if !ok {
		return clients, nil
	}

	clientRaw, hasClient := defMap["client"]
	if !hasClient {
		return clients, nil
	}

	clientMap, ok := clientRaw.(map[string]interface{})
	if !ok {
		return clients, nil
	}

	for _, cdef := range structUtil.Items(clientMap) {
		key, _ := cdef[0].(string)                    // cdef[0]
		valMap, _ := cdef[1].(map[string]interface{}) // cdef[1]

		if valMap == nil {
			continue
		}

		testRaw, _ := valMap["test"].(map[string]interface{})
		opts, _ := testRaw["options"].(map[string]interface{})
		if opts == nil {
			opts = make(map[string]interface{})
		}

		structUtil.Inject(opts, store)

		client, err := provider.Test(opts)
		if err != nil {
			return nil, err
		}

		clients[key] = client
	}

	return clients, nil
}

func resolveSubject(
	name string,
	structUtil *StructUtility,
) (Subject, error) {
	// Get a reflect.Value of the struct
	val := reflect.ValueOf(structUtil)

	if val.Kind() == reflect.Ptr {
		val = val.Elem()
	}
	if val.Kind() != reflect.Struct {
		return nil, errors.New("resolveSubject: not a struct or struct pointer")
	}

	fieldVal := val.FieldByName(name)
	if !fieldVal.IsValid() {
		return nil, nil
	}

	if fieldVal.Kind() != reflect.Func {
		return nil, fmt.Errorf("resolveSubject: field %q is not a func", name)
	}

	fn, ok := fieldVal.Interface().(Subject)
	if !ok {
		return nil, fmt.Errorf("resolveSubject: field %q does not match expected signature", name)
	}

	return fn, nil
}

func MatchNode(
	check interface{},
	base interface{},
	structUtil *StructUtility,
) (bool, error) {
	pass := true
	var err error = nil

	structUtil.Walk(
		check,
		func(key *string, val interface{}, _parent interface{}, path []string) interface{} {
			scalar := true

			switch val.(type) {
			case map[string]interface{}, []interface{}:
				scalar = true
			}

			if scalar {
				baseval := structUtil.GetPath(path, base)
				if !MatchScalar(val, baseval, structUtil) {
					pass = false
					err = fmt.Errorf(
						"MATCH: %s: [%s] <=> [%s]",
						strings.Join(path, "."),
						structUtil.Stringify(val),
						structUtil.Stringify(baseval),
					)
				}
			}
			return val
		},
		nil,
		nil,
		nil,
	)
	return pass, err
}

func MatchScalar(check, base interface{}, structUtil *StructUtility) bool {
	if s, ok := check.(string); ok && s == "__UNDEF__" {
		check = nil
	}

	pass := (check == base)

	if !pass {

		if checkStr, ok := check.(string); ok {
			basestr := structUtil.Stringify(base)

			if len(checkStr) > 2 && checkStr[0] == '/' && checkStr[len(checkStr)-1] == '/' {
				pat := checkStr[1 : len(checkStr)-1]
				if rx, err := regexp.Compile(pat); err == nil {
					pass = rx.MatchString(basestr)
				} else {
					pass = false
				}
			} else {
				pass = strings.Contains(
					strings.ToLower(basestr),
					strings.ToLower(structUtil.Stringify(checkStr)),
				)
			}
		} else {
			cv := reflect.ValueOf(check)
			isf := cv.Kind() == reflect.Func
			if isf {
				pass = true
			}
		}
	}

	return pass
}


func subjectify(fn interface{}) Subject {
	v := reflect.ValueOf(fn)
	if v.Kind() != reflect.Func {
		panic("subjectify: not a function")
	}

	fnType := v.Type()

	return func(args ...interface{}) (interface{}, error) {

    argCount := fnType.NumIn()

    if len(args) < argCount {
      extended := make([]interface{}, argCount)
      copy(extended, args)
      args = extended
    }

		// Build reflect.Value slice for call
		in := make([]reflect.Value, fnType.NumIn())
		for i := 0; i < fnType.NumIn(); i++ {
			paramType := fnType.In(i)
			arg := args[i]

			if arg == nil {
				// `reflect.Zero(paramType)` yields a typed "nil" if paramType is
				// a pointer/interface/slice/map/etc., or the zero value if paramType
				// is something like int/string/struct.
				in[i] = reflect.Zero(paramType)
			} else {
				val := reflect.ValueOf(arg)

				// Check compatibility so we don't panic on invalid type
				if !val.Type().AssignableTo(paramType) {
					return nil, fmt.Errorf(
						"subjectify: argument %d type %T not assignable to parameter type %s",
						i, arg, paramType,
					)
				}
				in[i] = val
			}
		}

		// Call the original function
		out := v.Call(in)

		// Interpret results
		switch len(out) {
		case 0:
			// No returns
			return nil, nil
		case 1:
			// Single return => (interface{}, nil)
			return out[0].Interface(), nil
		case 2:
			// Common pattern => (value, error)
			errVal := out[1].Interface()
			var err error
			if errVal != nil {
				err = errVal.(error)
			}
			return out[0].Interface(), err
		default:
			// You can adapt to handle more returns if needed
			return nil, fmt.Errorf("subjectify: function returns too many values (%d)", len(out))
		}
	}
}


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
