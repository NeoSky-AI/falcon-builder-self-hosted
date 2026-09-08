# Falcon Builder — self-hosted

[![Smoke test](https://github.com/NeoSky-AI/falcon-builder-self-hosted/actions/workflows/smoke.yml/badge.svg)](https://github.com/NeoSky-AI/falcon-builder-self-hosted/actions/workflows/smoke.yml)
[![Release](https://img.shields.io/badge/release-v0.4.0-blue)](UPGRADING.md#release-notes)

Run [Falcon Builder](https://falconbuilder.dev), the AI workflow and agent
builder, on your own server with Docker Compose. This repository holds the
deployment stack for the **Community edition**: prebuilt images, a Compose
file, a setup script that generates every secret, and the guides for the
services you connect (email, storage, sign-in).

The Community edition is the full builder — workflows, agents, knowledge
bases, hosted interfaces, integrations, scheduled and event triggers — with
one workspace per instance and unlimited members. Billing, affiliates and the
marketing site do not exist in it. Everything it talks to is yours: your
Postgres, your object storage, your SMTP server, your AI provider keys.

## Quick start

Requirements: Docker Engine 24+ with Compose v2.20+, 2 vCPU and 4 GB RAM to
start, and for a public server a DNS name pointing at it with ports 80, 443
and 9000 reachable.

```bash
git clone https://github.com/NeoSky-AI/falcon-builder-self-hosted
cd falcon-builder-self-hosted
./setup.sh          # asks for your public URL, generates every secret into .env
```

Open `.env` and set your SMTP server (`SMTP_HOST`, `SMTP_FROM`, and the
login it needs). Invitations and password resets go out through it; without
it the app tells you which variable is missing when you try. Add
`OPENAI_API_KEY` if you want knowledge bases (documents are embedded with
OpenAI). Then:

```bash
docker compose up -d
```

The `migrate` service creates the database schema, then web, worker and the
scheduler start. Open your URL. **The first account to sign up owns the
instance's workspace**; everyone after joins through an invitation from
Settings → Team.

On a laptop, `./setup.sh` with the default URL gives you
`http://localhost:3000` with nothing else to configure; file storage answers
on `http://localhost:9000`.

## What runs

| Service | Image | Role |
|---|---|---|
| `caddy` | `caddy:2-alpine` | TLS (automatic certificates) and reverse proxy. The only service that publishes ports. |
| `web` | `ghcr.io/neosky-ai/falcon-builder-web` | The application |
| `worker` | `ghcr.io/neosky-ai/falcon-builder-worker` | Runs workflows, processes documents, sends email. Reports its health (queues, Redis, database) so `docker compose ps` shows the real state |
| `scheduler` | `alpine` + curl | The scheduled jobs (triggers, timeouts, retention), see `crontab.template` |
| `migrate` | worker image | One-shot: pgvector extension + schema. Runs on every `up`; idempotent |
| `postgres` | `pgvector/pgvector:pg16` | The database |
| `redis` | `redis:7-alpine` | Job queues |
| `minio`, `minio-init` | `minio/minio`, `minio/mc` | File storage (profile `storage`, on by default) |

Data lives in named volumes: `postgres-data`, `redis-data`, `minio-data`,
`caddy-data`. Back up `postgres-data` and `minio-data`, and keep a copy of
`.env` — `CREDENTIAL_ENCRYPTION_KEY` in it encrypts every stored integration
credential and cannot be recovered.

## Configuring

Everything is in `.env`; `.env.example` documents each variable. The guides:

- [Email](docs/email.md) — SMTP for transactional mail; inbound email triggers
- [File storage](docs/storage.md) — the bundled MinIO, or your own S3, R2, …
- [Sign-in](docs/auth.md) — accounts, invitations, password reset, Google and Microsoft sign-in with your own OAuth apps

Using your own reverse proxy: point it at the `web` container on port 3000,
set `HTTP_PORT`/`HTTPS_PORT`/`STORAGE_PORT` in `.env` to ports Caddy may
keep, or remove the `caddy` service from your copy of the Compose file.

## Updating

```bash
git pull                       # new Compose file or defaults, if any
docker compose pull            # the release named by FALCON_VERSION in .env
docker compose up -d           # migrate applies schema changes, then rolls the services
```

`.env` pins `FALCON_VERSION` to the release setup.sh shipped with (the
default from `.env.example`); bump it to move, or set `latest` to follow every
release. Read [UPGRADING.md](UPGRADING.md)
before moving between versions — it lists the changes that need a step from
you.

## Getting help

- Something failing: `docker compose logs web worker migrate` — the app
  names the variable it is missing.
- Bugs and questions about this stack: open an issue in this repository.
- Security reports: see [SECURITY.md](SECURITY.md).

## License

The files in this repository (the Compose stack, scripts and documentation)
are licensed under [Apache-2.0](LICENSE). The Falcon Builder container images
this stack pulls are licensed separately under the Falcon Builder end-user
license, which governs their use.
