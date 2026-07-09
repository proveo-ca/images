package egresspolicy

import (
	"math"
	"testing"
)

func TestScannerExactAndInactive(t *testing.T) {
	t.Parallel()

	if newScanner(nil, false, false).active() {
		t.Error("scanner with no detectors must be inactive")
	}
	// A value shorter than minSecretLen is ignored (too FP-prone).
	if newScanner([]string{"short"}, false, false).active() {
		t.Error("sub-minSecretLen exact value must not activate the scanner")
	}

	s := newScanner([]string{"sk-ant-SECRETKEY-123456"}, false, false)
	if !s.hit("prefix sk-ant-SECRETKEY-123456 suffix") {
		t.Error("exact secret substring must hit")
	}
	if s.hit("nothing to see here") {
		t.Error("unrelated text must not hit")
	}
}

func TestScannerPatterns(t *testing.T) {
	t.Parallel()
	s := newScanner(nil, true, false)
	hits := []string{
		"sk-ABCDEFGHIJKLMNOPQRST",
		"AKIAIOSFODNN7EXAMPLE",
		"ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345",
		"xoxb-1234567890-abcdefghijkl",
		"-----BEGIN RSA PRIVATE KEY-----",
	}
	for _, h := range hits {
		if !s.hit(h) {
			t.Errorf("pattern scanner should hit %q", h)
		}
	}
	if s.hit("just a normal sentence with words") {
		t.Error("prose must not match any credential pattern")
	}
	// Patterns disabled => no hit.
	if newScanner(nil, false, false).hit("sk-ABCDEFGHIJKLMNOPQRST") {
		t.Error("pattern hit while BlockKnownSecrets disabled")
	}
}

func TestScannerEntropy(t *testing.T) {
	t.Parallel()
	s := newScanner(nil, false, true)

	if !s.hit("token=dGhpc2lzYVZlcnlMb25nQmFzZTY0U2VjcmV0MTIzNDU2Nzg5MA") {
		t.Error("long mixed high-entropy token should hit")
	}
	for _, benign := range []string{
		"the quick brown fox jumps over the lazy dog again",
		"https://docs.example.com/getting-started/configuration-guide",
		"search?q=how+to+configure+the+egress+proxy+for+local+models",
	} {
		if s.hit(benign) {
			t.Errorf("benign text must not trip the entropy heuristic: %q", benign)
		}
	}
	// Entropy disabled => no hit even on a high-entropy blob.
	if newScanner(nil, false, false).hit("dGhpc2lzYVZlcnlMb25nQmFzZTY0U2VjcmV0MTIzNDU2Nzg5MA") {
		t.Error("entropy hit while BlockEntropy disabled")
	}
}

func TestShannon(t *testing.T) {
	t.Parallel()
	if got := shannon(""); got != 0 {
		t.Errorf("shannon(\"\") = %v, want 0", got)
	}
	if got := shannon("aaaaaaaa"); got != 0 {
		t.Errorf("shannon(uniform) = %v, want 0", got)
	}
	// Four equiprobable symbols => 2 bits/char.
	if got := shannon("abcdabcdabcd"); math.Abs(got-2.0) > 1e-9 {
		t.Errorf("shannon(4-symbol uniform) = %v, want 2.0", got)
	}
}

func TestMixedClasses(t *testing.T) {
	t.Parallel()
	cases := map[string]bool{
		"abcDEF123":   true,
		"onlyletters": false,
		"12345678":    false,
		"a1":          true,
	}
	for in, want := range cases {
		if got := mixedClasses(in); got != want {
			t.Errorf("mixedClasses(%q) = %v, want %v", in, got, want)
		}
	}
}
