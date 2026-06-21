"""Import character cards dropped into the import/ folder."""

import base64
import hashlib
import json
import os
import shutil
import struct
import zlib
from datetime import datetime, timezone
from pathlib import Path

import psycopg2
from psycopg2.extensions import Binary
from psycopg2.extras import Json

DB_HOST = os.environ.get('DB_HOST', 'postgres')
DB_PORT = os.environ.get('DB_PORT', '5432')
DB_NAME = os.environ.get('DB_NAME', 'char_archive')
DB_USER = os.environ.get('DB_USER', 'char_archive')
DB_PASSWORD = os.environ.get('DB_PASSWORD', '')

ARCHIVE_PATH = Path(os.environ.get('ARCHIVE_PATH', '/archive'))
IMAGE_SUBDIR = os.environ.get('IMAGE_SUBDIR', '').strip().strip('/')
IMAGE_LAYOUT = os.environ.get('IMAGE_LAYOUT', 'sharded').lower()
IMPORT_DIR = Path(os.environ.get('IMPORT_DIR', '/import'))

CARD_EXTENSIONS = {'.png', '.json'}


def image_root():
    return ARCHIVE_PATH / IMAGE_SUBDIR if IMAGE_SUBDIR else ARCHIVE_PATH


def image_path_for_hash(image_hash):
    h = image_hash.lower()
    root = image_root()
    if IMAGE_LAYOUT == 'sharded':
        return root / h[0] / h[1] / h[2] / h[3:]
    return root / h


def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
    )


def extract_chara_from_png(png_data):
    """Extract embedded character JSON from PNG tEXt (chara/ccv3) chunks."""
    if png_data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Not a PNG file')

    pos = 8
    candidates = ('ccv3', 'chara')
    found = {}

    while pos + 12 <= len(png_data):
        length = struct.unpack('>I', png_data[pos:pos + 4])[0]
        chunk_type = png_data[pos + 4:pos + 8]
        chunk_data = png_data[pos + 8:pos + 8 + length]
        if chunk_type == b'tEXt':
            null = chunk_data.find(b'\x00')
            if null == -1:
                continue
            keyword = chunk_data[:null].decode('latin-1', errors='replace')
            if keyword in candidates:
                found[keyword] = chunk_data[null + 1:]
        pos += 12 + length

    for key in candidates:
        if key not in found:
            continue
        raw = found[key]
        try:
            decoded = base64.b64decode(raw)
        except Exception:
            decoded = raw
        text = decoded.decode('utf-8')
        return json.loads(text)

    raise ValueError('No chara/ccv3 data found in PNG')


def normalize_definition(data):
    """Ensure definition has a data sub-object for tag/search compatibility."""
    if not isinstance(data, dict):
        raise ValueError('Definition must be a JSON object')

    if 'data' in data and isinstance(data['data'], dict):
        return data

    name = data.get('name') or data.get('char_name') or 'Imported Character'
    inner = dict(data)
    inner.setdefault('name', name)
    return {'name': name, 'data': inner}


def card_data_hash(definition):
    payload = json.dumps(definition, sort_keys=True, ensure_ascii=False)
    return hashlib.md5(payload.encode('utf-8')).hexdigest()


def store_image(png_bytes):
    image_hash = hashlib.md5(png_bytes).hexdigest()
    dest = image_path_for_hash(image_hash)
    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(png_bytes)
    return image_hash


def card_name(definition):
    data = definition.get('data') or definition
    return (
        definition.get('name')
        or data.get('name')
        or data.get('char_name')
        or 'Imported Character'
    )


def insert_card(definition, raw_bytes, image_hash, source_file):
    name = card_name(definition)
    c_hash = card_data_hash(definition)
    compressed = zlib.compress(raw_bytes, 9)
    now = datetime.now(timezone.utc)

    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO generic_character_def (
                card_data_hash, name, definition, raw, image_hash,
                metadata, summary, tagline, source, source_url, added, hidden
            ) VALUES (
                %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s, %s, false
            )
            ON CONFLICT (card_data_hash) DO NOTHING
            """,
            (
                c_hash,
                name,
                Json(definition),
                Binary(compressed),
                image_hash,
                Json({'imported': True}),
                '',
                '',
                'import',
                source_file,
                now,
            ),
        )
        inserted = cur.rowcount > 0
        conn.commit()
        return c_hash, inserted
    finally:
        conn.close()


def import_file(path):
    """Import one card file. Returns (card_data_hash, inserted)."""
    path = Path(path)
    suffix = path.suffix.lower()
    raw_bytes = path.read_bytes()

    if suffix == '.png':
        definition = normalize_definition(extract_chara_from_png(raw_bytes))
        image_hash = store_image(raw_bytes)
        return insert_card(definition, raw_bytes, image_hash, path.name)

    if suffix == '.json':
        definition = normalize_definition(json.loads(raw_bytes.decode('utf-8')))
        image_hash = hashlib.md5(raw_bytes).hexdigest()
        return insert_card(definition, raw_bytes, image_hash, path.name)

    raise ValueError(f'Unsupported file type: {suffix}')


def scan_import_dir():
    """Process all pending files in IMPORT_DIR. Returns list of result dicts."""
    import_dir = IMPORT_DIR
    processed_dir = import_dir / 'processed'
    failed_dir = import_dir / 'failed'
    lock_file = import_dir / '.scan.lock'

    for sub in (import_dir, processed_dir, failed_dir):
        sub.mkdir(parents=True, exist_ok=True)

    try:
        fd = os.open(lock_file, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        return []

    results = []
    try:
        for path in sorted(import_dir.iterdir()):
            if not path.is_file():
                continue
            if path.suffix.lower() not in CARD_EXTENSIONS:
                continue
            if path.name == '.scan.lock':
                continue

            try:
                c_hash, inserted = import_file(path)
                dest = processed_dir / path.name
                if dest.exists():
                    dest = processed_dir / f'{path.stem}_{c_hash[:8]}{path.suffix}'
                shutil.move(str(path), str(dest))
                results.append({
                    'file': path.name,
                    'status': 'imported' if inserted else 'duplicate',
                    'card_data_hash': c_hash,
                })
                print(f"Import {path.name}: {'ok' if inserted else 'duplicate'} ({c_hash})", flush=True)
            except Exception as exc:
                dest = failed_dir / path.name
                if dest.exists():
                    dest = failed_dir / f'{path.stem}_{path.stat().st_mtime_ns}{path.suffix}'
                shutil.move(str(path), str(dest))
                err_file = dest.with_suffix(dest.suffix + '.error.txt')
                err_file.write_text(str(exc), encoding='utf-8')
                results.append({'file': path.name, 'status': 'failed', 'error': str(exc)})
                print(f"Import {path.name}: failed — {exc}", flush=True)
    finally:
        os.close(fd)
        lock_file.unlink(missing_ok=True)

    return results
