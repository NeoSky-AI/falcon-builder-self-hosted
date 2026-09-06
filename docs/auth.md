# Sign-in on a self-hosted Falcon Builder

A self-hosted (Community edition) instance signs users in with
[Better Auth](https://www.better-auth.com), running inside the web app against
your own Postgres. Nothing about sign-in routes through Falcon Builder's cloud
or through Supabase: sessions are cookies signed with a secret you hold,
password hashes live in your database, and password-reset emails leave through
your SMTP server ([Email](./email.md)).

The rest of the application is unaware of the switch. Every route and page
keeps calling the same auth wrapper it always did; the Community build simply
resolves that wrapper to the Better Auth implementation.

## 1. Required configuration

Set these in the web app's environment.

```bash
AUTH_SECRET=...                       # required, 32+ characters — signs session cookies
NEXT_PUBLIC_APP_URL=https://falcon.example.com   # required — the public origin of your instance
```

Generate the secret once and keep it stable:

```bash
openssl rand -base64 32
```

Rotating `AUTH_SECRET` signs every user out (their cookies stop verifying);
it does not touch accounts or passwords.

`NEXT_PUBLIC_APP_URL` must be the exact origin users see in the browser,
including the scheme. It decides the cookie's `Secure` flag (https only),
the OAuth redirect URIs below, and which redirect targets sign-in trusts.

The auth tables (`community_auth_*`) are part of the ordinary schema. Apply
`packages/db/migrations/066_add_community_auth_tables.sql`, or run `prisma db
push`, as with any other migration.

If the instance starts without `AUTH_SECRET`, the first sign-in attempt fails
with an error naming the variable. The build itself does not need it.

## 2. The first user and everyone after

The Community edition runs **one workspace per instance**:

1. The **first** account to sign up creates the workspace and owns it.
2. Every later account must be **invited** from that workspace (Settings →
   Team). Signing up, or signing in with Google or Microsoft, with an
   address that has no pending invitation is refused with *"Signups on this
   instance are invitation-only. Ask a workspace admin to invite you."*
3. An invited user signs up with the invited address (any method) and lands
   in the workspace with the role the invitation carried. The invitation
   email itself goes through your SMTP server.

The rule is enforced where the user is created, so it holds for OAuth
sign-ins as well as the signup form.

## 3. Email and password

Always on. Passwords must be at least 8 characters. Users change their
password under Account settings (current password required) or through the
**Forgot password** link:

- the reset email is sent over SMTP (`SMTP_HOST`, `SMTP_FROM` and friends
  must be configured, see [Email](./email.md); without them the request is
  refused with the missing variables named),
- the link points at `<NEXT_PUBLIC_APP_URL>/reset-password?code=…`,
- the link is valid for one hour and can be used once.

Requesting a reset for an address that has no account succeeds silently, as
on the cloud edition, so the form does not reveal which addresses exist.

## 4. Google and Microsoft sign-in (optional)

The "Continue with Google" and "Continue with Microsoft" buttons appear when
the matching pair of variables is set. Each needs an OAuth app that **you**
register; there is no shared Falcon Builder app for self-hosted instances.

```bash
AUTH_GOOGLE_CLIENT_ID=...
AUTH_GOOGLE_CLIENT_SECRET=...

AUTH_MICROSOFT_CLIENT_ID=...
AUTH_MICROSOFT_CLIENT_SECRET=...
AUTH_MICROSOFT_TENANT_ID=            # optional; default "common" = any Microsoft account
```

Setting only one half of a pair is a configuration error and is reported as
such on the first sign-in attempt.

### Redirect URIs

Register these exactly, with your own origin:

| Provider | Authorized redirect URI |
|---|---|
| Google | `https://falcon.example.com/api/auth-community/callback/google` |
| Microsoft | `https://falcon.example.com/api/auth-community/callback/microsoft` |

### Google

1. Google Cloud Console → *APIs & Services* → *Credentials* → *Create
   credentials* → *OAuth client ID*, application type **Web application**.
2. Add the redirect URI above. Authorized JavaScript origin:
   `https://falcon.example.com`.
3. Configure the OAuth consent screen (external or internal). Only the
   default `openid`, `email` and `profile` scopes are requested, so no
   verification is needed for internal use.
4. Copy the client ID and secret into `AUTH_GOOGLE_CLIENT_ID` and
   `AUTH_GOOGLE_CLIENT_SECRET`.

### Microsoft

1. Entra admin center → *App registrations* → *New registration*.
2. Supported account types: pick according to who should sign in. If you
   restrict it to your tenant, also set `AUTH_MICROSOFT_TENANT_ID` to the
   tenant id; leave it unset for any Microsoft account.
3. Redirect URI (platform **Web**): the Microsoft URI above.
4. *Certificates & secrets* → new client secret. Copy the **value** (not the
   secret id) into `AUTH_MICROSOFT_CLIENT_SECRET`, and the application
   (client) id into `AUTH_MICROSOFT_CLIENT_ID`.

These are separate from the `GOOGLE_OAUTH_*` and `MICROSOFT_OAUTH_*`
variables, which connect *integration* credentials (Gmail, Calendar,
SharePoint, …) to workflow nodes. Sign-in and integrations can use the same
OAuth apps if you register both redirect URIs on them, but they are
configured independently.

## 5. Sessions

- Cookie: `falcon.session_token` (`__Secure-falcon.session_token` over
  https), `HttpOnly`, `SameSite=Lax`, lifetime 7 days, renewed on use.
- Signing out clears the cookie and deletes the session row; **Sign out**
  in the app does this for the current browser.
- Sessions are verified against the database on every request that needs
  the user. The edge middleware only checks that the cookie is present and
  redirects to `/login` when it is not; a forged or expired cookie is then
  rejected by the first API call or page, which sends the user to `/login`
  the same way.

## 6. Endpoints

Sign-in, session lookup, password reset and the Google / Microsoft callbacks
are served under `/api/auth-community/*` by the web service. The health check
Compose uses is `GET /api/auth-community/ok`; it answers only when sign-in is
configured, so an instance without `AUTH_SECRET` reports unhealthy and
`docker compose logs web` names the variable.
