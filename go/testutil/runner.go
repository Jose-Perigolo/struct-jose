package runner

import (
	"fmt"

  "github.com/voxgig/struct"

	// "encoding/json"
	// "errors"
	// "io/ioutil"
	// "path/filepath"
	// "reflect"
	// "regexp"
	// "strings"
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

func Runner(name string, store interface{}, testfile string, provider Provider) error {
	client, err := provider.Test(nil)
	if err != nil {
		return fmt.Errorf("failed to retrieve client: %w", err)
	}

	utility := client.Utility()
	structUtil := utility.Struct()

	cloneFn := structUtil.Clone
	getpathFn := structUtil.GetPath
	injectFn := structUtil.Inject
	itemsFn := structUtil.Items
	stringifyFn := structUtil.Stringify
	walkFn := structUtil.Walk

	_ = cloneFn
	_ = getpathFn
	_ = injectFn
	_ = itemsFn
	_ = stringifyFn
	_ = walkFn

	return nil
}
