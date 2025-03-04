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

type RunPack struct {
	Spec    map[string]interface{}
	RunSet  RunSet
}

type RunSet func(
	t *testing.T,
	testspec interface{},
	testsubject interface{},
)

type Subject func(args ...interface{}) (interface{}, error)

type TestPack struct {
	Client  Client
	Subject Subject
	Utility Utility
}


func subjectify(val interface{}) Subject {
  subject, ok := val.(Subject)
  if ok {
    return subject
  }

  booler1arg, ok := val.(func(arg interface{}) bool)
  if ok {
    return func(args ...interface{}) (interface{}, error) {
      if 0 == len(args) {
        return booler1arg(nil), nil
      } else {
        return booler1arg(args[0]), nil
      }
    }
  }

  booler, ok := val.(func(arg ...interface{}) bool)
  if ok {
    return func(args ...interface{}) (interface{}, error) {
      return booler(args...), nil
    }
  }

  panic(fmt.Sprintf("SUBJECTIFY FAILED: %v", val))
  return nil
}


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

  var runset RunSet = func(
		t *testing.T,
		testspec interface{},
		testsubject interface{},
  ) {

    if testsubject != nil {
			subject = subjectify(testsubject)
		}

    var testspecmap = testspec.(map[string]interface{})
    
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

      entry["res"] = res
			entry["thrown"] = err

			if nil == err {
				checkResult(t, entry, res, structUtil)
			} else {
				handleError(t, entry, err, structUtil)
			}
		}
	}

	return &RunPack{
		Spec:    spec,
		RunSet:  runset,
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

      if(!matchErr) {
				t.Error(fmt.Sprintf("match failed: %v", matchErr))
			}

      if(nil != err) {
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

func resolveSpec(name string, testfile string) map[string]interface{} {

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
