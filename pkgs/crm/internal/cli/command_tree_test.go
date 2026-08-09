package cli

import (
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"

	crmformat "github.com/mecattaf/crm/internal/format"
	"github.com/mecattaf/crm/internal/model"
	"github.com/spf13/cobra"
)

func TestCommandTreeDocumentationContract(t *testing.T) {
	root := NewRootCmd("test")
	projectRoot, err := findProjectRoot()
	if err != nil {
		t.Fatalf("find project root: %v", err)
	}
	skillBytes, err := os.ReadFile(filepath.Join(projectRoot, "skills", "crm", "SKILL.md"))
	if err != nil {
		t.Fatalf("read crm skill: %v", err)
	}
	skill := string(skillBytes)

	mutationEntities := map[string]string{
		"init":                  "database",
		"log":                   "interaction",
		"org add":               "org",
		"org edit":              "org",
		"org merge":             "org",
		"org archive":           "org",
		"org unarchive":         "org",
		"org delete":            "org",
		"contact add":           "contact",
		"contact edit":          "contact",
		"contact merge":         "contact",
		"contact relate":        "contact",
		"contact unrelate":      "contact",
		"contact archive":       "contact",
		"contact unarchive":     "contact",
		"contact delete":        "contact",
		"import contacts":       "contact",
		"import orgs":           "org",
		"interaction edit":      "interaction",
		"interaction archive":   "interaction",
		"interaction unarchive": "interaction",
		"interaction delete":    "interaction",
		"pipeline add":          "pipeline",
		"pipeline rename":       "pipeline",
		"pipeline archive":      "pipeline",
		"pipeline unarchive":    "pipeline",
		"pipeline delete":       "pipeline",
		"stage add":             "stage",
		"stage rename":          "stage",
		"stage reorder":         "stage",
		"stage set-rot":         "stage",
		"stage archive":         "stage",
		"stage unarchive":       "stage",
		"stage delete":          "stage",
		"deal add":              "deal",
		"deal edit":             "deal",
		"deal move":             "deal",
		"deal win":              "deal",
		"deal lose":             "deal",
		"deal reopen":           "deal",
		"deal archive":          "deal",
		"deal unarchive":        "deal",
		"deal delete":           "deal",
	}
	enumFlags := map[string]map[string][]string{
		"log": {
			"kind": model.InteractionKinds,
		},
		"interaction ls": {
			"kind": model.InteractionKinds,
		},
		"interaction edit": {
			"kind": model.InteractionKinds,
		},
		"find": {
			"type": model.FindTypes,
		},
		"stale": {
			"type": model.StaleTypes,
		},
		"dupes": {
			"type": model.DupeTypes,
		},
		"deal ls": {
			"status": model.DealStatuses,
		},
	}

	walkLeafCommands(root, func(command *cobra.Command) {
		path := strings.TrimPrefix(command.CommandPath(), root.Name()+" ")
		if strings.TrimSpace(command.Example) == "" {
			t.Errorf("leaf command %q has an empty Example block", path)
		}
		if !strings.Contains(skill, "crm "+path) {
			t.Errorf("leaf command %q has no runnable example in skills/crm/SKILL.md", path)
		}

		wantMutationEntity := mutationEntities[path]
		if got := command.Annotations[postWriteEntityAnnotation]; got != wantMutationEntity {
			t.Errorf("leaf command %q post-write entity = %q, want %q", path, got, wantMutationEntity)
		}
		delete(mutationEntities, path)

		for flagName, values := range enumFlags[path] {
			assertFlagHelpUsesValues(t, command, flagName, values)
		}
		if command.Flags().Lookup("format") != nil {
			formats := crmformat.EntityFormats()
			switch path {
			case "context":
				formats = crmformat.ContextFormats()
			case "status":
				formats = statusFormats()
			case "doctor":
				formats = crmformat.DoctorFormats()
			case "dupes":
				formats = dupeFormats()
			case "export orgs", "export contacts", "export deals", "export interactions":
				formats = crmformat.ExportFormats()
			case "export all":
				formats = crmformat.ExportAllFormats()
			}
			values := make([]string, len(formats))
			for index, format := range formats {
				values[index] = string(format)
			}
			assertFlagHelpUsesValues(t, command, "format", values)
		}
	})
	if len(mutationEntities) != 0 {
		t.Fatalf("mutation commands missing from tree: %v", mutationEntities)
	}

	assertCommandAliases(t, root, "org", []string{"o", "orgs"})
	assertCommandAliases(t, root, "contact", []string{"c", "contacts"})
	assertCommandAliases(t, root, "interaction", []string{"i", "interactions"})
	assertCommandAliases(t, root, "pipeline", []string{"p", "pipelines"})
	assertCommandAliases(t, root, "deal", []string{"d", "deals"})
	assertCommandAliases(t, root, "stage", []string{"stages"})
	for _, noun := range []string{"org", "contact", "interaction", "pipeline", "deal"} {
		assertCommandAliases(t, root, noun+" ls", []string{"list"})
	}
}

func TestLeafHelpRendersExampleBlock(t *testing.T) {
	stdout, stderr, code := crm(
		t,
		filepath.Join(t.TempDir(), "missing.db"),
		"org", "add", "--help",
	)
	if code != 0 || stderr != "" {
		t.Fatalf("org add help stdout=%q stderr=%q code=%d", stdout, stderr, code)
	}
	if !strings.Contains(stdout, "Example:") {
		t.Fatalf("org add help omits Example block: %q", stdout)
	}
}

func walkLeafCommands(command *cobra.Command, visit func(*cobra.Command)) {
	children := command.Commands()
	if len(children) == 0 {
		visit(command)

		return
	}
	for _, child := range children {
		walkLeafCommands(child, visit)
	}
}

func assertFlagHelpUsesValues(
	t *testing.T,
	command *cobra.Command,
	flagName string,
	values []string,
) {
	t.Helper()
	flag := command.Flags().Lookup(flagName)
	if flag == nil {
		t.Errorf("command %q has no --%s flag", command.CommandPath(), flagName)

		return
	}
	for _, value := range values {
		if !strings.Contains(flag.Usage, value) {
			t.Errorf(
				"command %q --%s help %q omits enum value %q",
				command.CommandPath(),
				flagName,
				flag.Usage,
				value,
			)
		}
	}
}

func assertCommandAliases(
	t *testing.T,
	root *cobra.Command,
	path string,
	want []string,
) {
	t.Helper()
	command := commandAtPath(t, root, strings.Fields(path)...)
	got := append([]string(nil), command.Aliases...)
	sort.Strings(got)
	want = append([]string(nil), want...)
	sort.Strings(want)
	if !reflect.DeepEqual(got, want) {
		t.Errorf("command %q aliases = %v, want %v", path, got, want)
	}
}

func commandAtPath(t *testing.T, root *cobra.Command, path ...string) *cobra.Command {
	t.Helper()
	current := root
	for _, part := range path {
		var next *cobra.Command
		for _, child := range current.Commands() {
			if child.Name() == part {
				next = child
				break
			}
		}
		if next == nil {
			t.Fatalf("command path %q not found", strings.Join(path, " "))
		}
		current = next
	}

	return current
}
