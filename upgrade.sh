#!/bin/sh
# Moves a self-hosted Falcon Builder to a new release.
#
#   ./upgrade.sh                 the release this checkout ships (after git pull)
#   ./upgrade.sh v0.9.0          a specific release
#   ./upgrade.sh latest          follow every release from now on
#   ./upgrade.sh --no-pull       don't touch git; just re-read .env.example
#
# The step people miss is FALCON_VERSION in .env: setup.sh writes that file
# once and never overwrites it, so `git pull` moves .env.example and leaves the
# running release where it was. This does both halves, then pulls the images
# and rolls the services.
#
# Only the FALCON_VERSION line is touched; the previous .env is kept as
# .env.bak. Needs: sh, sed, grep, docker.
set -eu
cd "$(dirname "$0")"

pull=yes
target=""
for arg in "$@"; do
  case "$arg" in
    --no-pull) pull=no ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *) target="$arg" ;;
  esac
done

if [ ! -f .env ]; then
  echo "No .env here — run ./setup.sh first." >&2
  exit 1
fi

get() { # NAME FILE
  grep -E "^$1=" "$2" | head -n 1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

# ── Bring the checkout up to date ───────────────────────────────────────────
if [ "$pull" = yes ]; then
  if [ -d .git ]; then
    echo "Updating this repository"
    # --ff-only so an operator's clone never gains a surprise merge commit.
    if ! git pull --ff-only; then
      echo >&2
      echo "git pull could not fast-forward. Resolve that (or re-run with --no-pull)," >&2
      echo "then run this again." >&2
      exit 1
    fi
  else
    echo "Not a git checkout — skipping the repository update."
  fi
fi

# ── Work out where we are going ─────────────────────────────────────────────
current="$(get FALCON_VERSION .env)"
if [ -z "$target" ]; then
  target="$(get FALCON_VERSION .env.example)"
fi
if [ -z "$target" ]; then
  echo "Could not work out which release to move to: .env.example has no FALCON_VERSION." >&2
  echo "Pass one explicitly, e.g. ./upgrade.sh v1.0.0" >&2
  exit 1
fi

# This gets written straight into .env and used as an image tag, so check the
# characters first: `case` patterns are globs, not anchored regexes, so a shape
# test alone would let "v1.0.0; rm -rf /" through on the trailing *.
case "$target" in
  *[!A-Za-z0-9.-]*)
    echo "Not a release name: $target (letters, digits, dots and dashes only)" >&2
    exit 1
    ;;
esac
case "$target" in
  latest) ;;
  v[0-9]*) ;;
  *) echo "Not a release name: $target (expected something like v1.2.3, or latest)" >&2; exit 1 ;;
esac

if [ "$current" = "$target" ]; then
  echo "Already pinned to $target — re-pulling in case the images or Compose file moved."
else
  # .env holds CREDENTIAL_ENCRYPTION_KEY and the other secrets; keep the old
  # copy and write the new one out whole rather than editing in place.
  cp .env .env.bak
  chmod 600 .env.bak
  if grep -qE '^FALCON_VERSION=' .env.bak; then
    sed "s|^FALCON_VERSION=.*|FALCON_VERSION=$target|" .env.bak > .env.tmp
  else
    cat .env.bak > .env.tmp
    printf 'FALCON_VERSION=%s\n' "$target" >> .env.tmp
  fi

  # Refuse to install a file that lost the pin or lost lines.
  if [ "$(get FALCON_VERSION .env.tmp)" != "$target" ]; then
    rm -f .env.tmp
    echo "Refusing to write .env: the version line did not come out as expected." >&2
    echo "Your .env is untouched." >&2
    exit 1
  fi
  mv .env.tmp .env
  chmod 600 .env
  echo "FALCON_VERSION: ${current:-unset} -> $target   (previous .env saved as .env.bak)"
fi

# ── Roll the stack ──────────────────────────────────────────────────────────
echo
echo "Pulling images"
docker compose pull
echo
echo "Starting"
docker compose up -d

echo
echo "Now running:"
docker compose images 2>/dev/null | grep -i falcon-builder || true
echo
echo "Check the services with: docker compose ps"
