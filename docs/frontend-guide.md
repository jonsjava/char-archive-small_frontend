# Character Archive Frontend Guide

This document describes the frontend web application for searching and downloading character cards from the Character Archive.

## Overview

The frontend is a Flask-based web application with a Tailwind CSS UI that provides:
- Full-text search across all character sources
- Character card previews with images
- Detailed character information modal
- Character card downloads (PNG with embedded data)

## Architecture

```
small_front/
├── app.py              # Flask API backend
├── templates/
│   └── index.html      # Tailwind CSS frontend
├── requirements.txt    # Python dependencies
└── Dockerfile          # Container configuration
```

### Backend (app.py)

Flask application with the following endpoints:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Serves the main HTML page |
| `/api/search` | GET | Search characters across all sources |
| `/api/character/<source>/<id>` | GET | Get detailed character info |
| `/api/card/<source>/<id>` | GET | Download character card (PNG) |
| `/image/<hash>` | GET | Serve character image by hash |
| `/api/stats` | GET | Get database statistics |

#### Search API Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `q` | string | required | Search query |
| `source` | string | `all` | Filter by source (chub, generic, booru, webring, char_tavern, risuai, nyaime) |
| `page` | int | 1 | Page number |
| `per_page` | int | 24 | Results per page |

#### Example Search Response

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

### Frontend (index.html)

Single-page application using:
- **Tailwind CSS** (via CDN) for styling
- **Vanilla JavaScript** for interactivity
- Dark theme with purple accents and gradient effects

Features:
- Responsive grid layout (2-6 columns based on screen size)
- Lazy-loaded images with fallback placeholder
- Modal for character details with tags, description, and first message
- Pagination controls
- Source filter dropdown
- Staggered fade-in animations for search results
- Modal entrance animations
- Custom styled scrollbars
- Card hover effects with lift and glow

#### Text Cleaning

The frontend includes a `cleanCardText()` function that strips character card formatting from descriptions:
- Removes `[Character(...)]` notation
- Strips `{{user}}` and `{{char}}` placeholders
- Cleans up JSON-style brackets and formatting
- Converts delimiters to readable punctuation

## Database Schema

The frontend queries these tables:

| Source | Table | Searchable Columns |
|--------|-------|-------------------|
| chub | chub_character_def | name, author |
| generic | generic_character_def | name |
| booru | booru_character_def | name, author |
| webring | webring_character_def | name, author |
| char_tavern | char_tavern_character_def | path |
| risuai | risuai_character_def | author |
| nyaime | nyaime_character_def | author |

### Character Definition Structure

The `definition` JSONB column contains character data:

```json
{
  "data": {
    "name": "Character Name",
    "description": "Character description/persona",
    "first_mes": "First message/greeting",
    "tags": ["tag1", "tag2"],
    "creator": "username",
    "scenario": "...",
    "personality": "...",
    "mes_example": "Example messages..."
  },
  "spec": "chara_card_v2",
  "spec_version": "2.0"
}
```

## Image Storage

Images are stored in `archive/hashed-data/` using MD5 hash sharding:
- Path: `/{h[0]}/{h[1]}/{h[2]}/{h[3:]}`
- Example: `54db4830ceab552d4824dd5b016f4b06` → `/5/4/d/b4830ceab552d4824dd5b016f4b06`

## Docker Configuration

The frontend is defined in `docker-compose.yml` (build context `./small_front`). Credentials and bind addresses come from the root `.env` file (see `.env.example`). Image paths use `IMAGE_LAYOUT=sharded` and `IMAGE_SUBDIR=hashed-data` so files under `archive/hashed-data/` resolve correctly inside the container.

## Development

### Rebuild after changes
```bash
docker compose build frontend && docker compose up -d frontend
```

### View logs
```bash
docker compose logs -f frontend
```

### Test API directly
```bash
curl "http://100.108.69.91:8080/api/search?q=test&page=1"
curl "http://100.108.69.91:8080/api/stats"
```

## Troubleshooting

### Search returns no results
- Check database connection in logs
- Verify the search query format
- Test database directly with psql

### Images not loading
- Verify archive mount is correct
- Check image hash exists in hashed-data
- Check file permissions on archive folder

### Container keeps restarting
- Check logs: `docker compose logs frontend`
- Verify database is healthy before frontend starts
