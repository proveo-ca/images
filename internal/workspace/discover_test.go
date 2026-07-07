package workspace

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/google/go-cmp/cmp"
)

// mkproj creates dir under root with a marker file.
func mkproj(t *testing.T, root, dir string) {
	t.Helper()
	full := filepath.Join(root, filepath.FromSlash(dir))
	if err := os.MkdirAll(full, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(full, "package.json"), []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func write(t *testing.T, root, name, body string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(root, name), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestDiscoverProjects(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name  string
		setup func(t *testing.T, root string)
		want  []Project
	}{
		{
			name: "pnpm workspace, exclusions ignored, non-members filtered",
			setup: func(t *testing.T, root string) {
				write(t, root, "pnpm-workspace.yaml", "packages:\n  - \"apps/*\"\n  - \"packages/*\"\n  - \"!packages/private\"\n")
				mkproj(t, root, "apps/web")
				mkproj(t, root, "packages/util")
				// a dir that matches the glob but has NO marker -> excluded
				if err := os.MkdirAll(filepath.Join(root, "apps", "empty"), 0o755); err != nil {
					t.Fatal(err)
				}
			},
			want: []Project{
				{Name: "web", Path: "apps/web", Tool: "pnpm"},
				{Name: "util", Path: "packages/util", Tool: "pnpm"},
			},
		},
		{
			name: "package.json workspaces (array form)",
			setup: func(t *testing.T, root string) {
				write(t, root, "package.json", `{"workspaces":["apps/*"]}`)
				mkproj(t, root, "apps/api")
			},
			want: []Project{{Name: "api", Path: "apps/api", Tool: "npm/yarn"}},
		},
		{
			name: "package.json workspaces (object form)",
			setup: func(t *testing.T, root string) {
				write(t, root, "package.json", `{"workspaces":{"packages":["libs/*"]}}`)
				mkproj(t, root, "libs/core")
			},
			want: []Project{{Name: "core", Path: "libs/core", Tool: "npm/yarn"}},
		},
		{
			name: "convention fallback when no manifest",
			setup: func(t *testing.T, root string) {
				mkproj(t, root, "services/auth")
				mkproj(t, root, "apps/site")
			},
			want: []Project{
				{Name: "site", Path: "apps/site", Tool: "convention"},
				{Name: "auth", Path: "services/auth", Tool: "convention"},
			},
		},
		{
			name:  "not a monorepo (no members)",
			setup: func(t *testing.T, root string) { write(t, root, "README.md", "solo") },
			want:  nil,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			root := t.TempDir()
			tc.setup(t, root)
			got := DiscoverProjects(root)
			if diff := cmp.Diff(tc.want, got); diff != "" {
				t.Errorf("DiscoverProjects(%s) mismatch (-want +got):\n%s", tc.name, diff)
			}
		})
	}
}
