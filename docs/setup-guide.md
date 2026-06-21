# Character Archive Setup Guide

This guide covers installing the Character Archive search frontend using the official torrent layout and Docker Compose.

> **Not for production.** This project is intended for personal, local use only. It is not hardened for public deployment — no authentication, no rate limiting, no security audit. Run it on your own machine behind your own firewall; do not expose it to the internet as a public service.

## What you need

| Requirement | Notes |
|-------------|-------|
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows/macOS) or Docker Engine + Compose v2 (Linux) | |
| ~400 GiB free disk space | ~200 GiB torrent download + ~200 GiB for extracted `archive/` |
| Character Archive torrent | Download, then extract `archive.7z.001` before setup |

## Torrent layout

The torrent downloads as a single folder (**character-archive-final-torrent**, ~201 GiB):

```
character-archive-final-torrent/
  README.md                       # notes from the archive maintainers
  database.dump                   # PostgreSQL dump (~11 GB)
  archive.7z.001                  # 10 GB each (parts 001–019)
  archive.7z.002
  …
  archive.7z.019
  archive.7z.020                  # ~586 MB (last part)
  char-archive-server.zip         # original server source (optional)
  char-archive-scraper.zip        # original scraper source (optional)
```

**For this frontend you only need `database.dump` and the extracted `archive/` folder.** The zip files are reference material from the original project.

Extract `archive.7z.001` with [7-Zip](https://www.7-zip.org/). Right-click → "Extract Here" on Windows, or `7z x archive.7z.001` on Linux/macOS. All 20 parts are used automatically.

After extraction:

```
character-archive-final-torrent/
  database.dump
  archive/
    hashed-data/                  # character images (required)
    files/                        # raw files (not needed for search UI)
    webring/
```

## Quick start (recommended)

### Linux / macOS

```bash
git clone https://github.com/jonsjava/char-archive-small_frontend.git
cd char-archive-small_frontend
./setup.sh
```

When prompted, enter your **character-archive-final-torrent** folder (the one containing `database.dump` and, after extraction, `archive/`).

### Windows

```powershell
git clone https://github.com/jonsjava/char-archive-small_frontend.git
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
| Importer | *(background)* | scans `import/` every 60s |

pgAdmin login: `PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD` from `.env`.

To connect pgAdmin to Postgres: host `postgres`, port `5432`, database `char_archive`, user `char_archive`.

## Adding your own cards

Copy PNG or JSON character cards into the `import/` folder at the repo root:

```bash
cp ~/Downloads/new-character.png import/
docker compose logs -f importer
```

The importer runs as a Docker service, checks for new files every `IMPORT_SCAN_INTERVAL` seconds (default 60), and adds them to the **Generic** source. Processed files move to `import/processed/`; failures go to `import/failed/` with a `.error.txt` explanation.

## Common commands

```bash
docker compose ps
docker compose logs -f postgres    # watch DB import
docker compose logs -f frontend
docker compose logs -f importer
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

Use this if you prefer running Python and PostgreSQL directly on your host instead of Docker.

### Prerequisites

| Requirement | Notes |
|-------------|-------|
| Python 3.11+ | [python.org](https://www.python.org/downloads/) — on Windows, check "Add to PATH" during install |
| PostgreSQL 16 | [postgresql.org](https://www.postgresql.org/download/) |
| Torrent data | `database.dump` and extracted `archive/hashed-data/` |

### 1. Create the database

**Linux / macOS:**

```bash
createuser char_archive -P
createdb char_archive -O char_archive
pg_restore -U char_archive -d char_archive /path/to/character-archive-final-torrent/database.dump
```

**Windows (PowerShell):**

```powershell
# Create user/database via psql or pgAdmin first, then:
.\init-db.ps1 -DumpPath "C:\Downloads\character-archive-final-torrent\database.dump"
```

Requires `psql` and `pg_restore` on PATH (PostgreSQL install `bin` folder). Alternatively, create the user and database in pgAdmin, then restore `database.dump` via pgAdmin's restore dialog.

### 2. Configure `small_front/.env`

```bash
cd small_front
cp .env.example .env
```

Set at minimum:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=char_archive
DB_USER=char_archive
DB_PASSWORD=your_password
ARCHIVE_PATH=/full/path/to/character-archive-final-torrent/archive
IMAGE_LAYOUT=sharded
IMAGE_SUBDIR=hashed-data
PORT=5000
```

Windows example:

```env
ARCHIVE_PATH=C:\Downloads\character-archive-final-torrent\archive
VENV_PATH=C:\Users\you\venv
```

### 3. Run the frontend

**Linux / macOS:**

```bash
cd small_front
./runme.sh
```

**Windows (PowerShell):**

```powershell
cd small_front
.\runme.ps1
```

Open **http://localhost:5000**. The launcher scripts create a virtualenv on first run and install `requirements.txt` automatically.

### 4. Tag index and imports

After restoring `database.dump`, rebuild the tag index once:

```bash
# Linux/macOS
cd small_front
cp rebuild_tags.example.sh rebuild_tags.sh && chmod +x rebuild_tags.sh
./rebuild_tags.sh
```

```powershell
# Windows
cd small_front
.\rebuild_tags.ps1
```

To import new cards without Docker, drop files into `import/` while the app is running via `runme.sh` / `runme.ps1` — scanning is enabled by default (`ENABLE_IMPORT_SCANNER=true` in `small_front/.env`).

To run the watcher without the Flask app:

```bash
# Linux/macOS
python import_watcher.py
```

```powershell
# Windows
.\import_watcher.ps1
```

Set `IMPORT_DIR=../import` in `small_front/.env` (default in `.env.example`).

### Script reference (local dev)

| Task | Linux / macOS | Windows (PowerShell) |
|------|---------------|----------------------|
| Run frontend | `small_front/runme.sh` | `small_front/runme.ps1` |
| Restore DB (local) | `pg_restore ...` | `.\init-db.ps1 -DumpPath ...` |
| Rebuild tag index | `small_front/rebuild_tags.sh` | `small_front/rebuild_tags.ps1` |
| Import watcher | automatic with `runme.sh` / `runme.ps1` | automatic with `runme.ps1` |
| Import watcher (standalone) | `python import_watcher.py` | `small_front/import_watcher.ps1` |

## Related docs

- [README.md](../README.md) — features and API
- [frontend-guide.md](frontend-guide.md) — architecture
- [MIGRATION.md](MIGRATION.md) — moving to another server
- [DATABASE_STRUCTURE.md](DATABASE_STRUCTURE.md) — schema reference
