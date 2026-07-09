// Command proveo is the harness CLI. It composes the shared
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
	"golang.org/x/term"

	proveo "github.com/proveo-ca/proveo"
	"github.com/proveo-ca/proveo/internal/dind"
	"github.com/proveo-ca/proveo/internal/egress"
	"github.com/proveo-ca/proveo/internal/entrypoint"
	"github.com/proveo-ca/proveo/internal/gitidentity"
	"github.com/proveo-ca/proveo/internal/manifest"
	"github.com/proveo-ca/proveo/internal/provider"
	"github.com/proveo-ca/proveo/internal/runner"
	"github.com/proveo-ca/proveo/internal/shell"
	"github.com/proveo-ca/proveo/internal/ui"
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
		Short:         ui.BrandTagline,
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	defaultHelp := root.HelpFunc()
	root.SetHelpFunc(func(cmd *cobra.Command, args []string) {
		// Branding banner on root help only (proveo help / proveo --help).
		if !cmd.HasParent() {
			ui.WriteBrandBanner(cmd.OutOrStdout())
		}
		defaultHelp(cmd, args)
	})
	root.AddCommand(versionCmd(), listCmd(), runCmd(), projectsCmd(), setupCmd(), initCmd())
	if err := root.Execute(); err != nil {
		// The agent's own non-zero exit is not a proveo error — propagate its code
		// verbatim, without the "error:" prefix (C6). Only the agent's: a failed
		// helper subprocess (docker pull, build.sh) wraps an ExitError too and
		// must still be reported, so execAgent marks its exit with a named type.
		var ae agentExitError
		if errors.As(err, &ae) {
			os.Exit(ae.code)
		}
		ui.Failf("%v", err)
		os.Exit(1)
	}
}

// agentExitError carries the agent container's own non-zero exit code.
type agentExitError struct{ code int }

func (e agentExitError) Error() string { return fmt.Sprintf("agent exited with code %d", e.code) }

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
	cmd.Flags().StringVar(&egressMode, "egress-mode", "firewall", strings.Join(egress.Modes(), "|")+" (default firewall: enforced egress + credential broker)")
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

	// Cursor CLI has no local-model path — all inference transits Cursor's backend.
	if p.target == "cursor" && p.localModel != "" {
		return fmt.Errorf("cursor has no --local-model path (inference is vendor-pinned); unset it or use another harness")
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
		ui.Iconf("📂", "scope: %s", subScope)
	}

	// Build the mount plan from the manifest's workspace model (embedded whole —
	// no field-by-field copy to keep in sync).
	wsSpec := workspace.MountSpec{Workspace: man.Workspace, OutputDir: p.output, EgressMode: p.mode}
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

	// Host-side .env for broker ingestion (never mounted into the agent in
	// proxy/firewall). Explicit PROVEO_EGRESS_ENV_FILE wins. Resolve before
	// missing-env prompts so keys present only in a project .env are visible.
	invocationWD, _ := os.Getwd()
	hostEnvFile := strings.TrimSpace(os.Getenv("PROVEO_EGRESS_ENV_FILE"))
	if hostEnvFile == "" {
		hostEnvFile = workspace.EnvFileSource(invocationWD, wsSpec.InputDir, wsSpec.RepoRoot)
	}
	lookup := providerLookup(hostEnvFile)

	// DinD offer before the env wizard: cursor declares CURSOR_API_KEY and the
	// wizard may attach a bufio.Reader to stdin, which would starve the DinD prompt.
	dindScope := wsSpec.InputDir
	if dindScope == "" {
		dindScope = start
	}
	wantDind := !p.printOnly && dind.ShouldStart(man.Dind, dindScope, isStdinTTY(), func() bool {
		return dind.PromptYesNo(os.Stdin, os.Stderr)
	})

	// Declared-but-missing env: prompt (the DinD-prompt-style wizard) on a TTY,
	// else warn — a skipped var keeps today's warn-and-continue behavior. Runs
	// before provider detection so a prompted key feeds the broker + forwarding.
	if missing := man.MissingEnv(lookup); len(missing) > 0 && !p.printOnly {
		if isStdinTTY() && wizardEnabled() {
			for name, v := range promptEnv(p.target, missing, os.Stdin, os.Stderr, termSecret) {
				os.Setenv(name, v)
			}
			missing = man.MissingEnv(lookup)
		}
		for _, e := range missing {
			msg := e.Name + " not set"
			if e.Description != "" {
				msg += " — " + e.Description
			}
			ui.Warnf("%s", msg)
		}
	}

	mounts, planWorkdir := wsSpec.Plan()
	if planWorkdir != "" {
		workdir = planWorkdir
	}

	// Credential broker: gated by brokerProvider (firewall + a resolved provider +
	// not disabled). Vendor-pinned harnesses (manifest provider:) win over the
	// "exactly one detected key" rule so a multi-provider .env does not block
	// cursor when CURSOR_API_KEY lives only in the host env. Write secrets up front.
	detected := provider.Detect(lookup)
	providerName := brokerProvider(p.mode, man, detected, lookup, brokerEnabled())
	var brokerFile string
	if providerName != "" {
		if p.printOnly {
			brokerFile = filepath.Join(egDir, "inject", "broker.env") // path only in dry-run
		} else if f, err := writeBrokerEnv(filepath.Join(egDir, "inject"), lookup); err == nil {
			brokerFile = f
		} else {
			ui.Warnf("broker secret file: %v", err)
		}
	}

	// Local-model sidecar is an opt-in add-on: resolve its (config-driven) host
	// models dir only when --local-model is requested.
	var modelsDir string
	if p.localModel != "" {
		modelsDir = ollamaModelsDir()
	}

	// Declared env: bare `-e NAME` for non-secrets. Secrets: broker forwards real
	// value; firewall injects sentinel + PROVEO_CREDENTIAL_BROKER_KEYS; proxy withholds.
	var env []string
	var brokerKeyNames []string
	for _, e := range man.Env {
		if strings.TrimSpace(lookup(e.Name)) == "" {
			continue
		}
		if e.Secret {
			switch p.mode {
			case "broker":
				env = append(env, e.Name)
				hydrateProcessEnv(e.Name, lookup)
			case "firewall":
				env = append(env, e.Name+"="+entrypoint.DefaultSentinel)
				brokerKeyNames = append(brokerKeyNames, e.Name)
			}
			continue
		}
		env = append(env, e.Name)
	}
	if p.mode == "firewall" {
		for _, k := range provider.KeyVars() {
			if strings.TrimSpace(lookup(k)) == "" {
				continue
			}
			already := false
			for _, n := range brokerKeyNames {
				if n == k {
					already = true
					break
				}
			}
			if !already {
				env = append(env, k+"="+entrypoint.DefaultSentinel)
				brokerKeyNames = append(brokerKeyNames, k)
			}
		}
		if len(brokerKeyNames) > 0 {
			env = append(env, "PROVEO_CREDENTIAL_BROKER_KEYS="+strings.Join(brokerKeyNames, ","))
		}
	}
	env = append(env, gitidentity.Resolve(os.Getenv, nil).EnvPairs()...)

	var dindSidecar *dind.Sidecar

	plan, agent, err := assemble(assembleInput{
		params: p, sid: sid, egDir: egDir, uid: uid, gid: gid,
		modelsDir: modelsDir, provider: providerName, brokerFile: brokerFile,
		mounts: mounts, workdir: workdir, env: env,
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
	if err := preflightImages(plan, man, p.image); err != nil {
		return err
	}
	if wantDind {
		sc, err := dind.Start(dind.ExecRunner{}, p.target, dindScope, os.Stderr)
		if err != nil {
			return err
		}
		dindSidecar = sc
		agent.ExtraArgs = append(append([]string(nil), agent.ExtraArgs...), sc.AgentArgs()...)
		defer dindSidecar.Cleanup(dind.ExecRunner{})
	}
	warnMountedSecrets(wsSpec.InputDir, p.mode, lookup)
	if !needsLifecycle(plan) {
		return execAgent(agent)
	}
	squidProviders := detected
	if providerName != "" {
		squidProviders = []string{providerName}
	}
	return execWithEgress(plan, agent, egDir, squidProviders)
}

// brokerProvider returns the provider to broker for this run, or "" for none:
// firewall mode only (the sole mode whose MITM consumes it) and the broker not
// disabled. A manifest provider pin (vendor-pinned harness) is used when its
// detect key is present; otherwise exactly one detected provider is required.
func brokerProvider(mode string, man manifest.Manifest, detected []string, lookup func(string) string, brokerOn bool) string {
	if mode != "firewall" || !brokerOn {
		return ""
	}
	if pin := strings.TrimSpace(man.Provider); pin != "" {
		e, ok := provider.Lookup(pin)
		if !ok {
			return ""
		}
		for _, v := range e.Detect {
			if strings.TrimSpace(lookup(v)) != "" {
				return pin
			}
		}
		return ""
	}
	if len(detected) == 1 {
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
	env                                 []string // declared env var names to forward (bare -e)
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
		Env:       in.env,
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
	err := c.Run()
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return agentExitError{code: ee.ExitCode()}
	}
	return err
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
				// A note, not data: stdout stays empty so scripted callers see zero rows.
				ui.Notef("no monorepo sub-projects found (not a monorepo, or no workspace members)")
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
		ui.Notef("%s is not auto-configured. Add this to %s manually:\n  %s", sh.Name, rc, line)
		return nil
	}
	if onPath(binDir) {
		ui.Okf("%s is already on PATH", binDir)
		return nil
	}
	content, _ := os.ReadFile(rc) // missing rc is fine
	if shell.AlreadyConfigured(string(content), binDir) {
		ui.Okf("%s already configures PATH — restart your shell", rc)
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
	ui.Okf("added %s to PATH in %s — restart your shell or run: source %s", binDir, rc, rc)
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

// isStdinTTY gates every interactive prompt (scope picker, env wizard). A real
// ioctl check, not a char-device stat: /dev/null is a character device too and
// must not count as interactive.
func isStdinTTY() bool {
	return term.IsTerminal(int(os.Stdin.Fd()))
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
// prevent (S4). Skipped when proxy/broker mask the file out of the agent.
func warnMountedSecrets(dir, mode string, lookup func(string) string) {
	if dir == "" {
		return
	}
	switch strings.ToLower(mode) {
	case "proxy", "firewall":
		return
	}
	if _, err := os.Stat(filepath.Join(dir, ".env")); err != nil {
		return
	}
	if len(provider.Detect(lookup)) == 0 {
		return
	}
	ui.Warnf("%s/.env is mounted and a provider key is set — the agent can read it directly; use --egress-mode firewall so egress DLP blocks the key from leaving", dir)
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

// hydrateProcessEnv copies a secret from lookup into the proveo process env when
// it is present in a host .env but not exported. Docker's bare `-e NAME` only
// forwards the client process environment, so broker mode needs this.
func hydrateProcessEnv(name string, lookup func(string) string) {
	if strings.TrimSpace(os.Getenv(name)) != "" {
		return
	}
	if v := strings.TrimSpace(lookup(name)); v != "" {
		_ = os.Setenv(name, v)
	}
}

// providerLookup prefers the process env, then a host-side KEY=VALUE file
// (project .env / PROVEO_EGRESS_ENV_FILE) for detection and broker.env writing.
func providerLookup(envFile string) func(string) string {
	fileVals := parseEnvFile(envFile)
	return func(k string) string {
		if v := strings.TrimSpace(os.Getenv(k)); v != "" {
			return v
		}
		return fileVals[k]
	}
}

// parseEnvFile reads a KEY=VALUE env file (project .env shape). Missing => empty.
func parseEnvFile(path string) map[string]string {
	out := map[string]string{}
	if path == "" {
		return out
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return out
	}
	for _, raw := range strings.Split(string(b), "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "export ") {
			line = strings.TrimSpace(strings.TrimPrefix(line, "export "))
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		k = strings.TrimSpace(k)
		v = strings.TrimSpace(v)
		if len(v) >= 2 && ((v[0] == '"' && v[len(v)-1] == '"') || (v[0] == '\'' && v[len(v)-1] == '\'')) {
			v = v[1 : len(v)-1]
		}
		out[k] = v
	}
	return out
}

// writeBrokerEnv writes present provider keys to a 0600 file the egress proxy
// mounts. lookup may include host-side .env values not in the process env.
func writeBrokerEnv(dir string, lookup func(string) string) (string, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	path := filepath.Join(dir, "broker.env")
	var b strings.Builder
	for _, name := range provider.KeyVars() {
		if v := strings.TrimSpace(lookup(name)); v != "" {
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
