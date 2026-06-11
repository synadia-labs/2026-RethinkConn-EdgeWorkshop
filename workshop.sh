#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./workshop.sh setup
  ./workshop.sh list
  ./workshop.sh start <lab> [config-dir] [--trace]
  ./workshop.sh stop [lab]
  ./workshop.sh restart <lab> [config-dir] [--trace]
  ./workshop.sh status [lab]
  ./workshop.sh logs [lab] [server]
  ./workshop.sh clean [lab|all]

Examples:
  ./workshop.sh setup
  ./workshop.sh start 1
  ./workshop.sh start 6 --trace
  ./workshop.sh start 20 open
  ./workshop.sh start lab1
  ./workshop.sh logs
  ./workshop.sh logs hub
  ./workshop.sh stop

Lab inputs may be a number, a labN id, or a formal directory name such as
"Lab 01 - Same Cluster Name".

Only one local lab runner is tracked as current. Starting a different lab while
one is running prompts to stop the current lab first.
EOF
}

root_dir() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s\n' "$script_dir"
}

ROOT="$(root_dir)"
STATE_DIR="$ROOT/.workshop"
RUNS_DIR="$STATE_DIR/runs"
BIN_DIR="$STATE_DIR/bin"
CURRENT_FILE="$STATE_DIR/current-run"

export PATH="$BIN_DIR:$PATH"

is_running() {
  local pid="${1:-}"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

resolve_tool() {
  local name="$1"

  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return
  fi

  if [[ -x "$BIN_DIR/$name" ]]; then
    printf '%s/%s\n' "$BIN_DIR" "$name"
    return
  fi

  return 1
}

download_platform() {
  local os arch platform jq_platform

  case "$(uname -s)" in
    Darwin)
      platform="darwin"
      jq_platform="macos"
      ;;
    Linux)
      platform="linux"
      jq_platform="linux"
      ;;
    *)
      printf 'unsupported OS for automatic downloads: %s\n' "$(uname -s)" >&2
      return 1
      ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64)
      arch="amd64"
      ;;
    arm64|aarch64)
      arch="arm64"
      ;;
    *)
      printf 'unsupported architecture for automatic downloads: %s\n' "$(uname -m)" >&2
      return 1
      ;;
  esac

  DOWNLOAD_PLATFORM="$platform"
  DOWNLOAD_JQ_PLATFORM="$jq_platform"
  DOWNLOAD_ARCH="$arch"
}

latest_asset_url() {
  local repo="$1"
  local pattern="$2"
  local url

  command -v curl >/dev/null 2>&1 || {
    printf 'curl is required for automatic downloads\n' >&2
    return 1
  }

  url="$(
    {
      curl -fsSL "https://api.github.com/repos/$repo/releases/latest" |
        sed -n 's/.*"browser_download_url": "\(.*\)".*/\1/p' |
        grep -E "$pattern" |
        head -n 1
    } || true
  )"

  [[ -n "$url" ]] || {
    printf 'could not find a release asset for %s matching %s\n' "$repo" "$pattern" >&2
    return 1
  }

  printf '%s\n' "$url"
}

install_archive_tool() {
  local name="$1"
  local repo="$2"
  local pattern="$3"
  local url tmp archive found target

  mkdir -p "$BIN_DIR"
  url="$(latest_asset_url "$repo" "$pattern")"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/workshop-download.XXXXXX")"
  archive="$tmp/asset"
  target="$BIN_DIR/$name"

  printf 'downloading %s\n' "$url"
  curl -fsSL -o "$archive" "$url"

  case "$url" in
    *.zip)
      command -v unzip >/dev/null 2>&1 || {
        printf 'unzip is required to extract %s\n' "$url" >&2
        rm -rf "$tmp"
        return 1
      }
      unzip -q "$archive" -d "$tmp"
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "$archive" -C "$tmp"
      ;;
    *)
      printf 'unsupported archive type: %s\n' "$url" >&2
      rm -rf "$tmp"
      return 1
      ;;
  esac

  found="$(find "$tmp" -type f -name "$name" -perm -111 | head -n 1)"
  if [[ -z "$found" ]]; then
    found="$(find "$tmp" -type f -name "$name" | head -n 1)"
  fi

  [[ -n "$found" ]] || {
    printf 'could not find %s in downloaded archive\n' "$name" >&2
    rm -rf "$tmp"
    return 1
  }

  cp "$found" "$target"
  chmod 0755 "$target"
  rm -rf "$tmp"
  SETUP_INSTALLED=1
  printf 'installed %s\n' "$target"
}

install_direct_tool() {
  local name="$1"
  local repo="$2"
  local pattern="$3"
  local url target

  mkdir -p "$BIN_DIR"
  url="$(latest_asset_url "$repo" "$pattern")"
  target="$BIN_DIR/$name"

  printf 'downloading %s\n' "$url"
  curl -fsSL -o "$target" "$url"
  chmod 0755 "$target"
  SETUP_INSTALLED=1
  printf 'installed %s\n' "$target"
}

prompt_install() {
  local label="$1"
  local answer

  if [[ ! -t 0 ]]; then
    printf '%s is missing; rerun setup interactively to download it\n' "$label" >&2
    return 1
  fi

  printf '%s is missing. Download it to %s? [y/N] ' "$label" "$BIN_DIR"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

setup_requirement() {
  local command_name="$1"
  local label="$2"
  local installer="$3"
  local repo="$4"
  local pattern="$5"
  local path

  if path="$(resolve_tool "$command_name")"; then
    printf '%-12s found: %s\n' "$label" "$path"
    return 0
  fi

  if ! prompt_install "$label"; then
    printf '%-12s missing\n' "$label"
    return 1
  fi

  case "$installer" in
    archive) install_archive_tool "$command_name" "$repo" "$pattern" ;;
    direct) install_direct_tool "$command_name" "$repo" "$pattern" ;;
    *)
      printf 'unknown installer type: %s\n' "$installer" >&2
      return 1
      ;;
  esac
}

setup_tools() {
  local status=0 nats_cli jq_bin

  SETUP_INSTALLED=0
  download_platform
  mkdir -p "$BIN_DIR"
  printf 'local bin: %s\n' "$BIN_DIR"

  setup_requirement \
    nats-server \
    nats-server \
    archive \
    nats-io/nats-server \
    "/nats-server-v[^/]*-${DOWNLOAD_PLATFORM}-${DOWNLOAD_ARCH}\\.(zip|tar\\.gz)$" || status=1

  setup_requirement \
    nats \
    nats-cli \
    archive \
    nats-io/natscli \
    "/nats-[0-9][^/]*-${DOWNLOAD_PLATFORM}-${DOWNLOAD_ARCH}\\.(zip|tar\\.gz)$" || status=1

  setup_requirement \
    jq \
    jq \
    direct \
    jqlang/jq \
    "/jq-${DOWNLOAD_JQ_PLATFORM}-${DOWNLOAD_ARCH}$" || status=1

  if [[ "$status" -eq 0 ]]; then
    nats_cli="$(resolve_tool nats)"
    jq_bin="$(resolve_tool jq)"
    create_all_contexts "$nats_cli" "$jq_bin" || status=1
  fi

  if [[ "$status" -eq 0 ]]; then
    printf 'setup complete\n'
  else
    printf 'setup incomplete; resolve the errors above and rerun setup\n' >&2
  fi

  return "$status"
}

lab_number_from_name() {
  local base="${1##*/}"

  if [[ "$base" =~ ^[Ll][Aa][Bb][[:space:]]+0*([0-9]+)[[:space:]]+- ]]; then
    printf '%s\n' "$((10#${BASH_REMATCH[1]}))"
    return
  fi

  return 1
}

find_lab_by_number() {
  local number="$1"
  local dir base dir_number
  local matches=()

  shopt -s nullglob
  for dir in "$ROOT"/Lab\ *; do
    [[ -d "$dir" ]] || continue
    base="${dir##*/}"
    if dir_number="$(lab_number_from_name "$base")" && [[ "$dir_number" -eq "$number" ]]; then
      matches+=("$base")
    fi
  done
  shopt -u nullglob

  case "${#matches[@]}" in
    0)
      printf 'lab directory not found for lab %02d\n' "$number" >&2
      return 1
      ;;
    1)
      printf '%s\n' "${matches[0]}"
      ;;
    *)
      printf 'lab number %02d is ambiguous; use the full directory name:\n' "$number" >&2
      printf '  %s\n' "${matches[@]}" >&2
      return 1
      ;;
  esac
}

normalize_lab() {
  local input="$1"
  local base number

  input="${input%/}"
  base="${input##*/}"

  if [[ -d "$ROOT/$base" ]] && lab_number_from_name "$base" >/dev/null; then
    printf '%s\n' "$base"
    return
  fi

  if [[ "$base" =~ ^[0-9]+$ ]]; then
    number="$((10#$base))"
    find_lab_by_number "$number"
    return
  fi

  if [[ "$base" =~ ^[Ll][Aa][Bb]([0-9]+)$ ]]; then
    number="$((10#${BASH_REMATCH[1]}))"
    find_lab_by_number "$number"
    return
  fi

  if [[ "$base" =~ ^[Ll][Aa][Bb][[:space:]]+0*([0-9]+)[[:space:]]+- ]]; then
    printf 'lab directory not found: %s\n' "$base" >&2
    return 1
  fi

  printf 'unknown lab input: %s\n' "$input" >&2
  return 1
}

lab_title() {
  local title

  if title="$(normalize_lab "$1" 2>/dev/null)"; then
    printf '%s\n' "$title"
    return
  fi

  printf '%s\n' "$1"
}

lab_dir() {
  local lab="$1"
  local title

  title="$(normalize_lab "$lab")" || return 1
  printf '%s/%s\n' "$ROOT" "$title"
}

validate_config_dir_name() {
  local config_dir="$1"

  [[ -n "$config_dir" ]] || return 0
  case "$config_dir" in
    /*|.*|*/*|*..*)
      printf 'config-dir must be a direct child directory name inside the lab: %s\n' "$config_dir" >&2
      return 1
      ;;
  esac
}

lab_config_dir() {
  local lab="$1"
  local config_dir="${2:-}"
  local dir

  dir="$(lab_dir "$lab")" || return 1
  if [[ -n "$config_dir" ]]; then
    validate_config_dir_name "$config_dir" || return 1
    dir="$dir/$config_dir"
  fi

  printf '%s\n' "$dir"
}

target_title() {
  local lab="$1"
  local config_dir="${2:-}"

  if [[ -n "$config_dir" ]]; then
    printf '%s / %s\n' "$(lab_title "$lab")" "$config_dir"
  else
    lab_title "$lab"
  fi
}

known_labs() {
  local dir base

  shopt -s nullglob
  for dir in "$ROOT"/Lab\ *; do
    [[ -d "$dir" ]] || continue
    base="${dir##*/}"
    lab_number_from_name "$base" >/dev/null || continue
    printf '%s\n' "$base"
  done
  shopt -u nullglob
}

list_labs() {
  local lab number
  while IFS= read -r lab; do
    number="$(lab_number_from_name "$lab")"
    printf '%02d  %s\n' "$number" "$lab"
  done < <(known_labs)
}

validate_lab() {
  local lab="$1"
  local dir

  dir="$(lab_dir "$lab")" || return 1

  [[ -d "$dir" ]] || {
    printf 'lab directory not found: %s\n' "$dir" >&2
    return 1
  }
}

server_specs() {
  local lab="$1"
  local config_dir="${2:-}"
  local dir
  dir="$(lab_config_dir "$lab" "$config_dir")" || return 1

  if [[ -f "$dir/hub.conf" ]]; then
    [[ -f "$dir/hub.conf" ]] && printf '%s|%s|%s\n' hub "$dir" hub.conf
    [[ -f "$dir/l1.conf" ]] && printf '%s|%s|%s\n' l1 "$dir" l1.conf
    [[ -f "$dir/l2.conf" ]] && printf '%s|%s|%s\n' l2 "$dir" l2.conf
    [[ -f "$dir/l3.conf" ]] && printf '%s|%s|%s\n' l3 "$dir" l3.conf
    return
  fi

  if [[ -f "$dir/server.conf" ]]; then
    printf '%s|%s|%s\n' nats "$dir" server.conf
    return
  fi
}

context_specs() {
  cat <<'EOF'
hub|nats://localhost:4222|a|x|Workshop hub app user
l1|nats://localhost:4232|e|x|Workshop leaf 1 app user
l2|nats://localhost:4242|e|x|Workshop leaf 2 app user
l3|nats://localhost:4252|e|x|Workshop leaf 3 app user
syshub|nats://localhost:4222|s|x|Workshop hub SYS user
sysl1|nats://localhost:4232|s|x|Workshop leaf 1 SYS user
sysl2|nats://localhost:4242|s|x|Workshop leaf 2 SYS user
sysl3|nats://localhost:4252|s|x|Workshop leaf 3 SYS user
EOF
}

context_exists() {
  local nats_cli="$1"
  local jq_bin="$2"
  local name="$3"

  "$nats_cli" context ls -j 2>/dev/null |
    "$jq_bin" -e --arg name "$name" '(. // [])[] | select(.name == $name)' >/dev/null 2>&1
}

context_matches_spec() {
  local nats_cli="$1"
  local jq_bin="$2"
  local name="$3"
  local url="$4"
  local user="$5"
  local password="$6"
  local description="$7"

  "$nats_cli" context ls -j 2>/dev/null |
    "$jq_bin" -e \
      --arg name "$name" \
      --arg url "$url" \
      --arg user "$user" \
      --arg password "$password" \
      --arg description "$description" \
      '(. // [])[] | select(.name == $name and .url == $url and .user == $user and .password == $password and .description == $description)' \
      >/dev/null 2>&1
}

context_summary() {
  local nats_cli="$1"
  local jq_bin="$2"
  local name="$3"

  "$nats_cli" context ls -j 2>/dev/null |
    "$jq_bin" -r --arg name "$name" \
      '(. // [])[] | select(.name == $name) | "\(.name) -> \(.url) user=\(.user // "") description=\(.description // "")"' \
      2>/dev/null
}

confirm_context_overwrite() {
  local nats_cli="$1"
  local jq_bin="$2"
  local conflicts=()
  local name url user password description answer

  while IFS='|' read -r name url user password description; do
    if context_exists "$nats_cli" "$jq_bin" "$name" &&
      ! context_matches_spec "$nats_cli" "$jq_bin" "$name" "$url" "$user" "$password" "$description"; then
      conflicts+=("$(context_summary "$nats_cli" "$jq_bin" "$name")")
    fi
  done < <(context_specs)

  if [[ ${#conflicts[@]} -eq 0 ]]; then
    return 0
  fi

  printf 'NATS context name conflicts found:\n' >&2
  printf '  %s\n' "${conflicts[@]}" >&2

  if [[ ! -t 0 ]]; then
    printf 'refusing to overwrite existing NATS contexts without interactive confirmation\n' >&2
    return 1
  fi

  printf 'Overwrite these contexts with workshop local settings? [y/N] '
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

create_all_contexts() {
  local nats_cli="$1"
  local jq_bin="$2"
  local name url user password description status=0

  confirm_context_overwrite "$nats_cli" "$jq_bin" || return 1

  printf 'creating NATS contexts\n'
  while IFS='|' read -r name url user password description; do
    if "$nats_cli" --no-context --server "$url" --user "$user" --password "$password" \
      context add "$name" --description "$description" >/dev/null; then
      printf '%-8s %s\n' "$name" "$url"
    else
      status=1
    fi
  done < <(context_specs)

  return "$status"
}

remove_all_contexts() {
  local nats_cli="$1"
  local jq_bin="$2"
  local name url user password description

  while IFS='|' read -r name url user password description; do
    if context_matches_spec "$nats_cli" "$jq_bin" "$name" "$url" "$user" "$password" "$description" &&
      "$nats_cli" context rm -f "$name" >/dev/null 2>&1; then
      printf '%-8s removed\n' "$name"
    elif context_exists "$nats_cli" "$jq_bin" "$name"; then
      printf '%-8s skipped; context does not match workshop settings\n' "$name"
    fi
  done < <(context_specs)
}

remove_contexts_if_possible() {
  local nats_cli jq_bin

  if ! nats_cli="$(resolve_tool nats)"; then
    printf 'nats CLI not found; skipping context cleanup\n' >&2
    return 0
  fi

  if ! jq_bin="$(resolve_tool jq)"; then
    printf 'jq not found; skipping context cleanup\n' >&2
    return 0
  fi

  remove_all_contexts "$nats_cli" "$jq_bin"
}

lab_run_key() {
  local lab="$1"
  local config_dir="${2:-}"
  local number
  local key

  if number="$(lab_number_from_name "$lab" 2>/dev/null)"; then
    key="lab$number"
  elif [[ "$lab" =~ ^[Ll][Aa][Bb]([0-9]+)$ ]]; then
    key="lab$((10#${BASH_REMATCH[1]}))"
  else
    key="$lab"
  fi

  if [[ -n "$config_dir" ]]; then
    key="$key-${config_dir//[^A-Za-z0-9._-]/_}"
  fi

  printf '%s\n' "$key"
}

run_dir() {
  local lab="$1"
  local config_dir="${2:-}"
  printf '%s/%s\n' "$RUNS_DIR" "$(lab_run_key "$lab" "$config_dir")"
}

read_current() {
  local first second third
  local canonical

  [[ -f "$CURRENT_FILE" ]] || return 1
  IFS=$'\t' read -r first second third < "$CURRENT_FILE"
  [[ -n "${first:-}" ]] || return 1

  if canonical="$(normalize_lab "$first" 2>/dev/null)"; then
    CURRENT_LAB="$canonical"
  else
    CURRENT_LAB="$first"
  fi

  if [[ -n "${third:-}" ]]; then
    CURRENT_CONFIG_DIR="${second:-}"
    CURRENT_RUN_DIR="$third"
  else
    CURRENT_CONFIG_DIR=""
    CURRENT_RUN_DIR="$second"
  fi

  [[ -n "${CURRENT_RUN_DIR:-}" ]]
}

write_current() {
  local lab="$1"
  local config_dir="${2:-}"
  local dir="${3:-}"

  if [[ -z "$dir" ]]; then
    dir="$config_dir"
    config_dir=""
  fi

  mkdir -p "$STATE_DIR"
  printf '%s\t%s\t%s\n' "$lab" "$config_dir" "$dir" > "$CURRENT_FILE"
}

clear_current_if() {
  local lab="$1"
  local config_dir="${2:-}"
  if read_current && [[ "$CURRENT_LAB" == "$lab" && ( -z "$config_dir" || "${CURRENT_CONFIG_DIR:-}" == "$config_dir" ) ]]; then
    rm -f "$CURRENT_FILE"
  fi
}

run_dir_has_processes() {
  local dir="$1"
  local pid_file pid
  shopt -s nullglob
  for pid_file in "$dir"/*.pid; do
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    if is_running "$pid"; then
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob
  return 1
}

current_running() {
  read_current && run_dir_has_processes "$CURRENT_RUN_DIR"
}

target_from_args_or_current() {
  local lab="${1:-}"

  if [[ -z "$lab" ]]; then
    if ! read_current; then
      printf 'no current lab; specify a lab or "all"\n' >&2
      return 1
    fi
    TARGET_LAB="$CURRENT_LAB"
    TARGET_CONFIG_DIR="${CURRENT_CONFIG_DIR:-}"
    return
  fi

  TARGET_LAB="$(normalize_lab "$lab")"
  validate_lab "$TARGET_LAB"
  TARGET_CONFIG_DIR=""

  if read_current && [[ "$CURRENT_LAB" == "$TARGET_LAB" ]]; then
    TARGET_CONFIG_DIR="${CURRENT_CONFIG_DIR:-}"
  fi
}

target_from_logs_args() {
  local first="${1:-}"
  local second="${2:-}"

  LOG_SERVER=""
  if [[ -z "$first" ]]; then
    target_from_args_or_current
    return
  fi

  if [[ "$first" =~ ^(hub|l1|l2|l3|l3gate|nats)$ ]] && read_current; then
    TARGET_LAB="$CURRENT_LAB"
    TARGET_CONFIG_DIR="${CURRENT_CONFIG_DIR:-}"
    LOG_SERVER="$first"
    return
  fi

  target_from_args_or_current "$first"
  LOG_SERVER="${second:-}"
}

target_from_start_args() {
  local lab=""
  local config_dir=""

  START_TRACE=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --trace)
        START_TRACE=1
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf 'unknown start option: %s\n' "$1" >&2
        return 1
        ;;
      *)
        if [[ -z "$lab" ]]; then
          lab="$1"
        elif [[ -z "$config_dir" ]]; then
          config_dir="$1"
        else
          printf 'only one config directory may be specified\n' >&2
          return 1
        fi
        ;;
    esac
    shift
  done

  while [[ $# -gt 0 ]]; do
    if [[ -z "$lab" ]]; then
      lab="$1"
    elif [[ -z "$config_dir" ]]; then
      config_dir="$1"
    else
      printf 'only one config directory may be specified\n' >&2
      return 1
    fi
    shift
  done

  if [[ -z "$lab" ]]; then
    printf 'start requires a lab\n' >&2
    return 1
  fi

  target_from_args_or_current "$lab"
  START_CONFIG_DIR="$config_dir"
  validate_config_dir_name "$START_CONFIG_DIR"
}

require_configs() {
  local lab="$1"
  local config_dir="${2:-}"
  local config_abs name workdir conf found=0

  config_abs="$(lab_config_dir "$lab" "$config_dir")" || return 1
  [[ -d "$config_abs" ]] || {
    printf 'config directory not found: %s\n' "$config_abs" >&2
    return 1
  }

  while IFS='|' read -r name workdir conf; do
    found=1
    [[ -f "$workdir/$conf" ]] || {
      printf 'missing config for %s: %s\n' "$name" "$workdir/$conf" >&2
      return 1
    }
  done < <(server_specs "$lab" "$config_dir")

  [[ "$found" -eq 1 ]] || {
    printf 'no runnable NATS config found for %s\n' "$(target_title "$lab" "$config_dir")" >&2
    return 1
  }
}

stop_run_dir() {
  local lab="$1"
  local dir="$2"
  local config_dir="${3:-}"
  local name workdir conf pid_file pid

  while IFS='|' read -r name workdir conf; do
    pid_file="$dir/$name.pid"
    if [[ ! -f "$pid_file" ]]; then
      printf '%-5s not running\n' "$name"
      continue
    fi

    pid="$(cat "$pid_file")"
    if is_running "$pid"; then
      kill "$pid"
      printf '%-5s stopping pid=%s\n' "$name" "$pid"
    else
      printf '%-5s stale pid=%s\n' "$name" "$pid"
    fi
    rm -f "$pid_file"
  done < <(server_specs "$lab" "$config_dir")
}

maybe_stop_current_for() {
  local lab="$1"
  local config_dir="${2:-}"

  if ! current_running; then
    rm -f "$CURRENT_FILE"
    return
  fi

  if [[ "$CURRENT_LAB" == "$lab" && "${CURRENT_CONFIG_DIR:-}" == "$config_dir" ]]; then
    return
  fi

  printf 'Current lab is running: %s\n' "$(target_title "$CURRENT_LAB" "${CURRENT_CONFIG_DIR:-}")"
  printf 'Stop it and start %s? [y/N] ' "$(target_title "$lab" "$config_dir")"

  if [[ ! -t 0 ]]; then
    printf '\nrefusing to replace current lab without interactive confirmation\n' >&2
    return 1
  fi

  local answer
  read -r answer
  case "$answer" in
    y|Y|yes|YES)
      stop_run_dir "$CURRENT_LAB" "$CURRENT_RUN_DIR" "${CURRENT_CONFIG_DIR:-}"
      rm -f "$CURRENT_FILE"
      ;;
    *)
      printf 'leaving current lab running\n'
      return 1
      ;;
  esac
}

start_lab() {
  local lab="$1"
  local trace="${2:-0}"
  local config_dir="${3:-}"
  local dir name workdir conf pid_file log_file pid nats_server started=()

  validate_lab "$lab"
  require_configs "$lab" "$config_dir"
  nats_server="$(resolve_tool nats-server)" || {
    printf 'nats-server not found; run ./workshop.sh setup\n' >&2
    return 1
  }

  maybe_stop_current_for "$lab" "$config_dir"

  dir="$(run_dir "$lab" "$config_dir")"
  mkdir -p "$dir"

  if run_dir_has_processes "$dir"; then
    printf '%s is already running\n' "$(target_title "$lab" "$config_dir")"
    write_current "$lab" "$config_dir" "$dir"
    status_lab "$lab" "$config_dir"
    return
  fi

  if [[ "$trace" -eq 1 ]]; then
    printf 'nats-server trace enabled\n'
  fi

  while IFS='|' read -r name workdir conf; do
    pid_file="$dir/$name.pid"
    log_file="$dir/$name.log"

    (
      cd "$workdir"
      if [[ "$trace" -eq 1 ]]; then
        exec "$nats_server" -c "$conf" --trace
      else
        exec "$nats_server" -c "$conf"
      fi
    ) >"$log_file" 2>&1 &
    pid="$!"
    printf '%s\n' "$pid" > "$pid_file"
    sleep 0.3

    if ! is_running "$pid"; then
      printf '%s exited while starting; last log lines:\n' "$name" >&2
      tail -n 20 "$log_file" >&2 || true
      stop_run_dir "$lab" "$dir" "$config_dir" || true
      return 1
    fi

    started+=("$name")
    printf '%-5s started pid=%s log=%s\n' "$name" "$pid" "$log_file"
  done < <(server_specs "$lab" "$config_dir")

  write_current "$lab" "$config_dir" "$dir"
  printf 'current lab: %s\n' "$(target_title "$lab" "$config_dir")"
  status_lab "$lab" "$config_dir"
}

stop_lab() {
  local lab="$1"
  local config_dir="${2:-}"
  local dir

  validate_lab "$lab"
  dir="$(run_dir "$lab" "$config_dir")"
  stop_run_dir "$lab" "$dir" "$config_dir"
  clear_current_if "$lab" "$config_dir"
}

status_lab() {
  local lab="$1"
  local config_dir="${2:-}"
  local dir name workdir conf pid_file pid found=0

  validate_lab "$lab"
  dir="$(run_dir "$lab" "$config_dir")"
  printf '== %s ==\n' "$(target_title "$lab" "$config_dir")"

  while IFS='|' read -r name workdir conf; do
    found=1
    pid_file="$dir/$name.pid"
    if [[ -f "$pid_file" ]]; then
      pid="$(cat "$pid_file")"
      if is_running "$pid"; then
        printf '%-5s running pid=%s\n' "$name" "$pid"
      else
        printf '%-5s stopped stale-pid=%s\n' "$name" "$pid"
      fi
    else
      printf '%-5s stopped\n' "$name"
    fi
  done < <(server_specs "$lab" "$config_dir")

  if [[ "$found" -eq 0 ]]; then
    printf 'no runnable NATS config found\n'
  fi
}

logs_lab() {
  local lab="$1"
  local server="${2:-}"
  local config_dir="${3:-}"
  local dir

  validate_lab "$lab"
  dir="$(run_dir "$lab" "$config_dir")"

  printf '== %s logs ==\n' "$(target_title "$lab" "$config_dir")"
  if [[ -n "$server" ]]; then
    [[ -f "$dir/$server.log" ]] || {
      printf 'log not found: %s\n' "$dir/$server.log" >&2
      return 1
    }
    tail -f "$dir/$server.log"
    return
  fi

  shopt -s nullglob
  local logs=("$dir"/*.log)
  shopt -u nullglob
  if [[ ${#logs[@]} -eq 0 ]]; then
    printf 'no logs found for %s\n' "$(target_title "$lab" "$config_dir")" >&2
    return 1
  fi
  tail -f "${logs[@]}"
}

clean_lab_runtime() {
  local lab="$1"
  local config_dir="${2:-}"
  local dir

  validate_lab "$lab"
  dir="$(run_dir "$lab" "$config_dir")"
  stop_run_dir "$lab" "$dir" "$config_dir"
  rm -rf "$dir" "$(lab_dir "$lab")/js"
  clear_current_if "$lab" "$config_dir"
  printf 'cleaned %s\n' "$(target_title "$lab" "$config_dir")"
}

clean_lab() {
  local lab="$1"
  local config_dir="${2:-}"

  clean_lab_runtime "$lab" "$config_dir"
  remove_contexts_if_possible
}

clean_all() {
  local lab

  if current_running; then
    stop_run_dir "$CURRENT_LAB" "$CURRENT_RUN_DIR" "${CURRENT_CONFIG_DIR:-}"
  fi

  while IFS= read -r lab; do
    clean_lab_runtime "$lab"
  done < <(known_labs)
  remove_contexts_if_possible
  rm -f "$CURRENT_FILE"
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 2
  fi

  local action="$1"
  shift || true

  case "$action" in
    -h|--help|help)
      usage
      ;;
    setup)
      [[ $# -eq 0 ]] || {
        usage
        exit 2
      }
      setup_tools
      ;;
    list)
      [[ $# -eq 0 ]] || {
        usage
        exit 2
      }
      list_labs
      ;;
    start)
      [[ $# -ge 1 ]] || {
        usage
        exit 2
      }
      target_from_start_args "$@"
      start_lab "$TARGET_LAB" "$START_TRACE" "$START_CONFIG_DIR"
      ;;
    restart)
      [[ $# -ge 1 ]] || {
        usage
        exit 2
      }
      target_from_start_args "$@"
      stop_lab "$TARGET_LAB" "$START_CONFIG_DIR"
      start_lab "$TARGET_LAB" "$START_TRACE" "$START_CONFIG_DIR"
      ;;
    stop)
      [[ $# -le 1 ]] || {
        usage
        exit 2
      }
      target_from_args_or_current "${1:-}"
      stop_lab "$TARGET_LAB" "$TARGET_CONFIG_DIR"
      ;;
    status)
      [[ $# -le 1 ]] || {
        usage
        exit 2
      }
      target_from_args_or_current "${1:-}"
      status_lab "$TARGET_LAB" "$TARGET_CONFIG_DIR"
      ;;
    logs)
      [[ $# -le 2 ]] || {
        usage
        exit 2
      }
      target_from_logs_args "${1:-}" "${2:-}"
      logs_lab "$TARGET_LAB" "$LOG_SERVER" "$TARGET_CONFIG_DIR"
      ;;
    clean)
      [[ $# -le 1 ]] || {
        usage
        exit 2
      }
      if [[ "${1:-}" == "all" ]]; then
        clean_all
      else
        target_from_args_or_current "${1:-}"
        clean_lab "$TARGET_LAB" "$TARGET_CONFIG_DIR"
      fi
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
