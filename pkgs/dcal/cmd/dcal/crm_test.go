package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

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
