-- Tag index for fast autocomplete and tag-filter search.
-- Run once, then use rebuild_tag_index.py to populate.
-- Recommended to run this on a cron. Based on usage, adjust timing of cron
CREATE TABLE IF NOT EXISTS character_tags (
    source    TEXT NOT NULL,
    char_key  TEXT NOT NULL,
    tag_norm  TEXT NOT NULL,
    tag       TEXT NOT NULL,
    PRIMARY KEY (source, char_key, tag_norm)
);

CREATE INDEX IF NOT EXISTS character_tags_tag_norm_idx
    ON character_tags (source, tag_norm);

CREATE INDEX IF NOT EXISTS character_tags_tag_prefix_idx
    ON character_tags (tag_norm text_pattern_ops);

CREATE TABLE IF NOT EXISTS tag_index (
    source    TEXT NOT NULL,
    tag_norm  TEXT NOT NULL,
    tag       TEXT NOT NULL,
    count     BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (source, tag_norm)
);

CREATE INDEX IF NOT EXISTS tag_index_prefix_idx
    ON tag_index (tag_norm text_pattern_ops);

CREATE INDEX IF NOT EXISTS tag_index_count_idx
    ON tag_index (source, count DESC);

-- Sync character_tags + tag_index when a character definition is inserted/updated.
CREATE OR REPLACE FUNCTION sync_character_tags_from_def()
RETURNS TRIGGER AS $$
DECLARE
    v_source   TEXT := TG_ARGV[0];
    v_id_col   TEXT := TG_ARGV[1];
    v_char_key TEXT;
    v_tag      TEXT;
    v_tag_norm TEXT;
    v_old_norms TEXT[];
    v_new_norms TEXT[];
    v_all_norms TEXT[];
    v_norm     TEXT;
    v_count    BIGINT;
    v_display  TEXT;
BEGIN
    EXECUTE format('SELECT ($1).%I::text', v_id_col) INTO v_char_key USING NEW;

    SELECT COALESCE(array_agg(DISTINCT tag_norm), ARRAY[]::TEXT[])
    INTO v_old_norms
    FROM character_tags
    WHERE source = v_source AND char_key = v_char_key;

    DELETE FROM character_tags
    WHERE source = v_source AND char_key = v_char_key;

    v_new_norms := ARRAY[]::TEXT[];

    FOR v_tag IN
        SELECT trim(elem.tag)
        FROM jsonb_array_elements_text(
            COALESCE(NEW.definition->'data'->'tags', NEW.definition->'tags', '[]'::jsonb)
        ) AS elem(tag)
    LOOP
        IF v_tag = '' THEN
            CONTINUE;
        END IF;

        v_tag_norm := lower(v_tag);

        INSERT INTO character_tags (source, char_key, tag_norm, tag)
        VALUES (v_source, v_char_key, v_tag_norm, v_tag)
        ON CONFLICT (source, char_key, tag_norm) DO NOTHING;

        IF NOT v_tag_norm = ANY(v_new_norms) THEN
            v_new_norms := array_append(v_new_norms, v_tag_norm);
        END IF;
    END LOOP;

    SELECT array_agg(DISTINCT n)
    INTO v_all_norms
    FROM unnest(v_old_norms || v_new_norms) AS n;

    IF v_all_norms IS NULL THEN
        RETURN NEW;
    END IF;

    FOREACH v_norm IN ARRAY v_all_norms
    LOOP
        SELECT COUNT(*), MIN(tag)
        INTO v_count, v_display
        FROM character_tags
        WHERE source = v_source AND tag_norm = v_norm;

        IF v_count = 0 THEN
            DELETE FROM tag_index
            WHERE source = v_source AND tag_norm = v_norm;
        ELSE
            INSERT INTO tag_index (source, tag_norm, tag, count)
            VALUES (v_source, v_norm, v_display, v_count)
            ON CONFLICT (source, tag_norm)
            DO UPDATE SET
                count = EXCLUDED.count,
                tag = EXCLUDED.tag;
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers on all character definition tables
DROP TRIGGER IF EXISTS trg_sync_tags ON chub_character_def;
CREATE TRIGGER trg_sync_tags
    AFTER INSERT OR UPDATE OF definition ON chub_character_def
    FOR EACH ROW EXECUTE PROCEDURE sync_character_tags_from_def('chub', 'id');

DROP TRIGGER IF EXISTS trg_sync_tags ON generic_character_def;
CREATE TRIGGER trg_sync_tags
    AFTER INSERT OR UPDATE OF definition ON generic_character_def
    FOR EACH ROW EXECUTE PROCEDURE sync_character_tags_from_def('generic', 'card_data_hash');

DROP TRIGGER IF EXISTS trg_sync_tags ON booru_character_def;
CREATE TRIGGER trg_sync_tags
    AFTER INSERT OR UPDATE OF definition ON booru_character_def
    FOR EACH ROW EXECUTE PROCEDURE sync_character_tags_from_def('booru', 'id');

DROP TRIGGER IF EXISTS trg_sync_tags ON webring_character_def;
CREATE TRIGGER trg_sync_tags
    AFTER INSERT OR UPDATE OF definition ON webring_character_def
    FOR EACH ROW EXECUTE PROCEDURE sync_character_tags_from_def('webring', 'card_data_hash');

DROP TRIGGER IF EXISTS trg_sync_tags ON char_tavern_character_def;
CREATE TRIGGER trg_sync_tags
    AFTER INSERT OR UPDATE OF definition ON char_tavern_character_def
    FOR EACH ROW EXECUTE PROCEDURE sync_character_tags_from_def('char_tavern', 'path');

DROP TRIGGER IF EXISTS trg_sync_tags ON risuai_character_def;
CREATE TRIGGER trg_sync_tags
    AFTER INSERT OR UPDATE OF definition ON risuai_character_def
    FOR EACH ROW EXECUTE PROCEDURE sync_character_tags_from_def('risuai', 'id');

DROP TRIGGER IF EXISTS trg_sync_tags ON nyaime_character_def;
CREATE TRIGGER trg_sync_tags
    AFTER INSERT OR UPDATE OF definition ON nyaime_character_def
    FOR EACH ROW EXECUTE PROCEDURE sync_character_tags_from_def('nyaime', 'id');
