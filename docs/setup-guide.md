# Character Archive Setup Guide

This guide covers installing the Character Archive search frontend using the official torrent layout and Docker Compose.

## What you need

| Requirement | Notes |
|-------------|-------|
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows/macOS) or Docker Engine + Compose v2 (Linux) | |
| ~70GB free disk space | ~20GB database after import + torrent archive on disk |
| Character Archive torrent | Download and extract before setup |

## Torrent layout

Everything lives in one download folder:

```
<torrent-download-dir>/
  database.dump              # PostgreSQL dump (~11GB) — at torrent root
  archive.7z.001 … .020      # extract these with 7-Zip
  archive/                   # created by extraction
    hashed-data/             # character images (required)
    files/                   # raw files (not needed for search UI)
    webring/
```

Extract all `archive.7z.*` parts with [7-Zip](https://www.7-zip.org/) before running setup. You should end up with `archive/hashed-data/` alongside `database.dump`.

## Quick start (recommended)

### Linux / macOS

```bash
git clone https://github.com/sproutingnerd/char-archive-small_frontend.git
cd char-archive-small_frontend
./setup.sh
```

When prompted, enter your torrent download directory (the folder containing `database.dump` and `archive/`).

### Windows

```powershell
git clone https://github.com/sproutingnerd/char-archive-small_frontend.git
cd char-archive-small_frontend
.\setup.ps1
```

Requires PowerShell and Docker Desktop. Enter the torrent folder path when prompted.

### What setup does

1. Validates `database.dump` and `archive/hashed-data/` exist
2. Writes `.env` with paths and generated passwords
3. Writes `docker-compose.override.yml` to mount your torrent data (no copying)
4. Runs `docker compose up -d --build`
5. Waits for the database import to finish (first run only; can take 30+ minutes)
6. Rebuilds the tag search index

When finished, open **http://localhost:8080**. Credentials are in `.env`.

### Non-interactive (Linux/macOS)

```bash
./setup.sh --torrent-dir /path/to/character-archive-final-torrent
./setup.sh --torrent-dir /path/to/torrent --no-wait    # start stack, skip import wait
./setup.sh --torrent-dir /path/to/torrent --skip-tags  # skip tag index rebuild
```

## Manual setup (advanced)

If you prefer not to use the setup scripts:

```bash
cp .env.example .env
# Edit .env — set TORRENT_DIR, ARCHIVE_HOST_PATH, DATABASE_DUMP_PATH, passwords
```

Create `docker-compose.override.yml` (see `docker-compose.override.example.yml`) or merge the import overlay:

```bash
docker compose -f docker-compose.yml -f docker-compose.import.yml up -d
```

For normal runs after import:

```bash
docker compose up -d
```

## Service details

| Service | URL | Default port |
|---------|-----|--------------|
| Frontend | http://localhost:8080 | `FRONTEND_PORT` |
| pgAdmin | http://localhost:5050 | `PGADMIN_PORT` |
| PostgreSQL | localhost:5432 | `POSTGRES_PORT` |

pgAdmin login: `PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD` from `.env`.

To connect pgAdmin to Postgres: host `postgres`, port `5432`, database `char_archive`, user `char_archive`.

## Common commands

```bash
docker compose ps
docker compose logs -f postgres    # watch DB import
docker compose logs -f frontend
docker compose down
docker compose up -d
```

Rebuild tag index after a fresh import:

```bash
docker compose exec frontend python rebuild_tag_index.py
```

## Reset database

```bash
docker compose down
rm -rf db_data/postgres db_data/pgadmin
mkdir -p db_data/postgres db_data/pgadmin
./setup.sh --torrent-dir /path/to/torrent
```

## Troubleshooting

### "Missing archive/hashed-data — extract archive.7z.* first"

Extract all split archive parts in the torrent folder. On Windows, use 7-Zip "Extract Here" on `archive.7z.001`.

### Database import seems stuck

Watch progress: `docker compose logs -f postgres`. First import can take 30–60 minutes.

### Images not loading

Confirm setup pointed at the correct torrent folder. Inside the container, images resolve as `/archive/hashed-data/<h0>/<h1>/<h2>/<rest>`. Settings in `.env`:

```env
IMAGE_LAYOUT=sharded
IMAGE_SUBDIR=hashed-data
```

### Tag search shows a warning

Run: `docker compose exec frontend python rebuild_tag_index.py`

### Connection refused

Wait until `docker compose ps` shows postgres as `healthy`.

## Local development (without Docker)

See [README.md](../README.md#development). Use `small_front/.env` with `ARCHIVE_PATH` pointing at `<torrent-dir>/archive` and sharded layout settings.

## Related docs

- [README.md](../README.md) — features and API
- [frontend-guide.md](frontend-guide.md) — architecture
- [MIGRATION.md](MIGRATION.md) — moving to another server
- [DATABASE_STRUCTURE.md](DATABASE_STRUCTURE.md) — schema reference
