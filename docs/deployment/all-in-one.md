---
title: All-in-One Docker
description: Single-container deployment of KohakuHub (MinIO + LakeFS + API + Nginx) with simple backup via one volume mount.
icon: i-carbon-container-software
---

# All-in-One Docker Deployment

Deploy the **entire KohakuHub stack in a single Docker container**.

This image bundles:

- MinIO (S3-compatible storage)
- LakeFS (data versioning)
- Nginx (frontend + reverse proxy)
- KohakuHub API (FastAPI + uvicorn)

## When to Use All-in-One

**Good for:**
- Quick demos and trials
- Small self-hosted instances
- Development / testing environments
- Air-gapped or simple deployments
- Users who want **one command + one volume** for everything

**Not recommended for:**
- Production with many users (use [Docker Compose](./docker.md) + external services instead)
- High-availability or scaled setups
- Environments where you want independent scaling or updates of components

## Key Advantage: Easy Backup

All persistent data lives under a **single directory** inside the container (`/data` by default). You only need to mount and back up **one host directory**.

```
/data
├── minio/           # All your model/dataset files (LFS objects + LakeFS blockstore)
├── lakefs/          # LakeFS metadata and cache
├── db/              # SQLite database (hub.db)
├── creds/           # Auto-generated LakeFS credentials
└── logs/            # Service logs
```

This design directly addresses the requirement for easy, centralized backups.

## Build the Image

```bash
# From the repository root
docker build -f Dockerfile.all-in-one -t kohakuhub:all-in-one .
```

> **Note**: The build includes a full frontend build (pnpm). It can take several minutes the first time.

## Run the Container

### Recommended (with dedicated backup volume)

```bash
docker run -d \
  --name kohakuhub \
  -p 28080:80 \
  -v /path/on/host/kohakuhub-data:/data \
  -e KOHAKU_HUB_BASE_URL=http://localhost:28080 \
  -e KOHAKU_HUB_S3_PUBLIC_ENDPOINT=http://localhost:29001 \
  kohakuhub:all-in-one
```

### Minimal one-liner (data will be lost on container removal)

```bash
docker run -d -p 28080:80 kohakuhub:all-in-one
```

Access the service at: **http://localhost:28080**

- Main UI: http://localhost:28080
- Admin portal: http://localhost:28080/admin

## Data Directory & Backup Strategy

### Directory Layout

| Path               | Content                              | Importance for Backup |
|--------------------|--------------------------------------|-----------------------|
| `/data/minio`      | All uploaded files + LakeFS objects  | **Critical**          |
| `/data/lakefs`     | LakeFS metadata database + cache     | **Critical**          |
| `/data/db/hub.db`  | Application metadata (SQLite)        | **Critical**          |
| `/data/creds/`     | LakeFS access keys                   | **Critical** (losing this may make existing objects inaccessible) |
| `/data/logs/`      | Logs from all services               | Optional              |

### Backup Procedure (Recommended)

```bash
# 1. Stop the container gracefully
docker stop kohakuhub

# 2. Backup the entire data directory
tar czf kohakuhub-backup-$(date +%F-%H%M).tar.gz -C /path/on/host/kohakuhub-data .

# 3. (Optional) Start the container again
docker start kohakuhub
```

### Restore Procedure

```bash
# On the target machine
mkdir -p /path/on/host/kohakuhub-data
tar xzf kohakuhub-backup-....tar.gz -C /path/on/host/kohakuhub-data

docker run -d \
  -v /path/on/host/kohakuhub-data:/data \
  -p 28080:80 \
  kohakuhub:all-in-one
```

### Advanced: Separate Mounts

You can mount subdirectories individually if you want different storage backends:

```bash
docker run -d \
  -v /fast-ssd/kh-minio:/data/minio \
  -v /nas/backup/kh-lakefs:/data/lakefs \
  -v /nas/backup/kh-db:/data/db \
  -p 28080:80 \
  kohakuhub:all-in-one
```

## Important Environment Variables

| Variable                              | Default (in all-in-one)          | Notes |
|---------------------------------------|----------------------------------|-------|
| `KOHAKU_DATA_DIR`                     | `/data`                          | Root of all persistent data |
| `KOHAKU_HUB_BASE_URL`                 | `http://localhost:28080`         | **Must change** for external access |
| `KOHAKU_HUB_S3_PUBLIC_ENDPOINT`       | `http://127.0.0.1:29001`         | Used for presigned URLs – very important |
| `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` | `minioadmin` / `minioadmin`   | Change in production |
| `LAKEFS_AUTH_ENCRYPT_SECRET_KEY`      | (auto-generated)                 | Change for production |
| `KOHAKU_HUB_WORKERS`                  | `2`                              | Lower than compose because resources are shared |
| `KOHAKU_HUB_DB_BACKEND`               | `sqlite`                         | Uses SQLite by default |

All normal `KOHAKU_HUB_*` variables are supported.

## Exposing Internal Services

By default only port 80 (nginx) is used. You can expose the others if needed:

```bash
docker run -d \
  -p 28080:80 \
  -p 29001:9000 \     # MinIO S3 API
  -p 29000:29000 \    # MinIO Console
  -p 28000:28000 \    # LakeFS UI
  -v /your/data:/data \
  kohakuhub:all-in-one
```

## Logs

All logs are written inside the container:

- `/data/logs/`
- Also visible with `docker logs kohakuhub`

## Limitations

- **Single point of failure**: If the container dies, everything stops.
- **Resource contention**: MinIO, LakeFS, and the API share CPU/memory.
- **Image size**: ~1.2–1.4 GB (includes Node build stage artifacts + binaries).
- **No built-in Valkey**: Cache is disabled by default (`KOHAKU_HUB_CACHE_ENABLED=false`).
- **LakeFS uses local DB + MinIO** (inside the same container).

For serious production use, prefer the [Docker Compose deployment](./docker.md).

## Upgrading

1. Stop the container.
2. **Backup** your `/data` volume.
3. Pull or rebuild the new image.
4. Start the container with the same volume mount.

## Troubleshooting

**Container starts but UI doesn't load**
- Wait longer (LakeFS initialization + first-time setup can take 30–90 seconds).
- Check logs: `docker logs kohakuhub --tail 100`

**"Failed to resolve @unocss/reset" during custom rebuild**
- Not applicable to the pre-built image. If you modify the Dockerfile, ensure the `.npmrc` hoisting settings and the explicit `@unocss/reset` step are present.

**Presigned URLs don't work from browser / HF client**
- Set `KOHAKU_HUB_S3_PUBLIC_ENDPOINT` correctly to a URL that clients can reach (often the same as your main domain or an exposed MinIO port).

**Want to switch to external Postgres / external S3 later?**
- You can migrate. The all-in-one is just a convenience wrapper around the same components used in compose.

## Related Documentation

- [Docker Deployment (Compose)](./docker.md) – Recommended for most users
- [Production Deployment](./production.md)
- [docker/all-in-one/README.md](../../docker/all-in-one/README.md) – Technical reference inside the repository
