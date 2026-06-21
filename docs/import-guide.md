# Card Import Guide

Add your own character cards to the archive by dropping files into the `import/` folder. A background scanner picks them up automatically — no manual database steps required.

Imported cards are stored in the **Generic** source and appear in search after the next scan (default: every 60 seconds).

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

The repo includes `import/.gitkeep` so the folder exists after clone. Setup scripts also create `import/processed/` and `import/failed/`.

## Before you import

1. **The stack must be running** — Docker Compose (frontend + postgres + importer) or local dev via `runme.sh` / `runme.ps1`.
2. **Database must be restored** — import inserts into PostgreSQL; an empty database has nowhere to put cards.
3. **Archive path must be writable (PNG imports)** — PNG cards copy their image into `hashed-data/` under your torrent `archive/` folder. Docker mounts this read-only on the **frontend** but read-write on the **importer** service. Local dev needs write access to `ARCHIVE_PATH`.

---

## Docker (Linux, macOS, or Windows)

Docker Desktop on Windows uses the same commands as Linux. Path differences only matter for where **you** copy files from on the host.

### 1. Start the stack

If you have not run setup yet:

**Linux / macOS:**

```bash
./setup.sh
```

**Windows (PowerShell):**

```powershell
.\setup.ps1
```

Or manually:

```bash
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
# multiple files:
cp ~/Downloads/cards/*.png import/
```

**Windows (PowerShell)** — from the repo root:

```powershell
Copy-Item "C:\Users\you\Downloads\my-character.png" -Destination ".\import\"
# multiple files:
Copy-Item "C:\Users\you\Downloads\cards\*.png" -Destination ".\import\"
```

**Windows (File Explorer):** open the repo folder, drag files into `import\`.

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

Open the frontend (default **http://localhost:8080**), search by character name, or filter **Source → Generic**.

---

## Local dev (without Docker)

Import scanning runs **inside the Flask app** when started via `runme.sh` or `runme.ps1`. You do not need a second terminal unless you want a standalone watcher.

### 1. Configure `small_front/.env`

```env
ENABLE_IMPORT_SCANNER=true
IMPORT_DIR=../import
IMPORT_SCAN_INTERVAL=60
ARCHIVE_PATH=/full/path/to/character-archive-final-torrent/archive
IMAGE_LAYOUT=sharded
IMAGE_SUBDIR=hashed-data
DB_HOST=localhost
DB_PASSWORD=your_password
```

**Path examples:**

| Platform | `ARCHIVE_PATH` | `IMPORT_DIR` |
|----------|----------------|--------------|
| Linux / macOS | `/home/you/Downloads/character-archive-final-torrent/archive` | `../import` |
| Windows | `C:\Downloads\character-archive-final-torrent\archive` | `../import` |

On Windows, use backslashes or forward slashes in `.env`; both work for Python.

### 2. Start the app

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

You should see:

```
Import scanner enabled — watching ../import every 60s
Starting Flask app (http://localhost:5000)...
```

### 3. Drop a card

**Linux / macOS** (from repo root):

```bash
cp ~/Downloads/my-character.png import/
```

**Windows (PowerShell)** (from repo root):

```powershell
Copy-Item "C:\Users\you\Downloads\my-character.png" -Destination ".\import\"
```

Within one scan interval (default 60s), the **runme terminal** prints:

```
Import my-character.png: ok (a1b2c3d4...)
```

Open **http://localhost:5000** and search, or filter by **Generic**.

### Standalone watcher (optional)

Run the scanner without the web UI — useful for bulk imports.

**Linux / macOS:**

```bash
cd small_front
python import_watcher.py
```

**Windows:**

```powershell
cd small_front
.\import_watcher.ps1
```

---

## Configuration

| Variable | Where | Default | Purpose |
|----------|-------|---------|---------|
| `IMPORT_SCAN_INTERVAL` | Root `.env` (Docker) | `60` | Seconds between scans (importer service) |
| `IMPORT_SCAN_INTERVAL` | `small_front/.env` (local) | `60` | Seconds between scans (embedded scanner) |
| `ENABLE_IMPORT_SCANNER` | `small_front/.env` | `true` via runme | Set `false` to disable local scanning |
| `IMPORT_DIR` | `small_front/.env` | `../import` | Folder to watch (local dev) |
| `ARCHIVE_PATH` | `small_front/.env` | — | Must point at torrent `archive/` for PNG image storage |

Docker's importer always watches `/import` inside the container (host folder `./import`).

---

## Platform differences (quick reference)

| Step | Linux / macOS | Windows |
|------|---------------|---------|
| Docker setup | `./setup.sh` | `.\setup.ps1` |
| Copy file to import | `cp file.png import/` | `Copy-Item file.png .\import\` or drag-and-drop |
| Docker logs | `docker compose logs -f importer` | same (PowerShell or Git Bash) |
| Local app | `cd small_front && ./runme.sh` | `cd small_front; .\runme.ps1` |
| Local logs | runme terminal stdout | runme terminal stdout |
| Standalone watcher | `python import_watcher.py` | `.\import_watcher.ps1` |
| Archive path in `.env` | `/home/you/.../archive` | `C:\Users\you\...\archive` |

Docker behavior is identical on all platforms. Differences are mainly **how you copy files** and **path format in `.env`**.

---

## Troubleshooting

### File sits in `import/` and nothing happens

- **Docker:** check `docker compose ps importer` — service must be `running`.
- **Local:** confirm `ENABLE_IMPORT_SCANNER=true` and you started via `runme.sh` / `runme.ps1` (not raw `flask run` without the scanner).
- Wait up to one full scan interval (default 60s).
- Check logs (Docker: `docker compose logs importer`; local: runme terminal).

### File moved to `import/failed/`

Read the matching `.error.txt` in the same folder. Common causes:

| Error | Fix |
|-------|-----|
| `No chara/ccv3 data found in PNG` | File is a plain image, not a Tavern character card PNG |
| `Not a PNG file` | Wrong format or corrupted file |
| Database connection error | Postgres not running or wrong credentials in `.env` |
| Permission denied writing image | `ARCHIVE_PATH` not writable (local dev) or wrong mount (Docker) |

### `Import …: duplicate`

The card content already exists (same definition hash). The file is moved to `processed/`; no duplicate row is inserted.

### Imported card not in search

- Filter **Source → Generic** or search by exact name.
- Tags update automatically via database triggers; if tag search fails, run tag index rebuild:
  - **Docker:** `docker compose exec frontend python rebuild_tag_index.py`
  - **Local Linux/macOS:** `cd small_front && ./rebuild_tags.sh`
  - **Local Windows:** `cd small_front; .\rebuild_tags.ps1`

### Disable import scanning (local only)

In `small_front/.env`:

```env
ENABLE_IMPORT_SCANNER=false
```

Restart the app. Docker importer can be stopped separately:

```bash
docker compose stop importer
```

---

## Related docs

- [Setup Guide](setup-guide.md) — install and first-time database restore
- [README](../README.md) — project overview
- [File Structure](FILE_STRUCTURE.md) — how images are stored on disk
