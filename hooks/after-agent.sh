#!/usr/bin/env bash
# Gemini CLI AfterAgent: after every turn, upload the prompt and the final
# response (.prompt and .prompt_response on stdin; Gemini gives no
# transcript file) via log_session, from a detached worker. No usage
# telemetry: track_usage takes only Anthropic-shaped usage.

set -u
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=common.sh
. "$HOOK_DIR/common.sh"

anamnesis_load_config || exit 0

STDIN_JSON="$(cat)"
anamnesis_resolve_sid "$STDIN_JSON"
if [ -z "$ANAMNESIS_SID" ]; then
    ANAMNESIS_SID="recovered-$(date -u +"%Y%m%dT%H%M%SZ")"
    anamnesis_write_session_id "$ANAMNESIS_SID"
fi

if anamnesis_auth_warning_due; then
    jq -n --arg msg "$ANAMNESIS_AUTH_WARNING" '{systemMessage: $msg}'
fi

# Built from stdin, never from jq arguments: a long turn exceeds ARG_MAX.
TURNS="$(printf '%s' "$STDIN_JSON" | jq -c '
    (.prompt | strings | select(length > 0) | "user: " + .),
    (.prompt_response | strings | select(length > 0) | "assistant: " + .)' 2>/dev/null)"
[ -n "$TURNS" ] || exit 0

anamnesis_capture_worker() {
    anamnesis_send_turns "$ANAMNESIS_SID" '{"source": "gemini_cli_extension"}' <<<"$TURNS"
}

# Detached with no fds on the hook's pipes, so Gemini CLI does not wait.
anamnesis_capture_worker </dev/null >/dev/null 2>&1 &
exit 0
