#!/usr/bin/env python3
"""Create tag index schema and rebuild from latest character definitions."""

import os
import sys
import time
from pathlib import Path

import psycopg2

DB_HOST = os.environ.get('DB_HOST', 'postgres')
DB_PORT = os.environ.get('DB_PORT', '5432')
DB_NAME = os.environ.get('DB_NAME', 'char_archive')
DB_USER = os.environ.get('DB_USER', 'char_archive')
DB_PASSWORD = os.environ.get('DB_PASSWORD', '')

SQL_DIR = Path(__file__).parent / 'sql'

SOURCES = [
    ('chub', 'chub_character_def', 'id'),
    ('generic', 'generic_character_def', 'card_data_hash'),
    ('booru', 'booru_character_def', 'id'),
    ('webring', 'webring_character_def', 'card_data_hash'),
    ('char_tavern', 'char_tavern_character_def', 'path'),
    ('risuai', 'risuai_character_def', 'id'),
    ('nyaime', 'nyaime_character_def', 'id'),
]

TAGS_JSON = "COALESCE(definition->'data'->'tags', definition->'tags', '[]'::jsonb)"


def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
    )


def apply_schema(cur):
    schema_sql = (SQL_DIR / 'tag_index.sql').read_text()
    cur.execute(schema_sql)


def rebuild_source(cur, source, table, id_col):
    print(f'  Indexing {source} ({table})...', flush=True)
    started = time.time()

    cur.execute('DELETE FROM character_tags WHERE source = %s', (source,))

    insert_tags_sql = f"""
        INSERT INTO character_tags (source, char_key, tag_norm, tag)
        SELECT
            %s,
            latest.char_key,
            lower(trim(tag)),
            trim(tag)
        FROM (
            SELECT DISTINCT ON ({id_col}) {id_col}::text AS char_key, definition
            FROM {table}
            ORDER BY {id_col}, added DESC
        ) latest
        CROSS JOIN LATERAL jsonb_array_elements_text(
            COALESCE(latest.definition->'data'->'tags', latest.definition->'tags', '[]'::jsonb)
        ) AS tag
        WHERE trim(tag) <> ''
        ON CONFLICT (source, char_key, tag_norm) DO NOTHING
    """
    cur.execute(insert_tags_sql, (source,))

    cur.execute('DELETE FROM tag_index WHERE source = %s', (source,))

    cur.execute(
        """
        INSERT INTO tag_index (source, tag_norm, tag, count)
        SELECT source, tag_norm, MIN(tag), COUNT(*)
        FROM character_tags
        WHERE source = %s
        GROUP BY source, tag_norm
        """,
        (source,),
    )

    cur.execute('SELECT COUNT(*) FROM tag_index WHERE source = %s', (source,))
    tag_count = cur.fetchone()[0]
    elapsed = time.time() - started
    print(f'    {tag_count:,} unique tags in {elapsed:.1f}s', flush=True)
    return tag_count


def main():
    print(f'Connecting to {DB_HOST}:{DB_PORT}/{DB_NAME}...', flush=True)
    conn = get_connection()
    conn.autocommit = False
    cur = conn.cursor()

    try:
        print('Applying schema (tables, indexes, triggers)...', flush=True)
        apply_schema(cur)
        conn.commit()

        print('Rebuilding tag index from latest character definitions...', flush=True)
        total_tags = 0
        for source, table, id_col in SOURCES:
            total_tags += rebuild_source(cur, source, table, id_col)
            conn.commit()

        cur.execute('SELECT COUNT(*) FROM character_tags')
        char_tag_rows = cur.fetchone()[0]
        cur.execute('SELECT COUNT(*) FROM tag_index')
        index_rows = cur.fetchone()[0]

        print(flush=True)
        print(f'Done. {index_rows:,} tag_index rows, {char_tag_rows:,} character_tags rows.', flush=True)
        print('New cards will update the index automatically via database triggers.', flush=True)

    except Exception as exc:
        conn.rollback()
        print(f'Error: {exc}', file=sys.stderr)
        sys.exit(1)
    finally:
        cur.close()
        conn.close()


if __name__ == '__main__':
    main()
