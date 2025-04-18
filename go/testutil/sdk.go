package runner

import (
	"fmt"
	
	voxgigstruct "github.com/voxgig/struct"
)

// SDK is a Go implementation of the TypeScript SDK class
type SDK struct {
	opts    map[string]any
	utility *SDKUtility
}

// SDKUtility implements the Utility interface
type SDKUtility struct {
	sdk     *SDK
	structu *StructUtility
}

// Struct returns the StructUtility
func (u *SDKUtility) Struct() *StructUtility {
	return u.structu
}

// Contextify implements the contextify function
func (u *SDKUtility) Contextify(ctxmap map[string]any) map[string]any {
	return ctxmap
}

// Check implements the check function
func (u *SDKUtility) Check(ctx map[string]any) map[string]any {
	zed := "ZED"
	if u.sdk.opts != nil {
		if foo, ok := u.sdk.opts["foo"]; ok && foo != nil {
			zed += fmt.Sprint(foo)
		}
	}
	zed += "_"

	if ctx == nil {
		zed += "0"
	} else if meta, ok := ctx["meta"].(map[string]any); ok && meta != nil {
		if bar, ok := meta["bar"]; ok && bar != nil {
			zed += fmt.Sprint(bar)
		} else {
			zed += "0"
		}
	} else {
		zed += "0"
	}

	return map[string]any{
		"zed": zed,
	}
}

// NewSDK creates a new SDK instance with the given options
func NewSDK(opts map[string]any) *SDK {
	if opts == nil {
		opts = map[string]any{}
	}

	sdk := &SDK{
		opts: opts,
	}
	
	// Create the StructUtility
	structUtil := &StructUtility{
		IsNode:     voxgigstruct.IsNode,
		Clone:      voxgigstruct.Clone,
		CloneFlags: voxgigstruct.CloneFlags,
		GetPath:    voxgigstruct.GetPath,
		Inject:     voxgigstruct.Inject,
		Items:      voxgigstruct.Items,
		Stringify:  voxgigstruct.Stringify,
		Walk:       voxgigstruct.Walk,
	}
	
	// Create the utility
	sdk.utility = &SDKUtility{
		sdk:     sdk,
		structu: structUtil,
	}

	return sdk
}

// Test creates a new SDK instance (simulating the static async test method)
func TestSDK(opts map[string]any) (*SDK, error) {
	return NewSDK(opts), nil
}

// Tester creates a new SDK instance with options or default options
func (s *SDK) Tester(opts map[string]any) (*SDK, error) {
	if opts == nil {
		opts = s.opts
	}
	return NewSDK(opts), nil
}

// Utility returns the utility object
func (s *SDK) Utility() Utility {
	return s.utility
}
