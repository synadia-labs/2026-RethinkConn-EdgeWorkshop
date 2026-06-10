#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$ROOT/scripts/demo-helper.sh"

demo_use_local_bin "$ROOT"

SUBJECT="${1:->}"

demo_require_command nats 'run ../workshop.sh setup'
demo_prepare_logs "$ROOT" lab12-watch
demo_trap_cleanup

printf '== Lab 12 subject watch ==\n'
printf 'subject: %s\n' "$SUBJECT"
printf 'starting subscribers; press Ctrl-C to stop\n'
printf 'logs: %s\n\n' "$DEMO_LOG_DIR"
demo_run_bg_log hub-sub nats --context hub sub "$SUBJECT"
demo_run_bg_log l1-sub nats --context l1 sub "$SUBJECT"

status=0
demo_tail_logs || status=1

demo_cleanup
demo_clear_trap
exit "$status"
