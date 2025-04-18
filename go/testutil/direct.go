package runner

import (
	"fmt"
	
	voxgigstruct "github.com/voxgig/struct"
)

// Direct is a direct testing helper for validation functions
// Similar to the direct.ts TypeScript file, it provides a way to test validation directly
func DirectTest() {
	var out any
	var errs *voxgigstruct.ListRef[any]
	
	// Direct testing code ported from direct.ts
	
	// errs = []
	// out = validate(1, '`$STRING`', undefined, errs)
	// console.log('OUT-A0', out, errs)
	/*
	errs = voxgigstruct.ListRefCreate[any]()
	out, _ = voxgigstruct.ValidateCollect(1, "`$STRING`", nil, errs)
	fmt.Println("OUT-A0", out, errs.List)
	
	// errs = []
	// out = validate({ a: 1 }, { a: '`$STRING`' }, undefined, errs)
	// console.log('OUT-A1', out, errs)
	errs = voxgigstruct.ListRefCreate[any]()
	out, _ = voxgigstruct.ValidateCollect(map[string]any{"a": 1}, map[string]any{"a": "`$STRING`"}, nil, errs)
	fmt.Println("OUT-A1", out, errs.List)
	
	// errs = []
	// out = validate(true, ['`$ONE`', '`$STRING`', '`$NUMBER`'], undefined, errs)
	// console.log('OUT-B0', out, errs)
	errs = voxgigstruct.ListRefCreate[any]()
	out, _ = voxgigstruct.ValidateCollect(true, []any{"`$ONE`", "`$STRING`", "`$NUMBER`"}, nil, errs)
	fmt.Println("OUT-B0", out, errs.List)
	
	// errs = []
	// out = validate(true, ['`$ONE`', '`$STRING`'], undefined, errs)
	// console.log('OUT-B1', out, errs)
	errs = voxgigstruct.ListRefCreate[any]()
	out, _ = voxgigstruct.ValidateCollect(true, []any{"`$ONE`", "`$STRING`"}, nil, errs)
	fmt.Println("OUT-B1", out, errs.List)
	
	// errs = []
	// out = validate(3, ['`$EXACT`', 4], undefined, errs)
	// console.log('OUT', out, errs)
	errs = voxgigstruct.ListRefCreate[any]()
	out, _ = voxgigstruct.ValidateCollect(3, []any{"`$EXACT`", 4}, nil, errs)
	fmt.Println("OUT", out, errs.List)
	
	// errs = []
	// out = validate({ a: 3 }, { a: ['`$EXACT`', 4] }, undefined, errs)
	// console.log('OUT', out, errs)
	errs = voxgigstruct.ListRefCreate[any]()
	out, _ = voxgigstruct.ValidateCollect(map[string]any{"a": 3}, map[string]any{"a": []any{"`$EXACT`", 4}}, nil, errs)
	fmt.Println("OUT", out, errs.List)
	
	// errs = []
	// out = validate({}, { '`$EXACT`': 1 }, undefined, errs)
	// console.log('OUT', out, errs)
	errs = voxgigstruct.ListRefCreate[any]()
	out, _ = voxgigstruct.ValidateCollect(map[string]any{}, map[string]any{"`$EXACT`": 1}, nil, errs)
	fmt.Println("OUT", out, errs.List)
	
	// errs = []
	// out = validate({}, { a: '`$EXACT`' }, undefined, errs)
	// console.log('OUT', out, errs)
	errs = voxgigstruct.ListRefCreate[any]()
	out, _ = voxgigstruct.ValidateCollect(map[string]any{}, map[string]any{"a": "`$EXACT`"}, nil, errs)
	fmt.Println("OUT", out, errs.List)
	
	// errs = []
	// out = validate({}, { a: [1, '`$EXACT`'] }, undefined, errs)
	// console.log('OUT', out, errs)
	errs = voxgigstruct.ListRefCreate[any]()
	out, _ = voxgigstruct.ValidateCollect(map[string]any{}, map[string]any{"a": []any{1, "`$EXACT`"}}, nil, errs)
	fmt.Println("OUT", out, errs.List)
	
	// errs = []
	// out = validate({}, { a: ['`$ONE`', '`$STRING`', '`$NUMBER`'] }, undefined, errs)
	// console.log('OUT', out, errs)
	errs = voxgigstruct.ListRefCreate[any]()
	out, _ = voxgigstruct.ValidateCollect(map[string]any{}, map[string]any{"a": []any{"`$ONE`", "`$STRING`", "`$NUMBER`"}}, nil, errs)
	fmt.Println("OUT", out, errs.List)
	*/
	
	// This is the only uncommented test from direct.ts
	errs = voxgigstruct.ListRefCreate[any]()
	out, _ = voxgigstruct.ValidateCollect(
		map[string]any{
			// kind: undefined
		}, 
		map[string]any{
			// name: '`$STRING`',
			// kind: ['`$EXACT`', 'req', 'res'],
			// path: '`$STRING`',
			// entity: '`$STRING`',
			// reqform: ['`$ONE`', '`$STRING`', '`$OBJECT`', '`$FUNCTION`'],
			// resform: ['`$ONE`', '`$STRING`', '`$OBJECT`', '`$FUNCTION`'],
			// resform: ['`$ONE`', '`$STRING`', '`$OBJECT`'],
			// resform: ['`$ONE`', '`$STRING`'],
			"resform": []any{"`$ONE`", "`$OBJECT`"},
			// params: ['`$CHILD`', '`$STRING`'],
			// alias: { '`$CHILD`': '`$STRING`' },
			// match: {},
			// data: ['`$ONE`', {}, []],
			// state: {},
			// check: {},
		}, 
		nil, 
		errs)
	fmt.Println("OUT", out, errs.List)
}

// Run runs the direct tests
func Run() {
	DirectTest()
}