# Go Testing Standards

The conventions all Go tests in this repo follow. Sourced from the official
[Go Wiki: Go Test Comments](https://go.dev/wiki/TestComments) and
[Go Wiki: TableDrivenTests](https://go.dev/wiki/TableDrivenTests), adjusted for
Go 1.26 (this module's toolchain).

## Rules

1. **No assertion libraries.** Use plain `if got != want { t.Errorf(...) }`. Do not add
   testify/assert. *(Go Wiki: "Avoid the use of 'assert' libraries.")*
2. **Compare with `go-cmp`, not `reflect.DeepEqual`.** Use `cmp.Diff(want, got)` for structs/slices
   and print it as `t.Errorf("... mismatch (-want +got):\n%s", diff)`. Compare whole structs in one
   shot, never field-by-field.
3. **Failure messages: got before want, name the function, include the input.**
   `t.Errorf("Detect(%v) = %v, want %v", in, got, want)` — never a bare `got %v, want %v`, and never
   the table index as a stand-in for the input.
4. **Table-driven + subtests.** Cases are a slice of structs with a `name`; run each under
   `t.Run(tc.name, ...)`. On Go 1.22+ the loop variable is per-iteration — **no `tc := tc`**.
5. **`t.Error` over `t.Fatal`** for assertions, so one run reports every failure. `t.Fatal` only
   when setup failed and the test cannot continue (and inside a subtest, where it ends only that
   subtest).
6. **`t.Parallel()`** on independent tests/subtests. **Cannot** be combined with `t.Setenv` (the
   runtime panics) — pick one per test.
7. **Use the testing lifecycle helpers:** `t.TempDir()` (auto-cleaned), `t.Setenv()` (auto-restored,
   serial), `t.Cleanup()`, `t.Chdir()` (Go 1.24+). Don't hand-roll teardown.
8. **Mark helpers with `t.Helper()`** so failures point at the call site.
9. **Golden files** for large/structured output (e.g. generated config): compare against a
   `testdata/*.golden`, refreshable with a `-update` flag. Annotate the diff direction.
10. **Test error identity, not error strings.** Use `errors.Is`/`errors.As`, not substring matching.
11. **Run with `-race`** in CI; keep tests deterministic (no `Date.now()`-style nondeterminism).

## Canonical shape

```go
func TestDetect(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		env  map[string]string
		want []string
	}{
		{name: "anthropic api key", env: map[string]string{"ANTHROPIC_API_KEY": "x"}, want: []string{"anthropic"}},
		{name: "none", env: nil, want: nil},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got := Detect(lookupFrom(tc.env))
			if diff := cmp.Diff(tc.want, got); diff != "" {
				t.Errorf("Detect(%v) mismatch (-want +got):\n%s", tc.env, diff)
			}
		})
	}
}
```
