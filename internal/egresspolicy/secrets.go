package egresspolicy

import (
	"math"
	"regexp"
	"strings"
)

// minSecretLen ignores exact-match values too short to be a real credential (and
// prone to false positives).
const minSecretLen = 8

// entropy heuristic thresholds: a contiguous token must be at least this long,
// carry both letters and digits, and exceed this Shannon entropy to be flagged.
const (
	entropyMinTokenLen = 24
	entropyBitsPerChar = 4.0
)

// knownSecretPatterns match common credential shapes regardless of value.
var knownSecretPatterns = []*regexp.Regexp{
	regexp.MustCompile(`sk-[A-Za-z0-9_-]{16,}`),         // OpenAI / Anthropic sk-ant-…
	regexp.MustCompile(`AKIA[0-9A-Z]{16}`),              // AWS access key id
	regexp.MustCompile(`gh[pousr]_[A-Za-z0-9]{20,}`),    // GitHub tokens
	regexp.MustCompile(`xox[baprs]-[A-Za-z0-9-]{10,}`),  // Slack tokens
	regexp.MustCompile(`-----BEGIN [A-Z ]*PRIVATE KEY`), // PEM private keys
}

// scanner detects secrets in a text haystack via three optional detectors:
// exact user secret values, generic credential-shape patterns, and a
// high-entropy-token heuristic.
type scanner struct {
	secrets  []string // exact values (len >= minSecretLen), matched case-sensitively
	patterns bool
	entropy  bool
}

func newScanner(secrets []string, patterns, entropy bool) *scanner {
	s := &scanner{patterns: patterns, entropy: entropy}
	for _, v := range secrets {
		if len(strings.TrimSpace(v)) >= minSecretLen {
			s.secrets = append(s.secrets, v)
		}
	}
	return s
}

// active reports whether any detector is configured.
func (s *scanner) active() bool { return len(s.secrets) > 0 || s.patterns || s.entropy }

// hit reports whether hay carries a secret per the enabled detectors.
func (s *scanner) hit(hay string) bool {
	if hay == "" {
		return false
	}
	for _, v := range s.secrets {
		if strings.Contains(hay, v) {
			return true
		}
	}
	if s.patterns {
		for _, re := range knownSecretPatterns {
			if re.MatchString(hay) {
				return true
			}
		}
	}
	return s.entropy && hasHighEntropyToken(hay)
}

// hasHighEntropyToken reports whether hay contains a long, mixed, high-entropy
// token — the shape of an encoded credential, not of ordinary prose or paths.
func hasHighEntropyToken(hay string) bool {
	for _, tok := range tokenize(hay) {
		if len(tok) >= entropyMinTokenLen && mixedClasses(tok) && shannon(tok) >= entropyBitsPerChar {
			return true
		}
	}
	return false
}

// tokenize splits on characters outside a credential-ish alphabet, so slugs and
// prose break into short tokens while base64/hex secrets stay contiguous.
func tokenize(s string) []string {
	return strings.FieldsFunc(s, func(r rune) bool {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
			return false
		case r == '+' || r == '/' || r == '=' || r == '_' || r == '-':
			return false
		}
		return true
	})
}

func mixedClasses(s string) bool {
	var hasLetter, hasDigit bool
	for _, r := range s {
		switch {
		case r >= '0' && r <= '9':
			hasDigit = true
		case (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z'):
			hasLetter = true
		}
	}
	return hasLetter && hasDigit
}

// shannon returns the Shannon entropy of s in bits per byte.
func shannon(s string) float64 {
	if s == "" {
		return 0
	}
	var freq [256]float64
	for i := 0; i < len(s); i++ {
		freq[s[i]]++
	}
	n := float64(len(s))
	var h float64
	for _, c := range freq {
		if c == 0 {
			continue
		}
		p := c / n
		h -= p * math.Log2(p)
	}
	return h
}
