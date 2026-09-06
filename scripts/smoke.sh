#!/usr/bin/env bash
# Smoke test for a running stack: the sign-in flows over HTTP, the way the
# app's own pages make them. Used by .github/workflows/smoke.yml against the
# published images; runs against any instance:
#
#   BASE=http://localhost:3000 MAILPIT=http://localhost:8025 scripts/smoke.sh
#
# MAILPIT is optional; without it the password-reset email check is skipped.
set -u
BASE="${BASE:-http://localhost:3000}"
MAILPIT="${MAILPIT:-}"
J="$(mktemp -d)"; trap 'rm -rf "$J"' EXIT
pass=0; fail=0
check() { if eval "$2"; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1  -> $3"; fail=$((fail+1)); fi; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
hdr()  { curl -s -D - -o /dev/null "$@" | tr -d '\r'; }
stamp="$(date +%s)"
ADA="ada-$stamp@example.com"

echo "## reachable"
check "handler answers"                 "[ \"\$(code $BASE/api/auth-community/ok)\" = 200 ]" "$(code $BASE/api/auth-community/ok)"
r=$(hdr "$BASE/dashboard");             check "private page -> /login" "grep -q '^HTTP/[0-9.]* 30[27]' <<<\"\$r\" && grep -qi 'location: .*/login' <<<\"\$r\"" "$(head -3 <<<"$r" | tr '\n' ' ')"
check "cloud-only API -> 404"           "[ \"\$(code $BASE/api/stripe/x)\" = 404 ]" "$(code $BASE/api/stripe/x)"
check "login page -> 200"               "[ \"\$(code $BASE/login)\" = 200 ]" "$(code $BASE/login)"

echo "## first user"
r=$(curl -s -c "$J/a.jar" -H 'content-type: application/json' -d "{\"email\":\"$ADA\",\"password\":\"correct-horse-battery\",\"name\":\"Ada\"}" "$BASE/api/auth/signup" -w ' HTTP:%{http_code}')
if grep -q 'HTTP:403' <<<"$r"; then
  echo "SKIP  signup: this instance already has a workspace (invitation-only); using login checks only"
  first=0
else
  check "signup -> 200 with cookie"     "grep -q 'HTTP:200' <<<\"\$r\" && grep -q falcon.session_token $J/a.jar" "$r"
  first=1
fi
if [ "$first" = 1 ]; then
  r=$(curl -s -b "$J/a.jar" "$BASE/api/auth/session"); check "session live" "grep -q '\"authenticated\":true' <<<\"\$r\"" "$r"
  r=$(hdr -b "$J/a.jar" "$BASE/login");  check "signed-in /login -> /dashboard" "grep -qi 'location: .*/dashboard' <<<\"\$r\"" "$(head -3 <<<"$r" | tr '\n' ' ')"
  curl -s -b "$J/a.jar" -c "$J/a.jar" -X POST "$BASE/api/auth/logout" >/dev/null
  check "logout clears the session"     "[ \"\$(code -b $J/a.jar $BASE/api/auth/session)\" = 401 ]" "$(code -b $J/a.jar $BASE/api/auth/session)"
  r=$(curl -s -c "$J/b.jar" -H 'content-type: application/json' -d "{\"email\":\"$ADA\",\"password\":\"wrong\"}" "$BASE/api/auth/login" -w ' HTTP:%{http_code}')
  check "wrong password -> 401"         "grep -q 'HTTP:401' <<<\"\$r\"" "$r"
  r=$(curl -s -c "$J/b.jar" -H 'content-type: application/json' -d "{\"email\":\"$ADA\",\"password\":\"correct-horse-battery\"}" "$BASE/api/auth/login" -w ' HTTP:%{http_code}')
  check "login -> 200, session survives" "grep -q 'HTTP:200' <<<\"\$r\" && [ \"\$(code -b $J/b.jar $BASE/api/auth/session)\" = 200 ]" "$r"
  r=$(curl -s -H 'content-type: application/json' -d "{\"email\":\"intruder-$stamp@example.com\",\"password\":\"long-enough-password\"}" "$BASE/api/auth/signup" -w ' HTTP:%{http_code}')
  check "uninvited signup -> 403"       "grep -q 'HTTP:403' <<<\"\$r\"" "$r"

  echo "## password reset"
  r=$(curl -s -H 'content-type: application/json' -H "origin: $BASE" -d "{\"email\":\"$ADA\"}" "$BASE/api/auth/forgot-password" -w ' HTTP:%{http_code}')
  check "forgot-password -> 200"        "grep -q 'HTTP:200' <<<\"\$r\"" "$r"
  if [ -n "$MAILPIT" ]; then
    token=""
    for i in $(seq 1 20); do
      msg=$(curl -s "$MAILPIT/api/v1/search?query=to:$ADA" | grep -oE '"ID":"[^"]+"' | head -1 | cut -d'"' -f4)
      if [ -n "$msg" ]; then
        body=$(curl -s "$MAILPIT/api/v1/message/$msg" )
        token=$(grep -oE 'reset-password\?code=[A-Za-z0-9_-]+' <<<"$body" | head -1 | sed 's/.*code=//')
        [ -n "$token" ] && break
      fi
      sleep 1
    done
    check "reset email received with a code" "[ -n \"\$token\" ]" "no email in Mailpit for $ADA"
    r=$(curl -s -H 'content-type: application/json' -H "origin: $BASE" -d "{\"newPassword\":\"reset-me-please-123\",\"token\":\"$token\"}" "$BASE/api/auth-community/reset-password" -w ' HTTP:%{http_code}')
    check "reset with the code -> 200"  "grep -q 'HTTP:200' <<<\"\$r\"" "$r"
    r=$(curl -s -H 'content-type: application/json' -d "{\"email\":\"$ADA\",\"password\":\"reset-me-please-123\"}" "$BASE/api/auth/login" -w ' HTTP:%{http_code}')
    check "login with the new password" "grep -q 'HTTP:200' <<<\"\$r\"" "$r"
  else
    echo "SKIP  reset email (set MAILPIT to check it)"
  fi
fi

echo; echo "passed=$pass failed=$fail"
[ "$fail" = 0 ]
