# Character Archive Database Setup Guide

This guide documents the setup of PostgreSQL and pgAdmin using Docker Compose for the Character Archive project.

## Overview

The setup includes:
- **PostgreSQL 16 Alpine** - Database server
- **pgAdmin 4** - Web-based database management tool
- **Frontend** - Flask/Tailwind search interface
- **Persistent local storage** in `db_data/` folder

## Prerequisites

- Docker Engine (20.10+)
- Docker Compose (v2.0+)
- At least 20GB free disk space (for database)

## Quick Start

### 1. Start the Services

```bash
cd /mnt/char-archive
docker compose up -d
```

### 2. Verify Services are Running

```bash
docker compose ps
```

Both services should show `healthy` or `running` status.

### 3. Access pgAdmin

1. Open `http://localhost:5050` in your browser
2. Login with credentials from `database_logins.md`
3. Add a new server connection (see below)

## Service Details

### PostgreSQL Container

| Property | Value |
|----------|-------|
| Container Name | `char_archive_db` |
| Image | `postgres:16-alpine` |
| Internal Port | `5432` |
| External Port | `5432` |
| Data Volume | `./db_data/postgres` |

### pgAdmin Container

| Property | Value |
|----------|-------|
| Container Name | `char_archive_pgadmin` |
| Image | `dpage/pgadmin4:latest` |
| Internal Port | `80` |
| External Port | `5050` |
| Data Volume | `./db_data/pgadmin` |

## Connecting to PostgreSQL from pgAdmin

1. Click "Add New Server"
2. **General tab**: Enter a name (e.g., "Character Archive")
3. **Connection tab**:
   - Host: `postgres`
   - Port: `5432`
   - Maintenance database: `char_archive`
   - Username: `char_archive`
   - Password: See `database_logins.md`
4. Click "Save"

## Common Commands

### Start services
```bash
docker compose up -d
```

### Stop services
```bash
docker compose down
```

### View logs
```bash
docker compose logs -f
docker compose logs -f postgres
docker compose logs -f pgadmin
```

### Connect via psql (from host)
```bash
psql -h localhost -p 5432 -U char_archive -d char_archive
```

### Connect via psql (from container)
```bash
docker compose exec postgres psql -U char_archive -d char_archive
```

### Reset database (delete all data)
```bash
docker compose down
sudo rm -rf db_data/postgres db_data/pgadmin
mkdir -p db_data/postgres db_data/pgadmin
docker compose up -d
```

## Database Import (Manual)

The database has already been imported from `database.dump`. If you need to re-import or import on a fresh setup, merge `docker-compose.import.yml` (mounts `database.dump` and `init-db.sh`).

### Fresh import (auto-restore)

```bash
cp .env.example .env   # edit passwords and BIND_HOST
docker compose down
sudo rm -rf db_data/postgres db_data/pgadmin
mkdir -p db_data/postgres db_data/pgadmin
docker compose -f docker-compose.yml -f docker-compose.import.yml up -d
docker compose logs -f postgres   # watch import progress
```

After import completes, use the base file only: `docker compose up -d`.

### Manual Import with pg_restore

If you prefer to import manually:
```bash
# Ensure postgres is running
docker compose up -d postgres

# Run pg_restore
docker compose exec -T postgres pg_restore \
  -U char_archive \
  -d char_archive \
  -v /path/to/database.dump
```

### About the Original Dump

The dump was originally created with:
```bash
pg_dump -F c -O -x char_archive -Z 9 -f database.dump
```

- `-F c` - Custom format (compressed)
- `-O` - No owner
- `-x` - No privileges
- `-Z 9` - Maximum compression

## Troubleshooting

### "Connection refused" errors
Wait for PostgreSQL health check to pass:
```bash
docker compose ps
```
The `postgres` service should show `healthy` status.

### pgAdmin can't connect to PostgreSQL
- Use `postgres` as hostname (not `localhost`)
- Ensure PostgreSQL container is healthy
- Check credentials in `database_logins.md`

### Out of disk space
Ensure at least 20GB free space for the expanded database.

### Collation version warnings
If you see warnings about collation versions, you can silence them with:
```bash
docker compose exec postgres psql -U char_archive -d char_archive \
  -c "UPDATE pg_database SET datcollversion = NULL WHERE datname = 'char_archive';"
```

## File Structure

```
/mnt/char-archive/
├── docker-compose.yml          # Docker Compose configuration (production)
├── database.dump               # PostgreSQL dump file (for reference/re-import)
├── database_logins.md          # Login credentials
├── init-db.sh                  # Database initialization script (for re-import)
├── CLAUDE.md                   # Project overview for AI assistants
├── db_data/                    # Persistent storage (bind mounts)
│   ├── postgres/               # PostgreSQL data files
│   └── pgadmin/                # pgAdmin configuration
├── small_front/                # Frontend application
│   ├── app.py                  # Flask API backend
│   ├── templates/
│   │   └── index.html          # Tailwind CSS frontend
│   ├── requirements.txt        # Python dependencies
│   └── Dockerfile              # Container configuration
├── docs/
│   ├── setup-guide.md          # This documentation
│   ├── frontend-guide.md       # Frontend API and architecture
│   ├── migration-guide.md      # Server migration instructions
│   ├── docker-compose.yml.backup  # Compose file with import capability
│   └── backups/                # Frontend backups
└── archive/                    # Character images (hashed-data/)
```

## Security Considerations

- Default credentials are for local development only
- Change passwords before any production deployment
- Consider using Docker secrets for sensitive values
- Restrict port exposure in production environments
- Do not commit `database_logins.md` to public repositories

## Change Log

### January 3, 2026
- Initial setup with PostgreSQL 16 Alpine and pgAdmin 4
- Changed from Docker-managed volumes to local bind mounts (`db_data/`)
- Fixed pgAdmin email validation (changed from `.local` to `.dev` domain)
- Removed auto-import from production compose file (database already imported)
- Created backup compose file with import capability for future use
- Added Flask/Tailwind frontend for character search
- Frontend features: search, pagination, source filtering, character details modal
- Added text cleaning to strip character card JSON formatting
- UI polish: animations, gradients, custom scrollbars, hover effects
- Created migration guide for server transfers
