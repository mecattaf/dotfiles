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

// dotfiles stopped shipping a crm binary (issue #452, pull request #456), so the
// pointer is optional now. Name the variable and the successor's wrapper rather
// than a path that may not exist on this machine.
const crmMissingRefusal = "no crm executable on PATH: set DCAL_CRM_BIN to a CRM command, " +
	"such as the scripts/crm-cli.sh wrapper in github.com/mecattaf/crm"

type crmContact struct {
	Ref  string `json:"ref"`
	Name string `json:"name"`
}

type crmInteraction struct {
	OccurredOn string `json:"occurred_on"`
}

// crmBinary resolves the CRM executable before anything is spawned. DCAL_CRM_BIN
// wins and is honoured verbatim, including an absolute path PATH cannot reach.
// Otherwise the optional crm must resolve on PATH; a refusal by name beats an
// exec error naming a binary the fleet no longer installs.
func crmBinary() (string, error) {
	if configured := strings.TrimSpace(os.Getenv("DCAL_CRM_BIN")); configured != "" {
		return configured, nil
	}
	resolved, err := exec.LookPath(defaultCRMBinary)
	if err != nil {
		fmt.Fprintf(os.Stderr, "dcal: %s\n", crmMissingRefusal)
		return "", reportedWithCode(exitFailure, errors.New(crmMissingRefusal))
	}
	return resolved, nil
}

// runCRM preserves the CRM contract: stdout is structured data, while stderr
// is passed through unchanged. In particular, CRM's not-found/ambiguous exit
// codes (2/3) become dcal's exit codes without another wrapper line.
func runCRM(ctx context.Context, args ...string) ([]byte, error) {
	binary, err := crmBinary()
	if err != nil {
		return nil, err
	}
	cmd := exec.CommandContext(ctx, binary, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err = cmd.Run()
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
	return nil, fmt.Errorf("run %s: %w", binary, err)
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

func crmCallLogged(ctx context.Context, ref, date string) (bool, error) {
	raw, err := runCRM(ctx, "interaction", "ls", "--with", ref, "--kind", "call", "--format", "json")
	if err != nil {
		return false, err
	}
	var interactions []crmInteraction
	if err := json.Unmarshal(raw, &interactions); err != nil {
		return false, fmt.Errorf("decode crm interaction list: %w", err)
	}
	for _, interaction := range interactions {
		if strings.TrimSpace(interaction.OccurredOn) == date {
			return true, nil
		}
	}
	return false, nil
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
