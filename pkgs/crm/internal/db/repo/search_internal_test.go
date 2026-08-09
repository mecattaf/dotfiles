package repo

import "testing"

func TestBuildFTSQueryEscapesEachTokenAndPrefixesOnlyTheLast(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name  string
		input string
		want  string
	}{
		{name: "multiple tokens", input: "nick kima", want: `"nick" "kima"*`},
		{name: "fts punctuation", input: "nick@kima.vc a-b:c", want: `"nick@kima.vc" "a-b:c"*`},
		{name: "inner quotes", input: `say "hello"`, want: `"say" """hello"""*`},
		{name: "unicode whitespace", input: "  Léger\tParis  ", want: `"Léger" "Paris"*`},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			got, err := buildFTSQuery(test.input)
			if err != nil {
				t.Fatalf("build FTS query: %v", err)
			}
			if got != test.want {
				t.Fatalf("FTS query = %q, want %q", got, test.want)
			}
		})
	}
}

func TestBuildFTSQueryRejectsWhitespaceOnlyInput(t *testing.T) {
	t.Parallel()

	if _, err := buildFTSQuery(" \t\n "); err == nil {
		t.Fatal("whitespace-only FTS query succeeded")
	}
}
