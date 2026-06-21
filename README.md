# Character Archive Frontend

A Flask-based web application for searching and downloading character cards from the Character Archive. Features a modern Tailwind CSS interface with full-text search, character previews, and card downloads.

![Python](https://img.shields.io/badge/python-3.11-blue.svg)
![Flask](https://img.shields.io/badge/flask-3.1-green.svg)

## Features

- **Search** by name, author, and tags across Chub, Generic, Booru, Webring, Character Tavern, RisuAI, and Nyaime
- **Tag filtering** with autocomplete suggestions, required tags (comma-separated AND), and exclusions (`-tag`); backed by a pre-built `tag_index` for fast lookups
- **Author filter** plus click-through from result cards and the detail modal to search by author or tag
- **Sort** by date added or name, ascending or descending
- **Shareable URLs** — search filters and pagination are reflected in the address bar
- **Direct character links** at `/character/<source>/<id>` (opens the detail modal)
- **Character card previews** with lazy-loaded images (flat or sharded archive layouts via env config)
- **Detail modal** with tags, description, first message, and expandable tag list
- **Card downloads** as PNG (embedded character data) or raw JSON
- **Source filtering** per platform; optional **browse-all** mode when `ENABLE_BROWSE_ALL` is enabled
- **Archive stats** with per-source counts on the home page
- **Responsive design** with dark theme, purple gradient accents, and customizable results per page

## Architecture

### Backend (app.py)

Flask API with the following endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Serves the main HTML page |
| `/api/search` | GET | Search characters across all sources |
| `/api/character/<source>/<id>` | GET | Get detailed character info |
| `/api/card/<source>/<id>` | GET | Download character card (PNG) |
| `/image/<hash>` | GET | Serve character image by hash |
| `/api/stats` | GET | Get database statistics |

### Frontend (templates/index.html)

Single-page application using:
- **Tailwind CSS** (via CDN) for styling
- **Vanilla JavaScript** for interactivity
- Responsive grid layout (2-6 columns based on screen size)
- Modal animations and hover effects
- Custom text cleaning for character card formatting

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows/macOS) or Docker Engine + Compose v2 (Linux)
- Character Archive torrent downloaded and extracted (see [Setup Guide](docs/setup-guide.md))

## Quick Start

### 1. Get the torrent data

Download the Character Archive torrent. Your folder should look like:

```
<torrent-download-dir>/
  database.dump
  archive.7z.001 … archive.7z.020
  archive/hashed-data/    ← after extracting archive.7z.*
```

Extract all `archive.7z.*` parts with [7-Zip](https://www.7-zip.org/) before continuing.

### 2. Run setup

**Linux / macOS:**

```bash
git clone https://github.com/sproutingnerd/char-archive-small_frontend.git
cd char-archive-small_frontend
./setup.sh
```

**Windows (PowerShell):**

```powershell
git clone https://github.com/sproutingnerd/char-archive-small_frontend.git
cd char-archive-small_frontend
.\setup.ps1
```

Enter your torrent download directory when prompted. Setup mounts your archive and database in place — no need to copy files into the repo.

### 3. Open the frontend

Go to **http://localhost:8080** when setup finishes. Login credentials for pgAdmin and Postgres are in `.env`.

For manual configuration, flags, and troubleshooting, see the [Setup Guide](docs/setup-guide.md).

## Development

### Local Development Setup

1. Clone the repository:
```bash
git clone https://github.com/sproutingnerd/char-archive-small_frontend.git
cd char-archive-small_frontend/small_front
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Configure environment (copy `small_front/.env.example` to `small_front/.env`, or export variables):
```bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=char_archive
export DB_USER=char_archive
export DB_PASSWORD=your_password
export ARCHIVE_PATH=/path/to/torrent/archive   # contains hashed-data/
export IMAGE_LAYOUT=sharded
export IMAGE_SUBDIR=hashed-data
```

4. Run the Flask app:
```bash
./runme.sh
```

`runme.sh` loads `.env`, creates/activates the virtualenv if needed, installs dependencies, then starts the app. Default URL: `http://localhost:5000` (set `PORT` in `.env` to change).

### Rebuild After Changes

```bash
docker compose build frontend && docker compose up -d frontend
```

### View Logs

```bash
docker compose logs -f frontend
```

## API Usage

### Search Characters

```bash
curl "http://localhost:8080/api/search?q=test&source=chub&page=1&per_page=24"
```

**Parameters:**
- `q` (required): Search query
- `source` (optional): Filter by source (chub, generic, booru, webring, char_tavern, risuai, nyaime, all)
- `page` (optional): Page number (default: 1)
- `per_page` (optional): Results per page (default: 24)

**Response:**
```json
{
  "results": [
    {
      "id": "123456",
      "author": "username",
      "name": "Character Name",
      "image_hash": "abc123...",
      "added": "2024-12-01T00:00:00+00:00",
      "source": "chub"
    }
  ],
  "total": 1000,
  "page": 1,
  "per_page": 24,
  "pages": 42
}
```

### Get Character Details

```bash
curl "http://localhost:8080/api/character/chub/123456"
```

### Download Character Card

```bash
curl "http://localhost:8080/api/card/chub/123456" -o character.png
```

### Get Database Stats

```bash
curl "http://localhost:8080/api/stats"
```

## Database Schema

The frontend queries these tables per platform:

| Source | Table | Searchable Columns |
|--------|-------|-------------------|
| chub | chub_character_def | name, author |
| generic | generic_character_def | name |
| booru | booru_character_def | name, author |
| webring | webring_character_def | name, author |
| char_tavern | char_tavern_character_def | path |
| risuai | risuai_character_def | author |
| nyaime | nyaime_character_def | author |

Each table follows the pattern:
- `{platform}_character` - Scraped metadata with JSON data
- `{platform}_character_def` - Card definitions with:
  - `definition` (JSONB): Character data
  - `raw` (bytea): zlib-compressed original card
  - `image_hash`: MD5 hash for image lookup
  - `metadata` (JSON): Safety ratings and token info

## Image storage

The frontend resolves files from `image_hash` in the database using three settings (see `small_front/app.py` and `small_front/.env.example`):

| Variable | Role |
|----------|------|
| `ARCHIVE_PATH` | Root directory for images (Docker: `/archive` with `./archive` mounted) |
| `IMAGE_SUBDIR` | Optional folder under `ARCHIVE_PATH` (e.g. `hashed-data`; leave empty if hashes sit directly under the root) |
| `IMAGE_LAYOUT` | How each hash maps to a path: `flat` or `sharded` |

Effective lookup root: `ARCHIVE_PATH` / `IMAGE_SUBDIR` (if set).

### Sharded layout (`IMAGE_LAYOUT=sharded`)

Default for Docker Compose and the Character Archive image store. Files are split by the first three hex digits of the MD5 hash.

**Path:** `{root}/{h[0]}/{h[1]}/{h[2]}/{h[3:]}`

**Example** (hash `54db4830ceab552d4824dd5b016f4b06`, `IMAGE_SUBDIR=hashed-data`):

```
archive/hashed-data/5/4/d/b4830ceab552d4824dd5b016f4b06
```

**Docker / root `.env`:**

```env
IMAGE_LAYOUT=sharded
IMAGE_SUBDIR=hashed-data
```

### Flat layout (`IMAGE_LAYOUT=flat`)

One file per hash, named with the full hash, directly under the image root (no `h[0]/h[1]/h[2]/` prefix directories).

**Path:** `{root}/{full-hash}`

**Example** (same hash, no subdir):

```
/mnt/images/54db4830ceab552d4824dd5b016f4b06
```

**Local dev (`small_front/.env.example` defaults):**

```env
IMAGE_LAYOUT=flat
IMAGE_SUBDIR=
```

Use flat when your archive stores `{ARCHIVE_PATH}/{hash}` files. Use sharded when they live under the hashed directory tree (as in `docs/FILE_STRUCTURE.md`).

### Choosing settings

| Your files on disk | `IMAGE_LAYOUT` | `IMAGE_SUBDIR` |
|--------------------|----------------|----------------|
| `archive/hashed-data/5/4/d/...` | `sharded` | `hashed-data` |
| `archive/5/4/d/...` (no extra folder) | `sharded` | *(empty)* |
| `archive/<full-md5>` | `flat` | *(empty)* |
| `archive/cards/<full-md5>` | `flat` | `cards` |

## Troubleshooting

### Search returns no results
- Check database connection in logs
- Verify PostgreSQL is running and healthy
- Test database directly: `docker compose exec postgres psql -U char_archive -d char_archive`

### Images not loading
- Confirm setup pointed at the correct torrent folder (`TORRENT_DIR` in `.env`)
- Verify `archive/hashed-data/` exists on the host
- Check `IMAGE_LAYOUT=sharded` and `IMAGE_SUBDIR=hashed-data` in `.env`
- Check file permissions on the archive folder

### Container keeps restarting
- Check logs: `docker compose logs frontend`
- Ensure PostgreSQL is healthy before frontend starts
- Verify all environment variables are set correctly

### Database connection errors
- Ensure `DB_HOST` matches PostgreSQL service name in docker-compose
- Check database credentials
- Verify PostgreSQL port is accessible

## Project Structure

```
char-archive-small_frontend/
├── README.md                      # This file
├── setup.sh                       # One-shot setup (Linux / macOS)
├── setup.ps1                      # One-shot setup (Windows)
├── .env.example                   # Docker Compose env template
├── .gitignore
├── docker-compose.yml             # Stack: postgres, pgadmin, frontend
├── docker-compose.import.yml      # DB import overlay (manual/advanced)
├── docker-compose.override.example.yml
├── init-db.sh                     # Restores database.dump on empty Postgres data dir
├── db_data/                       # Postgres + pgAdmin persistence (local; gitignored)
├── docs/
│   ├── setup-guide.md             # Install guide (start here)
│   ├── MIGRATION.md               # Server migration guide
│   ├── frontend-guide.md          # API and architecture details
│   ├── DATABASE_STRUCTURE.md      # Full database schema
│   └── FILE_STRUCTURE.md          # Image storage layout
└── small_front/                   # Frontend application
    ├── .env.example               # Local dev env
    ├── app.py                     # Flask API backend
    ├── Dockerfile                 # Container image for Compose frontend service
    ├── requirements.txt           # Python dependencies
    ├── rebuild_tag_index.py       # Rebuild tag search index in PostgreSQL
    ├── rebuild_tags.example.sh    # Example wrapper; copy to rebuild_tags.sh
    ├── runme.sh                   # Local dev launcher
    ├── sql/
    │   └── tag_index.sql          # Tag index DDL
    └── templates/
        └── index.html             # Tailwind CSS frontend
```

## Dependencies

- **Flask** 3.1.0 - Web framework
- **psycopg2-binary** 2.9.10 - PostgreSQL adapter
- **Pillow** 11.0.0 - Image processing
- **gunicorn** 23.0.0 - Production WSGI server

See `requirements.txt` for complete list.

## Related Documentation

- [Full Setup Guide](docs/setup-guide.md) - Complete Docker setup instructions
- [Frontend Architecture](docs/frontend-guide.md) - Detailed API and schema documentation
- [Database Structure](docs/DATABASE_STRUCTURE.md) - Complete database schema reference
- [File Structure](docs/FILE_STRUCTURE.md) - Image storage and file organization
- [Migration Guide](docs/MIGRATION.md) - Server migration instructions


## Credits

Part of the Character Archive preservation project. Original server and scraper source code:
- [char-archive-server](https://git.evulid.cc/cyberes/char-archive-server)
- [char-archive-scraper](https://git.evulid.cc/cyberes/char-archive-scraper)

