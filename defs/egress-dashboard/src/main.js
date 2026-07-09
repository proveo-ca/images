const app = document.querySelector('#app')

async function loadEvents() {
  const response = await fetch('/api/events')
  if (!response.ok) throw new Error(`events failed: ${response.status}`)
  return response.json()
}

// esc HTML-escapes any value before it is interpolated into innerHTML. The
// event fields come from parsed egress logs — an agent controls the hosts/paths
// it requests, so those strings are untrusted and must never be rendered raw.
function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ))
}

function render(events) {
  const rows = events
    .map((event) => `
      <tr class="${esc(event.decision)}">
        <td>${esc(event.ts)}</td>
        <td>${esc(event.source)}</td>
        <td>${esc(event.decision)}</td>
        <td>${esc(event.protocol)}</td>
        <td>${esc(event.method)}</td>
        <td>${esc(event.host)}</td>
        <td>${esc(event.port)}</td>
        <td>${esc(event.status)}</td>
        <td>${esc(event.path)}</td>
        <td>${esc(event.reason)}</td>
      </tr>
    `)
    .join('')

  app.innerHTML = `
    <style>
      body { margin: 0; font-family: Inter, ui-sans-serif, system-ui, sans-serif; background: #101114; color: #f4f4f5; }
      main { padding: 24px; }
      h1 { margin: 0 0 8px; font-size: 28px; }
      p { color: #a1a1aa; }
      table { width: 100%; border-collapse: collapse; margin-top: 20px; font-size: 13px; }
      th, td { border-bottom: 1px solid #27272a; padding: 8px; text-align: left; vertical-align: top; }
      th { color: #d4d4d8; background: #18181b; position: sticky; top: 0; }
      tr.blocked td { color: #fca5a5; }
      tr.allowed td { color: #86efac; }
      tr.observed td { color: #93c5fd; }
      code { color: #fde68a; }
    </style>
    <h1>Proveo Egress Dashboard</h1>
    <p>Normalized view of mitmproxy flow exports, Squid access logs, and guard reject logs.</p>
    <p>Events: <code>${events.length}</code></p>
    <table>
      <thead>
        <tr><th>Time</th><th>Source</th><th>Decision</th><th>Protocol</th><th>Method</th><th>Host</th><th>Port</th><th>Status</th><th>Path</th><th>Reason</th></tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>
  `
}

loadEvents().then(render).catch((error) => {
  app.innerHTML = `<pre>${esc(error.stack || error.message)}</pre>`
})
