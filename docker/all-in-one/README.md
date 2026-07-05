# KohakuHub All-in-One Docker

> **Official documentation**: See [docs/deployment/all-in-one.md](../../docs/deployment/all-in-one.md) for the complete guide.

This directory contains the supporting files for the single-container image (`Dockerfile.all-in-one`).

## Quick Reference

- Build: `docker build -f Dockerfile.all-in-one -t kohakuhub:all-in-one .`
- Run with backup-friendly volume:
  ```bash
  docker run -d -p 28080:80 -v /your/backup/path:/data kohakuhub:all-in-one
  ```

All persistent data (MinIO, LakeFS, SQLite, credentials) lives under the mounted `/data` directory for easy backup and restore.

## Quick Start

```bash
# 1. Build
docker build -f Dockerfile.all-in-one -t kohakuhub:all-in-one .

# 2. Run (mount a dedicated host directory for all data)
docker run -d \
  --name kohakuhub \
  -p 28080:80 \
  -v /path/to/your/kohakuhub-data:/data \
  -e KOHAKU_HUB_BASE_URL=http://your-domain-or-ip:28080 \
  -e KOHAKU_HUB_S3_PUBLIC_ENDPOINT=http://your-domain-or-ip:29001 \
  kohakuhub:all-in-one
```

Access:
- UI: http://localhost:28080
- Admin: http://localhost:28080/admin

## Data & Backup (the important part)

All persistent state lives under a single directory inside the container:

```
/data
├── minio/          # All objects (LFS files + LakeFS blockstore data)
├── lakefs/         # LakeFS metadata.db + cache
├── db/             # SQLite database (hub.db)
├── creds/          # LakeFS access keys (auto-generated on first run)
└── logs/           # Service logs
```

### Recommended usage for backups

```bash
# Run with a dedicated storage location
docker run -d \
  -v /mnt/storage/kohakuhub:/data \
  ...
```

**Backup procedure (recommended):**

1. Stop the container cleanly:
   ```bash
   docker stop kohakuhub
   ```

2. Backup the entire directory:
   ```bash
   tar czf kohakuhub-backup-$(date +%F-%H%M).tar.gz -C /mnt/storage/kohakuhub .
   ```

3. (Optional) Backup only critical parts:
   - `minio/` — contains your actual model/dataset files
   - `db/hub.db` — metadata
   - `creds/credentials.env` — LakeFS keys (losing this may make existing LakeFS data inaccessible)
   - `lakefs/` — LakeFS metadata

**Restore:**

```bash
# On a new machine / new container
mkdir -p /mnt/storage/kohakuhub
tar xzf kohakuhub-backup-....tar.gz -C /mnt/storage/kohakuhub
docker run -d -v /mnt/storage/kohakuhub:/data ...
```

### Separate volume mounts (advanced)

You can mount subdirectories individually if you want different storage for different components:

```bash
docker run -d \
  -v /fast-ssd/kh-minio:/data/minio \
  -v /backup-disk/kh-lakefs:/data/lakefs \
  -v /backup-disk/kh-db:/data/db \
  ...
```

## Important Environment Variables

All normal `KOHAKU_HUB_*` variables are supported.

Particularly useful in all-in-one:

- `KOHAKU_DATA_DIR` — root for everything (default `/data`)
- `KOHAKU_HUB_BASE_URL`
- `KOHAKU_HUB_S3_PUBLIC_ENDPOINT` — **critical** for clients to download files correctly
- `LAKEFS_AUTH_ENCRYPT_SECRET_KEY` — change this (or let the entrypoint generate one)
- `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`
- `KOHAKU_HUB_WORKERS` — recommend 1–2 in all-in-one

You can override any LakeFS or MinIO variable as usual.

## Exposing internal services (optional)

```bash
# Also expose MinIO and LakeFS UIs / APIs
docker run -d \
  -p 28080:80 \
  -p 29001:9000 \     # MinIO S3
  -p 29000:29000 \    # MinIO Console
  -p 28000:28000 \    # LakeFS
  ...
```

## Logs

All logs are written to `/data/logs/` inside the container (also visible via `docker logs`).

## Upgrading

1. Stop container
2. Backup `/data`
3. Pull/build new image
4. Start again with same volume mount

## Limitations & Tips

- When using the default internal MinIO, direct S3 URLs may only work from inside or when you also publish port 29001.
- For production public deployments, consider putting a real reverse proxy in front and setting correct public endpoints.
- SQLite is used by default (fine for small-medium instances). For very high concurrency you may want to switch to external Postgres.
- The generated secrets on first run are printed to logs. Save them.

## Switching back to multi-container

You can always move the data out of the all-in-one volume into a normal docker-compose setup (MinIO data dir, LakeFS data dir, SQLite file or Postgres dump).

This all-in-one image is a convenience layer on top of the same components.
