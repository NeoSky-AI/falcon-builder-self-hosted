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

## Release notes

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
