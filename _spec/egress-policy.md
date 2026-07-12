# Egress Policy

Read-allow / write-deny / DLP at the firewall MITM hop.

**Diagrams (source of truth for structure and flow):**

| Diagram | What it shows |
|---------|----------------|
| [`egress-policy-components.puml`](egress-policy-components.puml) | Host → `proveo-egress` → Squid; broker then policy; destinations |
| [`egress-policy-layers.puml`](egress-policy-layers.puml) | Layers A (method), B (exfil sinks), C (DLP + budget) + config |
| [`egress-policy-decide.puml`](egress-policy-decide.puml) | Request sequence: provider skip, allow path, block + 403 |

**Code:** pure decisions in `internal/egresspolicy`; wired as a martian `RequestModifier` in `internal/egressproxy` (after the credential broker). Firewall mode only for full A/B/C.

**Related:** credential inject/strip on the same hop is described under Credential Boundary in [`paradigms.md`](paradigms.md) and the claudecode egress topology under [`defs/claudecode/claudecode-egress-topology.puml`](defs/claudecode/claudecode-egress-topology.puml).
