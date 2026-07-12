import logging
import os

from flask import Flask, jsonify
from google.cloud import secretmanager

# Structured JSON logging — Cloud Logging parses this automatically and extracts
# severity, so logs show up correctly leveled in the console instead of all as
# "default" severity. This is the equivalent of your Grafana/LGTM structured
# logging setup, just Google's ingestion side instead of Loki's.
logging.basicConfig(level=logging.INFO, format='{"severity":"%(levelname)s","message":"%(message)s"}')
logger = logging.getLogger(__name__)

app = Flask(__name__)

PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "unknown-project")


def get_secret(secret_id: str, version: str = "latest") -> str:
    """
    Reads a secret from Secret Manager at runtime using the pod's Workload
    Identity — no key files, no env var secrets. If you're demoing this,
    note that the CSI driver approach (mounting as a file) is the more
    "GitOps-native" pattern; this client-library approach is shown here
    because it's easier to reason about in an interview walkthrough.
    """
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/{version}"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")


@app.route("/")
def index():
    logger.info("index endpoint hit")
    return jsonify(message="GCP reference app is running", project=PROJECT_ID)


@app.route("/healthz")
def healthz():
    # Liveness probe target — no external dependency checks here on purpose,
    # this should only fail if the process itself is broken.
    return jsonify(status="ok"), 200


@app.route("/readyz")
def readyz():
    # Readiness probe target — checks a real dependency (Secret Manager reachability)
    # so Kubernetes stops routing traffic if the pod can't do its job, even though
    # the process is technically alive.
    try:
        get_secret("flask-app-secret-key")
        return jsonify(status="ready"), 200
    except Exception as e:
        logger.error(f"readiness check failed: {e}")
        return jsonify(status="not_ready"), 503


@app.route("/metrics-check")
def metrics_check():
    # Placeholder route to demonstrate a custom business metric you'd emit
    # via OpenTelemetry -> Cloud Monitoring in a real build.
    return jsonify(status="metric emitted"), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
