# Card Import Guide

Add your own character cards to the archive by dropping files into the `import/` folder. A background scanner picks them up automatically — no manual database steps required.

Imported cards are stored in the **Generic** source and appear in search after the next scan (default: every 60 seconds).

## Choose your setup

| | **Without Docker** | **With Docker** |
|---|-------------------|-----------------|
| **Best for** | Running Postgres + Flask directly on your machine | Everything in containers |
| **How scanning runs** | Built into `runme.sh` / `runme.ps1` | Separate `importer` container |
| **Frontend URL** | http://localhost:5000 | http://localhost:8080 |
| **Config file** | `small_front/.env` | Root `.env` + Docker Compose |
| **Jump to** | [Without Docker](#without-docker) | [With Docker](#with-docker) |

---

## Supported files

| Format | Requirements |
|--------|----------------|
| **`.png`** | SillyTavern / Tavern AI character card with embedded `chara` or `ccv3` metadata in a PNG `tEXt` chunk |
| **`.json`** | Character definition JSON (Tavern v1/v2 or similar). Image preview may be missing unless you also import a matching PNG |

Other extensions are ignored. Files already in `import/processed/` or `import/failed/` are not scanned again.

## Folder layout

```
char-archive-small_frontend/
  import/                  ← drop new files here
    processed/             ← successfully imported (moved automatically)
    failed/                ← import errors (moved automatically)
      my-card.png.error.txt   ← reason for failure
```

Create the subfolders if they are missing:

**Linux / macOS:**

```bash
mkdir -p import/processed import/failed
```

**Windows (PowerShell):**

```powershell
New-Item -ItemType Directory -Force -Path import\processed, import\failed
```

---

## Without Docker

Use this when PostgreSQL and the Flask app run **on your host** (see [Setup Guide — Local development](setup-guide.md#local-development-without-docker) for full install).

### Prerequisites

1. **PostgreSQL running locally** with the archive database restored (`database.dump` from the torrent).
2. **`small_front/.env` configured** — copy from `small_front/.env.example`.
3. **Writable archive folder** — PNG imports copy images into `hashed-data/` under your torrent `archive/`. Your user must be able to write to that path.

### 1. Configure `small_front/.env`

```bash
cd small_front
cp .env.example .env    # Windows: copy .env.example .env
```

Edit `small_front/.env`:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=char_archive
DB_USER=char_archive
DB_PASSWORD=your_postgres_password

ARCHIVE_PATH=/full/path/to/character-archive-final-torrent/archive
IMAGE_LAYOUT=sharded
IMAGE_SUBDIR=hashed-data

ENABLE_IMPORT_SCANNER=true
IMPORT_DIR=../import
IMPORT_SCAN_INTERVAL=60

PORT=5000
```

**Path examples:**

| Platform | `ARCHIVE_PATH` |
|----------|----------------|
| Linux / macOS | `/home/you/Downloads/character-archive-final-torrent/archive` |
| Windows | `C:\Downloads\character-archive-final-torrent\archive` |

`IMPORT_DIR=../import` is relative to `small_front/` and points at the repo's `import/` folder. On Windows, forward slashes in `.env` work fine.

If you have not restored the database yet:

**Linux / macOS:**

```bash
createuser char_archive -P
createdb char_archive -O char_archive
pg_restore -U char_archive -d char_archive /path/to/character-archive-final-torrent/database.dump
```

**Windows (PowerShell)** — from repo root, after creating the user/database in psql or pgAdmin:

```powershell
.\init-db.ps1 -DumpPath "C:\Downloads\character-archive-final-torrent\database.dump"
```

### 2. Start the app (import scanner starts with it)

The import scanner is **on by default** when you use the runme launchers. You do **not** need Docker or a separate importer process.

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

Confirm you see both lines:

```
Import scanner enabled — watching ../import every 60s
Starting Flask app (http://localhost:5000)...
```

If the scanner line is missing, check that `ENABLE_IMPORT_SCANNER` is not set to `false` in `.env`.

### 3. Drop a card into `import/`

From the **repo root** (not `small_front/`), copy or move files into `import/`:

**Linux / macOS:**

```bash
cp ~/Downloads/my-character.png import/
# bulk:
cp ~/Downloads/cards/*.png import/
```

**Windows (PowerShell):**

```powershell
Copy-Item "$env:USERPROFILE\Downloads\my-character.png" -Destination ".\import\"
# bulk:
Copy-Item "$env:USERPROFILE\Downloads\cards\*.png" -Destination ".\import\"
```

**Windows (File Explorer):** drag files into the repo's `import\` folder.

### 4. Watch progress

Logs appear in the **same terminal** where `runme` is running (not a separate Docker log). Within one scan interval (default 60 seconds):

```
Import my-character.png: ok (a1b2c3d4e5f6...)
```

Other outcomes:

| Message | Meaning |
|---------|---------|
| `Import …: ok` | Card added to the database |
| `Import …: duplicate` | Same card content already exists; file moved to `processed/` |
| `Import …: failed` | See `import/failed/<file>.error.txt` |

### 5. Find the card in the UI

Open **http://localhost:5000**, search by character name, or set **Source → Generic**.

### Import without the web UI (standalone watcher)

Useful for bulk imports when you do not need the search UI running.

**Linux / macOS:**

```bash
cd small_front
cp .env.example .env   # if not done already; edit DB + ARCHIVE_PATH
python import_watcher.py
```

**Windows (PowerShell):**

```powershell
cd small_front
.\import_watcher.ps1
```

The watcher uses the same `small_front/.env` settings (`IMPORT_DIR`, `IMPORT_SCAN_INTERVAL`, etc.).

### Disable local import scanning

In `small_front/.env`:

```env
ENABLE_IMPORT_SCANNER=false
```

Restart the app. You can still use the standalone watcher scripts above.

---

## With Docker

Docker Desktop on Windows uses the same commands as Linux. Path differences only matter for where **you** copy files from on the host.

### Prerequisites

1. Stack running: `docker compose up -d` (or `./setup.sh` / `.\setup.ps1`).
2. `importer` service running: `docker compose ps importer`.

### 1. Start the stack

**Linux / macOS:**

```bash
./setup.sh
# or, if already configured:
docker compose up -d
```

**Windows (PowerShell):**

```powershell
.\setup.ps1
# or:
docker compose up -d
```

Confirm the importer is running:

```bash
docker compose ps importer
```

### 2. Drop a card into `import/`

**Linux / macOS:**

```bash
cp ~/Downloads/my-character.png import/
```

**Windows (PowerShell)** — from repo root:

```powershell
Copy-Item "C:\Users\you\Downloads\my-character.png" -Destination ".\import\"
```

### 3. Watch progress

```bash
docker compose logs -f importer
```

Successful import:

```
Import my-character.png: ok (a1b2c3d4...)
Processed 1 file(s)
```

### 4. Find the card in the UI

Open **http://localhost:8080**, search by name, or filter **Source → Generic**.

To stop Docker import scanning only:

```bash
docker compose stop importer
```

---

## Configuration

| Variable | Without Docker | With Docker |
|----------|----------------|-------------|
| Config file | `small_front/.env` | Root `.env` (interval); importer uses container env |
| `ENABLE_IMPORT_SCANNER` | `true` (default via runme) | N/A — use importer service |
| `IMPORT_SCAN_INTERVAL` | `60` | `60` (root `.env`) |
| `IMPORT_DIR` | `../import` (relative to `small_front/`) | Host `./import` → container `/import` |
| `ARCHIVE_PATH` | Full path to torrent `archive/` | Set via setup (`ARCHIVE_HOST_PATH`) |

---

## Platform differences (quick reference)

| Step | Linux / macOS | Windows |
|------|---------------|---------|
| **Without Docker — start app** | `cd small_front && ./runme.sh` | `cd small_front; .\runme.ps1` |
| **Without Docker — logs** | runme terminal | runme terminal |
| **Without Docker — standalone watcher** | `python import_watcher.py` | `.\import_watcher.ps1` |
| **Without Docker — restore DB** | `pg_restore ...` | `.\init-db.ps1 -DumpPath ...` |
| **With Docker — setup** | `./setup.sh` | `.\setup.ps1` |
| **With Docker — logs** | `docker compose logs -f importer` | same |
| **Copy file to import** | `cp file.png import/` | `Copy-Item file.png .\import\` or drag-and-drop |
| **Archive path in `.env`** | `/home/you/.../archive` | `C:\Users\you\...\archive` |

---

## Troubleshooting

### File sits in `import/` and nothing happens

**Without Docker:**

- App must be running via `./runme.sh` or `.\runme.ps1` (or standalone watcher).
- Confirm `ENABLE_IMPORT_SCANNER=true` in `small_front/.env`.
- Wait up to one full scan interval (default 60s).
- Check the runme terminal for errors.

**With Docker:**

- Run `docker compose ps importer` — service must be `running`.
- Run `docker compose logs importer`.
- Wait up to one scan interval.

### File moved to `import/failed/`

Read the matching `.error.txt` in the same folder.

| Error | Fix |
|-------|-----|
| `No chara/ccv3 data found in PNG` | Plain image, not a Tavern character card PNG |
| `Not a PNG file` | Wrong format or corrupted file |
| Database connection error | Postgres not running, or wrong `DB_*` values in `small_front/.env` (local) / `.env` (Docker) |
| Permission denied writing image | **Without Docker:** `ARCHIVE_PATH` must be writable by your user. **With Docker:** importer service mounts archive read-write. |

### `Import …: duplicate`

Same card content already in the database. File is moved to `processed/`; no new row is inserted.

### Imported card not in search

- Filter **Source → Generic** or search by exact name.
- Rebuild tag index if tag search fails:
  - **Without Docker Linux/macOS:** `cd small_front && ./rebuild_tags.sh`
  - **Without Docker Windows:** `cd small_front; .\rebuild_tags.ps1`
  - **With Docker:** `docker compose exec frontend python rebuild_tag_index.py`

---

## Related docs

- [Setup Guide — Local development](setup-guide.md#local-development-without-docker) — Postgres + runme without Docker
- [Setup Guide](setup-guide.md) — Docker install
- [README](../README.md) — project overview
- [File Structure](FILE_STRUCTURE.md) — how images are stored on disk
