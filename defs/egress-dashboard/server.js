// SPEC: _spec/defs/claudecode/claudecode-egress-topology.puml
import { createServer } from 'node:http'
import { readFile, readdir } from 'node:fs/promises'
import { join } from 'node:path'

const root = process.env.PROVEO_EGRESS_DIR || process.cwd()
const port = Number(process.env.PORT || 4174)
// Bind loopback only — the dashboard serves captured egress (which may contain
// URL-embedded tokens), so it must never be reachable off the host.
const host = process.env.PROVEO_EGRESS_DASHBOARD_HOST || '127.0.0.1'
// Optional shared-secret gate (defense in depth on top of loopback binding).
const token = process.env.PROVEO_EGRESS_DASHBOARD_TOKEN || ''

async function listFiles(dir) {
  const result = []
  async function walk(current) {
    let entries = []
    try {
      entries = await readdir(current, { withFileTypes: true })
    } catch {
      return
    }
    for (const entry of entries) {
      const path = join(current, entry.name)
      if (entry.isDirectory()) await walk(path)
      else result.push(path)
    }
  }
  await walk(dir)
  return result
}

function parseMitmNdjson(text) {
  return text
    .split('\n')
    .filter(Boolean)
    .map((line) => {
      let event
      try {
        event = JSON.parse(line)
      } catch {
        return null
      }
      return {
        ts: event.ts || '',
        source: event.source || 'mitmproxy',
        decision: event.decision || 'observed',
        protocol: event.protocol || '',
        method: event.method || '',
        host: event.host || '',
        port: event.port || '',
        path: event.path || '',
        status: event.status || '',
        reason: event.reason || 'mitmproxy_flow',
      }
    })
    .filter(Boolean)
}

function parseSquidAccess(text) {
  return text.split('\n').filter(Boolean).map((line) => {
    const fields = line.trim().split(/\s+/)
    const status = fields[3] || ''
    const method = fields[5] || ''
    const url = fields[6] || ''
    let parsed
    try {
      parsed = new URL(url)
    } catch {
      parsed = null
    }
    return {
      ts: fields[0] || '',
      source: 'squid',
      decision: status.includes('DENIED') ? 'blocked' : 'allowed',
      protocol: parsed?.protocol?.replace(':', '') || '',
      method,
      host: parsed?.hostname || url,
      port: parsed?.port || '',
      path: parsed ? `${parsed.pathname}${parsed.search}` : '',
      status,
      reason: status,
    }
  })
}

function parseGuardLog(text) {
  return text.split('\n').filter(Boolean).map((line) => {
    const fields = Object.fromEntries([...line.matchAll(/([a-zA-Z_]+)=([^\s]+)/g)].map(([, key, value]) => [key, value]))
    return {
      ts: fields.ts || '',
      source: 'egress-guard',
      decision: 'blocked',
      protocol: fields.proto || fields.protocol || 'tcp',
      method: '',
      host: fields.dst || fields.host || '',
      port: fields.dpt || fields.port || '',
      path: '',
      status: '',
      reason: fields.reason || 'non_web_protocol',
    }
  })
}

async function loadEvents() {
  const files = await listFiles(root)
  const events = []
  for (const file of files) {
    const content = await readFile(file, 'utf8').catch(() => '')
    if (!content) continue
    if (file.endsWith('.ndjson')) events.push(...parseMitmNdjson(content))
    else if (file.endsWith('access.log')) events.push(...parseSquidAccess(content))
    else if (file.endsWith('reject.log')) events.push(...parseGuardLog(content))
  }
  return events.sort((a, b) => String(a.ts).localeCompare(String(b.ts)))
}

createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`)
  if (url.pathname === '/api/events') {
    if (token && req.headers['x-dashboard-token'] !== token && url.searchParams.get('token') !== token) {
      res.writeHead(403, { 'content-type': 'application/json' })
      res.end('{"error":"forbidden"}')
      return
    }
    const events = await loadEvents()
    res.writeHead(200, { 'content-type': 'application/json' })
    res.end(JSON.stringify(events))
    return
  }
  res.writeHead(200, { 'content-type': 'text/plain' })
  res.end('Run `npm run dev` for the Vite UI and `npm run serve-logs` for /api/events.\n')
}).listen(port, host, () => {
  console.log(`egress dashboard api listening on ${host}:${port}; root=${root}`)
})
