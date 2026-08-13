# Security Policy

Lineup Desktop is pre-release and not ready for public distribution. Security
reports are still welcome because this app handles local Plex credentials,
desktop storage, media playback, and diagnostics.

## Supported Versions

| Version | Supported |
| --- | --- |
| `0.x` | Private pre-release only |

## Reporting A Vulnerability

Do not open public issues for vulnerabilities or secret exposure.

Preferred reporting path:

1. Use the repository's private [GitHub vulnerability reporting form](https://github.com/TJZine/LineupDesktop/security/advisories/new).
2. If that private form is unavailable, do not include secret material in a
   public issue; report only that the private reporting channel is unavailable.

Include:

- summary
- severity estimate
- affected version or commit
- reproduction steps
- impact
- suggested fix, if known

## In Scope

- Plex token or auth-header exposure
- token-bearing URL leakage
- UI access to persistent credentials or token-bearing media details
- unsafe Dart/native player boundary behavior
- native media command injection, lifetime errors, or unsanitized logs
- diagnostics or crash dumps containing secret-bearing state
- insecure storage fallback behavior
- packaging or update behavior that weakens binary trust

## Out Of Scope

- vulnerabilities in Plex Media Server itself
- vulnerabilities in Flutter, Dart, Windows, macOS, mpv, FFmpeg, or other upstream
  projects that are not caused by Lineup Desktop integration
- reports that require unredacted tokens, credentials, or private media files

## User Security Notes

- Never share Plex tokens, auth headers, tokenized URLs, logs, or crash dumps
  unless they have been redacted.
- Keep Plex Media Server and the host operating system updated.
- Use trusted networks for local testing.
