#!/usr/bin/env bash
# anamnesis/hooks/after-agent.sh — Gemini CLI AfterAgent hook.
#
# Fires once per turn after the model generates its final response.
# Captures the turn via /mcp/tools/log_session. Server chunks on
# 2000-char boundaries and dedups by SHA-256 prefix — re-sending is
# idempotent (ADR-062 §4).
#
# Stdin (Gemini AfterAgent hook input) is a JSON object with:
#   .prompt           — the user's text
#   .prompt_response  — the assistant's final response text
#   .stop_hook_active — whether a Stop hook chain is in progress
#
# Unlike Claude Code's Stop hook, Gemini does not expose a transcript
# JSONL path — the response text comes directly via stdin. Simpler.
#
# Token-usage telemetry is NOT fired here. Gemini's API responses
# carry Google-shape usage (input_token_count / output_token_count
# under .usageMetadata) rather than Anthropic-shape, and the Tokens
# Paid pipeline currently only ingests the Anthropic shape. A future
# /mcp/tools/track_usage variant for Google usage data is the right
# follow-up; for now the dashboard's cost card stays Claude-Code-only.

set -u
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$HOOK_DIR/common.sh"

anamnesis_check_pause
anamnesis_load_config || exit 0

SID="$(anamnesis_read_session_id)"
if [ -z "$SID" ]; then
    SID="recovered-$(date -u +"%Y%m%dT%H%M%SZ")"
    anamnesis_write_session_id "$SID"
fi

STDIN_JSON="$(cat)"
PROMPT="$(printf '%s' "$STDIN_JSON" | jq -r '.prompt // empty' 2>/dev/null)"
RESPONSE="$(printf '%s' "$STDIN_JSON" | jq -r '.prompt_response // empty' 2>/dev/null)"

# Build a transcript-shaped blob: prompt + response joined. The server's
# chunker treats this as one "turn" — same shape it gets from the Claude
# Code Stop hook when transcript_path is missing.
TRANSCRIPT=""
if [ -n "$PROMPT" ] && [ -n "$RESPONSE" ]; then
    TRANSCRIPT="user: $PROMPT
assistant: $RESPONSE"
elif [ -n "$RESPONSE" ]; then
    TRANSCRIPT="$RESPONSE"
elif [ -n "$PROMPT" ]; then
    TRANSCRIPT="$PROMPT"
fi

if [ -z "$TRANSCRIPT" ]; then
    # Empty turn (rare — e.g. tool-only loop with no final text). Not an error.
    exit 0
fi

BODY="$(jq -n --arg sid "$SID" --arg tx "$TRANSCRIPT" \
    '{session_id: $sid, transcript: $tx, source: "gemini_cli_extension"}')"

if ! anamnesis_post "/mcp/tools/log_session" "$BODY" >/dev/null; then
    anamnesis_queue_payload "/mcp/tools/log_session" "$BODY"
    anamnesis_log_error "log_session_queued" "sid=$SID"
fi

exit 0
