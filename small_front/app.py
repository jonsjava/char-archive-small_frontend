import os
from flask import Flask, render_template, request, jsonify, send_file, abort
from flask_cors import CORS
import psycopg2
from psycopg2.extras import RealDictCursor
from pathlib import Path

app = Flask(__name__)
CORS(app)

# Configuration
DB_HOST = os.environ.get('DB_HOST', 'postgres')
DB_PORT = os.environ.get('DB_PORT', '5432')
DB_NAME = os.environ.get('DB_NAME', 'char_archive')
DB_USER = os.environ.get('DB_USER', 'char_archive')
DB_PASSWORD = os.environ.get('DB_PASSWORD', '')
ARCHIVE_PATH = Path(os.environ.get('ARCHIVE_PATH', '/archive'))
# IMAGE_SUBDIR: optional folder under ARCHIVE_PATH (e.g. hashed-data)
IMAGE_SUBDIR = os.environ.get('IMAGE_SUBDIR', '').strip().strip('/')
# IMAGE_LAYOUT: flat = root/<full-hash>  |  sharded = root/<h0>/<h1>/<h2>/<rest>
IMAGE_LAYOUT = os.environ.get('IMAGE_LAYOUT', 'flat').lower()


def image_root():
    return ARCHIVE_PATH / IMAGE_SUBDIR if IMAGE_SUBDIR else ARCHIVE_PATH


def get_image_path(image_hash):
    """Convert image hash to file path based on IMAGE_LAYOUT."""
    if not image_hash or len(image_hash) < 4:
        return None
    h = image_hash.lower()
    root = image_root()
    if IMAGE_LAYOUT == 'sharded':
        return root / h[0] / h[1] / h[2] / h[3:]
    if IMAGE_LAYOUT == 'flat':
        return root / h
    return None


def browse_all_enabled():
    return os.environ.get('ENABLE_BROWSE_ALL', 'false').lower() in ('1', 'true', 'yes')


SORT_COLUMNS = {'added': 'added', 'name': 'name'}

SOURCE_CONFIG = {
    'chub': {
        'label': 'Chub',
        'table': 'chub_character_def',
        'id_col': 'id',
        'name_col': 'name',
        'download_name_col': 'name',
        'has_author': True,
        'columns': "id::text, author, name, image_hash, added, 'chub' as source, COALESCE(LEFT(definition->'data'->>'description', 150), '') as tagline",
    },
    'generic': {
        'label': 'Generic',
        'table': 'generic_character_def',
        'id_col': 'card_data_hash',
        'name_col': 'name',
        'download_name_col': 'name',
        'has_author': False,
        'columns': "card_data_hash as id, '' as author, name, image_hash, added, 'generic' as source, COALESCE(LEFT(definition->'data'->>'description', 150), COALESCE(LEFT(tagline, 150), '')) as tagline",
    },
    'booru': {
        'label': 'Booru',
        'table': 'booru_character_def',
        'id_col': 'id',
        'name_col': 'name',
        'download_name_col': 'name',
        'has_author': True,
        'columns': "id::text, author, name, image_hash, added, 'booru' as source, COALESCE(LEFT(definition->'data'->>'description', 150), '') as tagline",
    },
    'webring': {
        'label': 'Webring',
        'table': 'webring_character_def',
        'id_col': 'card_data_hash',
        'name_col': 'name',
        'download_name_col': 'name',
        'has_author': True,
        'columns': "card_data_hash as id, author, name, image_hash, added, 'webring' as source, COALESCE(LEFT(definition->'data'->>'description', 150), COALESCE(LEFT(tagline, 150), '')) as tagline",
    },
    'char_tavern': {
        'label': 'Character Tavern',
        'table': 'char_tavern_character_def',
        'id_col': 'path',
        'name_col': 'path',
        'download_name_col': 'path',
        'has_author': False,
        'columns': "path as id, '' as author, path as name, image_hash, added, 'char_tavern' as source, COALESCE(LEFT(definition->'data'->>'description', 150), '') as tagline",
    },
    'risuai': {
        'label': 'RisuAI',
        'table': 'risuai_character_def',
        'id_col': 'id',
        'name_col': 'author',
        'download_name_col': 'id',
        'has_author': True,
        'columns': "id::text, author, author as name, image_hash, added, 'risuai' as source, COALESCE(LEFT(definition->'data'->>'description', 150), '') as tagline",
    },
    'nyaime': {
        'label': 'Nyaime',
        'table': 'nyaime_character_def',
        'id_col': 'id',
        'name_col': 'author',
        'download_name_col': 'id',
        'has_author': True,
        'columns': "id::text, author, author as name, image_hash, added, 'nyaime' as source, COALESCE(LEFT(definition->'data'->>'description', 150), '') as tagline",
    },
}

TAG_EXISTS_SQL = """
EXISTS (
    SELECT 1 FROM jsonb_array_elements_text(
        COALESCE(definition->'data'->'tags', definition->'tags', '[]'::jsonb)
    ) AS t(tag)
    WHERE lower(t.tag) = lower(%s)
)
"""

TAG_NOT_EXISTS_SQL = """
NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements_text(
        COALESCE(definition->'data'->'tags', definition->'tags', '[]'::jsonb)
    ) AS t(tag)
    WHERE lower(t.tag) = lower(%s)
)
"""


def parse_tag_filters(tag_tokens):
    """Split comma-separated tags into required (AND) and excluded (-tag) lists."""
    include = []
    exclude = []
    for token in tag_tokens:
        if token.startswith('-') and len(token) > 1:
            exclude.append(token[1:].strip())
        elif not token.startswith('-'):
            include.append(token)
    return include, exclude


_available_sources = None


def get_available_sources():
    """Load sources from SOURCE_CONFIG whose tables exist in the database."""
    global _available_sources
    if _available_sources is not None:
        return _available_sources

    sources = []
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        for source_id, cfg in SOURCE_CONFIG.items():
            cur.execute(
                """
                SELECT EXISTS (
                    SELECT 1 FROM information_schema.tables
                    WHERE table_schema = 'public' AND table_name = %s
                ) AS ok
                """,
                (cfg['table'],),
            )
            if cur.fetchone()['ok']:
                sources.append({
                    'id': source_id,
                    'label': cfg.get('label', source_id.replace('_', ' ').title()),
                    'table': cfg['table'],
                })
        cur.close()
        conn.close()
    except Exception as e:
        print(f"Source discovery error: {e}")
        sources = [
            {
                'id': source_id,
                'label': cfg.get('label', source_id.replace('_', ' ').title()),
                'table': cfg['table'],
            }
            for source_id, cfg in SOURCE_CONFIG.items()
        ]

    _available_sources = sources
    return _available_sources


def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        cursor_factory=RealDictCursor
    )


def get_source_config(source):
    available = {s['id']: SOURCE_CONFIG[s['id']] for s in get_available_sources()}
    if source == 'all':
        return available
    if source in available:
        return {source: available[source]}
    return {}


def build_source_subquery(src_name, src_info, name, author, include_tags, exclude_tags, use_tag_index):
    """Build one UNION ALL branch with filters applied."""
    if author and not src_info['has_author']:
        return None, []

    where_parts = []
    params = []
    table = src_info['table']
    id_col = src_info['id_col']

    if name:
        where_parts.append(f"{src_info['name_col']} ILIKE %s")
        params.append(f'%{name}%')

    if author:
        where_parts.append('author ILIKE %s')
        params.append(f'%{author}%')

    for tag in include_tags:
        if use_tag_index:
            where_parts.append(f"""
                EXISTS (
                    SELECT 1 FROM character_tags ct
                    WHERE ct.source = %s
                      AND ct.char_key = {table}.{id_col}::text
                      AND ct.tag_norm = lower(%s)
                )
            """)
            params.extend([src_name, tag])
        else:
            where_parts.append(TAG_EXISTS_SQL)
            params.append(tag)

    for tag in exclude_tags:
        if use_tag_index:
            where_parts.append(f"""
                NOT EXISTS (
                    SELECT 1 FROM character_tags ct
                    WHERE ct.source = %s
                      AND ct.char_key = {table}.{id_col}::text
                      AND ct.tag_norm = lower(%s)
                )
            """)
            params.extend([src_name, tag])
        else:
            where_parts.append(TAG_NOT_EXISTS_SQL)
            params.append(tag)

    if not where_parts:
        where_parts.append('TRUE')

    where_clause = ' AND '.join(where_parts)
    query = f"""
        SELECT {src_info['columns']}
        FROM {table}
        WHERE {where_clause}
    """
    return query, params


def tag_index_populated(cur):
    cur.execute('SELECT EXISTS (SELECT 1 FROM tag_index LIMIT 1) AS ok')
    return cur.fetchone()['ok']


@app.route('/api/tags')
def tag_suggestions():
    """Return tag suggestions from pre-built tag_index (fast prefix search)."""
    query = request.args.get('q', '').strip()
    source = request.args.get('source', 'all')
    limit = min(max(int(request.args.get('limit', 25)), 1), 50)

    if len(query) < 2:
        return jsonify({'tags': []})

    try:
        conn = get_db_connection()
        cur = conn.cursor()

        if not tag_index_populated(cur):
            cur.close()
            conn.close()
            return jsonify({
                'tags': [],
                'warning': 'Tag index empty. Run: python rebuild_tag_index.py'
            })

        prefix = query.lower()
        if source == 'all':
            sql = """
                SELECT
                    (array_agg(tag ORDER BY count DESC))[1] AS tag,
                    SUM(count) AS count
                FROM tag_index
                WHERE tag_norm LIKE %s
                GROUP BY tag_norm
                ORDER BY count DESC, tag ASC
                LIMIT %s
            """
            cur.execute(sql, (f'{prefix}%', limit))
        else:
            if source not in SOURCE_CONFIG:
                return jsonify({'tags': []})
            sql = """
                SELECT tag, count
                FROM tag_index
                WHERE source = %s AND tag_norm LIKE %s
                ORDER BY count DESC, tag ASC
                LIMIT %s
            """
            cur.execute(sql, (source, f'{prefix}%', limit))

        tags = [{'tag': row['tag'], 'count': row['count']} for row in cur.fetchall()]
        cur.close()
        conn.close()
        return jsonify({'tags': tags})

    except Exception as e:
        print(f"Tag suggestion error: {e}")
        return jsonify({'error': str(e)}), 500


@app.context_processor
def inject_template_config():
    return {
        'browse_all_enabled': browse_all_enabled(),
        'sources': get_available_sources(),
    }


@app.route('/')
def index():
    return render_template('index.html', open_character=None)


@app.route('/character/<source>/<path:char_id>')
def character_page(source, char_id):
    if source not in SOURCE_CONFIG:
        abort(404)
    return render_template('index.html', open_character={'source': source, 'id': char_id})


@app.route('/api/search')
def search():
    name = request.args.get('name', '').strip()
    author = request.args.get('author', '').strip()
    tag_tokens = [t.strip() for t in request.args.get('tags', '').split(',') if t.strip()]
    include_tags, exclude_tags = parse_tag_filters(tag_tokens)
    source = request.args.get('source', 'all')
    page = max(int(request.args.get('page', 1)), 1)
    per_page = max(int(request.args.get('per_page', 24)), 1)
    offset = (page - 1) * per_page

    browse_all = (
        browse_all_enabled()
        and request.args.get('browse', '').lower() == 'all'
    )
    has_filters = browse_all or bool(name or author or tag_tokens or source != 'all')
    if not has_filters:
        return jsonify({'results': [], 'total': 0, 'page': page, 'per_page': per_page, 'pages': 0})

    sort_key = request.args.get('sort', 'added')
    sort_col = SORT_COLUMNS.get(sort_key, 'added')
    order = 'ASC' if request.args.get('order', 'desc').lower() == 'asc' else 'DESC'

    try:
        conn = get_db_connection()
        cur = conn.cursor()

        union_parts = []
        params = []
        use_tag_index = tag_index_populated(cur)

        for src_name, src_info in get_source_config(source).items():
            subquery, sub_params = build_source_subquery(
                src_name, src_info, name, author, include_tags, exclude_tags, use_tag_index
            )
            if subquery:
                union_parts.append(subquery)
                params.extend(sub_params)

        if not union_parts:
            return jsonify({'results': [], 'total': 0, 'page': page, 'per_page': per_page, 'pages': 0})

        combined = ' UNION ALL '.join(union_parts)
        # 1) One row per source+id (latest version). 2) Collapse same author/name/date.
        results_query = f"""
            WITH combined AS (
                {combined}
            ),
            by_id AS (
                SELECT DISTINCT ON (source, id)
                    id, author, name, image_hash, added, source, tagline
                FROM combined
                ORDER BY source, id, added DESC
            ),
            deduped AS (
                SELECT DISTINCT ON (source, COALESCE(author, ''), name, added::date)
                    id, author, name, image_hash, added, source, tagline
                FROM by_id
                ORDER BY source, COALESCE(author, ''), name, added::date, added DESC, id
            )
            SELECT *, COUNT(*) OVER() AS total_count
            FROM deduped
            ORDER BY {sort_col} {order}
            LIMIT %s OFFSET %s
        """
        cur.execute(results_query, params + [per_page, offset])
        rows = cur.fetchall()

        total = rows[0]['total_count'] if rows else 0
        results = []
        for row in rows:
            item = dict(row)
            del item['total_count']
            results.append(item)

        cur.close()
        conn.close()

    except Exception as e:
        print(f"Database error: {e}")
        return jsonify({'error': str(e)}), 500

    return jsonify({
        'results': results,
        'total': total,
        'page': page,
        'per_page': per_page,
        'pages': (total + per_page - 1) // per_page if total else 0
    })


@app.route('/api/character/<source>/<path:char_id>')
def get_character(source, char_id):
    """Get detailed character information."""
    if source not in SOURCE_CONFIG:
        return jsonify({'error': 'Invalid source'}), 400

    try:
        conn = get_db_connection()
        cur = conn.cursor()

        cfg = SOURCE_CONFIG[source]
        table = cfg['table']
        id_col = cfg['id_col']

        cur.execute(f"""
            SELECT * FROM {table}
            WHERE {id_col} = %s
            ORDER BY added DESC
            LIMIT 1
        """, (char_id,))

        result = cur.fetchone()
        cur.close()
        conn.close()

        if not result:
            return jsonify({'error': 'Character not found'}), 404

        char_data = dict(result)
        if 'raw' in char_data:
            char_data['has_raw'] = True
            del char_data['raw']

        return jsonify(char_data)

    except Exception as e:
        print(f"Database error: {e}")
        return jsonify({'error': str(e)}), 500


def embed_chara_in_png(png_data, chara_json):
    """Embed character data into PNG as a tEXt chunk with keyword 'chara'."""
    import struct
    import base64
    import zlib as zlib_mod

    chara_b64 = base64.b64encode(chara_json.encode('utf-8'))
    keyword = b'chara'
    text_data = keyword + b'\x00' + chara_b64
    chunk_type = b'tEXt'
    crc = zlib_mod.crc32(chunk_type + text_data) & 0xffffffff
    chunk = struct.pack('>I', len(text_data)) + chunk_type + text_data + struct.pack('>I', crc)

    iend_pos = png_data.rfind(b'IEND')
    if iend_pos == -1:
        raise ValueError("Invalid PNG: no IEND chunk found")

    insert_pos = iend_pos - 4
    return png_data[:insert_pos] + chunk + png_data[insert_pos:]


@app.route('/api/card/<source>/<path:char_id>')
def download_card(source, char_id):
    """Download character as PNG card with embedded data."""
    if source not in SOURCE_CONFIG:
        return jsonify({'error': 'Invalid source'}), 400

    try:
        conn = get_db_connection()
        cur = conn.cursor()

        cfg = SOURCE_CONFIG[source]
        table = cfg['table']
        id_col = cfg['id_col']
        name_col = cfg['download_name_col']

        cur.execute(f"""
            SELECT {name_col}, raw, image_hash, definition FROM {table}
            WHERE {id_col} = %s
            ORDER BY added DESC
            LIMIT 1
        """, (char_id,))

        result = cur.fetchone()
        cur.close()
        conn.close()

        if not result:
            return jsonify({'error': 'Character not found'}), 404

        import zlib
        import io
        import json

        raw_data = result['raw']
        image_hash = result['image_hash']
        definition = result['definition']
        name = result[name_col] or char_id
        safe_name = "".join(c for c in str(name) if c.isalnum() or c in ' -_').strip() or 'character'

        if raw_data:
            try:
                raw_data = zlib.decompress(raw_data)
            except Exception:
                pass

        if raw_data and raw_data[:8] == b'\x89PNG\r\n\x1a\n':
            return send_file(
                io.BytesIO(raw_data),
                mimetype='image/png',
                as_attachment=True,
                download_name=f"{safe_name}.png"
            )

        image_path = get_image_path(image_hash)
        if not image_path or not image_path.exists():
            return jsonify({'error': 'Image not found'}), 404

        with open(image_path, 'rb') as f:
            png_data = f.read()

        if png_data[:8] != b'\x89PNG\r\n\x1a\n':
            return jsonify({'error': 'Image is not a valid PNG'}), 500

        if raw_data:
            try:
                json.loads(raw_data.decode('utf-8'))
                chara_json = raw_data.decode('utf-8')
            except Exception:
                chara_json = json.dumps(definition, ensure_ascii=False)
        else:
            chara_json = json.dumps(definition, ensure_ascii=False)

        card_png = embed_chara_in_png(png_data, chara_json)
        return send_file(
            io.BytesIO(card_png),
            mimetype='image/png',
            as_attachment=True,
            download_name=f"{safe_name}.png"
        )

    except Exception as e:
        print(f"Download error: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({'error': str(e)}), 500


@app.route('/api/card/<source>/<path:char_id>/json')
def download_card_json(source, char_id):
    """Download character definition as JSON."""
    if source not in SOURCE_CONFIG:
        return jsonify({'error': 'Invalid source'}), 400

    try:
        conn = get_db_connection()
        cur = conn.cursor()

        cfg = SOURCE_CONFIG[source]
        table = cfg['table']
        id_col = cfg['id_col']
        name_col = cfg['download_name_col']

        cur.execute(f"""
            SELECT {name_col}, definition FROM {table}
            WHERE {id_col} = %s
            ORDER BY added DESC
            LIMIT 1
        """, (char_id,))

        result = cur.fetchone()
        cur.close()
        conn.close()

        if not result:
            return jsonify({'error': 'Character not found'}), 404

        import io
        import json

        name = result[name_col] or char_id
        definition = result['definition']
        safe_name = "".join(c for c in str(name) if c.isalnum() or c in ' -_').strip() or 'character'
        json_data = json.dumps(definition, indent=2, ensure_ascii=False)

        return send_file(
            io.BytesIO(json_data.encode('utf-8')),
            mimetype='application/json',
            as_attachment=True,
            download_name=f"{safe_name}.json"
        )

    except Exception as e:
        print(f"JSON download error: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/image/<image_hash>')
def serve_image(image_hash):
    """Serve character image by hash."""
    image_path = get_image_path(image_hash)
    if not image_path or not image_path.exists():
        abort(404)
    return send_file(image_path, mimetype='image/png')


@app.route('/api/stats')
def stats():
    """Get database statistics."""
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        stats_data = {}
        total = 0
        for src in get_available_sources():
            cur.execute(f"SELECT COUNT(*) as count FROM {src['table']}")
            count = cur.fetchone()['count']
            stats_data[src['id']] = count
            total += count

        stats_data['total'] = total
        cur.close()
        conn.close()
        return jsonify(stats_data)

    except Exception as e:
        print(f"Stats error: {e}")
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    get_available_sources()
    port = int(os.environ.get('PORT', 5001))
    app.run(host='0.0.0.0', port=port, debug=True)
