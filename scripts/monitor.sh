#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/.workshop/bin:$PATH"

INTERVAL=2
ONCE=0
LINES_DRAWN=0
PREV_TIME=0
SNAPSHOT_TIME=0

usage() {
  cat <<'EOF'
Usage:
  scripts/monitor.sh [--once] [--interval SECONDS]

Watch the standard workshop NATS monitoring endpoints:

  hub:8222 l1:8232 l2:8242 l3:8252

Options:
  --once                 Print one snapshot and exit
  --interval SECONDS     Refresh interval in seconds (default: 2)
  -h, --help             Show this help
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help|help)
      usage
      exit 0
      ;;
    --once)
      ONCE=1
      ;;
    --interval)
      shift
      [[ $# -gt 0 ]] || die "--interval requires a value"
      [[ "$1" =~ ^[1-9][0-9]*$ ]] || die "invalid interval: $1"
      INTERVAL="$1"
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

command -v curl >/dev/null 2>&1 || die "curl not found in PATH"
command -v jq >/dev/null 2>&1 || die "jq not found in PATH"

servers=(
  "hub:8222"
  "l1:8232"
  "l2:8242"
  "l3:8252"
)

row_names=()
row_endpoints=()
row_servers=()
row_clusters=()
row_connections=()
row_subscriptions=()
row_in_msgs=()
row_out_msgs=()
row_in_rates=()
row_out_rates=()
row_leafs=()
prev_in_msgs=()
prev_out_msgs=()

NAME_W=4
ENDPOINT_W=8
SERVER_W=6
CLUSTER_W=7
CONN_W=4
SUBS_W=4
IN_RATE_W=4
OUT_RATE_W=5

cleanup() {
  if [[ "$ONCE" == "0" && -t 1 ]]; then
    printf '\033[?25h\n'
  fi
}

print_line() {
  local line="$1"

  if [[ -t 1 ]]; then
    printf '\r\033[2K'
  fi

  printf '%s\n' "$line"
  LINES_DRAWN=$((LINES_DRAWN + 1))
}

fill() {
  local width="$1"
  local value

  printf -v value '%*s' "$width" ''
  printf '%s' "${value// /-}"
}

msg_rate() {
  local current="$1"
  local previous="$2"
  local elapsed="$3"
  local delta

  [[ "$current" =~ ^[0-9]+$ && "$previous" =~ ^[0-9]+$ && "$elapsed" -gt 0 ]] || {
    printf '-'
    return
  }

  delta=$((current - previous))
  [[ "$delta" -ge 0 ]] || {
    printf '-'
    return
  }

  awk -v delta="$delta" -v elapsed="$elapsed" 'BEGIN { printf "%.1f", delta / elapsed }'
}

leaf_summary() {
  local port="$1"
  local body

  if ! body="$(curl -fsS --max-time 1 "http://localhost:$port/leafz?subs=1" 2>&1)"; then
    printf 'leafz unavailable'
    return
  fi

  jq -r '
    if ((.leafs // []) | length) == 0 then
      "-"
    else
      [
        (.leafs // [] | sort_by(.name // ""))[]
        | "\(.name // "unknown"):\(.subscriptions // 0)/\((.subscriptions_list // []) | length)"
      ] | join(" ")
    end
  ' <<<"$body"
}

collect_rows() {
  local entry name port body
  local server_name cluster_name connections subscriptions in_msgs out_msgs
  local i elapsed prev_in prev_out

  row_names=()
  row_endpoints=()
  row_servers=()
  row_clusters=()
  row_connections=()
  row_subscriptions=()
  row_in_msgs=()
  row_out_msgs=()
  row_in_rates=()
  row_out_rates=()
  row_leafs=()

  for entry in "${servers[@]}"; do
    i="${#row_names[@]}"
    name="${entry%%:*}"
    port="${entry##*:}"

    row_names+=("$name")
    row_endpoints+=("localhost:$port")

    if ! body="$(curl -fsS --max-time 1 "http://localhost:$port/varz" 2>&1)"; then
      row_servers+=("unavailable")
      row_clusters+=("-")
      row_connections+=("-")
      row_subscriptions+=("-")
      row_in_msgs+=("-")
      row_out_msgs+=("-")
      row_in_rates+=("-")
      row_out_rates+=("-")
      row_leafs+=("varz unavailable")
      continue
    fi

    server_name="$(jq -r '.server_name // "-"' <<<"$body")"
    cluster_name="$(jq -r 'if (.cluster | type) == "object" then (.cluster.name // "-") elif (.cluster // null) == null then "-" else (.cluster | tostring) end' <<<"$body")"
    connections="$(jq -r '.connections // "-"' <<<"$body")"
    subscriptions="$(jq -r '.subscriptions // "-"' <<<"$body")"
    in_msgs="$(jq -r '.in_msgs // 0' <<<"$body")"
    out_msgs="$(jq -r '.out_msgs // 0' <<<"$body")"

    row_servers+=("$server_name")
    row_clusters+=("$cluster_name")
    row_connections+=("$connections")
    row_subscriptions+=("$subscriptions")
    row_in_msgs+=("$in_msgs")
    row_out_msgs+=("$out_msgs")

    if [[ "$PREV_TIME" -gt 0 ]]; then
      elapsed=$((SNAPSHOT_TIME - PREV_TIME))
      prev_in="${prev_in_msgs[$i]:-}"
      prev_out="${prev_out_msgs[$i]:-}"
      row_in_rates+=("$(msg_rate "$in_msgs" "$prev_in" "$elapsed")")
      row_out_rates+=("$(msg_rate "$out_msgs" "$prev_out" "$elapsed")")
    else
      row_in_rates+=("-")
      row_out_rates+=("-")
    fi

    row_leafs+=("$(leaf_summary "$port")")
  done
}

measure_table() {
  local i

  NAME_W=4
  ENDPOINT_W=8
  SERVER_W=6
  CLUSTER_W=7
  CONN_W=4
  SUBS_W=4
  IN_RATE_W=4
  OUT_RATE_W=5

  for i in "${!row_names[@]}"; do
    [[ ${#row_names[$i]} -le "$NAME_W" ]] || NAME_W="${#row_names[$i]}"
    [[ ${#row_endpoints[$i]} -le "$ENDPOINT_W" ]] || ENDPOINT_W="${#row_endpoints[$i]}"
    [[ ${#row_servers[$i]} -le "$SERVER_W" ]] || SERVER_W="${#row_servers[$i]}"
    [[ ${#row_clusters[$i]} -le "$CLUSTER_W" ]] || CLUSTER_W="${#row_clusters[$i]}"
    [[ ${#row_connections[$i]} -le "$CONN_W" ]] || CONN_W="${#row_connections[$i]}"
    [[ ${#row_subscriptions[$i]} -le "$SUBS_W" ]] || SUBS_W="${#row_subscriptions[$i]}"
    [[ ${#row_in_rates[$i]} -le "$IN_RATE_W" ]] || IN_RATE_W="${#row_in_rates[$i]}"
    [[ ${#row_out_rates[$i]} -le "$OUT_RATE_W" ]] || OUT_RATE_W="${#row_out_rates[$i]}"
  done
}

print_table_row() {
  local name="$1"
  local endpoint="$2"
  local server="$3"
  local cluster="$4"
  local connections="$5"
  local subscriptions="$6"
  local in_rate="$7"
  local out_rate="$8"
  local leaf="$9"

  printf '%-*s %-*s %-*s %-*s %*s %*s %*s %*s %s' \
    "$NAME_W" "$name" \
    "$ENDPOINT_W" "$endpoint" \
    "$SERVER_W" "$server" \
    "$CLUSTER_W" "$cluster" \
    "$CONN_W" "$connections" \
    "$SUBS_W" "$subscriptions" \
    "$IN_RATE_W" "$in_rate" \
    "$OUT_RATE_W" "$out_rate" \
    "$leaf"
}

print_server_row() {
  local i="$1"

  print_table_row \
    "${row_names[$i]}" \
    "${row_endpoints[$i]}" \
    "${row_servers[$i]}" \
    "${row_clusters[$i]}" \
    "${row_connections[$i]}" \
    "${row_subscriptions[$i]}" \
    "${row_in_rates[$i]}" \
    "${row_out_rates[$i]}" \
    "${row_leafs[$i]}"
}

print_snapshot() {
  local i

  if [[ "$ONCE" == "0" && -t 1 && "$LINES_DRAWN" -gt 0 ]]; then
    printf '\033[%sA' "$LINES_DRAWN"
  fi

  LINES_DRAWN=0

  SNAPSHOT_TIME="$(date +%s)"
  collect_rows
  measure_table

  print_line "NATS monitor snapshot  $(date '+%Y-%m-%d %H:%M:%S')"
  [[ "$ONCE" == "1" ]] || print_line "Refreshing every ${INTERVAL}s. Press Ctrl-C to stop."
  print_line ""
  print_line "$(print_table_row "NAME" "ENDPOINT" "SERVER" "CLUSTER" "CONN" "SUBS" "IN/s" "OUT/s" "LEAF INTEREST")"
  print_line "$(print_table_row "$(fill "$NAME_W")" "$(fill "$ENDPOINT_W")" "$(fill "$SERVER_W")" "$(fill "$CLUSTER_W")" "$(fill "$CONN_W")" "$(fill "$SUBS_W")" "$(fill "$IN_RATE_W")" "$(fill "$OUT_RATE_W")" "-------------")"

  for i in "${!row_names[@]}"; do
    print_line "$(print_server_row "$i")"
  done

  PREV_TIME="$SNAPSHOT_TIME"
  prev_in_msgs=("${row_in_msgs[@]}")
  prev_out_msgs=("${row_out_msgs[@]}")
}

if [[ "$ONCE" == "0" && -t 1 ]]; then
  trap cleanup EXIT
  printf '\033[?25l'
fi

while true; do
  print_snapshot

  [[ "$ONCE" == "0" ]] || break
  sleep "$INTERVAL"
done
