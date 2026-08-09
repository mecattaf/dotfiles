package cli

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDocumentedCompositionRecipes(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "crm.db")
	commands := [][]string{
		{"init"},
		{"org", "add", "Kima Ventures"},
		{"contact", "add", "Nick Dupont", "--org", "o1", "--email", "nick@kima.vc"},
		{"contact", "add", "No Email", "--org", "o1"},
		{"log", "--kind", "note", "--with", "c1", "--org", "o1", "--summary", "Kima update"},
		{"pipeline", "add", "Seed raise"},
		{"stage", "add", "p1", "sourced", "--rot", "1"},
		{"deal", "add", "Kima seed round", "--pipeline", "p1", "--org", "o1"},
	}
	for _, arguments := range commands {
		stdout, stderr, code := crm(t, databasePath, arguments...)
		if stderr != "" || code != 0 {
			t.Fatalf("fixture crm %v stdout=%q stderr=%q code=%d", arguments, stdout, stderr, code)
		}
	}
	backdateDealStage(t, databasePath, "d1", 5*24*time.Hour)

	tests := []struct {
		name       string
		recipe     string
		wantOutput []string
		exact      string
	}{
		{
			name:       "find ids into polymorphic show",
			recipe:     `crm find kima --format ids | xargs -n1 crm show`,
			wantOutput: []string{`"ref":"o1"`, `"ref":"c1"`, `"ref":"i1"`, `"ref":"d1"`},
		},
		{
			name:       "stale ids into context",
			recipe:     `crm stale --days 60 --format ids | xargs -n1 crm context`,
			wantOutput: []string{`"ref":"c2"`, `"name":"No Email"`},
		},
		{
			name:   "JSON null-email selection",
			recipe: `crm contact ls --format json | jq -r '.[] | select(.email == null) | .ref'`,
			exact:  "c2\n",
		},
		{
			name:       "rotting deal ids into deal show",
			recipe:     `crm deal ls --rotting --format ids | xargs -n1 crm deal show`,
			wantOutput: []string{`"ref":"d1"`, `"title":"Kima seed round"`},
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			stdout, stderr, code := runCompositionRecipe(t, databasePath, test.recipe)
			if code != 0 || stderr != "" {
				t.Fatalf("recipe %q stdout=%q stderr=%q code=%d", test.recipe, stdout, stderr, code)
			}
			if test.exact != "" && stdout != test.exact {
				t.Fatalf("recipe %q stdout=%q, want %q", test.recipe, stdout, test.exact)
			}
			for _, wanted := range test.wantOutput {
				if !strings.Contains(stdout, wanted) {
					t.Errorf("recipe %q stdout %q omits %q", test.recipe, stdout, wanted)
				}
			}
		})
	}
	assertNoSidecars(t, databasePath)
}

func runCompositionRecipe(
	t *testing.T,
	databasePath string,
	recipe string,
) (string, string, int) {
	t.Helper()
	command := exec.Command("sh", "-c", recipe)
	environment := replaceEnvironment(os.Environ(), "CRM_DB", databasePath)
	environment = replaceEnvironment(environment, "CRM_POST_WRITE_HOOK", "")
	environment = replaceEnvironment(
		environment,
		"PATH",
		filepath.Dir(testBinaryPath)+string(os.PathListSeparator)+os.Getenv("PATH"),
	)
	command.Env = environment
	var stdout strings.Builder
	var stderr strings.Builder
	command.Stdout = &stdout
	command.Stderr = &stderr

	err := command.Run()
	code := 0
	if err != nil {
		var exitError *exec.ExitError
		if !errors.As(err, &exitError) {
			t.Fatalf("run composition recipe %q: %v", recipe, err)
		}
		code = exitError.ExitCode()
	}

	return stdout.String(), stderr.String(), code
}
