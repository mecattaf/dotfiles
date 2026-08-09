package model

import (
	"errors"
	"fmt"
	"testing"
)

func TestExitCode(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		err  error
		want int
	}{
		{name: "success", err: nil, want: 0},
		{name: "validation", err: ErrValidation, want: 1},
		{name: "generic", err: errors.New("unexpected failure"), want: 1},
		{name: "not found", err: ErrNotFound, want: 2},
		{name: "ambiguous", err: ErrAmbiguous, want: 3},
		{name: "conflict", err: ErrConflict, want: 4},
		{name: "wrapped not found", err: fmt.Errorf("lookup: %w", ErrNotFound), want: 2},
		{
			name: "exit error wrapping conflict",
			err:  NewExitError(ErrConflict, "already exists: %s", "record"),
			want: 4,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			if got := ExitCode(test.err); got != test.want {
				t.Fatalf("ExitCode() = %d, want %d", got, test.want)
			}
		})
	}
}

func TestExitError(t *testing.T) {
	t.Parallel()

	err := NewExitError(ErrNotFound, "no record at %s", "c12")
	if got, want := err.Error(), "no record at c12"; got != want {
		t.Fatalf("Error() = %q, want %q", got, want)
	}
	if !errors.Is(err, ErrNotFound) {
		t.Fatal("ExitError does not unwrap to ErrNotFound")
	}
}
