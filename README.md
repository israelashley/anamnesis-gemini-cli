# anamnesis — persistent encrypted memory for Gemini CLI

Four lifecycle hooks capture every Gemini CLI session. A per-user
HKDF-derived key encrypts content server-side — nobody at smtry.ai can
read it without your credentials. Browse, search, and delete any memory
at [anamnesis.smtry.ai/memory](https://anamnesis.smtry.ai/memory).

Companion to [`anamnesis-claude-code`](https://github.com/israelashley/anamnesis-claude-code).
Same backend, same memory root, same engrams — your work in Gemini and
Claude lands in one place.

## Install

```
gemini extensions install https://github.com/israelashley/anamnesis-gemini-cli
```

Then, once:

```
/anamnesis-config
```

(Or run `bin/anamnesis-config` directly from any shell.)

`anamnesis-config` starts a loopback server, registers a Dynamic Client
(RFC 7591), opens your browser to
`anamnesis.smtry.ai/oauth/authorize`, and catches the redirect. You
paste your api_key on the consent page, approve the scopes
(`memory.read memory.write` by default — add `--allow-delete` to also
request `memory.delete`), and return to the terminal. Access + refresh
tokens land in `~/.anamnesis/config.json` (mode 0600); hooks rotate the
refresh token automatically before expiry, so the setup is one-and-done.

**If you've already run `anamnesis-config` from the Claude Code plugin,
you can skip this step.** Both extensions read the same
`~/.anamnesis/config.json`. One identity, one consent, every assistant.

## What the hooks do

| Hook | When | What it does |
|------|------|--------------|
| `SessionStart` | Once per session | Issues a fresh `session_id`, drains the pending-upload queue, probes server reachability. |
| `BeforeAgent` | After the user submits a prompt, before the agent plans | Retrieves top-5 relevant engrams + a **server-time anchor** (authoritative, from the HTTP `Date:` header), injects them as `additionalContext`. Model starts the turn oriented. |
| `AfterAgent` | After every assistant turn ends | Captures the prompt + response via `log_session`. Server dedups by SHA-256 prefix — re-sends are idempotent. |
| `SessionEnd` | Session close | Calls `session_close`, advancing the server-side pipeline (episodes → echoes). Clears the session marker. |

All four are POSIX shell scripts that use `curl` + `jq`. No Node, no
compiled binaries. `python3` is only required once, by
`anamnesis-config`, for the PKCE loopback server during the OAuth
consent flow.

## Control surface

```
anamnesis                  status (default)
anamnesis pause            suspend capture — hooks become no-ops
anamnesis resume           re-enable capture
```

The `paused` sentinel file at `~/.anamnesis/paused` is the first thing
every hook checks. Deleting the file resumes immediately. No daemon, no
restart, no shell refresh needed. **Pausing also pauses the Claude Code
plugin** — the sentinel is global to your machine.

## Configuration files

| Path | Contents | Mode |
|------|----------|------|
| `~/.anamnesis/config.json` | OAuth: handle, server_url, access_token, refresh_token, expires_at, client_id. Legacy: api_key, handle, server_url. | 0600 |
| `~/.anamnesis/current_session.json` | session_id for the live session | 0600 |
| `~/.anamnesis/paused` | present ⇒ hooks exit 0 silently | 0600 |
| `~/.anamnesis/pending_uploads/*.json` | queued payloads from prior failures; drained on next SessionStart | 0600 |
| `~/.anamnesis/hook_errors.log` | structured JSONL of transient errors — for debugging only | 0644 |

All state is user-local and user-readable. Nothing in
`~/.gemini/settings.json` holds your api_key.

## Failure behavior

Hooks **never block Gemini CLI.** On any server error they:

1. Print a one-line warning to stderr.
2. Append a structured entry to `~/.anamnesis/hook_errors.log`.
3. Queue the failed payload under `~/.anamnesis/pending_uploads/`.
4. Exit `1` — non-blocking. Gemini CLI continues the session.

The next `SessionStart` drains the queue before doing anything else.

## What's different from the Claude Code plugin

The hook lifecycle maps 1:1 (`UserPromptSubmit` → `BeforeAgent`,
`Stop` → `AfterAgent`, `SessionStart` and `SessionEnd` are
identical). The differences are minor:

- **Token-usage telemetry is disabled.** Claude Code's plugin pushes
  Anthropic-shape usage to `/mcp/tools/track_usage` so the dashboard's
  Tokens Paid card ticks live. Gemini's API returns Google-shape usage
  (`usageMetadata.input_token_count` etc.), which the current
  ingestion path does not understand. The dashboard's cost card stays
  Claude-Code-only until a Google-shape ingestion variant ships.
- **Stdin payload field names** differ (`prompt` instead of
  `user_prompt`; `prompt_response` instead of `last_assistant_message`;
  no `transcript_path`). The hooks handle these directly — same
  observable behavior.

## Uninstall

```
gemini extensions uninstall anamnesis
rm -rf ~/.anamnesis   # optional — removes local config + queued uploads
```

If you also use the Claude Code plugin, leave `~/.anamnesis/` alone —
it's shared.

Delete your server-side memory at `anamnesis.smtry.ai/memory` if you
want all traces gone. Deletes are cryptographic — content is written
to disk encrypted under your key; when you delete we also drop the key
reference, so recovery is structurally impossible.

## License

MIT. See [`LICENSE`](LICENSE).
