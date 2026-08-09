package model

import (
	"net/mail"
	"net/url"
	"strings"
	"time"
	"unicode"

	"golang.org/x/text/cases"
	"golang.org/x/text/unicode/norm"
)

const dateLayout = "2006-01-02"

// NormalizeDate applies strict date normalization and rejects any value that
// is not a real calendar date written as YYYY-MM-DD.
func NormalizeDate(input string) (string, error) {
	if normalized, ok := TryNormalizeDate(input); ok {
		return normalized, nil
	}

	return "", NewExitError(ErrValidation, "invalid date %q (want YYYY-MM-DD)", input)
}

// TryNormalizeDate returns a canonical YYYY-MM-DD date when input is valid.
func TryNormalizeDate(input string) (string, bool) {
	trimmed := strings.TrimSpace(input)
	parsed, err := time.Parse(dateLayout, trimmed)
	if err != nil || parsed.Format(dateLayout) != trimmed {
		return "", false
	}

	return parsed.Format(dateLayout), true
}

// NormalizeEmail applies strict email normalization: syntactically invalid
// values are rejected and valid values are lowercased.
func NormalizeEmail(input string) (string, error) {
	if normalized, ok := TryNormalizeEmail(input); ok {
		return normalized, nil
	}

	return "", NewExitError(ErrValidation, "invalid email %q", input)
}

// TryNormalizeEmail returns a lowercase addr-spec when input contains exactly
// one email address without a display name.
func TryNormalizeEmail(input string) (string, bool) {
	trimmed := strings.TrimSpace(input)
	if trimmed == "" || strings.Count(trimmed, "@") != 1 {
		return "", false
	}

	parsed, err := mail.ParseAddress(trimmed)
	if err != nil || parsed.Name != "" || parsed.Address != trimmed {
		return "", false
	}

	local, domain, found := strings.Cut(parsed.Address, "@")
	if !found || local == "" || domain == "" {
		return "", false
	}

	return strings.ToLower(parsed.Address), true
}

// NormalizeWebsite applies permissive website normalization. Recognized HTTP
// URLs lose their scheme, query, fragment, www prefix, and root slash; an
// unrecognized value is preserved rather than rejected.
func NormalizeWebsite(input string) (string, error) {
	if normalized, ok := TryNormalizeWebsite(input); ok {
		return normalized, nil
	}

	return input, nil
}

// TryNormalizeWebsite returns a canonical host-and-path website when input is
// recognizable as an HTTP or HTTPS URL.
func TryNormalizeWebsite(input string) (string, bool) {
	trimmed := strings.TrimSpace(input)
	if trimmed == "" || strings.IndexFunc(trimmed, unicode.IsSpace) >= 0 {
		return "", false
	}

	parseable := trimmed
	if strings.HasPrefix(parseable, "//") {
		parseable = "https:" + parseable
	} else if !strings.Contains(parseable, "://") {
		parseable = "https://" + parseable
	}

	parsed, err := url.Parse(parseable)
	if err != nil || parsed.User != nil || parsed.Hostname() == "" {
		return "", false
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return "", false
	}

	host := strings.ToLower(parsed.Host)
	host = strings.TrimPrefix(host, "www.")
	path := parsed.EscapedPath()
	if path == "/" {
		path = ""
	}

	return host + path, true
}

// NormalizePhone applies permissive phone normalization. Plausible formatted
// numbers are reduced to digits with an optional leading plus; other values
// are preserved exactly.
func NormalizePhone(input string) (string, error) {
	if normalized, ok := TryNormalizePhone(input); ok {
		return normalized, nil
	}

	return input, nil
}

// TryNormalizePhone recognizes a conservative international-or-local phone
// shape without guessing a country code.
func TryNormalizePhone(input string) (string, bool) {
	trimmed := strings.TrimSpace(input)
	if trimmed == "" {
		return "", false
	}

	var normalized strings.Builder
	digits := 0
	for _, current := range trimmed {
		switch {
		case current >= '0' && current <= '9':
			normalized.WriteRune(current)
			digits++
		case current == '+' && normalized.Len() == 0 && digits == 0:
			normalized.WriteRune(current)
		case unicode.IsSpace(current) || strings.ContainsRune("-().", current):
			continue
		default:
			return "", false
		}
	}
	if digits < 7 || digits > 15 {
		return "", false
	}

	return normalized.String(), true
}

// NormalizeLocation applies permissive location normalization. Ordinary
// whitespace is collapsed; unusual control-bearing values are preserved.
func NormalizeLocation(input string) (string, error) {
	if normalized, ok := TryNormalizeLocation(input); ok {
		return normalized, nil
	}

	return input, nil
}

// TryNormalizeLocation returns a trimmed, single-spaced location when input
// contains printable text.
func TryNormalizeLocation(input string) (string, bool) {
	if strings.IndexFunc(input, unicode.IsControl) >= 0 {
		return "", false
	}

	fields := strings.Fields(input)
	if len(fields) == 0 {
		return "", false
	}

	return strings.Join(fields, " "), true
}

// NormalizeLinkedIn applies extract-tier normalization. LinkedIn profile and
// company URLs become bare handles, a leading @ is removed, and unrecognized
// input is retained as a best-effort value.
func NormalizeLinkedIn(input string) (string, error) {
	if normalized, ok := TryNormalizeLinkedIn(input); ok {
		return normalized, nil
	}

	return strings.TrimPrefix(strings.TrimSpace(input), "@"), nil
}

// TryNormalizeLinkedIn extracts a bare handle from known LinkedIn URL forms
// or recognizes an already-bare handle.
func TryNormalizeLinkedIn(input string) (string, bool) {
	trimmed := strings.TrimSpace(input)
	if trimmed == "" {
		return "", false
	}
	if strings.HasPrefix(trimmed, "@") {
		return recognizeLinkedInHandle(strings.TrimPrefix(trimmed, "@"))
	}

	parseable := trimmed
	lower := strings.ToLower(parseable)
	if strings.HasPrefix(lower, "linkedin.com/") || strings.HasPrefix(lower, "www.linkedin.com/") {
		parseable = "https://" + parseable
	}
	if parsed, err := url.Parse(parseable); err == nil && parsed.Hostname() != "" {
		host := strings.ToLower(parsed.Hostname())
		if host == "linkedin.com" || strings.HasSuffix(host, ".linkedin.com") {
			parts := strings.Split(strings.Trim(parsed.Path, "/"), "/")
			if len(parts) >= 2 && isLinkedInPathKind(parts[0]) {
				handle, unescapeErr := url.PathUnescape(parts[1])
				if unescapeErr == nil {
					return recognizeLinkedInHandle(handle)
				}
			}
			return "", false
		}
		if parsed.Scheme != "" {
			return "", false
		}
	}

	return recognizeLinkedInHandle(trimmed)
}

func isLinkedInPathKind(value string) bool {
	switch strings.ToLower(value) {
	case "in", "company", "school", "pub":
		return true
	default:
		return false
	}
}

func recognizeLinkedInHandle(input string) (string, bool) {
	if input == "" || strings.ContainsAny(input, "/?#") ||
		strings.IndexFunc(input, unicode.IsSpace) >= 0 {
		return "", false
	}

	return input, true
}

// NormalizeNameNorm applies the name_norm extract transform: NFKD
// decomposition, combining-mark removal, then Unicode case folding.
func NormalizeNameNorm(input string) (string, error) {
	normalized, _ := TryNormalizeNameNorm(input)

	return normalized, nil
}

// TryNormalizeNameNorm returns the name_norm form and reports whether the
// result contains any non-whitespace text.
func TryNormalizeNameNorm(input string) (string, bool) {
	decomposed := norm.NFKD.String(input)
	var withoutMarks strings.Builder
	withoutMarks.Grow(len(decomposed))
	for _, current := range decomposed {
		if unicode.Is(unicode.Mn, current) {
			continue
		}
		withoutMarks.WriteRune(current)
	}

	normalized := cases.Fold().String(withoutMarks.String())
	return normalized, strings.TrimSpace(normalized) != ""
}

// NormalizeName is a convenience alias for the name_norm transform.
func NormalizeName(input string) (string, error) {
	return NormalizeNameNorm(input)
}

// TryNormalizeName is a convenience alias for the name_norm transform.
func TryNormalizeName(input string) (string, bool) {
	return TryNormalizeNameNorm(input)
}
