# Upgrading

Falcon Builder releases are tagged `vX.Y.Z` in this repository's images.
Pin the one you run with `FALCON_VERSION` in `.env`.

Upgrading is two steps, from the directory you cloned:

```bash
git pull        # update this repository (including upgrade.sh itself)
./upgrade.sh    # move to the release this repository now ships
```

`upgrade.sh` moves `FALCON_VERSION` in `.env`, pulls the images and rolls the
services, then prints what ended up running. It pulls the repository again
itself, so the `git pull` is only needed the first time — on a checkout from
before the script existed, `./upgrade.sh` would not be there yet.

To go somewhere other than the release this checkout ships:

```bash
./upgrade.sh v0.9.0     # a specific release
./upgrade.sh latest     # follow every release from now on
```

**Why a script rather than `git pull && docker compose up -d`:** `git pull`
does not change which release you run. It updates `.env.example`, while your
`.env` — written once by `setup.sh` and never overwritten — keeps whatever
version it was created with, and that is the file the Compose images are named
from. Pulling and restarting without touching it re-fetches the release you
were already on, and everything reports success. The script does both halves.
It changes only the `FALCON_VERSION` line and keeps your previous `.env` as
`.env.bak`.

By hand, if you prefer, the equivalent is: edit `FALCON_VERSION` in `.env`,
then `docker compose pull && docker compose up -d`. Either way,
`docker compose images | grep falcon-builder` shows which release is actually
running.

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

### 2026-09-26 — bundled storage is now SeaweedFS, not MinIO

MinIO archived its community edition and withdrew the public container images:
the `minio` Docker Hub namespace went first, this repository repointed to
quay.io on 2026-09-13, and quay stopped serving them too on 2026-09-24. Since
then every `docker compose pull` failed with `unauthorized: access to the
requested resource is not authorized`, which also means **`./upgrade.sh` fails
part-way** — it moves `FALCON_VERSION` in `.env`, then dies on the image pull,
leaving the file pinned to a release you are not yet running. Restore
`.env.bak` or simply re-run the upgrade once you are on this version.

The bundled storage is now [SeaweedFS](https://github.com/seaweedfs/seaweedfs)
(Apache-2.0), serving the same S3 API on the same port. `minio` and
`minio-init` are replaced by one `storage` service; no init container, because
the bucket is created on first upload. Nothing in the app changes.

**If you use your own S3 bucket** (no `storage` in `COMPOSE_PROFILES`), there
is nothing to do — you never pulled these images.

**If you use the bundled storage, your files do not move themselves.** They are
in the `falcon_minio-data` volume, in MinIO's on-disk format, which SeaweedFS
cannot read. The new service uses a new volume, so the old one is left intact
and `docker compose down -v` will not delete it. To carry the files across,
copy them bucket to bucket while both are running — the MinIO image is gone
from the registries, but yours is still on the host:

```bash
cd falcon-builder-self-hosted
git pull                              # get this version of the stack

# 1. Old MinIO on a spare port, from the image already on this machine.
docker run -d --name minio-old --network falcon_default \
  -v falcon_minio-data:/data \
  -e MINIO_ROOT_USER="$(grep ^STORAGE_S3_ACCESS_KEY_ID= .env | cut -d= -f2-)" \
  -e MINIO_ROOT_PASSWORD="$(grep ^STORAGE_S3_SECRET_ACCESS_KEY= .env | cut -d= -f2-)" \
  quay.io/minio/minio:RELEASE.2024-12-18T13-15-44Z server /data

# 2. New stack up, so SeaweedFS is serving.
./upgrade.sh

# 3. Copy every object across, using the mc image you already have.
docker run --rm --network falcon_default --entrypoint /bin/sh \
  quay.io/minio/mc:RELEASE.2024-11-17T19-35-25Z -c '
    mc alias set old http://minio-old:9000 "$OLD_KEY" "$OLD_SECRET" &&
    mc alias set new http://storage:9000   "$OLD_KEY" "$OLD_SECRET" &&
    mc mb --ignore-existing new/falcon &&
    mc mirror --overwrite old/falcon new/falcon' \
  -e OLD_KEY="$(grep ^STORAGE_S3_ACCESS_KEY_ID= .env | cut -d= -f2-)" \
  -e OLD_SECRET="$(grep ^STORAGE_S3_SECRET_ACCESS_KEY= .env | cut -d= -f2-)"

# 4. Check the app can open an uploaded file, then clean up.
docker rm -f minio-old
# docker volume rm falcon_minio-data     # only once you are satisfied
```

Step 4 is not a formality: keep `falcon_minio-data` until you have opened a
knowledge-base document and an interface upload in the browser. Removing it is
the one irreversible step here.

If `docker images | grep minio` comes back empty, the images have been pruned
from this host and there is no way to read the volume through MinIO any more.
Say so in an issue before doing anything else — the raw files are still in the
volume and recovering them is a different procedure.

### 2026-09-13 — MinIO now comes from quay.io

**Superseded by the 2026-09-26 entry above — quay.io stopped serving these
images too.** Kept as the record of how the stack got here.

Docker Hub removed the `minio` namespace when the MinIO community edition
went source-only, so `minio/minio` and `minio/mc` stopped resolving there and
a fresh `docker compose pull` failed with "pull access denied for
minio/minio". `docker-compose.yml` now pulls the same images, at the same
tags, from `quay.io`.

Nothing to migrate, and no `FALCON_VERSION` change either — this is a stack
change, so `git pull && docker compose pull && docker compose up -d` is enough
on its own: it re-pulls the image under its new name and recreates the
container. Your files are in the `minio-data` volume, which is untouched.
Instances already running were unaffected — the image was already on the host —
and instances using their own S3 bucket (no `storage` profile) never pulled it
at all.

## Release notes

### v0.10.0

- **"Continue with Google" and "Continue with Microsoft" now appear only when
  you have configured them.** Before this, both buttons showed on every
  instance and clicking one failed with "Provider not found" — the first thing
  a new operator saw. Set the credentials as described in
  [docs/auth.md](docs/auth.md#4-google-and-microsoft-sign-in-optional) and the
  matching button comes back; leave them unset and the sign-in page is just the
  email and password form.
- Google Drive node: file content the API returns base64-encoded is decoded
  rather than passed through as base64.
- MCP: a `rerun_executions` tool replays past executions, filtered by payload
  and paged in batches. Available where you have set `MCP_ADMIN_TOKEN` /
  `MCP_ADMIN_WRITE_TOKEN`.

Cloudflare Turnstile can now guard the signup form, and **this release does not
turn it on here**. The widget's site key is compiled into the web bundle, and
the image you pull is built without one, so a prebuilt instance cannot display
the challenge. Do not set `TURNSTILE_SECRET_KEY` in `.env`: the server would
then demand a token the page cannot produce and every signup would fail. Signup
on this edition is already limited to invited addresses.

No configuration change; upgrade with the steps at the top of this file.

### v0.9.0

Coming from v0.5.0 this is four releases in one step; the notes below cover
each of them.

- The embed loader (`/embed.js`) is served with this instance's own origin
  baked in, so a website chatbot widget loads its chat from your server. It
  reads `APP_URL`, so it follows the address you configured with no extra
  setting. Snippets already pasted on a site keep working unchanged — the
  loader no longer needs the snippet to tell it where the app lives.

Nothing to migrate; upgrade with the steps at the top of this file.

### v0.8.0

- Agent Loop is switched on for the workspace this instance already has. The
  v0.6.0 default below only applied to workspaces created after it, so an
  existing one kept failing Agent Loop nodes with "agent-loop is disabled for
  this workspace". The migrate step backfills it on `up`.
- Agent Loop nodes can use extended thinking on models that support it — a
  reasoning budget configured on the node.
- Internal: Anthropic SDK updated.

No configuration change.

### v0.7.0

- Embed widget hardening: it survives Google Tag Manager (which rebuilds the
  script tag and drops `data-*` attributes — the loader also reads `?slug=`,
  `?color=` and `?base=` from the script `src`) and caching/minify plugins
  such as WP Rocket, the chat icon is legible at the real button size, and the
  widget is isolated from the host page's CSS.

No configuration change. On v0.7.0 and v0.8.0 the loader fell back to the
Falcon Builder cloud origin when a snippet carried no `data-base-url`; v0.9.0
removes that fallback, so upgrading straight to v0.9.0 never passes through
it.

### v0.6.0

- Agent Loop nodes are enabled by default. Existing workspaces are backfilled
  by v0.8.0's migrate step, so this upgrade path covers both.
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

Nothing to migrate; upgrade with the steps at the top of this file.

### v0.4.0

- Updated AI model listings and pricing (LLM node model pickers, capability
  flags, token pricing used for usage estimates). No configuration change;
  you bring your own provider keys either way.

Nothing to migrate; upgrade with the steps at the top of this file.

### v0.3.0

- The web image no longer rewrites its own files at start. The app resolves
  its public origin at runtime: `APP_URL` on the server, the page's own
  origin in the browser. Nothing changes in `.env`; `APP_URL` was already
  the value `setup.sh` writes.
- Sign-in configuration errors name `APP_URL`.

Nothing to migrate; upgrade with the steps at the top of this file.

### v0.2.0

- The worker reports its health: `docker compose ps` shows `healthy` only
  when its job queues, Redis and the database all answer, and
  `docker compose up -d --wait` waits for that. No configuration change.
- Community-edition worker logs no longer mention Supabase or the affiliate
  programme, which do not exist in this edition.
- Configuration errors link to the guides in this repository.
- Release notes are generated on each tag; see the
  [releases](https://github.com/NeoSky-AI/falcon-builder/releases) page.

Nothing to migrate; upgrade with the steps at the top of this file.

### v0.1.0

First public release of the Community edition. Nothing to migrate from.
