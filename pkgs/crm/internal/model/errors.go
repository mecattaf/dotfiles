// Package model contains shared domain types and error classifications.
package model

import (
	"errors"
	"fmt"
)

var (
	// ErrValidation classifies validation and command-usage failures.
	ErrValidation = errors.New("validation error")
	// ErrNotFound classifies missing records, files, and databases.
	ErrNotFound = errors.New("not found")
	// ErrAmbiguous classifies references that match more than one record.
	ErrAmbiguous = errors.New("ambiguous reference")
	// ErrConflict classifies duplicate and idempotent-conflict failures.
	ErrConflict = errors.New("conflict")
)

// ExitError pairs a user-facing message with a sentinel error classification.
type ExitError struct {
	Message string
	Err     error
}

// Error returns the user-facing portion of the error.
func (e *ExitError) Error() string {
	return e.Message
}

// Unwrap exposes the sentinel used to classify the error.
func (e *ExitError) Unwrap() error {
	return e.Err
}

// NewExitError constructs an ExitError with a formatted user-facing message.
func NewExitError(sentinel error, message string, args ...any) *ExitError {
	return &ExitError{
		Message: fmt.Sprintf(message, args...),
		Err:     sentinel,
	}
}

// ExitCode maps errors to the CLI's stable process exit codes.
func ExitCode(err error) int {
	switch {
	case err == nil:
		return 0
	case errors.Is(err, ErrValidation):
		return 1
	case errors.Is(err, ErrNotFound):
		return 2
	case errors.Is(err, ErrAmbiguous):
		return 3
	case errors.Is(err, ErrConflict):
		return 4
	default:
		return 1
	}
}
