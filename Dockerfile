# Stage 1: Build virtual environment dependencies using uv
FROM python:3.14-slim AS builder

# Install uv binary from official image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Set environment variables for uv build process
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

WORKDIR /app

# Install dependencies into .venv using cache and bind mounts for maximum performance
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    --mount=type=bind,source=uv.lock,target=uv.lock,errors=ignore \
    uv venv /app/.venv && \
    uv pip install --system --target /app/.venv/lib/python3.14/site-packages -r pyproject.toml

# Stage 2: Minimal runtime container
FROM python:3.14-slim AS runner

WORKDIR /app

# Create non-root system user and prepare media/static directories
RUN groupadd --system appgroup && \
    useradd --system -g appgroup appuser && \
    mkdir -p /app/media /app/static && \
    chown -R appuser:appgroup /app

# Environment configuration
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Copy virtual environment and source code with proper ownership
COPY --from=builder --chown=appuser:appgroup /app/.venv /app/.venv
COPY --chown=appuser:appgroup . .

# Expose default Django port
EXPOSE 8000

# Switch to non-root user
USER appuser

# Health-check routine via internal Django endpoint
HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health/').read()"]

# Default run command
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]