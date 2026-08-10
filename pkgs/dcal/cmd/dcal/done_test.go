package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLocateCallRecording(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{
		"2026-08-09-nick-dupont",
		"2026-08-09-other-call",
		"2026-08-10-nick-dupont",
	} {
		require.NoError(t, os.Mkdir(filepath.Join(root, name), 0o700))
	}

	got, err := locateCallRecording(root, "2026-08-09", "call with Nick Dupont", "Nick Dupont", "c42")
	require.NoError(t, err)
	assert.Equal(t, filepath.Join(root, "2026-08-09-nick-dupont"), got)

	_, err = locateCallRecording(root, "2026-08-09", "custom title", "Unknown Name", "c42")
	require.ErrorContains(t, err, "multiple call recordings")

	_, err = locateCallRecording(root, "2026-08-11", "call with Nick Dupont", "Nick Dupont", "c42")
	require.ErrorContains(t, err, "no call recording")
}

func TestCallSlugAndSummary(t *testing.T) {
	assert.Equal(t, "nick-dupont", callSlug(" Nick Dupont "))
	assert.Equal(t, "ada-lovelace", callSlug("Ada / Lovelace"))
	assert.Equal(t, "c42", callSlug("c42"))

	long := strings.Repeat("word ", 40)
	got := shortCallSummary(long)
	assert.LessOrEqual(t, len([]rune(got)), 120)
	assert.True(t, strings.HasSuffix(got, "..."))
}

func TestCopyTranscriptIsIdempotentAndProtectsDifferentEvidence(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "recording", "transcript.md")
	target := filepath.Join(root, "crm", "transcripts", "2026", "call.md")
	require.NoError(t, os.MkdirAll(filepath.Dir(source), 0o700))
	require.NoError(t, os.WriteFile(source, []byte("# Transcript\n"), 0o600))

	require.NoError(t, copyTranscript(source, target))
	require.NoError(t, copyTranscript(source, target))

	require.NoError(t, os.WriteFile(source, []byte("# Different\n"), 0o600))
	require.ErrorContains(t, copyTranscript(source, target), "refusing to replace different transcript")
}
