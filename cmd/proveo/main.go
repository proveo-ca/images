// Command proveo is the harness CLI (Plan 4 Phase 1). It composes the shared
// hardened docker-run builder (internal/runner), the egress orchestration
// (internal/egress), and provider detection (internal/provider) into one typed
// binary — replacing the triplicated Bash run logic. Distributed as a single
// checksummed static binary (see .goreleaser.yaml, dist/install.sh).
package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/spf13/cobra"

	proveo "github.com/proveo-ca/proveo"
	"github.com/proveo-ca/proveo/internal/egress"
	"github.com/proveo-ca/proveo/internal/manifest"
	"github.com/proveo-ca/proveo/internal/provider"
	"github.com/proveo-ca/proveo/internal/runner"
	"github.com/proveo-ca/proveo/internal/shell"
	"github.com/proveo-ca/proveo/internal/workspace"
)

// version is overridden at build time via -ldflags "-X main.version=...".
var version = "dev"

// loadManifests reads the harness manifests embedded in the binary, or a
// working-tree defs dir when PROVEO_DEFS_DIR is set (dev iteration without a
// rebuild).
func loadManifests() ([]manifest.Manifest, error) {
	if dir := os.Getenv("PROVEO_DEFS_DIR"); dir != "" {
		return manifest.Load(dir)
	}
	return manifest.LoadFS(proveo.Manifests)
}

// loadTargets resolves the target->image map across all manifests.
func loadTargets() (map[string]string, error) {
	ms, err := loadManifests()
	if err != nil {
		return nil, err
	}
	return manifest.Targets(ms)
}

// manifestForTarget returns the manifest that owns the given runnable target.
func manifestForTarget(target string) (manifest.Manifest, error) {
	ms, err := loadManifests()
	if err != nil {
		return manifest.Manifest{}, err
	}
	for _, m := range ms {
		if _, ok := m.Images[target]; ok {
			return m, nil
		}
	}
	return manifest.Manifest{}, fmt.Errorf("no manifest for target %q", target)
}

func main() {
	root := &cobra.Command{
		Use:           "proveo",
		Short:         "Deterministic Docker coding-agent harnesses",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.AddCommand(versionCmd(), listCmd(), runCmd(), projectsCmd(), setupCmd())
	if err := root.Execute(); err != nil {
		// The agent's own non-zero exit is not a proveo error — propagate its code
		// verbatim, without the "error:" prefix (C6).
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			os.Exit(ee.ExitCode())
		}
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func versionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print the proveo version",
		Args:  cobra.NoArgs,
		Run:   func(*cobra.Command, []string) { fmt.Println("proveo", version) },
	}
}

func listCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "list",
		Short: "List available harness targets",
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			targets, err := loadTargets()
			if err != nil {
				return err
			}
			for _, name := range sortedKeys(targets) {
				fmt.Printf("%-16s %s\n", name, targets[name])
			}
			return nil
		},
	}
}

func runCmd() *cobra.Command {
	var egressMode, localModel, input, output, scope, dataDir, imageOverride string
	var printOnly, shellMode bool
	cmd := &cobra.Command{
		Use:   "run <target> [-- args...]",
		Short: "Run a harness against the current repo",
		Args:  cobra.MinimumNArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			target := args[0]
			targets, err := loadTargets()
			if err != nil {
				return err
			}
			image, ok := targets[target]
			if !ok {
				return fmt.Errorf("unknown target %q (see `proveo list`)", target)
			}
			if imageOverride != "" {
				image = imageOverride
			}
			if !egress.ValidMode(egressMode) {
				return fmt.Errorf("invalid --egress-mode %q (%s)", egressMode, strings.Join(egress.Modes(), "|"))
			}
			return doRun(runParams{
				target: target, image: image, mode: egressMode, localModel: localModel,
				input: input, output: output, scope: scope, dataDir: dataDir,
				shell: shellMode, printOnly: printOnly, extra: args[1:],
			})
		},
	}
	cmd.Flags().StringVar(&egressMode, "egress-mode", "firewall", strings.Join(egress.Modes(), "|")+" (default firewall: enforced egress)")
	cmd.Flags().StringVar(&localModel, "local-model", "", "Ollama model to serve locally")
	cmd.Flags().StringVar(&input, "input", "", "input dir to mount read-only (default: cwd)")
	cmd.Flags().StringVar(&output, "output", "", "output dir to mount read-write (default: <input>/reports)")
	cmd.Flags().StringVar(&scope, "scope", "", "monorepo sub-project to open (repo-relative; omit for an interactive picker)")
	cmd.Flags().StringVar(&dataDir, "data-dir", "", "extra directory to mount read-only at /workspace/data")
	cmd.Flags().StringVar(&imageOverride, "image", "", "override the image for the target")
	cmd.Flags().BoolVar(&shellMode, "shell", false, "open a shell in the container instead of the agent")
	cmd.Flags().BoolVar(&printOnly, "print", false, "print the docker plan instead of executing")
	return cmd
}

type runParams struct {
	target, image, mode, localModel, input, output, scope, dataDir string
	shell, printOnly                                               bool
	extra                                                          []string
}

func doRun(p runParams) error {
	uid, gid := strconv.Itoa(os.Getuid()), strconv.Itoa(os.Getgid())
	sid := fmt.Sprintf("proveo-%d-%d", time.Now().Unix(), os.Getpid())
	egDir := filepath.Join(stateDir(), "egress", sid)

	// The harness's mount model comes from its manifest (workspace layout).
	man, err := manifestForTarget(p.target)
	if err != nil {
		return err
	}

	// Monorepo scope: the repo root gives full git/workspace context.
	start := orWD(p.input)
	ws := workspace.Resolve(start)
	repoRoot := start
	if ws.IsRepo {
		repoRoot = ws.Root
	}
	if p.output == "" {
		p.output = filepath.Join(repoRoot, "reports")
	}

	// Sub-project scope: an explicit --scope, else an interactive picker when in a
	// monorepo, on a TTY, and not just printing.
	subScope := strings.Trim(p.scope, "/")
	if subScope == "" && !p.printOnly && isStdinTTY() && ws.IsRepo {
		if projs := workspace.DiscoverProjects(repoRoot); len(projs) > 0 {
			subScope = pickProject(projs, os.Stdin, os.Stderr)
		}
	}
	if subScope != "" {
		fmt.Fprintf(os.Stderr, "📂 scope: %s\n", subScope)
	}

	// Build the mount plan from the manifest's workspace model (embedded whole —
	// no field-by-field copy to keep in sync).
	wsSpec := workspace.MountSpec{Workspace: man.Workspace, OutputDir: p.output}
	var workdir string
	if wsSpec.Layout == "input-output" {
		wsSpec.InputDir = repoRoot // whole repo mounted read-only
		if subScope != "" {
			workdir = "/workspace/input/" + subScope
		}
	} else { // app layout: the scope dir drives the /app mount path
		if subScope != "" {
			wsSpec.InputDir = filepath.Join(repoRoot, subScope)
		} else {
			wsSpec.InputDir = start
		}
		if ws.IsRepo {
			wsSpec.RepoRoot = repoRoot
		}
	}
	mounts, planWorkdir := wsSpec.Plan()
	if planWorkdir != "" {
		workdir = planWorkdir
	}

	// Credential broker: gated by brokerProvider (firewall + exactly one provider +
	// not disabled). Write the secret file up front on real runs.
	providerName := brokerProvider(p.mode, provider.Detect(os.Getenv), brokerEnabled())
	var brokerFile string
	if providerName != "" {
		if p.printOnly {
			brokerFile = filepath.Join(egDir, "inject", "broker.env") // path only in dry-run
		} else if f, err := writeBrokerEnv(filepath.Join(egDir, "inject")); err == nil {
			brokerFile = f
		}
	}

	// Local-model sidecar is an opt-in add-on: resolve its (config-driven) host
	// models dir only when --local-model is requested.
	var modelsDir string
	if p.localModel != "" {
		modelsDir = ollamaModelsDir()
	}

	// Pure assembly of the topology + agent config from the resolved inputs — the
	// unit-testable seam (D2); all I/O (scope resolve, picker, secret write) is above.
	plan, agent, err := assemble(assembleInput{
		params: p, sid: sid, egDir: egDir, uid: uid, gid: gid,
		modelsDir: modelsDir, provider: providerName, brokerFile: brokerFile,
		mounts: mounts, workdir: workdir,
		providerDomains: os.Getenv("PROVEO_EGRESS_PROVIDER_DOMAINS"),
		squidImage:      os.Getenv("PROVEO_SQUID_PROXY_IMAGE"),
		proxyImage:      os.Getenv("PROVEO_EGRESS_PROXY_IMAGE"),
		ollamaImage:     os.Getenv("PROVEO_OLLAMA_IMAGE"),
	})
	if err != nil {
		return err
	}

	if p.printOnly {
		fmt.Print(plan.Render())
		fmt.Printf("# agent\ndocker %s\n", strings.Join(runner.DockerRunArgs(agent), " "))
		return nil
	}
	warnMountedSecrets(wsSpec.InputDir, p.mode)
	// Dispatch on whether the plan actually has sidecars/networks — not on the mode
	// name. Pure open mode runs the agent directly; anything with a sidecar/network
	// (proxy, firewall, open + --local-model) goes through the lifecycle.
	if !needsLifecycle(plan) {
		return execAgent(agent)
	}
	return execWithEgress(plan, agent, egDir, provider.Detect(os.Getenv))
}

// brokerProvider returns the provider to broker for this run, or "" for none:
// firewall mode only (the sole mode whose MITM consumes it), exactly one detected
// provider (never guess which key to inject), and the broker not disabled.
func brokerProvider(mode string, detected []string, brokerOn bool) string {
	if mode == "firewall" && brokerOn && len(detected) == 1 {
		return detected[0]
	}
	return ""
}

// needsLifecycle reports whether the plan created any network/sidecar, so the run
// must go through the egress lifecycle rather than a bare `docker run`.
func needsLifecycle(p egress.Plan) bool {
	return len(p.Networks) > 0 || len(p.Sidecars) > 0
}

// assembleInput is the fully-resolved, side-effect-free input to assemble.
type assembleInput struct {
	params                              runParams
	sid, egDir                          string
	uid, gid                            string
	modelsDir, provider, brokerFile     string
	mounts                              []runner.Mount
	workdir                             string
	providerDomains                     string
	squidImage, proxyImage, ollamaImage string
}

// assemble builds the egress plan and the agent's docker-run config from resolved
// inputs. Pure (no env/filesystem/exec), so the topology + config wiring is
// unit-testable without Docker (D2).
func assemble(in assembleInput) (egress.Plan, runner.Config, error) {
	plan, err := egress.BuildPlan(egress.Options{
		Mode: in.params.mode, SessionID: in.sid, AgentName: in.params.target, UID: in.uid, GID: in.gid,
		LocalModel: in.params.localModel, ModelsDir: in.modelsDir, Provider: in.provider, BrokerEnvFile: in.brokerFile,
		ProviderDomains: in.providerDomains,
		ConfDir:         filepath.Join(in.egDir, "mitmproxy", "confdir"),
		FlowsDir:        filepath.Join(in.egDir, "mitmproxy", "flows"),
		SquidConfigDir:  filepath.Join(in.egDir, "squid", "config"),
		SquidLogDir:     filepath.Join(in.egDir, "squid", "logs"),
		// Image overrides (pin by digest in production; enforcement images are the trust root).
		SquidImage: in.squidImage, ProxyImage: in.proxyImage, OllamaImage: in.ollamaImage,
	})
	if err != nil {
		return egress.Plan{}, runner.Config{}, err
	}
	agent := runner.Config{
		Interactive: true, Remove: true, User: in.uid + ":" + in.gid,
		Mounts:    in.mounts,
		Workdir:   in.workdir,
		ExtraArgs: plan.AgentArgs, Image: in.params.image, Command: in.params.extra,
	}
	if in.params.dataDir != "" {
		agent.Mounts = append(agent.Mounts, runner.Mount{Host: in.params.dataDir, Container: "/workspace/data", ReadOnly: true})
	}
	if in.params.shell {
		agent.Entrypoint = "bash" // open a shell instead of launching the agent
	}
	return plan, agent, nil
}

// execWithEgress stages only what the plan needs (C7), brings up the egress
// topology, waits for readiness, runs the agent, then tears the topology down —
// including on SIGINT/SIGTERM (C4), and removes the broker secret (C2).
func execWithEgress(plan egress.Plan, agent runner.Config, egDir string, providers []string) error {
	// Squid config + logs only when a Squid sidecar is present (proxy/firewall).
	if plan.UsesSquid {
		squidCfg := filepath.Join(egDir, "squid", "config")
		if err := egress.StageSquidConfig(proveo.SquidConfig, squidCfg, providers, os.Getenv("PROVEO_EGRESS_PROVIDER_DOMAINS")); err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Join(egDir, "squid", "logs"), 0o755); err != nil {
			return err
		}
	}
	// mitmproxy confdir/flows only in firewall mode (the only mode with the MITM).
	if plan.CAWaitPath != "" {
		for _, d := range []string{filepath.Join(egDir, "mitmproxy", "confdir"), filepath.Join(egDir, "mitmproxy", "flows")} {
			if err := os.MkdirAll(d, 0o755); err != nil {
				return err
			}
		}
	}

	r := egress.ExecRunner{Stderr: true}
	// Teardown containers/networks and wipe the injected secret. Run exactly once,
	// on normal return AND on a termination signal (Go defers don't run on signal).
	var once sync.Once
	cleanup := func() {
		once.Do(func() {
			plan.Teardown(r)
			_ = os.RemoveAll(filepath.Join(egDir, "inject")) // broker.env must not outlive the run
		})
	}
	defer cleanup()

	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(sigs)
	go func() {
		if _, ok := <-sigs; ok {
			cleanup()
			os.Exit(130) // 128 + SIGINT
		}
	}()

	if err := plan.Apply(r); err != nil {
		return err
	}
	if plan.CAWaitPath != "" {
		if err := waitForFile(plan.CAWaitPath, 20*time.Second); err != nil {
			return fmt.Errorf("inspector CA not ready: %w", err)
		}
	}
	if plan.OllamaContainer != "" {
		if err := egress.WaitOllamaReady(r, plan.OllamaContainer, 60*time.Second); err != nil {
			return fmt.Errorf("ollama sidecar not ready: %w", err)
		}
	}
	return execAgent(agent)
}

func execAgent(agent runner.Config) error {
	c := exec.Command("docker", runner.DockerRunArgs(agent)...)
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	return c.Run()
}

// ollamaModelsDir resolves the host Ollama model store: PROVEO_OLLAMA_MODELS_DIR
// else $HOME/.ollama/models (mirrors defs/lib/egress.sh).
func ollamaModelsDir() string {
	if d := os.Getenv("PROVEO_OLLAMA_MODELS_DIR"); d != "" {
		return d
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return ""
	}
	return filepath.Join(home, ".ollama", "models")
}

func waitForFile(path string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for {
		if fi, err := os.Stat(path); err == nil && fi.Size() > 0 {
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("timed out waiting for %s", path)
		}
		time.Sleep(200 * time.Millisecond)
	}
}

// --- helpers ---------------------------------------------------------------

func projectsCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "projects",
		Short: "List monorepo sub-projects discoverable from the current repo",
		Args:  cobra.NoArgs,
		RunE: func(*cobra.Command, []string) error {
			root := workspace.Resolve(orWD("")).Root
			projs := workspace.DiscoverProjects(root)
			if len(projs) == 0 {
				fmt.Println("no monorepo sub-projects found (not a monorepo, or no workspace members)")
				return nil
			}
			for _, p := range projs {
				fmt.Printf("%-34s %s\n", p.Path, p.Tool)
			}
			return nil
		},
	}
}

func setupCmd() *cobra.Command {
	var printOnly bool
	cmd := &cobra.Command{
		Use:   "setup",
		Short: "Add the proveo binary's directory to your shell PATH",
		Args:  cobra.NoArgs,
		RunE:  func(*cobra.Command, []string) error { return doSetup(printOnly) },
	}
	cmd.Flags().BoolVar(&printOnly, "print", false, "show the change without writing it")
	return cmd
}

func doSetup(printOnly bool) error {
	sh, ok := shell.Detect(os.Getenv("SHELL"))
	if !ok {
		return fmt.Errorf("unrecognized shell %q; add the proveo dir to PATH manually", os.Getenv("SHELL"))
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	binDir := filepath.Dir(exe)
	home, _ := os.UserHomeDir()
	rc := sh.RCFile(runtime.GOOS, home)
	line := sh.PathLine(binDir)

	if !sh.Supported {
		fmt.Printf("%s is not auto-configured. Add this to %s manually:\n  %s\n", sh.Name, rc, line)
		return nil
	}
	if onPath(binDir) {
		fmt.Printf("✓ %s is already on PATH\n", binDir)
		return nil
	}
	content, _ := os.ReadFile(rc) // missing rc is fine
	if shell.AlreadyConfigured(string(content), binDir) {
		fmt.Printf("✓ %s already configures PATH — restart your shell\n", rc)
		return nil
	}
	if printOnly {
		fmt.Printf("would append to %s:\n%s", rc, sh.Block(binDir))
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(rc), 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(rc, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	if _, err := f.WriteString(sh.Block(binDir)); err != nil {
		return err
	}
	fmt.Printf("✓ added %s to PATH in %s — restart your shell or run: source %s\n", binDir, rc, rc)
	return nil
}

func onPath(dir string) bool {
	for _, p := range filepath.SplitList(os.Getenv("PATH")) {
		if p == dir {
			return true
		}
	}
	return false
}

func isStdinTTY() bool {
	fi, err := os.Stdin.Stat()
	return err == nil && fi.Mode()&os.ModeCharDevice != 0
}

// pickProject prints a numbered menu and returns the chosen sub-project path
// ("" for the repo root / on any invalid or empty input).
func pickProject(projs []workspace.Project, in io.Reader, out io.Writer) string {
	fmt.Fprintln(out, "Monorepo detected — choose a scope:")
	fmt.Fprintln(out, "   0) <repo root>")
	for i, p := range projs {
		fmt.Fprintf(out, "  %2d) %s\n", i+1, p.Path)
	}
	fmt.Fprint(out, "scope [0]: ")
	s, _ := bufio.NewReader(in).ReadString('\n')
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil || n < 1 || n > len(projs) {
		return ""
	}
	return projs[n-1].Path
}

func sortedKeys(m map[string]string) []string {
	names := make([]string, 0, len(m))
	for n := range m {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

func orWD(p string) string {
	if p != "" {
		return p
	}
	wd, _ := os.Getwd()
	return wd
}

// warnMountedSecrets warns when the mounted workspace contains a .env while a
// provider key is present — the agent reads it directly, which the broker cannot
// prevent (S4). In firewall mode the egress DLP still blocks it from leaving; in
// open/proxy mode nothing does.
func warnMountedSecrets(dir, mode string) {
	if dir == "" {
		return
	}
	if _, err := os.Stat(filepath.Join(dir, ".env")); err != nil {
		return
	}
	if len(provider.Detect(os.Getenv)) == 0 {
		return
	}
	tail := " (egress DLP will block it from leaving)"
	if mode != "firewall" {
		tail = "; use --egress-mode firewall so egress DLP blocks the key from leaving"
	}
	fmt.Fprintf(os.Stderr, "⚠️  %s/.env is mounted and a provider key is set — the agent can read it directly%s\n", dir, tail)
}

func brokerEnabled() bool {
	switch strings.ToLower(os.Getenv("PROVEO_CREDENTIAL_BROKER")) {
	case "off", "0", "no", "false", "disable", "disabled":
		return false
	}
	return true
}

func stateDir() string {
	if x := os.Getenv("PROVEO_EGRESS_ROOT"); x != "" {
		return x
	}
	if x := os.Getenv("XDG_STATE_HOME"); x != "" {
		return filepath.Join(x, "proveo")
	}
	return filepath.Join(os.Getenv("HOME"), ".local", "state", "proveo")
}

// writeBrokerEnv writes the present provider keys to a 0600 file the egress
// proxy mounts. Mirrors defs/lib/egress.sh `proveo_egress_prepare_broker_secrets`.
func writeBrokerEnv(dir string) (string, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	path := filepath.Join(dir, "broker.env")
	var b strings.Builder
	for _, name := range provider.KeyVars() {
		if v, ok := os.LookupEnv(name); ok && v != "" {
			b.WriteString(name + "=" + v + "\n")
		}
	}
	if b.Len() == 0 {
		return "", fmt.Errorf("no provider key in host env")
	}
	if err := os.WriteFile(path, []byte(b.String()), 0o600); err != nil {
		return "", err
	}
	return path, nil
}
