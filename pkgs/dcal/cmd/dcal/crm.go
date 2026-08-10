package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

const defaultCRMBinary = "crm"

type crmContact struct {
	Ref  string `json:"ref"`
	Name string `json:"name"`
}

func crmBinary() string {
	if configured := strings.TrimSpace(os.Getenv("DCAL_CRM_BIN")); configured != "" {
		return configured
	}
	return defaultCRMBinary
}

// runCRM preserves the CRM contract: stdout is structured data, while stderr
// is passed through unchanged. In particular, CRM's not-found/ambiguous exit
// codes (2/3) become dcal's exit codes without another wrapper line.
func runCRM(ctx context.Context, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, crmBinary(), args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if stderr.Len() > 0 {
		_, _ = os.Stderr.Write(stderr.Bytes())
	}
	if err == nil {
		return stdout.Bytes(), nil
	}

	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) && stderr.Len() > 0 {
		code := exitErr.ExitCode()
		if code < exitFailure || code > exitConflict {
			code = exitFailure
		}
		return nil, reportedWithCode(code, err)
	}
	return nil, fmt.Errorf("run %s: %w", crmBinary(), err)
}

func resolveCRMContact(ctx context.Context, ref string) (crmContact, error) {
	raw, err := runCRM(ctx, "show", strings.TrimSpace(ref), "--format", "json")
	if err != nil {
		return crmContact{}, err
	}
	contact, err := decodeCRMContact(raw)
	if err != nil {
		return crmContact{}, fmt.Errorf("decode crm show output: %w", err)
	}
	return contact, nil
}

// CRM's JSON record format is an array. Accepting a single object as well
// keeps DCAL_CRM_BIN fakes small without weakening validation of the record.
func decodeCRMContact(raw []byte) (crmContact, error) {
	var records []crmContact
	if bytes.HasPrefix(bytes.TrimSpace(raw), []byte("[")) {
		if err := json.Unmarshal(raw, &records); err != nil {
			return crmContact{}, err
		}
	} else {
		var record crmContact
		if err := json.Unmarshal(raw, &record); err != nil {
			return crmContact{}, err
		}
		records = []crmContact{record}
	}
	if len(records) != 1 {
		return crmContact{}, fmt.Errorf("expected one contact, got %d", len(records))
	}
	contact := records[0]
	contact.Ref = strings.TrimSpace(contact.Ref)
	contact.Name = strings.TrimSpace(contact.Name)
	if !isContactRef(contact.Ref) {
		return crmContact{}, fmt.Errorf("crm show returned non-contact ref %q", contact.Ref)
	}
	if contact.Name == "" {
		return crmContact{}, errors.New("crm show returned a contact without a name")
	}
	return contact, nil
}

func isContactRef(ref string) bool {
	if len(ref) < 2 || ref[0] != 'c' {
		return false
	}
	for _, char := range ref[1:] {
		if char < '0' || char > '9' {
			return false
		}
	}
	return true
}
