#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$ROOT/scripts/demo-helper.sh"

demo_use_local_bin "$ROOT"

SUBJECT="${1:-foo}"

demo_require_command nats 'run ../workshop.sh setup'
demo_prepare_logs "$ROOT" lab02-interest
demo_trap_cleanup

printf '== Lab 02 subscriber view ==\n'
printf 'starting subscribers; press Ctrl-C to stop\n'
printf 'logs: %s\n\n' "$DEMO_LOG_DIR"
demo_run_bg_log hub-sub nats --context hub sub "$SUBJECT.hub"
demo_run_bg_log l1-sub nats --context l1 sub "$SUBJECT.l1"
demo_run_bg_log l2-sub nats --context l2 sub "$SUBJECT.l2"
demo_run_bg_log l3-sub nats --context l3 sub "$SUBJECT.l3"

status=0
demo_tail_logs || status=1

demo_cleanup
demo_clear_trap
exit "$status"
