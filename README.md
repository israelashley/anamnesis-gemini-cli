# anamnesis — persistent encrypted memory for Gemini CLI

Four lifecycle hooks capture every Gemini CLI session. Content is
encrypted at rest under a per-user key with no master key; not yet
end-to-end, and [anamnesis.smtry.ai/security](https://anamnesis.smtry.ai/security)
says exactly who can decrypt what. Browse, search, and delete any memory
at [anamnesis.smtry.ai/memory](https://anamnesis.smtry.ai/memory). What
is sent, and when, is in [PRIVACY.md](PRIVACY.md).

Companion to [`anamnesis-claude-code`](https://github.com/smtrycorp/anamnesis-claude-code).
Same backend, same memory root, same engrams — your work in Gemini and
Claude lands in one place.

## Install

```
gemini extensions install https://github.com/smtrycorp/anamnesis-gemini-cli
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
| `SessionStart` | Once per session | Adopts Gemini CLI's session id. In the background, replays the pending-upload queue and probes the server. |
| `BeforeAgent` | After the user submits a prompt, before the agent plans | Retrieves up to 5 relevant memories and injects them with a `<current-datetime>` anchor (local clock, plus server UTC from the HTTP `Date:` header) as `additionalContext`. Gives up after about 3 seconds so a slow server never holds the prompt. |
| `AfterAgent` | After every assistant turn ends | In the background, uploads the prompt and final response via `log_session`. |
| `SessionEnd` | Session close | Calls `session_close`, advancing the server-side pipeline (episodes → echoes). |

All four are bash scripts that use `curl` + `jq`. No Node, no
compiled binaries. `python3` is only required once, by
`anamnesis-config`, for the PKCE loopback server during the OAuth
consent flow.

## Control surface

```
anamnesis                  status (default)
anamnesis pause            suspend capture — hooks become no-ops
anamnesis resume           re-enable capture
```

While `~/.anamnesis/paused` exists, every hook exits without sending
anything. `ANAMNESIS_CAPTURE=off` (or `0`, `false`, `no`, any case) does
the same for one process tree. Neither switch covers the remote MCP server
Gemini CLI connects to itself; see [PRIVACY.md](PRIVACY.md). **Pausing
also pauses the Claude Code and Codex hooks**; the sentinel is global to
your machine.

## Configuration files

| Path | Contents | Mode |
|------|----------|------|
| `~/.anamnesis/config.json` | OAuth: handle, server_url, access_token, refresh_token, expires_at, client_id. Legacy: api_key, handle, server_url. | 0600 |
| `~/.anamnesis/current_session.json` | last session id, a fallback for hooks whose payload has none | 0600 |
| `~/.anamnesis/paused` | present ⇒ hooks exit 0 silently | 0600 |
| `~/.anamnesis/pending_uploads/*.json` | queued payloads from failed uploads; replayed in the background at the next SessionStart | 0600 |
| `~/.anamnesis/auth_failed` | present while the server is rejecting your sign-in | 0600 |
| `~/.anamnesis/hook_errors.log` | structured JSONL of errors — for debugging only | 0600 |

Modes are those the hooks create files with (they run under `umask 077`);
files left by older versions keep their mode. Nothing in
`~/.gemini/settings.json` holds your credentials.

## Failure behavior

Hooks **never block Gemini CLI** and always exit 0. On a server error
they append a structured entry to `~/.anamnesis/hook_errors.log` and, for
an upload, queue the payload under `~/.anamnesis/pending_uploads/`. The
next `SessionStart` replays the queue in the background, stopping at the
first failure. When the server rejects your sign-in, the hooks emit one
`[anamnesis]` warning line per session as a `systemMessage` until
`anamnesis-config` fixes it.

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
want all traces gone — deletion removes the encrypted files from the
live store, and full account deletion is self-serve from the account
page.

## License

MIT. See [`LICENSE`](LICENSE).
