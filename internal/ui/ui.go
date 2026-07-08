// Package ui is the single home for the CLI's human-facing status vocabulary —
// the ✓/⚠️/❌ prefixes the Bash wrappers established, lifted into Go so every
// binary (proveo, proveo-egress, later proveo-entrypoint) speaks it once.
// Status lines go to stderr so stdout stays reserved for machine output
// (plans, lists, generated config). When the writer is not a terminal, or
// TERM=dumb / NO_COLOR is set, the emoji degrade to stable text tags
// ("ok:", "warn:", "error:") so CI logs and screen-scraping tests stay
// deterministic.
//
// Deliberately line-oriented, never a full-screen TUI: proveo is a launcher
// that hands the PTY to the agent's own TUI (`docker run -it`), and the tmux
// agent-E2E layer screen-scrapes its output — both depend on the CLI printing
// a few stable lines and getting out of the way.
package ui

import (
	"fmt"
	"io"
	"os"
)

// Printer writes prefixed status lines to W. Plain swaps the emoji prefixes
// for text tags; New sets it from the writer and environment.
type Printer struct {
	W     io.Writer
	Plain bool
}

// New returns a Printer for w. Plain mode is on unless w is a terminal and
// neither TERM=dumb nor NO_COLOR is set.
func New(w io.Writer) *Printer {
	return &Printer{W: w, Plain: !isFancy(w)}
}

// Default is the process-wide status printer (stderr).
var Default = New(os.Stderr)

func isFancy(w io.Writer) bool {
	if os.Getenv("TERM") == "dumb" || os.Getenv("NO_COLOR") != "" {
		return false
	}
	f, ok := w.(*os.File)
	if !ok {
		return false
	}
	fi, err := f.Stat()
	return err == nil && fi.Mode()&os.ModeCharDevice != 0
}

func (p *Printer) line(icon, tag, format string, a ...any) {
	prefix := icon
	if p.Plain {
		prefix = tag
	}
	fmt.Fprintf(p.W, prefix+format+"\n", a...)
}

// Okf reports a success ("✓ ", plain "ok: ").
func (p *Printer) Okf(format string, a ...any) { p.line("✓ ", "ok: ", format, a...) }

// Warnf reports a non-fatal problem ("⚠️  ", plain "warn: ").
func (p *Printer) Warnf(format string, a ...any) { p.line("⚠️  ", "warn: ", format, a...) }

// Failf reports an error ("❌ ", plain "error: ").
func (p *Printer) Failf(format string, a ...any) { p.line("❌ ", "error: ", format, a...) }

// Notef writes an informational line with no prefix in either mode.
func (p *Printer) Notef(format string, a ...any) { p.line("", "", format, a...) }

// Iconf writes a line decorated with a caller-chosen icon (e.g. 📂, 🔑, 🚀);
// in plain mode the icon is dropped, not replaced.
func (p *Printer) Iconf(icon, format string, a ...any) { p.line(icon+" ", "", format, a...) }

// Package-level helpers write via Default (stderr).

// Okf reports a success on Default.
func Okf(format string, a ...any) { Default.Okf(format, a...) }

// Warnf reports a non-fatal problem on Default.
func Warnf(format string, a ...any) { Default.Warnf(format, a...) }

// Failf reports an error on Default.
func Failf(format string, a ...any) { Default.Failf(format, a...) }

// Notef writes an informational line on Default.
func Notef(format string, a ...any) { Default.Notef(format, a...) }

// Iconf writes an icon-decorated line on Default.
func Iconf(icon, format string, a ...any) { Default.Iconf(icon, format, a...) }
