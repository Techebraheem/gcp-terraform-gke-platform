# Multi-stage build: build deps in one layer, ship only what's needed at runtime.

FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Distroless: no shell, no package manager, no Perl/ncurses/etc — the OS-level
# CVEs Trivy was flagging (perl-archive-tar, ncurses, perl itself) don't exist
# here because those packages simply aren't present. Trade-off: no `docker
# exec ... sh` for interactive debugging — use `kubectl debug` with an
# ephemeral container instead if you ever need a shell against a running pod.
FROM gcr.io/distroless/python3-debian12

WORKDIR /app
# Distroless images run as a non-root "nonroot" user by default already —
# no separate `useradd` step needed, unlike the Debian-slim version.
COPY --from=builder /root/.local /home/nonroot/.local
COPY main.py .

ENV PATH=/home/nonroot/.local/bin:$PATH
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/home/nonroot/.local/lib/python3.12/site-packages

USER nonroot

EXPOSE 8080

# Distroless has no shell, so exec form (already used here) is mandatory —
# shell form (CMD "gunicorn ...") would fail with no /bin/sh to invoke.
# Also note: gunicorn itself must be present in the copied .local packages,
# which it is, since requirements.txt installs it into --user site-packages.
CMD ["/home/nonroot/.local/bin/gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "4", "main:app"]