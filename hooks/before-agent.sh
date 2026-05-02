#!/usr/bin/env bash
# anamnesis/hooks/before-agent.sh — Gemini CLI BeforeAgent hook.
#
# Fires after the user submits a prompt, before the agent begins
# planning. Retrieves top-k engrams + injects them plus a server-time
# anchor as hookSpecificOutput.additionalContext, identical shape to
# the Claude Code UserPromptSubmit hook (Gemini and Claude both honor
# the same {hookSpecificOutput: {hookEventName, additionalContext}}
# protocol — only the hookEventName value differs).
#
# Design constraints (mirrors anamnesis-claude-code Phase 1):
#   - Terse. Self-cap ~2000 chars.
#   - Topically gated: skip injection entirely when no engram clears
#     the similarity floor.
#   - Never persona/rules/guidance. Only retrieval + time anchor.

set -u
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$HOOK_DIR/common.sh"

anamnesis_check_pause
anamnesis_load_config || exit 0

# Stdin is a JSON object with at least .prompt (BeforeAgent hook input).
STDIN_JSON="$(cat)"
PROMPT="$(printf '%s' "$STDIN_JSON" | jq -r '.prompt // empty' 2>/dev/null)"

if [ -z "$PROMPT" ]; then
    exit 0
fi

QUERY_BODY="$(jq -n \
    --arg q "$PROMPT" \
    '{query: $q, top_n: 5, mode: "hierarchical", detail_level: "standard", min_similarity: 0.35, diversity: 0.3}')"

RESPONSE="$(anamnesis_post "/mcp/tools/retrieve_memories" "$QUERY_BODY")"
POST_STATUS=$?

if [ $POST_STATUS -ne 0 ]; then
    anamnesis_log_error "retrieve_failed" "status=$POST_STATUS"
    # Fail-open: still emit the time anchor so the model at least knows
    # what day it is.
    if [ -n "${ANAMNESIS_SERVER_TIME:-}" ]; then
        ADDL=$(printf '<server-time source="anamnesis">%s</server-time>' "$ANAMNESIS_SERVER_TIME")
        jq -n --arg ctx "$ADDL" \
            '{hookSpecificOutput: {hookEventName: "BeforeAgent", additionalContext: $ctx}}'
    fi
    exit 0
fi

ENGRAMS_JSON="$(printf '%s' "$RESPONSE" | jq -c '
    def pick:
        if (.content // null) != null then {score: (.score // 0), content: .content}
        elif (.text // null) != null    then {score: (.score // 0), content: .text}
        else empty end;
    ((.engrams // []) + (.results // [])) | map(pick) | .[0:5]
' 2>/dev/null)"

ENGRAM_COUNT="$(printf '%s' "$ENGRAMS_JSON" | jq 'length' 2>/dev/null)"
ENGRAM_COUNT="${ENGRAM_COUNT:-0}"

ADDL=""
if [ "$ENGRAM_COUNT" -gt 0 ]; then
    BODY="$(printf '%s' "$ENGRAMS_JSON" | jq -r '
        .[] | "- (" + ((.score | tostring)[0:5]) + ") " + (.content | gsub("\n"; " ") | .[0:350])
    ' 2>/dev/null)"
    ADDL="$(printf '<anamnesis-context source="anamnesis" count="%s">\n%s\n</anamnesis-context>' "$ENGRAM_COUNT" "$BODY")"
fi

if [ -n "${ANAMNESIS_SERVER_TIME:-}" ]; then
    TIME_LINE="$(printf '<server-time source="anamnesis">%s</server-time>' "$ANAMNESIS_SERVER_TIME")"
    if [ -n "$ADDL" ]; then
        ADDL="$ADDL"$'\n'"$TIME_LINE"
    else
        ADDL="$TIME_LINE"
    fi
fi

if [ -z "$ADDL" ]; then
    exit 0
fi

CAP=2000
ADDL_LEN=${#ADDL}
if [ "$ADDL_LEN" -gt $CAP ]; then
    ADDL="$(printf '%s' "$ADDL" | head -c $CAP)…"
fi

jq -n --arg ctx "$ADDL" \
    '{hookSpecificOutput: {hookEventName: "BeforeAgent", additionalContext: $ctx}}'

exit 0
