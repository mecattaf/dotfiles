package model

import (
	"errors"
	"testing"
)

func TestStrictNormalizers(t *testing.T) {
	t.Parallel()

	date, err := NormalizeDate(" 2026-07-31 ")
	if err != nil || date != "2026-07-31" {
		t.Fatalf("NormalizeDate() = %q, %v", date, err)
	}
	if _, err := NormalizeDate("2026-02-30"); !errors.Is(err, ErrValidation) {
		t.Fatalf("NormalizeDate() error = %v, want validation", err)
	}
	if _, ok := TryNormalizeDate("31/07/2026"); ok {
		t.Fatal("TryNormalizeDate() accepted a non-ISO date")
	}

	email, err := NormalizeEmail(" Nick.Dupont@KIMA.VC ")
	if err != nil || email != "nick.dupont@kima.vc" {
		t.Fatalf("NormalizeEmail() = %q, %v", email, err)
	}
	for _, invalid := range []string{"", "Nick <nick@kima.vc>", "not-an-email"} {
		if _, err := NormalizeEmail(invalid); !errors.Is(err, ErrValidation) {
			t.Fatalf("NormalizeEmail(%q) error = %v, want validation", invalid, err)
		}
		if _, ok := TryNormalizeEmail(invalid); ok {
			t.Fatalf("TryNormalizeEmail(%q) unexpectedly succeeded", invalid)
		}
	}
}

func TestPermissiveNormalizers(t *testing.T) {
	t.Parallel()

	website, err := NormalizeWebsite("https://www.ACME.COM/Labs?from=crm#team")
	if err != nil || website != "acme.com/Labs" {
		t.Fatalf("NormalizeWebsite() = %q, %v", website, err)
	}
	if got, ok := TryNormalizeWebsite("kima.vc/"); !ok || got != "kima.vc" {
		t.Fatalf("TryNormalizeWebsite() = %q, %v, want kima.vc, true", got, ok)
	}
	weirdWebsite := "not a website value"
	website, err = NormalizeWebsite(weirdWebsite)
	if err != nil || website != weirdWebsite {
		t.Fatalf("permissive NormalizeWebsite() = %q, %v", website, err)
	}
	if _, ok := TryNormalizeWebsite(weirdWebsite); ok {
		t.Fatal("TryNormalizeWebsite() recognized malformed input")
	}

	phone, err := NormalizePhone("+33 (0)6 12-34-56-78")
	if err != nil || phone != "+330612345678" {
		t.Fatalf("NormalizePhone() = %q, %v", phone, err)
	}
	weirdPhone := "ask for the office line"
	phone, err = NormalizePhone(weirdPhone)
	if err != nil || phone != weirdPhone {
		t.Fatalf("permissive NormalizePhone() = %q, %v", phone, err)
	}

	location, err := NormalizeLocation("  Paris,   France  ")
	if err != nil || location != "Paris, France" {
		t.Fatalf("NormalizeLocation() = %q, %v", location, err)
	}
	weirdLocation := "Paris\nFrance"
	location, err = NormalizeLocation(weirdLocation)
	if err != nil || location != weirdLocation {
		t.Fatalf("permissive NormalizeLocation() = %q, %v", location, err)
	}
}

func TestExtractNormalizers(t *testing.T) {
	t.Parallel()

	tests := []struct {
		input string
		want  string
	}{
		{input: "https://www.linkedin.com/in/nickdupont/?trk=profile", want: "nickdupont"},
		{input: "linkedin.com/company/kima-ventures/", want: "kima-ventures"},
		{input: "@leger-capital", want: "leger-capital"},
		{input: "bare-handle", want: "bare-handle"},
	}
	for _, test := range tests {
		normalized, err := NormalizeLinkedIn(test.input)
		if err != nil || normalized != test.want {
			t.Fatalf("NormalizeLinkedIn(%q) = %q, %v, want %q", test.input, normalized, err, test.want)
		}
	}

	unknown := "https://example.com/not-linkedin"
	normalized, err := NormalizeLinkedIn(unknown)
	if err != nil || normalized != unknown {
		t.Fatalf("extract fallback = %q, %v", normalized, err)
	}
	if _, ok := TryNormalizeLinkedIn(unknown); ok {
		t.Fatal("TryNormalizeLinkedIn() recognized a non-LinkedIn URL")
	}

	nameNorm, err := NormalizeName("Léger Straße")
	if err != nil || nameNorm != "leger strasse" {
		t.Fatalf("NormalizeName() = %q, %v", nameNorm, err)
	}
	decomposed, ok := TryNormalizeNameNorm("Le\u0301ger")
	if !ok || decomposed != "leger" {
		t.Fatalf("TryNormalizeNameNorm() = %q, %v", decomposed, ok)
	}
	if _, ok := TryNormalizeName("   "); ok {
		t.Fatal("TryNormalizeName() reported an empty name as usable")
	}
}
