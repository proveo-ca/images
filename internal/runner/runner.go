// Package runner builds the single hardened `docker run` invocation shared by
// every harness. It replaces the hardening baseline
// that was copy-pasted across the consumer CLI, lib/runners.sh, and each
// defs/<name>/run.sh. The argv is built as pure data so it is golden-testable;
// execution is the caller's concern.
package runner

// Mount is a bind mount.
type Mount struct {
	Host      string
	Container string
	ReadOnly  bool
}

// Config describes a harness container run. The security hardening (cap-drop,
// no-new-privileges, pids-limit) is NOT configurable — it is always applied.
type Config struct {
	Name        string   // container name (optional)
	User        string   // "uid:gid"; empty => runtime default (caller should set)
	Interactive bool     // add -it
	Remove      bool     // add --rm
	Tmpfs       []string // e.g. "/tmp:noexec,nosuid,size=100m"
	Mounts      []Mount
	Env         []string // "KEY=VALUE", or bare "KEY" to forward the client env value (keeps secrets off the argv)
	Workdir     string   // container working dir (-w), e.g. a monorepo sub-scope
	Entrypoint  string   // override the image entrypoint (--entrypoint), e.g. "bash" for --shell
	ExtraArgs   []string // pass-through (e.g. egress agent args, --network)
	Image       string
	Command     []string // args after the image
}

// hardening is the non-negotiable baseline every harness container runs with.
// This is the single source; the contract test asserts no def re-declares it.
var hardening = []string{
	"--cap-drop=ALL",
	"--security-opt=no-new-privileges:true",
	"--pids-limit=100",
}

// DockerRunArgs returns the full argument vector after the literal `docker`,
// i.e. {"run", ...flags..., image, ...command...}. Deterministic ordering so
// golden tests are stable.
func DockerRunArgs(cfg Config) []string {
	args := []string{"run"}
	if cfg.Interactive {
		args = append(args, "-it")
	}
	if cfg.Remove {
		args = append(args, "--rm")
	}
	if cfg.Name != "" {
		args = append(args, "--name", cfg.Name)
	}
	if cfg.User != "" {
		args = append(args, "--user", cfg.User)
	}
	args = append(args, hardening...)
	for _, t := range cfg.Tmpfs {
		args = append(args, "--tmpfs", t)
	}
	for _, m := range cfg.Mounts {
		spec := m.Host + ":" + m.Container
		if m.ReadOnly {
			spec += ":ro"
		}
		args = append(args, "-v", spec)
	}
	for _, e := range cfg.Env {
		args = append(args, "-e", e)
	}
	if cfg.Workdir != "" {
		args = append(args, "-w", cfg.Workdir)
	}
	if cfg.Entrypoint != "" {
		args = append(args, "--entrypoint", cfg.Entrypoint)
	}
	args = append(args, cfg.ExtraArgs...)
	if cfg.Image != "" {
		args = append(args, cfg.Image)
	}
	args = append(args, cfg.Command...)
	return args
}

// Hardening returns a copy of the baseline flags (for the contract test / docs).
func Hardening() []string { return append([]string(nil), hardening...) }
