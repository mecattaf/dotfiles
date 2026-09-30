package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// dotfiles no longer installs a crm binary (issue #452, pull request #456), so a
// bare `crm` may not resolve. dcal must refuse by name before it spawns
// anything, rather than surface an exec "file not found".
func TestRunCRMWithoutBinaryRefusesByName(t *testing.T) {
	t.Setenv("DCAL_CRM_BIN", "")
	t.Setenv("PATH", t.TempDir())

	out, err := runCRM(context.Background(), "show", "c42", "--format", "json")
	require.Error(t, err)
	assert.Nil(t, out)
	assert.NotContains(t, err.Error(), "executable file not found")
	assert.Contains(t, err.Error(), "DCAL_CRM_BIN")
	assert.Contains(t, err.Error(), "mecattaf/crm")
	assert.Equal(t, exitFailure, exitCode(err))
}

// DCAL_CRM_BIN stays the escape hatch: it is honoured verbatim, including a path
// that PATH cannot reach, which is how the successor CRM wrapper is used.
func TestRunCRMUsesConfiguredBinaryVerbatim(t *testing.T) {
	fake := filepath.Join(t.TempDir(), "fake-crm")
	require.NoError(t, os.WriteFile(fake, []byte("#!/bin/sh\nprintf '%s\\n' \"$*\"\n"), 0o700))
	t.Setenv("DCAL_CRM_BIN", fake)
	t.Setenv("PATH", t.TempDir())

	out, err := runCRM(context.Background(), "show", "c42")
	require.NoError(t, err)
	assert.Equal(t, "show c42\n", string(out))
}

func TestDecodeCRMContact(t *testing.T) {
	tests := []struct {
		name    string
		raw     string
		want    crmContact
		wantErr string
	}{
		{
			name: "real crm array",
			raw:  `[{"ref":"c42","name":"Nick Dupont"}]`,
			want: crmContact{Ref: "c42", Name: "Nick Dupont"},
		},
		{
			name: "stub object",
			raw:  `{"ref":"c7","name":" Ada Lovelace "}`,
			want: crmContact{Ref: "c7", Name: "Ada Lovelace"},
		},
		{name: "not a contact", raw: `[{"ref":"o4","name":"Kima"}]`, wantErr: "non-contact"},
		{name: "missing name", raw: `[{"ref":"c42"}]`, wantErr: "without a name"},
		{name: "multiple", raw: `[{"ref":"c1","name":"One"},{"ref":"c2","name":"Two"}]`, wantErr: "expected one"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := decodeCRMContact([]byte(tc.raw))
			if tc.wantErr != "" {
				require.ErrorContains(t, err, tc.wantErr)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tc.want, got)
		})
	}
}

func TestContactRefParsing(t *testing.T) {
	for _, ref := range []string{"c1", "c42", "c9000"} {
		assert.True(t, isContactRef(ref), ref)
	}
	for _, ref := range []string{"", "c", "C42", "o42", "c-1", "c 1", "nick"} {
		assert.False(t, isContactRef(ref), ref)
	}
}
