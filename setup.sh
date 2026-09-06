#!/bin/sh
# Prepares .env for a self-hosted Falcon Builder.
#
#   ./setup.sh                      asks for the public URL, generates secrets
#   APP_URL=https://x.example ./setup.sh   non-interactive
#
# Safe to re-run: a value that is already set is never changed, so this only
# ever fills blanks. Needs: sh, openssl, sed, grep.
set -eu
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example"
fi

get() { grep -E "^$1=" .env | head -n 1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }

set_if_empty() { # NAME VALUE
  if [ -z "$(get "$1")" ]; then
    if grep -qE "^$1=" .env; then
      # '|' cannot appear in any value we set here
      sed -i.bak "s|^$1=.*|$1=$2|" .env && rm -f .env.bak
    else
      printf '%s=%s\n' "$1" "$2" >> .env
    fi
    echo "  set $1"
  fi
}

secret() { openssl rand -hex 32; }

# ── Public URL ──────────────────────────────────────────────────────────────
app_url="$(get APP_URL)"
if [ -z "$app_url" ]; then
  if [ -n "${APP_URL:-}" ]; then
    app_url="$APP_URL"
  elif [ -t 0 ]; then
    printf 'Public URL of this instance, as users will see it [http://localhost:3000]: '
    read -r app_url
    app_url="${app_url:-http://localhost:3000}"
  else
    app_url="http://localhost:3000"
  fi
fi
app_url="${app_url%/}"
case "$app_url" in
  http://*|https://*) ;;
  *) echo "APP_URL must start with http:// or https:// (got: $app_url)" >&2; exit 1 ;;
esac
set_if_empty APP_URL "$app_url"

scheme="${app_url%%://*}"
hostport="${app_url#*://}"; hostport="${hostport%%/*}"
host="${hostport%%:*}"
port=""
case "$hostport" in *:*) port="${hostport##*:}" ;; esac

case "$host" in
  localhost|127.0.0.1)
    set_if_empty HTTP_PORT "${port:-80}"
    set_if_empty STORAGE_URL "http://$host:9000"
    ;;
  *)
    set_if_empty HTTP_PORT 80
    set_if_empty STORAGE_URL "$scheme://$host:9000"
    ;;
esac

# ── Secrets ─────────────────────────────────────────────────────────────────
for name in AUTH_SECRET CREDENTIAL_ENCRYPTION_KEY INVITATION_TOKEN_SECRET INTERFACE_SESSION_SECRET CRON_SECRET POSTGRES_PASSWORD MINIO_ROOT_PASSWORD; do
  set_if_empty "$name" "$(secret)"
done
set_if_empty MINIO_ROOT_USER falcon
set_if_empty COMPOSE_PROFILES storage

# ── Bundled storage wiring (only fills blanks; an external bucket stays) ────
set_if_empty STORAGE_S3_BUCKET falcon
set_if_empty STORAGE_S3_ENDPOINT http://minio:9000
set_if_empty STORAGE_S3_PUBLIC_ENDPOINT "$(get STORAGE_URL)"
set_if_empty STORAGE_S3_ACCESS_KEY_ID "$(get MINIO_ROOT_USER)"
set_if_empty STORAGE_S3_SECRET_ACCESS_KEY "$(get MINIO_ROOT_PASSWORD)"

chmod 600 .env

echo
echo "Configured for $(get APP_URL)  (storage at $(get STORAGE_URL))"
if [ -z "$(get SMTP_HOST)" ]; then
  echo "Still needed in .env: SMTP_HOST and SMTP_FROM — invitations and password resets are sent over your SMTP server (docs/email.md)."
fi
if [ -z "$(get OPENAI_API_KEY)" ]; then
  echo "Recommended in .env: OPENAI_API_KEY — knowledge bases embed documents with OpenAI."
fi
echo "Then: docker compose up -d"
