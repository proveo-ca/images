// Package manifest reads the per-harness `defs/<name>/harness.manifest` files —
// the single registration point. Adding a harness should mean dropping
// a def dir with a manifest; nothing else enumerates harnesses by hand.
package manifest

import (
	"fmt"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

// Filename is the manifest basename inside each def directory.
const Filename = "harness.manifest"

// Workspace declares how a harness mounts the working tree — the model the
// run.sh files encode today, lifted into data so `proveo run` can reproduce it.
type Workspace struct {
	// Layout: "app" (mount the repo at /app, -w /app; the monorepo model used by
	// cursor/opencode/cecli) or "input-output" (claudecode: input:ro + output:rw).
	Layout string `yaml:"layout"`
	// ConfigDir is the tool config dir preserved from the repo root in the
	// monorepo-subdir case (e.g. ".cursor", ".opencode", ".cecli"). app layout only.
	ConfigDir string `yaml:"configDir"`
	// GitMode is how the root .git is mounted in the subdir case: "rw" (default)
	// or "ro" (cecli). app layout only.
	GitMode string `yaml:"gitMode"`
	// Output mounts the output dir at /app/output:rw (cecli). app layout only.
	Output bool `yaml:"output"`
	// Mode is how the working tree itself is mounted: "rw" (default) or "ro". app
	// layout only.
	Mode string `yaml:"mode"`
}

// EnvVar declares an environment variable a harness reads at run time, so the
// CLI can forward it into the container and — when it is missing — prompt for
// it (interactive wizard) or warn (non-TTY). Secret values are prompted with
// echo off and are only ever forwarded by name (`-e NAME`), never on an argv.
type EnvVar struct {
	Name        string `yaml:"name"`
	Description string `yaml:"description"`
	Secret      bool   `yaml:"secret"`
}

// Manifest describes one harness definition.
type Manifest struct {
	Name        string            `yaml:"name"`
	Description string            `yaml:"description"`
	Egress      bool              `yaml:"egress"`    // sources the egress lifecycle
	Dind        bool              `yaml:"dind"`      // image ships docker client; may get DinD sidecar
	Stability   string            `yaml:"stability"` // experimental | candidate | stable
	Images      map[string]string `yaml:"images"`    // target name -> image ref
	Workspace   Workspace         `yaml:"workspace"` // mount model
	Env         []EnvVar          `yaml:"env"`       // env vars the harness reads
	Dir         string            `yaml:"-"`         // def directory (set by Load)
}

// MissingEnv returns the declared env vars whose value is empty per getenv,
// in declaration order.
func (m Manifest) MissingEnv(getenv func(string) string) []EnvVar {
	var out []EnvVar
	for _, e := range m.Env {
		if strings.TrimSpace(getenv(e.Name)) == "" {
			out = append(out, e)
		}
	}
	return out
}

// Validate reports whether a manifest is well-formed.
func (m Manifest) Validate() error {
	if m.Name == "" {
		return fmt.Errorf("manifest %s: missing name", m.Dir)
	}
	if len(m.Images) == 0 {
		return fmt.Errorf("manifest %q: at least one images entry is required", m.Name)
	}
	for target, image := range m.Images {
		if target == "" || image == "" {
			return fmt.Errorf("manifest %q: empty target or image (%q: %q)", m.Name, target, image)
		}
	}
	switch m.Stability {
	case "", "experimental", "candidate", "stable":
	default:
		return fmt.Errorf("manifest %q: invalid stability %q", m.Name, m.Stability)
	}
	switch m.Workspace.Layout {
	case "", "app", "input-output":
	default:
		return fmt.Errorf("manifest %q: invalid workspace.layout %q", m.Name, m.Workspace.Layout)
	}
	switch m.Workspace.GitMode {
	case "", "rw", "ro":
	default:
		return fmt.Errorf("manifest %q: invalid workspace.gitMode %q", m.Name, m.Workspace.GitMode)
	}
	switch m.Workspace.Mode {
	case "", "rw", "ro":
	default:
		return fmt.Errorf("manifest %q: invalid workspace.mode %q", m.Name, m.Workspace.Mode)
	}
	seen := map[string]bool{}
	for _, e := range m.Env {
		if e.Name == "" {
			return fmt.Errorf("manifest %q: env entry with empty name", m.Name)
		}
		if seen[e.Name] {
			return fmt.Errorf("manifest %q: duplicate env entry %q", m.Name, e.Name)
		}
		seen[e.Name] = true
	}
	return nil
}

// Parse decodes one manifest from YAML bytes (dir is used only for messages).
func Parse(data []byte, dir string) (Manifest, error) {
	var m Manifest
	if err := yaml.Unmarshal(data, &m); err != nil {
		return Manifest{}, fmt.Errorf("manifest %s: %w", dir, err)
	}
	m.Dir = dir
	if err := m.Validate(); err != nil {
		return Manifest{}, err
	}
	return m, nil
}

// Load reads every `defs/*/harness.manifest` under defsDir, sorted by name.
func Load(defsDir string) ([]Manifest, error) {
	matches, err := filepath.Glob(filepath.Join(defsDir, "*", Filename))
	if err != nil {
		return nil, err
	}
	var out []Manifest
	for _, path := range matches {
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		m, err := Parse(data, filepath.Dir(path))
		if err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

// LoadFS reads every defs/*/harness.manifest from an fs.FS (e.g. the embedded
// manifests), so the CLI works without the defs tree on disk.
func LoadFS(fsys fs.FS) ([]Manifest, error) {
	matches, err := fs.Glob(fsys, "defs/*/"+Filename)
	if err != nil {
		return nil, err
	}
	var out []Manifest
	for _, p := range matches {
		data, err := fs.ReadFile(fsys, p)
		if err != nil {
			return nil, err
		}
		m, err := Parse(data, path.Dir(p))
		if err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

// Targets flattens the images across manifests into target -> image, erroring on
// a duplicate target name (two harnesses claiming the same runnable target).
func Targets(ms []Manifest) (map[string]string, error) {
	out := make(map[string]string)
	for _, m := range ms {
		for target, image := range m.Images {
			if prev, dup := out[target]; dup {
				return nil, fmt.Errorf("duplicate target %q (%q and %q)", target, prev, image)
			}
			out[target] = image
		}
	}
	return out, nil
}
