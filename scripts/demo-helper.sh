#!/usr/bin/env bash

DEMO_PIDS=()
DEMO_LOGS=()
DEMO_LOG_DIR=""
DEMO_TAIL_PID=""

demo_use_local_bin() {
  local root="$1"
  export PATH="$root/.workshop/bin:$PATH"
}

demo_require_command() {
  local command_name="$1"
  local hint="${2:-}"

  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi

  if [[ -n "$hint" ]]; then
    printf '%s not found; %s\n' "$command_name" "$hint" >&2
  else
    printf '%s not found\n' "$command_name" >&2
  fi
  return 1
}

demo_color_enabled() {
  case "${DEMO_COLOR:-auto}" in
    force) return 0 ;;
    never|0|no|false) return 1 ;;
  esac

  [[ -z "${NO_COLOR:-}" ]] || return 1
  case "${DEMO_COLOR:-auto}" in
    always|1|yes|true) return 0 ;;
  esac

  [[ -t 1 ]] || [[ -n "${COLORTERM:-}" ]] || [[ "${TERM:-}" != "" && "${TERM:-}" != "dumb" ]]
}

demo_color() {
  local label="$1"

  if ! demo_color_enabled; then
    printf ''
    return
  fi

  case "$label" in
    hub*) printf '%s' $'\033[36m' ;;
    l1*) printf '%s' $'\033[32m' ;;
    l2*) printf '%s' $'\033[33m' ;;
    l3*) printf '%s' $'\033[35m' ;;
    *) printf '%s' $'\033[37m' ;;
  esac
}

demo_reset() {
  if demo_color_enabled; then
    printf '%s' $'\033[0m'
  fi
}

demo_prefix_output() {
  local label="$1"
  local color="$2"
  local reset="$3"
  local color_output="${4:-0}"
  local line

  while IFS= read -r line; do
    if [[ "$color_output" == "1" ]]; then
      printf '%b%-10s %s%b\n' "$color" "[$label]" "$line" "$reset"
    else
      printf '%b%-10s%b %s\n' "$color" "[$label]" "$reset" "$line"
    fi
  done
}

demo_run_bg() {
  local label="$1"
  local color reset
  shift

  color="$(demo_color "$label")"
  reset="$(demo_reset)"
  (
    "$@" 2>&1 | demo_prefix_output "$label" "$color" "$reset" 1
  ) &
  DEMO_PIDS+=("$!")
}

demo_prepare_logs() {
  local root="$1"
  local name="$2"

  DEMO_LOG_DIR="$root/.workshop/demo/$name"
  DEMO_LOGS=()
  mkdir -p "$DEMO_LOG_DIR"
}

demo_run_bg_log() {
  local label="$1"
  local log_file
  shift

  [[ -n "$DEMO_LOG_DIR" ]] || {
    printf 'demo log directory not initialized\n' >&2
    return 1
  }

  log_file="$DEMO_LOG_DIR/$label.log"
  : > "$log_file"
  (
    "$@"
  ) >"$log_file" 2>&1 &
  DEMO_PIDS+=("$!")
  DEMO_LOGS+=("$log_file")
}

demo_tail_logs() {
  local log_file
  local logs=()

  [[ -n "$DEMO_LOG_DIR" ]] || {
    printf 'demo log directory not initialized\n' >&2
    return 1
  }

  for log_file in "${DEMO_LOGS[@]:-}"; do
    logs+=("${log_file##*/}")
  done

  [[ ${#logs[@]} -gt 0 ]] || {
    printf 'no demo logs to follow\n' >&2
    return 1
  }

  (
    cd "$DEMO_LOG_DIR"
    tail -n 0 -f "${logs[@]}"
  ) &
  DEMO_TAIL_PID="$!"
  wait "$DEMO_TAIL_PID"
}

demo_run() {
  local label="$1"
  local color reset
  shift

  color="$(demo_color "$label")"
  reset="$(demo_reset)"
  "$@" 2>&1 | demo_prefix_output "$label" "$color" "$reset"
}

demo_cleanup() {
  local pid log_file

  if [[ -n "${DEMO_TAIL_PID:-}" ]]; then
    kill "$DEMO_TAIL_PID" >/dev/null 2>&1 || true
    wait "$DEMO_TAIL_PID" >/dev/null 2>&1 || true
    DEMO_TAIL_PID=""
  fi

  for pid in "${DEMO_PIDS[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
  wait "${DEMO_PIDS[@]:-}" >/dev/null 2>&1 || true
  DEMO_PIDS=()

  for log_file in "${DEMO_LOGS[@]:-}"; do
    [[ -n "$log_file" ]] && rm -f "$log_file"
  done
  DEMO_LOGS=()

  if [[ -n "${DEMO_LOG_DIR:-}" ]]; then
    rmdir "$DEMO_LOG_DIR" >/dev/null 2>&1 || true
    DEMO_LOG_DIR=""
  fi
}

demo_wait() {
  local pid status=0

  for pid in "${DEMO_PIDS[@]:-}"; do
    wait "$pid" || status=1
  done

  DEMO_PIDS=()
  return "$status"
}

demo_trap_cleanup() {
  trap demo_cleanup INT TERM EXIT
}

demo_clear_trap() {
  trap - INT TERM EXIT
}
