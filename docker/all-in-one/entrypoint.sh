#!/bin/bash
# All-in-One entrypoint for KohakuHub
# - Sets up data directories under KOHAKU_DATA_DIR (default /data)
# - Configures environment for MinIO, LakeFS, App (SQLite + localhost services)
# - Launches supervisord which manages all services
#
# Backup-friendly design:
#   Mount a single host directory to /data (or override subpaths).
#   All persistent state lives under it:
#     /data/minio/   - Object storage (LFS + LakeFS blocks)
#     /data/lakefs/  - LakeFS metadata.db + cache
#     /data/db/      - SQLite database (hub.db)
#     /data/creds/   - Auto-generated LakeFS credentials
#     /data/logs/    - Logs (optional to backup)

set -euo pipefail

# Root data directory - the "專屬儲存位置" user mounts
DATA_DIR="${KOHAKU_DATA_DIR:-/data}"

echo "[entrypoint] Using data directory: $DATA_DIR"

# Create standard layout for easy backup/restore
mkdir -p \
  "$DATA_DIR/minio" \
  "$DATA_DIR/lakefs" \
  "$DATA_DIR/db" \
  "$DATA_DIR/creds" \
  "$DATA_DIR/logs"

# Fix permissions so non-root friendly if user passes --user
# (supervisord runs as root by default for binding ports, but data is world-readable where possible)
chown -R root:root "$DATA_DIR" 2>/dev/null || true

# ============================================================
# MinIO configuration (internal only by default)
# ============================================================
export MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
export MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin}"
# Allow CORS for browser previews (same as compose example)
export MINIO_API_CORS_ALLOW_ORIGIN="${MINIO_API_CORS_ALLOW_ORIGIN:-*}"

# ============================================================
# LakeFS configuration (local DB + S3 blockstore pointing at internal MinIO)
# ============================================================
export LAKEFS_DATABASE_TYPE="${LAKEFS_DATABASE_TYPE:-local}"
export LAKEFS_DATABASE_LOCAL_PATH="${LAKEFS_DATABASE_LOCAL_PATH:-$DATA_DIR/lakefs/metadata.db}"
export LAKEFS_BLOCKSTORE_TYPE="${LAKEFS_BLOCKSTORE_TYPE:-s3}"
export LAKEFS_BLOCKSTORE_S3_ENDPOINT="${LAKEFS_BLOCKSTORE_S3_ENDPOINT:-http://127.0.0.1:9000}"
export LAKEFS_BLOCKSTORE_S3_BUCKET="${LAKEFS_BLOCKSTORE_S3_BUCKET:-hub-storage}"
export LAKEFS_BLOCKSTORE_S3_FORCE_PATH_STYLE="${LAKEFS_BLOCKSTORE_S3_FORCE_PATH_STYLE:-true}"
export LAKEFS_BLOCKSTORE_S3_CREDENTIALS_ACCESS_KEY_ID="${LAKEFS_BLOCKSTORE_S3_CREDENTIALS_ACCESS_KEY_ID:-$MINIO_ROOT_USER}"
export LAKEFS_BLOCKSTORE_S3_CREDENTIALS_SECRET_ACCESS_KEY="${LAKEFS_BLOCKSTORE_S3_CREDENTIALS_SECRET_ACCESS_KEY:-$MINIO_ROOT_PASSWORD}"
export LAKEFS_BLOCKSTORE_S3_REGION="${LAKEFS_BLOCKSTORE_S3_REGION:-us-east-1}"
export LAKEFS_AUTH_ENCRYPT_SECRET_KEY="${LAKEFS_AUTH_ENCRYPT_SECRET_KEY:-change-me-in-production-all-in-one}"
export LAKEFS_LOGGING_FORMAT="${LAKEFS_LOGGING_FORMAT:-text}"
export LAKEFS_LISTEN_ADDRESS="${LAKEFS_LISTEN_ADDRESS:-127.0.0.1:28000}"

# ============================================================
# KohakuHub App configuration (SQLite + internal endpoints)
# ============================================================
export KOHAKU_HUB_DB_BACKEND="${KOHAKU_HUB_DB_BACKEND:-sqlite}"
export KOHAKU_HUB_DATABASE_URL="${KOHAKU_HUB_DATABASE_URL:-sqlite:///$DATA_DIR/db/hub.db}"
export KOHAKU_HUB_AUTO_MIGRATE="${KOHAKU_HUB_AUTO_MIGRATE:-true}"

# S3 points to the internal MinIO
export KOHAKU_HUB_S3_ENDPOINT="${KOHAKU_HUB_S3_ENDPOINT:-http://127.0.0.1:9000}"
export KOHAKU_HUB_S3_ACCESS_KEY="${KOHAKU_HUB_S3_ACCESS_KEY:-$MINIO_ROOT_USER}"
export KOHAKU_HUB_S3_SECRET_KEY="${KOHAKU_HUB_S3_SECRET_KEY:-$MINIO_ROOT_PASSWORD}"
export KOHAKU_HUB_S3_BUCKET="${KOHAKU_HUB_S3_BUCKET:-hub-storage}"
export KOHAKU_HUB_S3_REGION="${KOHAKU_HUB_S3_REGION:-us-east-1}"
export KOHAKU_HUB_S3_PUBLIC_ENDPOINT="${KOHAKU_HUB_S3_PUBLIC_ENDPOINT:-http://127.0.0.1:29001}"  # change in production!

# LakeFS endpoint (internal)
export KOHAKU_HUB_LAKEFS_ENDPOINT="${KOHAKU_HUB_LAKEFS_ENDPOINT:-http://127.0.0.1:28000}"
export KOHAKU_HUB_LAKEFS_REPO_NAMESPACE="${KOHAKU_HUB_LAKEFS_REPO_NAMESPACE:-hf}"

# Base URL users will access (important for generated links)
export KOHAKU_HUB_BASE_URL="${KOHAKU_HUB_BASE_URL:-http://localhost:28080}"

# Creds file for LakeFS auto-setup (shared with startup.py)
export CRED_FILE="${CRED_FILE:-$DATA_DIR/creds/credentials.env}"  # startup.py reads/writes this

# Performance: fewer workers in all-in-one (resources shared with MinIO+LakeFS)
export KOHAKU_HUB_WORKERS="${KOHAKU_HUB_WORKERS:-2}"

# Other common sane defaults
# Generate secrets only if not provided (first run convenience)
generate_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 48 | tr -d '\n'
    else
        python3 -c 'import secrets; print(secrets.token_urlsafe(48))' 2>/dev/null || echo "change-this-$(date +%s)"
    fi
}

export KOHAKU_HUB_SESSION_SECRET="${KOHAKU_HUB_SESSION_SECRET:-$(generate_secret)}"
export KOHAKU_HUB_ADMIN_SECRET_TOKEN="${KOHAKU_HUB_ADMIN_SECRET_TOKEN:-$(generate_secret)}"

# Optional: Cache disabled by default in all-in-one (no valkey)
export KOHAKU_HUB_CACHE_ENABLED="${KOHAKU_HUB_CACHE_ENABLED:-false}"

echo "[entrypoint] Environment prepared."
echo "[entrypoint]   DATA_DIR=$DATA_DIR"
echo "[entrypoint]   DB: $KOHAKU_HUB_DATABASE_URL"
echo "[entrypoint]   S3 internal: $KOHAKU_HUB_S3_ENDPOINT"
echo "[entrypoint]   LakeFS: $KOHAKU_HUB_LAKEFS_ENDPOINT"
echo "[entrypoint] Starting supervisord..."

# Ensure logs dir exists for supervisor too
mkdir -p /data/logs

# Launch supervisord (it will start minio, lakefs, nginx, api)
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
