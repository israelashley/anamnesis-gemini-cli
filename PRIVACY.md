# Privacy — anamnesis Gemini CLI extension

## What the hooks send, and when

The hooks run on your machine and send to the `server_url` in
`~/.anamnesis/config.json` (by default `https://anamnesis.smtry.ai`) over
HTTPS:

- **SessionStart.** In the background: any payloads queued after an earlier
  failed upload (conversation text or a session close), then a
  `get_memory_stats` reachability probe.
- **BeforeAgent.** Your prompt text and the session id, as a
  `retrieve_memories` query. Up to five recalled lines and a date/time
  anchor are added to the turn's context.
- **AfterAgent.** In the background, after each turn: your prompt and the
  model's final response for that turn, with the session id, to
  `log_session`. No usage telemetry is sent.
- **SessionEnd.** The session id and the close reason, to `session_close`.

Every request carries `Authorization: Bearer <access token>` (OAuth), or
`X-Anamnesis-Key: <api_key>` for a legacy api_key install. When the access
token is near expiry, the refresh token and client id go to `/oauth/token`.
Credentials and bodies reach `curl` through 0600 files or stdin, never its
command line.

## When nothing is sent

With `anamnesis pause` in effect, or `ANAMNESIS_CAPTURE` set to `off`, `0`,
`false` or `no` (any case; an unrecognised value also counts as off), every
hook exits without sending anything or adding anything to context, and the
upload queue is not replayed.

The extension also registers Anamnesis as a remote MCP server
(`httpUrl`) that Gemini CLI connects to itself. Tools the model calls
through it are not covered by the pause file or `ANAMNESIS_CAPTURE`.

## What stays on your machine

`~/.anamnesis/` holds your tokens (`config.json`), payloads waiting to be
uploaded (`pending_uploads/`, plaintext conversation text until delivered)
and an error log. Files the hooks create are mode 0600.

## What the server does

Content is encrypted at rest under a per-user key derived from your own
api_key, with no master key. It is not yet end-to-end encrypted:
[anamnesis.smtry.ai/security](https://anamnesis.smtry.ai/security) says
exactly who can decrypt what, and
[anamnesis.smtry.ai/privacy](https://anamnesis.smtry.ai/privacy) has the full
policy, including subprocessors and retention.

## Pausing / revoking

- `anamnesis pause` stops the hooks until `anamnesis resume`.
- `anamnesis-config` signs in again and replaces the stored tokens.
- Delete individual memories or wipe everything at
  [anamnesis.smtry.ai/memory](https://anamnesis.smtry.ai/memory).

## Uninstall

```
gemini extensions uninstall anamnesis
rm -rf ~/.anamnesis
```

Server-side deletion is a separate action at `/memory`.
