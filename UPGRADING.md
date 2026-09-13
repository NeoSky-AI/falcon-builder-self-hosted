# Upgrading

Falcon Builder releases are tagged `vX.Y.Z` in this repository's images.
Pin the one you run with `FALCON_VERSION` in `.env`.

Every upgrade is the same three commands:

```bash
git pull
docker compose pull
docker compose up -d
```

`migrate` runs before the app starts and applies schema changes with
`prisma db push`. Take a database backup first when moving between minor
versions:

```bash
docker compose exec postgres pg_dump -U falcon -Fc falcon > falcon-$(date +%F).dump
```

Rolling back means restoring that dump and setting `FALCON_VERSION` back;
schema changes are not reversible in place.

## Stack changes

Changes to the Compose stack itself, independent of any Falcon release. They
reach you with `git pull`.

### 2026-09-13 — MinIO now comes from quay.io

Docker Hub removed the `minio` namespace when the MinIO community edition
went source-only, so `minio/minio` and `minio/mc` stopped resolving there and
a fresh `docker compose pull` failed with "pull access denied for
minio/minio". `docker-compose.yml` now pulls the same images, at the same
tags, from `quay.io`.

Nothing to migrate: `git pull && docker compose pull && docker compose up -d`
re-pulls the image under its new name and recreates the container. Your files
are in the `minio-data` volume, which is untouched. Instances already running
were unaffected — the image was already on the host — and instances using
their own S3 bucket (no `storage` profile) never pulled it at all.

## Release notes

### v0.8.0

Coming from v0.5.0 this is three releases in one step — read the v0.7.0 and
v0.6.0 notes below too.

**Re-copy your embed snippet if you run the website chatbot.** The snippet in
the agent's Interfaces panel now carries a `data-base-url` attribute pointing
at your instance. A snippet you copied before this upgrade does not have it,
and the embed loader shipped since v0.7.0 falls back to the Falcon Builder
cloud origin when it is missing — so a widget already embedded on your site
would start loading its chat from falconbuilder.dev instead of your server.
Copy the embed code again and replace the old `<script>` tag wherever you
pasted it. Hosted interfaces (`/i/<slug>`) are unaffected; this is only the
embeddable widget.

- Agent Loop is switched on for the workspace this instance already has. The
  v0.6.0 default (below) only covered workspaces created after it; the migrate
  step now backfills existing ones, so Agent Loop nodes stop failing with
  "agent-loop is disabled for this workspace". Applied automatically.
- Agent Loop nodes can use extended thinking on models that support it — a
  reasoning budget configured on the node.
- Internal: Anthropic SDK updated.

Nothing to migrate by hand.

### v0.7.0

- Embed widget fixes: it now survives installation through Google Tag Manager
  (which rebuilds the script tag and drops `data-*` attributes — the loader
  also accepts `?slug=`, `?color=`, `?base=` query params on the script `src`),
  and through caching/minify plugins such as WP Rocket. The chat icon is
  legible at the real button size, and the widget is isolated from the host
  page's CSS.

No configuration change. See the v0.8.0 note above before upgrading if you
have the widget embedded somewhere.

### v0.6.0

- Agent Loop nodes are enabled by default. Existing workspaces are backfilled
  by v0.8.0's migrate step, so on this upgrade path both are covered.
- Publishing a workflow now blocks on configuration that is guaranteed to fail
  at runtime — an empty Agent Loop prompt, an unset routing condition, an empty
  AI Judge input or criteria. Publish returns the offending nodes instead of
  shipping a definition that cannot run.

No configuration change.

### v0.5.0

- Fixed a race that could throw an unhandled Prisma error on a workspace's
  very first dashboard visit right after sign-up (a subscription record
  auto-created on first use, created twice by two concurrent requests).
  Every fresh instance hits this window once, on its first workspace;
  self-hosted operators may have seen a "duplicate key" error in
  `docker compose logs web` on first sign-up. No configuration change.

Nothing to migrate. `git pull && docker compose pull && docker compose up -d`.

### v0.4.0

- Updated AI model listings and pricing (LLM node model pickers, capability
  flags, token pricing used for usage estimates). No configuration change;
  you bring your own provider keys either way.

Nothing to migrate. `git pull && docker compose pull && docker compose up -d`.

### v0.3.0

- The web image no longer rewrites its own files at start. The app resolves
  its public origin at runtime: `APP_URL` on the server, the page's own
  origin in the browser. Nothing changes in `.env`; `APP_URL` was already
  the value `setup.sh` writes.
- Sign-in configuration errors name `APP_URL`.

Nothing to migrate. `git pull && docker compose pull && docker compose up -d`.

### v0.2.0

- The worker reports its health: `docker compose ps` shows `healthy` only
  when its job queues, Redis and the database all answer, and
  `docker compose up -d --wait` waits for that. No configuration change.
- Community-edition worker logs no longer mention Supabase or the affiliate
  programme, which do not exist in this edition.
- Configuration errors link to the guides in this repository.
- Release notes are generated on each tag; see the
  [releases](https://github.com/NeoSky-AI/falcon-builder/releases) page.

Nothing to migrate. `git pull && docker compose pull && docker compose up -d`.

### v0.1.0

First public release of the Community edition. Nothing to migrate from.
