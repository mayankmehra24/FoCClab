




"""
FoCC Lab 2 - Flask Frontend with Redis Backend
Two-tier cloud-native web application that tracks HTTP request counts
and exposes Prometheus-compatible metrics for monitoring integration.
"""

import os
import time
import logging
import socket

import redis
from flask import Flask, render_template_string, jsonify, request, Response

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = Flask(__name__)

# ---------------------------------------------------------------------------
# Redis connection  (environment-driven, no hard-coded values)
# ---------------------------------------------------------------------------
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", None)   # optional


def get_redis():
    """Return a Redis client, or None if unavailable."""
    try:
        client = redis.Redis(
            host=REDIS_HOST,
            port=REDIS_PORT,
            password=REDIS_PASSWORD,
            decode_responses=True,
            socket_connect_timeout=2,
        )
        client.ping()
        return client
    except Exception as exc:
        logger.warning("Redis unavailable: %s", exc)
        return None


# ---------------------------------------------------------------------------
# Prometheus-style metrics (simple in-process counters)
# ---------------------------------------------------------------------------
_req_count = 0
_latency_sum = 0.0
_latency_count = 0
_latency_buckets = {
    0.005: 0, 0.01: 0, 0.025: 0, 0.05: 0,
    0.1: 0, 0.25: 0, 0.5: 0, 1.0: 0, float("inf"): 0,
}


def record_latency(elapsed: float):
    global _latency_sum, _latency_count
    _latency_sum += elapsed
    _latency_count += 1
    for upper in sorted(_latency_buckets):
        if elapsed <= upper:
            _latency_buckets[upper] += 1
            break


# ---------------------------------------------------------------------------
# Middleware - count every request
# ---------------------------------------------------------------------------
@app.before_request
def _before():
    request._start = time.perf_counter()


@app.after_request
def _after(response):
    global _req_count
    _req_count += 1
    elapsed = time.perf_counter() - getattr(request, "_start", time.perf_counter())
    record_latency(elapsed)
    return response


# ---------------------------------------------------------------------------
# HTML Template
# ---------------------------------------------------------------------------
INDEX_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>FoCC Lab 2 - Cloud Visit Counter</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;700&display=swap" rel="stylesheet">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Inter', sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: linear-gradient(135deg, #0f0c29, #302b63, #24243e);
      color: #e2e8f0;
    }
    .card {
      background: rgba(255,255,255,0.07);
      backdrop-filter: blur(18px);
      border: 1px solid rgba(255,255,255,0.12);
      border-radius: 24px;
      padding: 3rem 2.5rem;
      max-width: 640px;
      width: 95%;
      box-shadow: 0 25px 60px rgba(0,0,0,0.4);
      animation: fadeUp .6s ease both;
    }
    @keyframes fadeUp {
      from { opacity:0; transform:translateY(30px); }
      to   { opacity:1; transform:translateY(0); }
    }
    .badge {
      display: inline-block;
      background: linear-gradient(90deg, #7c3aed, #2563eb);
      font-size: .75rem;
      font-weight: 600;
      letter-spacing: .08em;
      text-transform: uppercase;
      padding: .3rem .9rem;
      border-radius: 999px;
      margin-bottom: 1.5rem;
    }
    h1 { font-size: 2rem; font-weight: 700; line-height: 1.2; margin-bottom: .5rem; }
    .subtitle { color: #94a3b8; font-size: .95rem; margin-bottom: 2rem; }
    .counter-box {
      background: rgba(124,58,237,0.18);
      border: 1px solid rgba(124,58,237,0.4);
      border-radius: 16px;
      padding: 1.5rem;
      text-align: center;
      margin-bottom: 1.5rem;
    }
    .counter-label { font-size: .85rem; color: #a78bfa; font-weight: 600; text-transform: uppercase; letter-spacing: .06em; }
    .counter-value { font-size: 4rem; font-weight: 700; color: #c4b5fd; line-height: 1.1; }
    .meta-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: .75rem;
      margin-bottom: 1.5rem;
    }
    .meta-item {
      background: rgba(255,255,255,0.05);
      border-radius: 12px;
      padding: .9rem 1rem;
    }
    .meta-item .key { font-size: .75rem; color: #64748b; text-transform: uppercase; letter-spacing: .05em; }
    .meta-item .val { font-size: .95rem; font-weight: 600; margin-top: .2rem; word-break: break-all; }
    .status { display: flex; align-items: center; gap: .5rem; font-size: .85rem; }
    .dot { width: 9px; height: 9px; border-radius: 50%; }
    .dot.ok  { background: #22c55e; box-shadow: 0 0 6px #22c55e; }
    .dot.err { background: #ef4444; box-shadow: 0 0 6px #ef4444; }
    .refresh-btn {
      display: block; width: 100%;
      background: linear-gradient(90deg, #7c3aed, #2563eb);
      color: #fff; font-size: 1rem; font-weight: 600;
      border: none; border-radius: 12px;
      padding: .85rem; cursor: pointer;
      transition: opacity .2s, transform .1s;
      margin-top: 1rem;
    }
    .refresh-btn:hover { opacity: .88; }
    .refresh-btn:active { transform: scale(.98); }
    .footer { margin-top: 2rem; font-size: .78rem; color: #475569; text-align: center; }
  </style>
</head>
<body>
<div class="card">
  <span class="badge">FoCC Lab 2</span>
  <h1>Cloud Visit Counter</h1>
  <p class="subtitle">Two-tier Flask + Redis on Kubernetes</p>

  <div class="counter-box">
    <div class="counter-label">Total Visits (Redis)</div>
    <div class="counter-value">{{ visit_count }}</div>
  </div>

  <div class="meta-grid">
    <div class="meta-item">
      <div class="key">Pod / Host</div>
      <div class="val">{{ hostname }}</div>
    </div>
    <div class="meta-item">
      <div class="key">Redis Host</div>
      <div class="val">{{ redis_host }}</div>
    </div>
    <div class="meta-item">
      <div class="key">App Version</div>
      <div class="val">{{ app_version }}</div>
    </div>
    <div class="meta-item">
      <div class="key">Redis Status</div>
      <div class="val">
        <span class="status">
          <span class="dot {{ 'ok' if redis_ok else 'err' }}"></span>
          {{ 'Connected' if redis_ok else 'Unavailable' }}
        </span>
      </div>
    </div>
  </div>

  <button class="refresh-btn" onclick="location.reload()">Refresh Counter</button>
  <p class="footer">Fundamentals of Cloud Computing - Lab 2 | Pod: {{ hostname }}</p>
</div>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    r = get_redis()
    if r:
        visit_count = r.incr("visit_count")
        redis_ok = True
    else:
        visit_count = "N/A (Redis down)"
        redis_ok = False

    return render_template_string(
        INDEX_HTML,
        visit_count=visit_count,
        hostname=socket.gethostname(),
        redis_host=REDIS_HOST,
        redis_ok=redis_ok,
        app_version=os.getenv("APP_VERSION", "1.0.0"),
    )


@app.route("/health")
@app.route("/health/live")
def liveness():
    """Liveness probe - returns HTTP 200 and a simple JSON status response."""
    return jsonify(status="ok", pod=socket.gethostname()), 200


@app.route("/ready")
@app.route("/health/ready")
def readiness():
    """Readiness probe - checks whether Flask can connect to Redis."""
    r = get_redis()
    if r is None:
        return jsonify(status="unavailable", reason="redis unreachable"), 503
    return jsonify(status="ok", redis="connected"), 200


@app.route("/metrics")
def metrics():
    """Minimal Prometheus text exposition format."""
    global _req_count, _latency_sum, _latency_count, _latency_buckets

    r = get_redis()
    redis_visits = 0
    try:
        redis_visits = int(r.get("visit_count") or 0) if r else 0
    except Exception:
        pass

    lines = [
        "# HELP http_requests_total Total HTTP requests received",
        "# TYPE http_requests_total counter",
        'http_requests_total{app="focc-lab2"} ' + str(_req_count),
        "",
        "# HELP http_request_duration_seconds HTTP request latency",
        "# TYPE http_request_duration_seconds histogram",
    ]
    cumulative = 0
    for upper in sorted(_latency_buckets):
        cumulative += _latency_buckets[upper]
        le = "+Inf" if upper == float("inf") else str(upper)
        lines.append(
            'http_request_duration_seconds_bucket{app="focc-lab2",le="' + le + '"} ' + str(cumulative)
        )
    lines += [
        'http_request_duration_seconds_sum{app="focc-lab2"} ' + f"{_latency_sum:.6f}",
        'http_request_duration_seconds_count{app="focc-lab2"} ' + str(_latency_count),
        "",
        "# HELP redis_visit_count Total visits stored in Redis",
        "# TYPE redis_visit_count gauge",
        'redis_visit_count{app="focc-lab2"} ' + str(redis_visits),
        "",
    ]
    return Response("\n".join(lines), mimetype="text/plain; version=0.0.4")


@app.route("/api/stats")
def api_stats():
    """JSON endpoint for dashboard / testing."""
    r = get_redis()
    redis_visits = None
    try:
        redis_visits = int(r.get("visit_count") or 0) if r else None
    except Exception:
        pass
    avg_latency = (_latency_sum / _latency_count) if _latency_count else 0
    return jsonify(
        http_requests_total=_req_count,
        redis_visit_count=redis_visits,
        avg_latency_ms=round(avg_latency * 1000, 3),
        pod=socket.gethostname(),
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    debug = os.getenv("FLASK_DEBUG", "false").lower() == "true"
    logger.info("Starting Flask app on port %d (debug=%s)", port, debug)
    app.run(host="0.0.0.0", port=port, debug=debug)
