package main

import (
	"errors"
	"fmt"
	"io"
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

// reportedError marks an external-command failure whose stderr has already
// been copied verbatim to dcal's stderr. The top-level runner must preserve the
// exit code without adding another prefixed error line.
type reportedError struct {
	*codedError
}

func (e *codedError) Error() string { return e.err.Error() }
func (e *codedError) Unwrap() error { return e.err }

func withCode(code int, format string, args ...any) error {
	return &codedError{code: code, err: fmt.Errorf(format, args...)}
}

func reportedWithCode(code int, err error) error {
	return &reportedError{codedError: &codedError{code: code, err: err}}
}

func exitCode(err error) int {
	var reported *reportedError
	if errors.As(err, &reported) {
		return reported.code
	}
	var coded *codedError
	if errors.As(err, &coded) {
		return coded.code
	}
	return exitFailure
}

func printCommandError(w io.Writer, err error) {
	var reported *reportedError
	if errors.As(err, &reported) {
		return
	}
	fmt.Fprintf(w, "dcal: %v\n", err)
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
