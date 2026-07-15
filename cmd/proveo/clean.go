package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"

	"github.com/proveo-ca/proveo/internal/clean"
	"github.com/proveo-ca/proveo/internal/proveohome"
	"github.com/proveo-ca/proveo/internal/ui"
)

// cleanCmd reclaims leaked proveo run artifacts. Two tiers: routine (per-run
// ephemera left by crashed/killed runs — egress containers/networks, DinD
// sidecars, and egress state dirs incl. any leaked broker.env secret) and
// --deep (also removes proveo/* images). --homes removes ~/.proveo (durable
// session cache) — opt-in, never part of routine clean. It never disturbs a
// live run unless --force. See internal/clean for the decision logic.
func cleanCmd() *cobra.Command {
	var deep, force, dryRun, homes bool
	cmd := &cobra.Command{
		Use:   "clean",
		Short: "Reclaim leaked proveo run artifacts (--deep also removes proveo/* images)",
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			inv, err := gatherCleanInventory(deep)
			if err != nil {
				return err
			}
			if err := runClean(clean.BuildPlan(inv, clean.Options{Deep: deep, Force: force}), dryRun); err != nil {
				return err
			}
			if homes {
				return cleanProveoHomes(dryRun)
			}
			return nil
		},
	}
	cmd.Flags().BoolVar(&deep, "deep", false, "also remove proveo/* images (harness + base + sidecars)")
	cmd.Flags().BoolVar(&force, "force", false, "also remove resources that look live (disrupts an in-progress run)")
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "print what would be removed, without removing it")
	cmd.Flags().BoolVar(&homes, "homes", false, "also remove PROVEO_HOME (~/.proveo) durable session/config cache")
	return cmd
}

func cleanProveoHomes(dryRun bool) error {
	root := proveohome.Root(os.Getenv)
	verb := "removing"
	if dryRun {
		verb = "would remove"
	}
	if _, err := os.Stat(root); os.IsNotExist(err) {
		ui.Okf("no proveo home at %s", root)
		return nil
	}
	ui.Iconf("🗑️", "%s proveo home %s (sessions + seeded config)", verb, root)
	if dryRun {
		return nil
	}
	return os.RemoveAll(root)
}

func gatherCleanInventory(deep bool) (clean.Inventory, error) {
	var inv clean.Inventory

	// Egress session containers (labeled proveo.egress.session).
	for _, line := range dockerLines("ps", "-a", "--filter", "label=proveo.egress.session",
		"--format", "{{.Names}}\t{{.State}}\t{{.Label \"proveo.egress.session\"}}") {
		if f := strings.SplitN(line, "\t", 3); len(f) == 3 {
			inv.Egress = append(inv.Egress, clean.Container{Name: f[0], Running: f[1] == "running", Session: f[2]})
		}
	}

	// DinD sidecars (proveo-dind-*, not session-labeled).
	for _, line := range dockerLines("ps", "-a", "--filter", "name=proveo-dind-",
		"--format", "{{.Names}}\t{{.State}}") {
		if f := strings.SplitN(line, "\t", 2); len(f) == 2 {
			inv.Dind = append(inv.Dind, clean.Container{Name: f[0], Running: f[1] == "running"})
		}
	}

	// Egress networks (labeled); inspect for the session id + endpoint count.
	for _, name := range dockerLines("network", "ls", "--filter", "label=proveo.egress.session", "--format", "{{.Name}}") {
		n := clean.Net{Name: name}
		if insp := dockerLines("network", "inspect", name,
			"--format", "{{index .Labels \"proveo.egress.session\"}}\t{{len .Containers}}"); len(insp) == 1 {
			if f := strings.SplitN(insp[0], "\t", 2); len(f) == 2 {
				n.Session, n.HasEndpoints = f[0], f[1] != "0"
			}
		}
		inv.Networks = append(inv.Networks, n)
	}

	// Egress state dirs (each holds a session's squid config, mitm confdir, and
	// — critically — the injected broker.env secret).
	if entries, err := os.ReadDir(filepath.Join(stateDir(), "egress")); err == nil {
		for _, e := range entries {
			if e.IsDir() {
				inv.StateDirs = append(inv.StateDirs, e.Name())
			}
		}
	}

	// proveo/* images (only for --deep). Upstream sidecar bases are left alone.
	if deep {
		seen := map[string]bool{}
		for _, ref := range dockerLines("image", "ls", "--format", "{{.Repository}}:{{.Tag}}") {
			if strings.HasPrefix(ref, "proveo/") && !strings.HasSuffix(ref, ":<none>") && !seen[ref] {
				seen[ref] = true
				inv.Images = append(inv.Images, ref)
			}
		}
	}
	return inv, nil
}

// runClean executes (or, with dryRun, prints) the plan. All removals are
// best-effort: an image still in use by a live run fails to remove and is left.
func runClean(p clean.Plan, dryRun bool) error {
	if len(p.Containers)+len(p.Networks)+len(p.StateDirs)+len(p.Images) == 0 {
		if len(p.SkippedLive) == 0 {
			ui.Okf("nothing to clean")
			return nil
		}
	}
	verb := "removing"
	if dryRun {
		verb = "would remove"
	}
	for _, c := range p.Containers {
		ui.Iconf("🗑️", "%s container %s", verb, c)
		if !dryRun {
			_ = exec.Command("docker", "rm", "-f", c).Run()
		}
	}
	for _, n := range p.Networks {
		ui.Iconf("🗑️", "%s network %s", verb, n)
		if !dryRun {
			_ = exec.Command("docker", "network", "rm", n).Run()
		}
	}
	for _, sid := range p.StateDirs {
		dir := filepath.Join(stateDir(), "egress", sid)
		ui.Iconf("🗑️", "%s state %s (incl. any injected broker secret)", verb, dir)
		if !dryRun {
			_ = os.RemoveAll(dir)
		}
	}
	for _, img := range p.Images {
		ui.Iconf("🗑️", "%s image %s", verb, img)
		if !dryRun {
			_ = exec.Command("docker", "image", "rm", img).Run()
		}
	}
	if len(p.SkippedLive) > 0 {
		ui.Warnf("left %d resource(s) that look live (in-progress run?): %s",
			len(p.SkippedLive), strings.Join(p.SkippedLive, ", "))
		ui.Notef("re-run with --force to remove those too (disrupts an in-progress run)")
	}
	return nil
}

// dockerLines runs a docker query and returns non-empty output lines.
func dockerLines(args ...string) []string {
	out, err := exec.Command("docker", args...).Output()
	if err != nil {
		return nil
	}
	var lines []string
	for _, l := range strings.Split(string(out), "\n") {
		if l = strings.TrimRight(l, "\r"); strings.TrimSpace(l) != "" {
			lines = append(lines, l)
		}
	}
	return lines
}
