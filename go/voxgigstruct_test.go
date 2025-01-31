package voxgigstruct

import "testing"

// TestAdd verifies that Add(a, b) returns the correct result.
func TestAdd(t *testing.T) {
	tests := []struct {
		a, b   int
		want   int
	}{
		{1, 1, 2},
		{2, 3, 5},
		{10, 5, 15},
		{-1, 1, 0},
	}

	for _, tt := range tests {
		got := Add(tt.a, tt.b)
		if got != tt.want {
			t.Errorf("Add(%d, %d) = %d; want %d", tt.a, tt.b, got, tt.want)
		}
	}
}
