package ui

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestPrinterVocabulary(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name      string
		print     func(p *Printer)
		want      string // fancy (terminal) form
		wantPlain string
	}{
		{
			name:      "ok",
			print:     func(p *Printer) { p.Okf("added %s to PATH", "/bin") },
			want:      "✓ added /bin to PATH\n",
			wantPlain: "ok: added /bin to PATH\n",
		},
		{
			name:      "warn",
			print:     func(p *Printer) { p.Warnf("%s not set", "CURSOR_API_KEY") },
			want:      "⚠️  CURSOR_API_KEY not set\n",
			wantPlain: "warn: CURSOR_API_KEY not set\n",
		},
		{
			name:      "fail",
			print:     func(p *Printer) { p.Failf("unknown target %q", "nope") },
			want:      "❌ unknown target \"nope\"\n",
			wantPlain: "error: unknown target \"nope\"\n",
		},
		{
			name:      "note has no prefix in either mode",
			print:     func(p *Printer) { p.Notef("restart your shell") },
			want:      "restart your shell\n",
			wantPlain: "restart your shell\n",
		},
		{
			name:      "icon is dropped, not replaced, in plain mode",
			print:     func(p *Printer) { p.Iconf("📂", "scope: %s", "apps/web") },
			want:      "📂 scope: apps/web\n",
			wantPlain: "scope: apps/web\n",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			var buf bytes.Buffer
			tc.print(&Printer{W: &buf})
			if diff := cmp.Diff(tc.want, buf.String()); diff != "" {
				t.Errorf("fancy output mismatch (-want +got):\n%s", diff)
			}
			buf.Reset()
			tc.print(&Printer{W: &buf, Plain: true})
			if diff := cmp.Diff(tc.wantPlain, buf.String()); diff != "" {
				t.Errorf("plain output mismatch (-want +got):\n%s", diff)
			}
		})
	}
}

// New must degrade to plain mode for anything that is not a terminal: pipes,
// buffers, regular files. (The terminal=fancy side needs a real PTY, which unit
// tests don't have — it is exercised by the tmux-driven agent-E2E layer.)
func TestNewDetectsPlain(t *testing.T) {
	t.Run("non-file writer is plain", func(t *testing.T) {
		if p := New(&bytes.Buffer{}); !p.Plain {
			t.Error("New(bytes.Buffer) should be plain: a buffer is not a terminal")
		}
	})
	t.Run("regular file is plain", func(t *testing.T) {
		f, err := os.Create(filepath.Join(t.TempDir(), "out"))
		if err != nil {
			t.Fatal(err)
		}
		defer f.Close()
		if p := New(f); !p.Plain {
			t.Error("New(regular file) should be plain: a file is not a terminal")
		}
	})
}
