"""Append each completed flow as one NDJSON line for the egress dashboard.

The dashboard (`defs/egress-dashboard/server.js`) normalizes Squid access logs,
egress-guard reject logs, and these mitmproxy flow records into a single event
timeline. Emit exactly the fields it expects, one JSON object per line.

Because HTTPS interception is on, this records the decrypted method, path, and
host for HTTPS flows too — visibility the previous Charles wiring never had.
"""

import json
import os

from mitmproxy import http


class NdjsonDump:
    def __init__(self) -> None:
        flows_dir = os.getenv("PROVEO_MITM_FLOWS", "/flows")
        os.makedirs(flows_dir, exist_ok=True)
        # Line-buffered append so the dashboard sees events as they happen.
        self._fh = open(os.path.join(flows_dir, "flows.ndjson"), "a", buffering=1)

    def response(self, flow: http.HTTPFlow) -> None:
        self._write(flow)

    def error(self, flow: http.HTTPFlow) -> None:
        self._write(flow)

    def _write(self, flow: http.HTTPFlow) -> None:
        req = flow.request
        resp = flow.response
        ts = req.timestamp_start
        record = {
            "ts": f"{ts:.3f}" if ts else "",
            "source": "mitmproxy",
            "decision": "observed",
            "protocol": req.scheme,
            "method": req.method,
            "host": req.pretty_host,
            "port": str(req.port),
            "path": req.path,
            "status": str(resp.status_code) if resp else "",
            "reason": "mitmproxy_flow",
        }
        self._fh.write(json.dumps(record) + "\n")

    def done(self) -> None:
        try:
            self._fh.close()
        except Exception:
            pass


addons = [NdjsonDump()]
