package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDoInitCreatesEnvFromProviderKeys(t *testing.T) {
	dir := t.TempDir()
	envPath := filepath.Join(dir, ".env")
	t.Setenv("PROVEO_ENV_FILE", envPath)
	for _, k := range initProviderKeys {
		t.Setenv(k, "")
	}
	t.Setenv("OPENAI_API_KEY", "sk-test")
	t.Setenv("ANTHROPIC_API_KEY", "sk-ant")

	if err := doInit(); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(envPath)
	if err != nil {
		t.Fatal(err)
	}
	got := string(b)
	if !strings.Contains(got, "OPENAI_API_KEY=") || !strings.Contains(got, "ANTHROPIC_API_KEY=") {
		t.Fatalf("env missing keys: %s", got)
	}
	if !strings.Contains(got, "ATTACH_RTK=false") {
		t.Fatalf("missing ATTACH_RTK: %s", got)
	}
	fi, err := os.Stat(envPath)
	if err != nil {
		t.Fatal(err)
	}
	if perm := fi.Mode().Perm(); perm != 0o600 {
		t.Fatalf("perm = %o, want 0600", perm)
	}
}

func TestDoInitLeavesExistingEnv(t *testing.T) {
	dir := t.TempDir()
	envPath := filepath.Join(dir, ".env")
	if err := os.WriteFile(envPath, []byte("KEEP=1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PROVEO_ENV_FILE", envPath)
	t.Setenv("OPENAI_API_KEY", "sk-new")
	if err := doInit(); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(envPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(b) != "KEEP=1\n" {
		t.Fatalf("existing .env was modified: %q", b)
	}
}

func TestDoInitErrorsWithoutKeys(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("PROVEO_ENV_FILE", filepath.Join(dir, ".env"))
	for _, k := range initProviderKeys {
		t.Setenv(k, "")
	}
	if err := doInit(); err == nil {
		t.Fatal("expected error when no keys present")
	}
}
