# Character Archive Migration Guide

This guide explains how to migrate the Character Archive to another server.

## What You Need to Transfer

### Required Files and Folders

| Item | Size (approx) | Description |
|------|---------------|-------------|
| `docker-compose.yml` | 2KB | Docker service configuration |
| `small_front/` | ~50KB | Frontend application code |
| `archive/` | Varies | Character images and data files |
| `database.dump` | ~11GB | PostgreSQL database dump |

### Optional Files

| Item | Description |
|------|-------------|
| `database_logins.md` | Credentials (update for new server) |
| `docs/` | Documentation |
| `init-db.sh` | Database import script |
| `CLAUDE.md` | Project overview |

## Migration Steps

### Step 1: Prepare the New Server

```bash
# Install Docker and Docker Compose
# (Follow Docker's official installation guide for your OS)

# Create project directory
mkdir -p /path/to/char-archive
cd /path/to/char-archive
```

### Step 2: Transfer Files

**Option A: Using rsync (recommended for large transfers)**
```bash
# From the source server
rsync -avz --progress \
  /mnt/char-archive/docker-compose.yml \
  /mnt/char-archive/small_front/ \
  /mnt/char-archive/archive/ \
  /mnt/char-archive/database.dump \
  /mnt/char-archive/init-db.sh \
  user@new-server:/path/to/char-archive/
```

**Option B: Using scp**
```bash
scp -r docker-compose.yml small_front/ archive/ database.dump init-db.sh \
  user@new-server:/path/to/char-archive/
```

**Option C: Using tar + transfer**
```bash
# On source server - create archive (excluding db_data)
tar -cvzf char-archive-backup.tar.gz \
  --exclude='db_data' \
  docker-compose.yml small_front/ archive/ database.dump init-db.sh docs/

# Transfer the archive
scp char-archive-backup.tar.gz user@new-server:/path/to/

# On new server - extract
cd /path/to/char-archive
tar -xvzf ../char-archive-backup.tar.gz
```

### Step 3: Update Configuration

Copy and edit `.env` on the new server:

```bash
cp .env.example .env
nano .env
```

Set `BIND_HOST` to your server or Tailscale IP (or `0.0.0.0` / `127.0.0.1` as needed). Ports are controlled with `POSTGRES_PORT`, `PGADMIN_PORT`, and `FRONTEND_PORT`:

```env
BIND_HOST=YOUR_NEW_IP
POSTGRES_PORT=5432
PGADMIN_PORT=5050
FRONTEND_PORT=8080
```

Or set `BIND_HOST=0.0.0.0` to listen on all interfaces.

**Update passwords** in `.env` and `database_logins.md` (documentation).

### Step 4: Create Data Directories

```bash
mkdir -p db_data/postgres db_data/pgadmin
```

### Step 5: Import the Database

**Option A: Using the import compose overlay**

```bash
cp .env.example .env
nano .env   # set BIND_HOST, passwords

docker compose -f docker-compose.yml -f docker-compose.import.yml up -d
docker compose -f docker-compose.yml -f docker-compose.import.yml logs -f postgres
```

**Option B: Manual import**
```bash
# Start only PostgreSQL first
docker compose up -d postgres

# Wait for it to be healthy
docker compose ps

# Import the database
docker compose exec -T postgres pg_restore \
  -U char_archive \
  -d char_archive \
  -v < database.dump

# Or if database.dump is inside the container:
docker compose cp database.dump postgres:/tmp/
docker compose exec postgres pg_restore \
  -U char_archive \
  -d char_archive \
  -v /tmp/database.dump
```

### Step 6: Start All Services

```bash
docker compose up -d
```

### Step 7: Verify the Migration

```bash
# Check all containers are running
docker compose ps

# Test the frontend
curl "http://YOUR_IP:8080/api/stats"

# Test search
curl "http://YOUR_IP:8080/api/search?q=test"
```

## Quick Migration Checklist

- [ ] Transfer `docker-compose.yml`
- [ ] Transfer `small_front/` folder
- [ ] Transfer `archive/` folder
- [ ] Transfer `database.dump`
- [ ] Transfer `init-db.sh` (optional)
- [ ] Create `db_data/postgres` and `db_data/pgadmin` directories
- [ ] Update IP addresses in `docker-compose.yml`
- [ ] Update passwords if desired
- [ ] Import database
- [ ] Start all services
- [ ] Verify frontend works
- [ ] Verify search works
- [ ] Verify images load

## Alternative: Export Running Database

If migrating from a running instance (instead of using the original dump):

```bash
# On source server - create fresh dump
docker compose exec postgres pg_dump \
  -U char_archive \
  -d char_archive \
  -F c -Z 9 \
  > database-export.dump

# Transfer this new dump to the new server
```

## Troubleshooting

### Database import fails
- Ensure PostgreSQL container is healthy before importing
- Check available disk space (need ~20GB+ for expanded database)
- Verify the dump file transferred completely (check file size)

### Frontend can't connect to database
- Wait for PostgreSQL health check to pass
- Verify `DB_HOST: postgres` in frontend environment
- Check database credentials match

### Images not loading
- Verify `archive/` folder transferred completely
- Check the volume mount path in `docker-compose.yml`
- Ensure read permissions on archive folder

### Port binding errors
- Check if ports 5432, 5050, 8080 are available
- Verify the IP address exists on the system
- Try using `0.0.0.0` instead of specific IP

## Estimated Transfer Sizes

| Component | Compressed | Uncompressed |
|-----------|------------|--------------|
| database.dump | ~11GB | ~20GB+ (after import) |
| archive/ | Varies | Varies |
| small_front/ | ~50KB | ~50KB |
| docker-compose.yml | ~2KB | ~2KB |

## Minimum Server Requirements

- **CPU**: 2+ cores recommended
- **RAM**: 4GB minimum, 8GB+ recommended
- **Storage**: 50GB+ (depends on archive size)
- **Docker**: Version 20.10+
- **Docker Compose**: Version 2.0+
