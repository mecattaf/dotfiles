package main

import (
	"errors"
	"fmt"
	"strings"
)

const (
	exitFailure   = 1
	exitNotFound  = 2
	exitAmbiguous = 3
	exitConflict  = 4
)

type codedError struct {
	code int
	err  error
}

func (e *codedError) Error() string { return e.err.Error() }
func (e *codedError) Unwrap() error { return e.err }

func withCode(code int, format string, args ...any) error {
	return &codedError{code: code, err: fmt.Errorf(format, args...)}
}

func exitCode(err error) int {
	var coded *codedError
	if errors.As(err, &coded) {
		return coded.code
	}
	return exitFailure
}

func remoteError(message string) error {
	lower := strings.ToLower(message)
	switch {
	case strings.Contains(lower, "not found"), strings.HasPrefix(lower, "no account"), strings.HasPrefix(lower, "no calendar"):
		return withCode(exitNotFound, "%s", message)
	case strings.Contains(lower, "ambiguous"):
		return withCode(exitAmbiguous, "%s", message)
	case strings.Contains(lower, "already exists"), strings.Contains(lower, "constraint"):
		return withCode(exitConflict, "%s", message)
	default:
		return errors.New(message)
	}
}
