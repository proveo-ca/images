// Package maintain is the maintainer-side target registry: the single source of
// truth for which images the build/deploy/test tooling operates on and where
// each is defined. Harness targets are drawn from the harness manifests
// (internal/manifest); the shared base image and the egress sidecars are fixed
// entries that have no manifest. It is consumed by `proveo targets`
// (cmd/proveo), which the maintainer mise tasks read instead of re-parsing the
// manifests in Bash — replacing lib/manifest-enum.sh + lib/runners.sh.
package maintain

import (
	"path/filepath"
	"sort"
	"strings"

	"github.com/proveo-ca/proveo/internal/manifest"
)

// Target kinds.
const (
	KindBase    = "base"
	KindHarness = "harness"
	KindSidecar = "sidecar"
)

// Target is one buildable/deployable image in the maintainer registry.
type Target struct {
	Name   string // e.g. "claudecode-solo"
	Kind   string // KindBase | KindHarness | KindSidecar
	Image  string // org/name without a tag, e.g. "proveo/claudecode-solo"
	DefDir string // def directory holding build.sh / test.sh
}

// sidecars are the fixed egress-enforcement images (no harness manifest). Name
// doubles as the defs/sidecars/<name> subdir and the proveo/<name> image.
var sidecars = []string{"egress-proxy", "mitmproxy"}

// Registry returns the maintainer targets in stable order: the base image, then
// the harness targets (sorted by name) from ms, then the egress sidecars.
// defsDir is the on-disk defs/ root; the base + sidecar DefDirs are joined onto
// it, while harness DefDirs come from each manifest's own Dir.
func Registry(ms []manifest.Manifest, defsDir string) []Target {
	out := []Target{
		{Name: "base", Kind: KindBase, Image: "proveo/base", DefDir: filepath.Join(defsDir, "base")},
	}

	var harness []Target
	for _, m := range ms {
		for target, image := range m.Images {
			harness = append(harness, Target{
				Name:   target,
				Kind:   KindHarness,
				Image:  stripTag(image),
				DefDir: m.Dir,
			})
		}
	}
	sort.Slice(harness, func(i, j int) bool { return harness[i].Name < harness[j].Name })
	out = append(out, harness...)

	for _, name := range sidecars {
		out = append(out, Target{
			Name:   name,
			Kind:   KindSidecar,
			Image:  "proveo/" + name,
			DefDir: filepath.Join(defsDir, "sidecars", name),
		})
	}
	return out
}

// stripTag drops a trailing ":tag" from an image reference.
func stripTag(image string) string {
	if i := strings.IndexByte(image, ':'); i >= 0 {
		return image[:i]
	}
	return image
}
