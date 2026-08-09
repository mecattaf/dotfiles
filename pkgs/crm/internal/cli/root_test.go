package cli

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/mecattaf/crm/internal/db"
	"github.com/mecattaf/crm/internal/model"
)

var testBinaryPath string

func TestMain(m *testing.M) {
	temporaryDirectory, err := os.MkdirTemp("", "crm-test-bin-")
	if err != nil {
		panic(fmt.Sprintf("create binary temp directory: %v", err))
	}
	testBinaryPath = filepath.Join(temporaryDirectory, "crm")

	projectRoot, err := findProjectRoot()
	if err != nil {
		_ = os.RemoveAll(temporaryDirectory)
		panic(fmt.Sprintf("find project root: %v", err))
	}
	build := exec.Command(
		"go",
		"build",
		"-ldflags",
		"-X main.version=0.0.0-test",
		"-o",
		testBinaryPath,
		"./cmd/crm",
	)
	build.Dir = projectRoot
	build.Env = replaceEnvironment(os.Environ(), "CGO_ENABLED", "0")
	if output, err := build.CombinedOutput(); err != nil {
		_ = os.RemoveAll(temporaryDirectory)
		panic(fmt.Sprintf("build integration-test binary: %v\n%s", err, output))
	}

	code := m.Run()
	if err := os.RemoveAll(temporaryDirectory); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "remove binary temp directory: %v\n", err)
		code = 1
	}
	os.Exit(code)
}

func crm(t *testing.T, databasePath string, args ...string) (string, string, int) {
	t.Helper()

	fullArgs := make([]string, 0, len(args)+2)
	fullArgs = append(fullArgs, "--db", databasePath)
	fullArgs = append(fullArgs, args...)

	return runCRM(t, fullArgs...)
}

func crmWithStdin(
	t *testing.T,
	databasePath string,
	stdin string,
	args ...string,
) (string, string, int) {
	t.Helper()

	fullArgs := make([]string, 0, len(args)+2)
	fullArgs = append(fullArgs, "--db", databasePath)
	fullArgs = append(fullArgs, args...)

	command := exec.Command(testBinaryPath, fullArgs...)
	command.Stdin = strings.NewReader(stdin)
	var stdout strings.Builder
	var stderr strings.Builder
	command.Stdout = &stdout
	command.Stderr = &stderr

	err := command.Run()
	code := 0
	if err != nil {
		var exitError *exec.ExitError
		if !errors.As(err, &exitError) {
			t.Fatalf("run crm with stdin: %v", err)
		}
		code = exitError.ExitCode()
	}

	return stdout.String(), stderr.String(), code
}

func runCRM(t *testing.T, args ...string) (string, string, int) {
	t.Helper()

	command := exec.Command(testBinaryPath, args...)
	var stdout strings.Builder
	var stderr strings.Builder
	command.Stdout = &stdout
	command.Stderr = &stderr

	err := command.Run()
	code := 0
	if err != nil {
		var exitError *exec.ExitError
		if !errors.As(err, &exitError) {
			t.Fatalf("run crm: %v", err)
		}
		code = exitError.ExitCode()
	}

	return stdout.String(), stderr.String(), code
}

func TestInit(t *testing.T) {
	temporaryDirectory := t.TempDir()
	databasePath := filepath.Join(temporaryDirectory, "crm.db")

	stdout, stderr, code := crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)

	transcriptDirectory := filepath.Join(
		temporaryDirectory,
		"transcripts",
		fmt.Sprintf("%d", time.Now().Year()),
	)
	if info, err := os.Stat(transcriptDirectory); err != nil || !info.IsDir() {
		t.Fatalf("transcript directory %s was not created: info=%v err=%v", transcriptDirectory, info, err)
	}
	readmePath := filepath.Join(temporaryDirectory, "README.md")
	readmeBefore, err := os.ReadFile(readmePath)
	if err != nil {
		t.Fatalf("read orientation README: %v", err)
	}
	if got := string(readmeBefore); got != orientationREADME {
		t.Fatalf("orientation README = %q, want %q", got, orientationREADME)
	}

	stdout, stderr, code = crm(t, databasePath, "init")
	assertCommandResult(t, stdout, stderr, code, databasePath+"\n", "", 0)
	readmeAfter, err := os.ReadFile(readmePath)
	if err != nil {
		t.Fatalf("read orientation README after second init: %v", err)
	}
	if string(readmeAfter) != string(readmeBefore) {
		t.Fatal("second init overwrote the orientation README")
	}

	backups, err := filepath.Glob(databasePath + ".pre-migrate-*")
	if err != nil {
		t.Fatalf("glob pre-migration copies: %v", err)
	}
	if len(backups) != 0 {
		t.Fatalf("fresh init created pre-migration copies: %v", backups)
	}

	assertInitializedDatabase(t, databasePath)
	assertNoSidecars(t, databasePath)
}

func TestVersionIsInjectedExactly(t *testing.T) {
	stdout, stderr, code := crm(t, filepath.Join(t.TempDir(), "absent.db"), "--version")
	assertCommandResult(t, stdout, stderr, code, "0.0.0-test\n", "", 0)
}

func TestUnknownCommandUsesErrorVoiceWithoutUsage(t *testing.T) {
	stdout, stderr, code := crm(
		t,
		filepath.Join(t.TempDir(), "absent.db"),
		"definitely-not-a-verb",
	)
	if code != 1 {
		t.Fatalf("exit code = %d, want 1; stderr=%q", code, stderr)
	}
	if stdout != "" {
		t.Fatalf("stdout = %q, want empty", stdout)
	}
	if !strings.HasPrefix(stderr, "crm: error:") {
		t.Fatalf("stderr = %q, want crm error prefix", stderr)
	}
	if strings.Contains(stderr, "Usage:") {
		t.Fatalf("stderr contains a usage dump: %q", stderr)
	}
}

func TestDatabasePathResolutionOrder(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	environmentPath := filepath.Join(t.TempDir(), "environment.db")
	t.Setenv("CRM_DB", environmentPath)
	flagPath := filepath.Join(t.TempDir(), "flag.db")

	paths, err := (&rootOptions{databasePath: flagPath}).resolvePaths()
	if err != nil {
		t.Fatalf("resolve flag path: %v", err)
	}
	if paths.database != flagPath {
		t.Fatalf("flag database path = %q, want %q", paths.database, flagPath)
	}
	if paths.base != filepath.Dir(flagPath) {
		t.Fatalf("flag base path = %q, want %q", paths.base, filepath.Dir(flagPath))
	}

	paths, err = (&rootOptions{}).resolvePaths()
	if err != nil {
		t.Fatalf("resolve environment path: %v", err)
	}
	if paths.database != environmentPath {
		t.Fatalf("environment database path = %q, want %q", paths.database, environmentPath)
	}

	t.Setenv("CRM_DB", "")
	paths, err = (&rootOptions{}).resolvePaths()
	if err != nil {
		t.Fatalf("resolve default path: %v", err)
	}
	wantDefault := filepath.Join(home, "mecattaf", "notes", "crm", "crm.db")
	if paths.database != wantDefault {
		t.Fatalf("default database path = %q, want %q", paths.database, wantDefault)
	}
}

func TestMissingDatabaseGuard(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "missing.db")
	err := (&rootOptions{databasePath: databasePath}).requireDatabase()
	if !errors.Is(err, model.ErrNotFound) {
		t.Fatalf("missing database error = %v, want ErrNotFound", err)
	}
	wantMessage := fmt.Sprintf("no database at %s (run 'crm init')", databasePath)
	if err.Error() != wantMessage {
		t.Fatalf("missing database error = %q, want %q", err, wantMessage)
	}
	if got := model.ExitCode(err); got != 2 {
		t.Fatalf("missing database exit code = %d, want 2", got)
	}
}

func assertInitializedDatabase(t *testing.T, databasePath string) {
	t.Helper()

	database, err := db.Open(databasePath)
	if err != nil {
		t.Fatalf("open initialized database through production funnel: %v", err)
	}

	var journalMode string
	if err := database.QueryRow("PRAGMA journal_mode").Scan(&journalMode); err != nil {
		_ = database.Close()
		t.Fatalf("read journal_mode: %v", err)
	}
	if journalMode != "delete" {
		_ = database.Close()
		t.Fatalf("journal_mode = %q, want %q", journalMode, "delete")
	}

	var userVersion int
	if err := database.QueryRow("PRAGMA user_version").Scan(&userVersion); err != nil {
		_ = database.Close()
		t.Fatalf("read user_version: %v", err)
	}
	if userVersion != 1 {
		_ = database.Close()
		t.Fatalf("user_version = %d, want 1", userVersion)
	}

	var foreignKeys int
	if err := database.QueryRow("PRAGMA foreign_keys").Scan(&foreignKeys); err != nil {
		_ = database.Close()
		t.Fatalf("read foreign_keys: %v", err)
	}
	if foreignKeys != 1 {
		_ = database.Close()
		t.Fatalf("foreign_keys = %d, want 1", foreignKeys)
	}
	if err := database.Close(); err != nil {
		t.Fatalf("close initialized database: %v", err)
	}
}

func assertNoSidecars(t *testing.T, databasePath string) {
	t.Helper()

	for _, suffix := range []string{"-wal", "-shm"} {
		sidecarPath := databasePath + suffix
		if _, err := os.Stat(sidecarPath); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("sidecar %s exists or could not be inspected: %v", sidecarPath, err)
		}
	}
}

func assertCommandResult(
	t *testing.T,
	stdout string,
	stderr string,
	code int,
	wantStdout string,
	wantStderr string,
	wantCode int,
) {
	t.Helper()

	if stdout != wantStdout {
		t.Fatalf("stdout = %q, want %q", stdout, wantStdout)
	}
	if stderr != wantStderr {
		t.Fatalf("stderr = %q, want %q", stderr, wantStderr)
	}
	if code != wantCode {
		t.Fatalf("exit code = %d, want %d", code, wantCode)
	}
}

func findProjectRoot() (string, error) {
	directory, err := os.Getwd()
	if err != nil {
		return "", err
	}

	for {
		if _, err := os.Stat(filepath.Join(directory, "go.mod")); err == nil {
			return directory, nil
		}
		parent := filepath.Dir(directory)
		if parent == directory {
			return "", os.ErrNotExist
		}
		directory = parent
	}
}

func replaceEnvironment(environment []string, key, value string) []string {
	prefix := key + "="
	replaced := make([]string, 0, len(environment)+1)
	for _, entry := range environment {
		if !strings.HasPrefix(entry, prefix) {
			replaced = append(replaced, entry)
		}
	}

	return append(replaced, prefix+value)
}
