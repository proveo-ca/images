const app = document.querySelector('#app')

async function loadEvents() {
  const response = await fetch('/api/events')
  if (!response.ok) throw new Error(`events failed: ${response.status}`)
  return response.json()
}

function render(events) {
  const rows = events
    .map((event) => `
      <tr class="${event.decision}">
        <td>${event.ts || ''}</td>
        <td>${event.source}</td>
        <td>${event.decision}</td>
        <td>${event.protocol || ''}</td>
        <td>${event.method || ''}</td>
        <td>${event.host || ''}</td>
        <td>${event.port || ''}</td>
        <td>${event.status || ''}</td>
        <td>${event.path || ''}</td>
        <td>${event.reason || ''}</td>
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
  app.innerHTML = `<pre>${error.stack || error.message}</pre>`
})
