#!/usr/bin/env bash
# Gemini CLI SessionEnd: ask the server to advance this session's pipeline
# (episodes to echoes) now rather than in the nightly batch.

set -u
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=common.sh
. "$HOOK_DIR/common.sh"

anamnesis_load_config || exit 0

STDIN_JSON="$(cat)"
anamnesis_resolve_sid "$STDIN_JSON"
[ -n "$ANAMNESIS_SID" ] || exit 0
REASON="$(printf '%s' "$STDIN_JSON" | jq -r '.reason // "exit"' 2>/dev/null)"
[ -n "$REASON" ] || REASON="exit"

BODY="$(jq -n --arg sid "$ANAMNESIS_SID" --arg reason "$REASON" '{session_id: $sid, reason: $reason}')"
if ! anamnesis_post "/mcp/tools/session_close" "$BODY" >/dev/null; then
    anamnesis_queue_payload "/mcp/tools/session_close" "$BODY"
    anamnesis_log_error "session_close_queued" "sid=$ANAMNESIS_SID reason=$REASON"
fi
rm -f "$ANAMNESIS_RECEIPT_DIR/$(anamnesis_transcript_key "$ANAMNESIS_SID")".*
anamnesis_receipt_prune
anamnesis_clear_session_id "$ANAMNESIS_SID"
exit 0
