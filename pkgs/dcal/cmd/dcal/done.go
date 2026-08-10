package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/spf13/cobra"
)

const defaultCallDiarizeBinary = "call-diarize"

type doneOptions struct {
	dryRun bool
}

type donePlan struct {
	EventRef         string         `json:"eventRef"`
	CRMRef           string         `json:"crmRef"`
	Date             string         `json:"date"`
	RecordingDir     string         `json:"recordingDir"`
	TranscriptSource string         `json:"transcriptSource"`
	TranscriptTarget string         `json:"transcriptTarget"`
	DiarizeArgv      []string       `json:"diarizeArgv"`
	CRMLogArgv       []string       `json:"crmLogArgv"`
	DryRun           bool           `json:"dryRun"`
	Steps            []donePlanStep `json:"steps,omitempty"`
}

type donePlanStep struct {
	Action string `json:"action"`
	Status string `json:"status"`
	Detail string `json:"detail"`
}

var doneFlags doneOptions

var doneCmd = &cobra.Command{
	Use:   "done <event-ref>",
	Short: "Diarize a finished call and log it in the CRM",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		client, err := dialDaemon()
		if err != nil {
			return err
		}
		defer client.Close()

		event, err := getEvent(client, args[0])
		if err != nil {
			return err
		}
		if !doneFlags.dryRun {
			if event.CRMKind != "call" {
				return fmt.Errorf("event %s is not a CRM call", event.ID)
			}
			if event.CRMRef == "" {
				return fmt.Errorf("event %s has no CRM ref", event.ID)
			}
			if !event.End.Before(timeNow()) {
				return fmt.Errorf("event %s has not ended yet", event.ID)
			}
		}

		plan, err := buildDonePlan(event, doneFlags.dryRun)
		if err != nil {
			return err
		}
		if doneFlags.dryRun {
			return printDonePlan(plan)
		}
		if err := executeDonePlan(cmd.Context(), plan); err != nil {
			return err
		}
		return nil
	},
}

func init() {
	doneCmd.Flags().BoolVar(&doneFlags.dryRun, "dry-run", false, "Print the resolved plan without executing it")
}

var timeNow = func() time.Time { return time.Now() }

func buildDonePlan(event eventRecord, dryRun bool) (donePlan, error) {
	date := callEventDate(event.Start)
	subject := callSubject(event.Summary)
	plan := donePlan{
		EventRef: event.ID,
		CRMRef:   event.CRMRef,
		Date:     date,
		DryRun:   dryRun,
	}

	recordings, recordingErr := recordingsRoot()
	if recordingErr == nil {
		plan.RecordingDir, recordingErr = locateCallRecording(recordings, date, event.Summary, subject, event.CRMRef)
	}
	if recordingErr != nil && !dryRun {
		return donePlan{}, recordingErr
	}
	if recordingErr == nil {
		plan.TranscriptSource = filepath.Join(plan.RecordingDir, "transcript.md")
		plan.DiarizeArgv = []string{callDiarizeBinary(), plan.RecordingDir}
	}

	crmBase, targetErr := crmBaseDir()
	if targetErr != nil && !dryRun {
		return donePlan{}, targetErr
	}
	nameSlug := callSlug(subject)
	if nameSlug == "" {
		nameSlug = event.CRMRef
	}
	if nameSlug == "" {
		nameSlug = "call"
	}
	relative := filepath.Join("transcripts", date[:4], date+"-"+nameSlug+"-call.md")
	if targetErr == nil {
		plan.TranscriptTarget = filepath.Join(crmBase, relative)
	}
	if event.CRMRef != "" {
		plan.CRMLogArgv = []string{
			crmBinary(), "log",
			"--kind", "call",
			"--transcript", filepath.ToSlash(relative),
			"--refs", event.CRMRef,
			"--date", date,
			"--summary", shortCallSummary(event.Summary),
		}
	}
	if dryRun {
		plan.Steps = buildDonePreviewSteps(event, recordings, recordingErr, targetErr, plan)
	}
	return plan, nil
}

func buildDonePreviewSteps(event eventRecord, recordings string, recordingErr, targetErr error, plan donePlan) []donePlanStep {
	var steps []donePlanStep
	if recordingErr == nil {
		steps = append(steps, readyDoneStep("search recording", plan.RecordingDir))
	} else {
		steps = append(steps, missingDoneStep("search recording", previewRecordingMissing(recordings, recordingErr)))
	}

	var actionMissing []string
	if recordingErr != nil {
		actionMissing = append(actionMissing, "matching recording is missing")
	}
	if len(actionMissing) == 0 {
		steps = append(steps, readyDoneStep("run call-diarize", formatArgv(plan.DiarizeArgv)))
	} else {
		steps = append(steps, missingDoneStep("run call-diarize", actionMissing...))
	}

	copyMissing := append([]string(nil), actionMissing...)
	if targetErr != nil {
		copyMissing = append(copyMissing, "CRM transcript root is unavailable: "+targetErr.Error())
	}
	if len(copyMissing) == 0 {
		detail := fmt.Sprintf("%s -> %s (source produced by call-diarize)", plan.TranscriptSource, plan.TranscriptTarget)
		steps = append(steps, readyDoneStep("copy transcript", detail))
	} else {
		steps = append(steps, missingDoneStep("copy transcript", copyMissing...))
	}
	logMissing := doneEventPrerequisites(event, timeNow())
	logMissing = append(logMissing, copyMissing...)
	if len(logMissing) == 0 {
		steps = append(steps, readyDoneStep("run crm log", formatArgv(plan.CRMLogArgv)))
	} else {
		steps = append(steps, missingDoneStep("run crm log", logMissing...))
	}
	return steps
}

func doneEventPrerequisites(event eventRecord, now time.Time) []string {
	var missing []string
	if event.CRMKind != "call" {
		if event.CRMKind == "" {
			missing = append(missing, "CRM call kind is missing")
		} else {
			missing = append(missing, fmt.Sprintf("CRM call kind is %q, not %q", event.CRMKind, "call"))
		}
	}
	if event.CRMRef == "" {
		missing = append(missing, "CRM linkage is missing")
	}
	if !event.End.Before(now) {
		missing = append(missing, "event has not ended yet")
	}
	return missing
}

func previewRecordingMissing(root string, err error) string {
	if root == "" {
		return "recordings root is unavailable: " + err.Error()
	}
	if errors.Is(err, os.ErrNotExist) || strings.Contains(err.Error(), "no call recording found") {
		return "none found under " + root
	}
	return err.Error()
}

func readyDoneStep(action, detail string) donePlanStep {
	return donePlanStep{Action: action, Status: "ready", Detail: detail}
}

func missingDoneStep(action string, missing ...string) donePlanStep {
	if len(missing) == 0 {
		missing = []string{"prerequisite is missing"}
	}
	return donePlanStep{Action: action, Status: "missing", Detail: strings.Join(missing, "; ")}
}

func formatArgv(argv []string) string {
	encoded, _ := json.Marshal(argv)
	return string(encoded)
}

func printDonePlan(plan donePlan) error {
	if jsonOutput {
		return printJSON(plan)
	}
	fmt.Fprintf(os.Stdout, "Event:\t%s\n", plan.EventRef)
	if plan.CRMRef == "" {
		fmt.Fprintln(os.Stdout, "CRM ref:\t(missing)")
	} else {
		fmt.Fprintf(os.Stdout, "CRM ref:\t%s\n", plan.CRMRef)
	}
	fmt.Fprintf(os.Stdout, "Date:\t%s\n", plan.Date)
	fmt.Fprintln(os.Stdout, "Plan:")
	for _, step := range plan.Steps {
		if step.Status == "ready" {
			fmt.Fprintf(os.Stdout, "would %s: ready — %s\n", step.Action, step.Detail)
			continue
		}
		fmt.Fprintf(os.Stdout, "would %s: %s (missing)\n", step.Action, step.Detail)
	}
	if plan.RecordingDir != "" {
		fmt.Fprintf(os.Stdout, "Recording dir:\t%s\n", plan.RecordingDir)
	}
	if plan.TranscriptSource != "" {
		fmt.Fprintf(os.Stdout, "Transcript source:\t%s\n", plan.TranscriptSource)
	}
	if plan.TranscriptTarget != "" {
		fmt.Fprintf(os.Stdout, "Transcript target:\t%s\n", plan.TranscriptTarget)
	}
	if len(plan.DiarizeArgv) > 0 {
		fmt.Fprintf(os.Stdout, "call-diarize argv:\t%s\n", formatArgv(plan.DiarizeArgv))
	}
	if len(plan.CRMLogArgv) > 0 {
		fmt.Fprintf(os.Stdout, "crm log argv:\t%s\n", formatArgv(plan.CRMLogArgv))
	}
	return nil
}

func executeDonePlan(ctx context.Context, plan donePlan) error {
	if err := runPassthrough(ctx, plan.DiarizeArgv, os.Stderr); err != nil {
		return fmt.Errorf("diarize event %s: %w", plan.EventRef, err)
	}
	if err := copyTranscript(plan.TranscriptSource, plan.TranscriptTarget); err != nil {
		return err
	}
	if err := runPassthrough(ctx, plan.CRMLogArgv, os.Stdout); err != nil {
		return fmt.Errorf("log event %s: %w", plan.EventRef, err)
	}
	return nil
}

func runPassthrough(ctx context.Context, argv []string, stdout io.Writer) error {
	if len(argv) == 0 {
		return errors.New("empty command argv")
	}
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Stdout = stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func copyTranscript(source, target string) error {
	content, err := os.ReadFile(source)
	if err != nil {
		return fmt.Errorf("read diarized transcript: %w", err)
	}
	if len(bytes.TrimSpace(content)) == 0 {
		return fmt.Errorf("diarized transcript is empty: %s", source)
	}
	if existing, err := os.ReadFile(target); err == nil {
		if bytes.Equal(existing, content) {
			return nil
		}
		return fmt.Errorf("refusing to replace different transcript: %s", target)
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("read transcript target: %w", err)
	}

	if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
		return fmt.Errorf("create transcript directory: %w", err)
	}
	temporary, err := os.CreateTemp(filepath.Dir(target), ".dcal-transcript-*.tmp")
	if err != nil {
		return fmt.Errorf("create transcript temporary file: %w", err)
	}
	temporaryName := temporary.Name()
	defer os.Remove(temporaryName)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(content); err != nil {
		temporary.Close()
		return fmt.Errorf("write transcript: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close transcript: %w", err)
	}
	if err := os.Rename(temporaryName, target); err != nil {
		return fmt.Errorf("publish transcript: %w", err)
	}
	return nil
}

func recordingsRoot() (string, error) {
	for _, key := range []string{"DCAL_RECORDINGS_ROOT", "CALL_RECORDINGS_ROOT"} {
		if configured := strings.TrimSpace(os.Getenv(key)); configured != "" {
			return absolutePath(configured)
		}
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home for recordings: %w", err)
	}
	return filepath.Join(home, "Recordings", "calls"), nil
}

func crmBaseDir() (string, error) {
	if configured := strings.TrimSpace(os.Getenv("DCAL_CRM_BASE")); configured != "" {
		return absolutePath(configured)
	}
	if database := strings.TrimSpace(os.Getenv("CRM_DB")); database != "" {
		resolved, err := absolutePath(database)
		if err != nil {
			return "", err
		}
		return filepath.Dir(resolved), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home for CRM transcripts: %w", err)
	}
	return filepath.Join(home, "mecattaf", "notes", "crm"), nil
}

func absolutePath(path string) (string, error) {
	if strings.HasPrefix(path, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		path = filepath.Join(home, strings.TrimPrefix(path, "~/"))
	}
	resolved, err := filepath.Abs(path)
	if err != nil {
		return "", fmt.Errorf("resolve path %q: %w", path, err)
	}
	return resolved, nil
}

func callDiarizeBinary() string {
	if configured := strings.TrimSpace(os.Getenv("DCAL_CALL_DIARIZE_BIN")); configured != "" {
		return configured
	}
	return defaultCallDiarizeBinary
}

func locateCallRecording(root, date, summary, contactName, crmRef string) (string, error) {
	entries, err := os.ReadDir(root)
	if err != nil {
		return "", fmt.Errorf("read call recordings: %w", err)
	}
	prefix := date + "-"
	var dated []string
	for _, entry := range entries {
		if entry.IsDir() && strings.HasPrefix(entry.Name(), prefix) {
			dated = append(dated, entry.Name())
		}
	}
	sort.Strings(dated)

	summaryContact := callSubject(summary)
	for _, slug := range uniqueStrings(callSlug(contactName), callSlug(summaryContact), callSlug(summary), strings.ToLower(crmRef)) {
		if slug == "" {
			continue
		}
		name := prefix + slug
		index := sort.SearchStrings(dated, name)
		if index < len(dated) && dated[index] == name {
			return filepath.Join(root, name), nil
		}
	}
	if len(dated) == 1 {
		return filepath.Join(root, dated[0]), nil
	}
	if len(dated) == 0 {
		return "", fmt.Errorf("no call recording found for %s under %s", date, root)
	}
	return "", fmt.Errorf("multiple call recordings found for %s under %s: %s", date, root, strings.Join(dated, ", "))
}

func uniqueStrings(values ...string) []string {
	seen := make(map[string]struct{}, len(values))
	out := make([]string, 0, len(values))
	for _, value := range values {
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
	}
	return out
}

func callSlug(value string) string {
	var b strings.Builder
	separator := false
	for _, char := range strings.ToLower(strings.TrimSpace(value)) {
		switch {
		case char >= 'a' && char <= 'z', char >= '0' && char <= '9':
			if separator && b.Len() > 0 {
				b.WriteByte('-')
			}
			b.WriteRune(char)
			separator = false
		case unicode.IsSpace(char) || unicode.IsPunct(char) || unicode.IsSymbol(char):
			separator = true
		}
	}
	return strings.Trim(b.String(), "-")
}

func callSubject(summary string) string {
	subject := strings.TrimSpace(summary)
	if len(subject) >= len("call with ") && strings.EqualFold(subject[:len("call with ")], "call with ") {
		return strings.TrimSpace(subject[len("call with "):])
	}
	return subject
}

func shortCallSummary(summary string) string {
	cleaned := strings.Join(strings.Fields(summary), " ")
	const maxRunes = 120
	if utf8.RuneCountInString(cleaned) <= maxRunes {
		return cleaned
	}
	runes := []rune(cleaned)
	return strings.TrimSpace(string(runes[:maxRunes-3])) + "..."
}

func callEventDate(start time.Time) string {
	return start.In(time.Local).Format(time.DateOnly)
}
