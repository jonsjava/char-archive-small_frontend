#!/usr/bin/env bash
# Shared database import progress helpers for setup.sh

format_bytes() {
  local b="${1:-0}"
  if (( b >= 1073741824 )); then
    awk -v b="$b" 'BEGIN { printf "%.1f GB", b/1073741824 }'
  elif (( b >= 1048576 )); then
    awk -v b="$b" 'BEGIN { printf "%.1f MB", b/1048576 }'
  elif (( b >= 1024 )); then
    awk -v b="$b" 'BEGIN { printf "%.1f KB", b/1024 }'
  else
    echo "${b} B"
  fi
}

pg_restore_object_count() {
  local dump_path="$1"
  local docker_dump count
  [[ -f "$dump_path" ]] || { echo 0; return; }
  docker_dump="${dump_path//\\//}"
  count="$(docker run --rm -v "${docker_dump}:/dump:ro" postgres:16-alpine \
    sh -c "pg_restore -l /dump 2>/dev/null | grep -c '^[0-9]'" 2>/dev/null | tr -d ' \r\n' || true)"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  if (( count <= 0 )); then
    local dump_size
    dump_size="$(wc -c <"$dump_path" | tr -d ' ')"
    count=$(( dump_size / 80000 ))
    (( count < 500 )) && count=500
  fi
  echo "$count"
}

postgres_import_logs() {
  docker compose logs postgres --no-color 2>&1 || true
}

pg_restore_log_stats() {
  local logs="$1"
  local steps last
  steps="$(grep -Ec 'pg_restore: (creating|processing|connecting|executing)' <<<"$logs" || true)"
  last="$(grep 'pg_restore:' <<<"$logs" | tail -1 | sed 's/^[[:space:]]*//' || true)"
  [[ ${#last} -gt 55 ]] && last="${last:0:52}..."
  printf '%s|%s' "${steps:-0}" "${last}"
}

docker_db_metrics() {
  local raw
  raw="$(docker compose exec -T postgres psql -U char_archive -d char_archive -t -A -c \
    "SELECT pg_database_size(current_database()), (SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public');" 2>/dev/null | tr -d '\r' || true)"
  [[ -n "$raw" ]] || return 1
  echo "$raw"
}

import_complete() {
  local logs="$1"
  local metrics="${2:-}"
  if grep -q 'Database restore completed!' <<<"$logs"; then
    return 0
  fi
  if grep -qE 'Database already has [0-9]+ tables, skipping restore' <<<"$logs"; then
    return 0
  fi
  if [[ -n "$metrics" ]]; then
    local tables="${metrics#*|}"
    if [[ "$tables" =~ ^[0-9]+$ ]] && (( tables > 0 )); then
      local active
      active="$(docker compose exec -T postgres psql -U char_archive -d char_archive -t -A -c \
        "SELECT count(*) FROM pg_stat_activity WHERE query ILIKE '%pg_restore%' AND pid <> pg_backend_pid();" 2>/dev/null | tr -d ' \r\n' || true)"
      [[ "$active" == "0" ]] && return 0
    fi
  fi
  return 1
}

draw_import_progress() {
  local percent="$1"
  local phase="$2"
  local detail="$3"
  local elapsed="$4"
  local width=36 filled bar pct_text mins secs
  mins=$(( elapsed / 60 ))
  secs=$(( elapsed % 60 ))
  if (( percent < 0 )); then
    filled=$(( elapsed % (width + 1) ))
    (( filled >= width )) && filled=$(( width - 1 ))
    bar="$(printf '%*s' "$filled" '' | tr ' ' '=')>"
    bar="${bar}$(printf '%*s' $(( width - filled - 1 )) '')"
    pct_text="..."
  else
    filled=$(( percent * width / 100 ))
    (( filled > width )) && filled=$width
    bar="$(printf '%*s' "$filled" '' | tr ' ' '=')"
    bar="${bar}$(printf '%*s' $(( width - filled )) '')"
    pct_text="${percent}%"
  fi
  printf '\r  [%s] %s  %s  (%02d:%02d)  %s    ' "$bar" "$pct_text" "$phase" "$mins" "$secs" "$detail"
}

wait_for_docker_db_import() {
  local dump_path="$1"
  local poll_seconds="${2:-5}"
  local max_attempts="${3:-720}"
  local total_objects steps last_line logs metrics stats elapsed attempt start_ts now tables pct detail phase db_size

  echo "Waiting for database import (first run can take 30+ minutes)..."
  echo "  Measuring dump catalog size..."
  total_objects="$(pg_restore_object_count "$dump_path")"
  echo "  Import has about ${total_objects} restore steps."

  start_ts=$(date +%s)
  attempt=0

  while (( attempt < max_attempts )); do
    attempt=$((attempt + 1))
    now=$(date +%s)
    elapsed=$((now - start_ts))

    logs="$(postgres_import_logs)"
    stats="$(pg_restore_log_stats "$logs")"
    steps="${stats%%|*}"
    last_line="${stats#*|}"
    metrics="$(docker_db_metrics || true)"

    if import_complete "$logs" "$metrics"; then
      tables="?"
      [[ -n "$metrics" ]] && tables="${metrics#*|}"
      draw_import_progress 100 "Done" "tables: ${tables}" "$elapsed"
      echo
      info "Database ready (${tables} public tables)."
      return 0
    fi

    pct=-1
    if (( total_objects > 0 && steps > 0 )); then
      pct=$(( steps * 100 / total_objects ))
      (( pct > 99 )) && pct=99
    fi

    detail="$last_line"
    [[ -z "$detail" ]] && detail="waiting for pg_restore output"
    if [[ -n "$metrics" ]]; then
      db_size="${metrics%%|*}"
      tables="${metrics#*|}"
      detail="tables: ${tables}, size: $(format_bytes "$db_size") - ${detail}"
    elif (( steps > 0 )); then
      detail="step ${steps} of ~${total_objects} - ${detail}"
    fi

    phase="Starting"
    grep -q 'Starting database restore' <<<"$logs" && phase="Restoring"
    draw_import_progress "$pct" "$phase" "$detail" "$elapsed"
    sleep "$poll_seconds"
  done

  echo
  die "Timed out waiting for database. Check: docker compose logs postgres"
}
