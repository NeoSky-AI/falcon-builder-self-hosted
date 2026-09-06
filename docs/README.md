# Guides

These cover the parts of a self-hosted instance that talk to services you
operate. If something is not configured, the feature that needs it fails
with an error naming the missing variables; nothing falls back to a
Falcon-operated service.

| Guide | Covers |
|---|---|
| [Email](email.md) | Transactional email over your SMTP server; inbound email triggers through your own Mailgun domain |
| [File storage](storage.md) | The bundled MinIO, or knowledge-base documents, interface media and attachments in your own S3-compatible bucket |
| [Sign-in](auth.md) | Accounts, sessions and password resets in your database; optional Google / Microsoft sign-in with your own OAuth apps |

In the Compose stack, `setup.sh` fills in the storage variables for the
bundled MinIO; email and sign-in providers are yours to set in `.env`.
