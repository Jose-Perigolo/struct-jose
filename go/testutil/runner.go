package runner

import (
	"fmt"

  "github.com/voxgig/struct"
  
  "os"
	"encoding/json"
	"errors"
	// "io/ioutil"
	"path/filepath"
	"reflect"
	"regexp"
	"strings"
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
	Clone func(val interface{}) interface{}
	GetPath func(path interface{}, store interface{}) interface{}
	Inject func(val interface{}, store interface{}) interface{}
	Items func(val interface{}) [][2]interface{} // each element => [key, value]
	Stringify func(val interface{}, maxlen ...int) string
	Walk func(
		val interface{},
    apply voxgigstruct.WalkApply,
    key *string,
    parent interface{},
    path []string,
	) interface{}
}

type RunnerMap struct {
  spec map[string]interface{}
  clients map[string]Client
  subject interface{}
  runset RunSet
}


type RunSet func(testspec map[string]interface{}, testsubject func(...interface{}) interface{})



func Runner(
  name string,
  store interface{},
  testfile string,
  provider Provider,
) (*RunnerMap, error) {
	client, err := provider.Test(nil)
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve client: %w", err)
	}

	utility := client.Utility()
	structUtil := utility.Struct()

	// cloneFn := structUtil.Clone
	// getpathFn := structUtil.GetPath
	// injectFn := structUtil.Inject
	// itemsFn := structUtil.Items
	// stringifyFn := structUtil.Stringify
	// walkFn := structUtil.Walk

	// _ = cloneFn
	// _ = getpathFn
	// _ = injectFn
	// _ = itemsFn
	// _ = stringifyFn
	// _ = walkFn

  spec := resolveSpec(name, testfile)
  clients, err := resolveClients(spec, store, provider, structUtil)
  if err != nil {
    return nil, err
  }

  subject, err := resolveSubject(name, structUtil)
  if err != nil {
    return nil, err
  }
  

  var runset RunSet = func(testspec map[string]interface{}, testsubject func(...interface{}) interface{}) {
    if testsubject == nil {
      testsubject = subject
    }
  }

  
  return &RunnerMap{
    spec: spec,
    clients: clients,
    subject: subject,
    runset: runset,
  }, nil
}



func resolveSpec(name string, testfile string) (map[string]interface{}) {

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
		key, _ := cdef[0].(string)       // cdef[0]
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


func resolveSubject(name string, structUtil *StructUtility) (func(...interface{}) interface{}, error) {
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

  fn, ok := fieldVal.Interface().(func(...interface{}) interface{})
  if !ok {
    return nil, fmt.Errorf("resolveSubject: field %q does not match expected signature", name)
  }

  return fn, nil
}


func Match(
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
        if !MatchVal(val, baseval, structUtil) {
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

func MatchVal(check, base interface{}, structUtil *StructUtility) bool {
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
