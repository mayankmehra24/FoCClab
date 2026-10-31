# ============================================================
# FoCC Lab 2 - Multi-stage Dockerfile
# Stage 1: builder  - installs Python deps into a venv
# Stage 2: runtime  - slim production image
# ============================================================

# ---- Stage 1: Builder ----
FROM python:3.12-slim AS builder

WORKDIR /build

# Install build tools only in this stage
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Create an isolated virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy only requirements first for layer caching
COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt


# ---- Stage 2: Runtime ----
FROM python:3.12-slim AS runtime

# Metadata labels
LABEL org.opencontainers.image.title="FoCC Lab 2 Frontend" \
      org.opencontainers.image.description="Flask + Redis visit counter" \
      org.opencontainers.image.version="1.0.0"

# Non-root user for security
RUN groupadd --gid 1001 appgroup && \
    useradd  --uid 1001 --gid appgroup --no-create-home appuser

WORKDIR /app

# Copy the pre-built venv from builder stage (multi-stage benefit)
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application source
COPY app.py .

# Environment defaults (overridden at runtime via env vars / k8s secrets)
ENV REDIS_HOST=redis \
    REDIS_PORT=6379 \
    PORT=5000 \
    FLASK_DEBUG=false \
    APP_VERSION=1.0.0

# Use non-root user
USER appuser

EXPOSE 5000

# Health check for docker-compose (Kubernetes uses probes instead)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health/live')"

# Run via Gunicorn for production performance
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", \
     "--timeout", "30", "--access-logfile", "-", "--error-logfile", "-", \
     "app:app"]
