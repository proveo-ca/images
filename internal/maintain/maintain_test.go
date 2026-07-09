package maintain

import (
	"testing"

	"github.com/proveo-ca/proveo/internal/manifest"
)

func TestRegistry(t *testing.T) {
	t.Parallel()
	ms := []manifest.Manifest{
		{Name: "claudecode", Dir: "/d/claudecode", Images: map[string]string{
			"claudecode":      "proveo/claudecode:latest",
			"claudecode-solo": "proveo/claudecode-solo:latest",
			"claudecode-sol":  "proveo/claudecode-sol:latest",
		}},
		{Name: "cecli", Dir: "/d/cecli", Images: map[string]string{
			"cecli":      "proveo/cecli:latest",
			"cecli-node": "proveo/cecli-node:latest",
		}},
	}

	got := Registry(ms, "/d")

	// Stable order: base, harness (sorted), then the sidecars last.
	wantOrder := []string{
		"base", "cecli", "cecli-node", "claudecode", "claudecode-sol",
		"claudecode-solo", "egress-proxy", "mitmproxy",
	}
	if len(got) != len(wantOrder) {
		t.Fatalf("got %d targets, want %d: %+v", len(got), len(wantOrder), got)
	}
	byName := map[string]Target{}
	for i, tgt := range got {
		if tgt.Name != wantOrder[i] {
			t.Errorf("order[%d] = %q, want %q", i, tgt.Name, wantOrder[i])
		}
		byName[tgt.Name] = tgt
	}

	// Image is org/name with the manifest tag stripped; DefDir matches the Bash baseline.
	for _, tc := range []struct{ name, kind, image, dir string }{
		{"base", KindBase, "proveo/base", "/d/base"},
		{"cecli", KindHarness, "proveo/cecli", "/d/cecli"},
		{"cecli-node", KindHarness, "proveo/cecli-node", "/d/cecli"}, // shares cecli's def dir
		{"claudecode", KindHarness, "proveo/claudecode", "/d/claudecode"},
		{"claudecode-sol", KindHarness, "proveo/claudecode-sol", "/d/claudecode"},
		{"claudecode-solo", KindHarness, "proveo/claudecode-solo", "/d/claudecode"},
		{"egress-proxy", KindSidecar, "proveo/egress-proxy", "/d/sidecars/egress-proxy"},
		{"mitmproxy", KindSidecar, "proveo/mitmproxy", "/d/sidecars/mitmproxy"},
	} {
		g := byName[tc.name]
		if g.Kind != tc.kind || g.Image != tc.image || g.DefDir != tc.dir {
			t.Errorf("%s = {kind:%s image:%s dir:%s}, want {kind:%s image:%s dir:%s}",
				tc.name, g.Kind, g.Image, g.DefDir, tc.kind, tc.image, tc.dir)
		}
	}
}
