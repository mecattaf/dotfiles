package model

import (
	"math"
	"slices"
	"testing"
)

func TestNameSimilarityUsesRunesAndTheStrongerMetric(t *testing.T) {
	t.Parallel()

	if got, want := nameSimilarity("😀a", "😀b"), 0.5; math.Abs(got-want) > 1e-9 {
		t.Fatalf("rune name similarity = %v, want %v", got, want)
	}
	if got, want := nameSimilarity("acme", "acme inc"), 0.6; math.Abs(got-want) > 1e-9 {
		t.Fatalf("Dice-backed name similarity = %v, want %v", got, want)
	}
}

func TestContactDuplicateScoreUsesNamedWeightedReasons(t *testing.T) {
	t.Parallel()

	leftEmail := "alice@kima.vc"
	rightEmail := "a.martin@kima.vc"
	score, reasons := ContactDuplicateScore(
		Contact{NameNorm: "alice martin", Email: &leftEmail},
		Contact{NameNorm: "alice martin", Email: &rightEmail},
	)
	if got, want := score, 1.0; got != want {
		t.Fatalf("contact duplicate score = %v, want capped %v", got, want)
	}
	wantReasons := []string{"identical name_norm", "similar name", "shared email domain"}
	if !slices.Equal(reasons, wantReasons) {
		t.Fatalf("contact duplicate reasons = %v, want %v", reasons, wantReasons)
	}
}

func TestContactDuplicateScoreExcludesFreeMailDomains(t *testing.T) {
	t.Parallel()

	providers := []string{"gmail.com", "yahoo.com", "hotmail.com", "outlook.com"}
	for _, provider := range providers {
		provider := provider
		t.Run(provider, func(t *testing.T) {
			t.Parallel()

			leftEmail := "alice@" + provider
			rightEmail := "bob@" + provider
			score, reasons := ContactDuplicateScore(
				Contact{NameNorm: "alice", Email: &leftEmail},
				Contact{NameNorm: "bob", Email: &rightEmail},
			)
			if score != 0 || len(reasons) != 0 {
				t.Fatalf("free-mail-only score = %v, reasons = %v; want 0, []", score, reasons)
			}
		})
	}
}

func TestOrgDuplicateScoreUsesRegistrableWebsiteDomain(t *testing.T) {
	t.Parallel()

	leftWebsite := "sales.example.co.uk/team"
	rightWebsite := "https://support.example.co.uk"
	score, reasons := OrgDuplicateScore(
		Org{NameNorm: "alpha", Website: &leftWebsite},
		Org{NameNorm: "zulu", Website: &rightWebsite},
	)
	if got, want := score, 0.2; got != want {
		t.Fatalf("organization duplicate score = %v, want %v", got, want)
	}
	wantReasons := []string{"same registrable website domain"}
	if !slices.Equal(reasons, wantReasons) {
		t.Fatalf("organization duplicate reasons = %v, want %v", reasons, wantReasons)
	}
}
