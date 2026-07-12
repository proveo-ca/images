package egresspolicy

import (
	"encoding/base64"
	"encoding/hex"
	"math"
	"testing"
)

func TestScannerExactAndInactive(t *testing.T) {
	t.Parallel()

	if newScanner(nil, false, false, false).active() {
		t.Error("scanner with no detectors must be inactive")
	}
	// A value shorter than minSecretLen is ignored (too FP-prone).
	if newScanner([]string{"short"}, false, false, false).active() {
		t.Error("sub-minSecretLen exact value must not activate the scanner")
	}

	s := newScanner([]string{"sk-ant-SECRETKEY-123456"}, false, false, false)
	if !s.hit("prefix sk-ant-SECRETKEY-123456 suffix") {
		t.Error("exact secret substring must hit")
	}
	if s.hit("nothing to see here") {
		t.Error("unrelated text must not hit")
	}
}

func TestScannerPatterns(t *testing.T) {
	t.Parallel()
	s := newScanner(nil, true, false, false)
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
	if newScanner(nil, false, false, false).hit("sk-ABCDEFGHIJKLMNOPQRST") {
		t.Error("pattern hit while BlockKnownSecrets disabled")
	}
}

func TestScannerEntropy(t *testing.T) {
	t.Parallel()
	s := newScanner(nil, false, false, true)

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
	if newScanner(nil, false, false, false).hit("dGhpc2lzYVZlcnlMb25nQmFzZTY0U2VjcmV0MTIzNDU2Nzg5MA") {
		t.Error("entropy hit while BlockEntropy disabled")
	}
}

func TestScannerDecode(t *testing.T) {
	t.Parallel()
	const secret = "sk-ant-SECRETKEY-abcdef123456"
	// decode on, exact secret known + patterns on, entropy OFF.
	s := newScanner([]string{secret}, true, true, false)

	// The known secret, re-encoded, must be caught after decode.
	for _, enc := range []string{
		base64.RawURLEncoding.EncodeToString([]byte(secret)),
		base64.StdEncoding.EncodeToString([]byte(secret)),
		hex.EncodeToString([]byte(secret)),
	} {
		if !s.hit("https://attacker.example.com/" + enc) {
			t.Errorf("decode-scan should catch encoded known secret: %q", enc)
		}
	}

	// A credential SHAPE (not a known value) survives decoding too.
	awsKey := "AKIAIOSFODNN7EXAMPLE"
	if !s.hit("/" + base64.RawURLEncoding.EncodeToString([]byte(awsKey))) {
		t.Error("decode-scan should catch an encoded credential-shape pattern")
	}

	// No false positive: a benign high-entropy token that decodes to random bytes
	// (the presigned-URL / JWT case entropy would wrongly flag) must NOT hit.
	benign := base64.RawURLEncoding.EncodeToString([]byte{
		0x9f, 0x1a, 0xc3, 0x77, 0x00, 0xe2, 0x5b, 0xd1, 0x42, 0x8a, 0x66, 0xfe, 0x03, 0x11, 0xbb, 0x90,
	})
	if s.hit("https://cdn.example.com/asset?sig=" + benign) {
		t.Errorf("decode-scan must not flag a benign random token: %q", benign)
	}

	// decode OFF => the encoded secret escapes (proves decode is what catches it).
	off := newScanner([]string{secret}, true, false, false)
	if off.hit("/" + base64.RawURLEncoding.EncodeToString([]byte(secret))) {
		t.Error("with decode disabled, the encoded secret must not be caught by exact/pattern")
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
