package workspace

import (
	"errors"
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestResolveWith(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		git  gitFunc
		dir  string
		want Scope
	}{
		{
			name: "at repo root",
			dir:  "/repo",
			git: func(_ string, args ...string) (string, error) {
				if args[1] == "--show-toplevel" {
					return "/repo", nil
				}
				return "", nil // empty prefix at root
			},
			want: Scope{Root: "/repo", Prefix: "", IsRepo: true},
		},
		{
			name: "in a subproject",
			dir:  "/repo/apps/web",
			git: func(_ string, args ...string) (string, error) {
				if args[1] == "--show-toplevel" {
					return "/repo", nil
				}
				return "apps/web/", nil // trailing slash trimmed
			},
			want: Scope{Root: "/repo", Prefix: "apps/web", IsRepo: true},
		},
		{
			name: "not a git repo",
			dir:  "/tmp/plain",
			git:  func(string, ...string) (string, error) { return "", errors.New("not a git repository") },
			want: Scope{Root: "/tmp/plain", Prefix: "", IsRepo: false},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got := resolveWith(tc.dir, tc.git)
			if diff := cmp.Diff(tc.want, got); diff != "" {
				t.Errorf("resolveWith(%q) mismatch (-want +got):\n%s", tc.dir, diff)
			}
		})
	}
}
