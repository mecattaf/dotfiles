package model

import (
	"net/url"
	"slices"
	"strings"

	"golang.org/x/net/publicsuffix"
)

const similarNameThreshold = 0.6

const (
	identicalNameReason = "identical name_norm"
	similarNameReason   = "similar name"
	sharedEmailReason   = "shared email domain"
	sameWebsiteReason   = "same registrable website domain"
)

var freeEmailDomains = []string{
	"gmail.com",
	"yahoo.com",
	"hotmail.com",
	"outlook.com",
}

// DupeTypes is the accepted crm dupes entity filter set.
var DupeTypes = []string{"contact", "org"}

// ValidDupeType reports whether value names a supported duplicate entity.
func ValidDupeType(value string) bool {
	return slices.Contains(DupeTypes, value)
}

// DupeFilters controls advisory duplicate pair generation.
type DupeFilters struct {
	Type      string
	Threshold float64
	Limit     int
}

// DupeResult is one auditable duplicate candidate pair. Left and Right hold
// complete contact or organization records, whose refs identify their type.
type DupeResult struct {
	Left    any      `json:"left"`
	Right   any      `json:"right"`
	Score   float64  `json:"score"`
	Reasons []string `json:"reasons"`
}

// ContactDuplicateScore returns a capped weighted score and its named
// reasons. It operates on canonical name_norm and email values as stored.
func ContactDuplicateScore(left, right Contact) (float64, []string) {
	reasons := make([]string, 0, 3)
	points := 0
	if left.NameNorm != "" && left.NameNorm == right.NameNorm {
		reasons = append(reasons, identicalNameReason)
		points += 50
	}
	if nameSimilarity(left.NameNorm, right.NameNorm) >= similarNameThreshold {
		reasons = append(reasons, similarNameReason)
		points += 40
	}
	leftDomain := emailDomain(left.Email)
	rightDomain := emailDomain(right.Email)
	if leftDomain != "" && leftDomain == rightDomain && !slices.Contains(freeEmailDomains, leftDomain) {
		reasons = append(reasons, sharedEmailReason)
		points += 15
	}

	return float64(min(points, 100)) / 100, reasons
}

// OrgDuplicateScore returns a capped weighted score and its named reasons.
// Website matching compares effective registrable domains, not raw hosts.
func OrgDuplicateScore(left, right Org) (float64, []string) {
	reasons := make([]string, 0, 2)
	points := 0
	if nameSimilarity(left.NameNorm, right.NameNorm) >= similarNameThreshold {
		reasons = append(reasons, similarNameReason)
		points += 40
	}
	leftDomain := registrableWebsiteDomain(left.Website)
	rightDomain := registrableWebsiteDomain(right.Website)
	if leftDomain != "" && leftDomain == rightDomain {
		reasons = append(reasons, sameWebsiteReason)
		points += 20
	}

	return float64(min(points, 100)) / 100, reasons
}

func nameSimilarity(left, right string) float64 {
	leftRunes := []rune(left)
	rightRunes := []rune(right)
	maximumLength := max(len(leftRunes), len(rightRunes))
	levenshteinSimilarity := 0.0
	if maximumLength > 0 {
		levenshteinSimilarity = 1 - float64(levenshteinDistance(leftRunes, rightRunes))/float64(maximumLength)
	}

	return max(levenshteinSimilarity, diceBigramCoefficient(leftRunes, rightRunes))
}

func levenshteinDistance(left, right []rune) int {
	previous := make([]int, len(right)+1)
	current := make([]int, len(right)+1)
	for index := range previous {
		previous[index] = index
	}

	for leftIndex, leftRune := range left {
		current[0] = leftIndex + 1
		for rightIndex, rightRune := range right {
			substitution := previous[rightIndex]
			if leftRune != rightRune {
				substitution++
			}
			current[rightIndex+1] = min(
				previous[rightIndex+1]+1,
				current[rightIndex]+1,
				substitution,
			)
		}
		previous, current = current, previous
	}

	return previous[len(right)]
}

func diceBigramCoefficient(left, right []rune) float64 {
	if slices.Equal(left, right) {
		if len(left) == 0 {
			return 0
		}

		return 1
	}
	if len(left) < 2 || len(right) < 2 {
		return 0
	}

	leftBigrams := runeBigrams(left)
	rightBigrams := runeBigrams(right)
	overlap := 0
	for bigram, count := range leftBigrams {
		overlap += min(count, rightBigrams[bigram])
	}

	return float64(2*overlap) / float64(len(left)-1+len(right)-1)
}

func runeBigrams(value []rune) map[[2]rune]int {
	bigrams := make(map[[2]rune]int, len(value)-1)
	for index := 0; index < len(value)-1; index++ {
		bigram := [2]rune{value[index], value[index+1]}
		bigrams[bigram]++
	}

	return bigrams
}

func emailDomain(email *string) string {
	if email == nil {
		return ""
	}
	_, domain, found := strings.Cut(*email, "@")
	if !found || domain == "" || strings.Contains(domain, "@") {
		return ""
	}

	return strings.ToLower(domain)
}

func registrableWebsiteDomain(website *string) string {
	if website == nil {
		return ""
	}
	normalized, ok := TryNormalizeWebsite(*website)
	if !ok {
		return ""
	}
	parsed, err := url.Parse("https://" + normalized)
	if err != nil {
		return ""
	}
	host := strings.TrimSuffix(strings.ToLower(parsed.Hostname()), ".")
	registrable, err := publicsuffix.EffectiveTLDPlusOne(host)
	if err != nil {
		return ""
	}

	return registrable
}
