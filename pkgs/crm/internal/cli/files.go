package cli

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/mecattaf/crm/internal/model"
)

// resolveTranscriptPath is the single transcript-base rule shared by writes
// now and the doctor audit later. It returns the base-relative stored path.
func resolveTranscriptPath(base, rawPath string) (string, error) {
	if strings.TrimSpace(rawPath) == "" {
		return "", nil
	}

	absoluteBase, err := filepath.Abs(base)
	if err != nil {
		return "", fmt.Errorf("resolve transcript base %s: %w", base, err)
	}
	candidate := rawPath
	if !filepath.IsAbs(candidate) {
		candidate = filepath.Join(absoluteBase, candidate)
	}
	absoluteCandidate, err := filepath.Abs(candidate)
	if err != nil {
		return "", fmt.Errorf("resolve transcript path %s: %w", rawPath, err)
	}
	relative, err := filepath.Rel(absoluteBase, absoluteCandidate)
	if err != nil {
		return "", fmt.Errorf("relativize transcript path %s: %w", rawPath, err)
	}
	if relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", model.NewExitError(
			model.ErrValidation,
			"transcript path %q is outside transcript base %q",
			rawPath,
			absoluteBase,
		)
	}

	info, err := os.Stat(absoluteCandidate)
	if errors.Is(err, os.ErrNotExist) {
		return "", model.NewExitError(
			model.ErrNotFound,
			"transcript path %q not found — create the file and retry",
			rawPath,
		)
	}
	if err != nil {
		return "", fmt.Errorf("inspect transcript path %s: %w", rawPath, err)
	}
	if !info.Mode().IsRegular() {
		return "", model.NewExitError(
			model.ErrValidation,
			"transcript path %q is not a regular file",
			rawPath,
		)
	}

	return filepath.Clean(relative), nil
}

func readBodyFile(input io.Reader, rawPath string) (*string, error) {
	var content []byte
	var err error
	if rawPath == "-" {
		content, err = io.ReadAll(input)
		if err != nil {
			return nil, fmt.Errorf("read interaction body from stdin: %w", err)
		}
	} else {
		content, err = os.ReadFile(rawPath)
		if errors.Is(err, os.ErrNotExist) {
			return nil, model.NewExitError(
				model.ErrNotFound,
				"body file %q not found — check the path and retry",
				rawPath,
			)
		}
		if err != nil {
			return nil, fmt.Errorf("read body file %s: %w", rawPath, err)
		}
	}
	if len(content) == 0 {
		return nil, nil
	}
	body := string(content)

	return &body, nil
}
