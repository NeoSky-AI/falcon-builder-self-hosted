# Email on a self-hosted Falcon Builder

A self-hosted (Community edition) instance sends and receives email through
services **you** own. Nothing routes through Falcon Builder's own mail
providers, and there is no fallback to them: if outbound email is not
configured, sends fail with an error that names the missing variables.

There are three separate email paths. Configure the ones you need.

| Path | What it covers | What you need |
|---|---|---|
| **Transactional email** (outbound) | Workspace and agent invitations, interface OTP codes, workflow failure and approval notifications, redaction digests | An SMTP server (`SMTP_*` variables) |
| **Send Email node** (outbound, per workflow) | The "Send Email" action inside workflows | An SMTP credential in the app, or the same `SMTP_*` variables as a fallback |
| **Email trigger** (inbound) | Workflows that start when an email arrives | Your own Mailgun account and domain |

## 1. Transactional email (SMTP)

Set these in the environment of **both** the web app and the worker. The web
app sends invitations and OTP codes; the worker sends workflow notifications.

```bash
SMTP_HOST=smtp.example.com        # required
SMTP_FROM="Falcon Builder <noreply@example.com>"   # required
SMTP_PORT=587                     # default 587
SMTP_USER=postmaster@example.com  # usually required by your provider
SMTP_PASS=...                     # usually required by your provider
SMTP_SECURE=                      # "true" for implicit TLS (port 465); inferred from port 465 when unset
SMTP_TLS_REJECT_UNAUTHORIZED=     # set "false" only for a relay with a self-signed certificate
```

`SMTP_FROM` must be an address your provider allows you to send from. Most
providers require the domain to be verified (SPF and DKIM records) before
they will relay it.

### Provider examples

All of these are plain SMTP relays and work with the variables above.

| Provider | `SMTP_HOST` | `SMTP_PORT` | Notes |
|---|---|---|---|
| Mailgun | `smtp.mailgun.org` (US) or `smtp.eu.mailgun.org` (EU) | 587 | User is `postmaster@<your domain>`; password is the SMTP password from the domain settings, not your API key |
| Amazon SES | `email-smtp.<region>.amazonaws.com` | 587 | Create SMTP credentials in the SES console; they are not your IAM keys |
| Postmark | `smtp.postmarkapp.com` | 587 | User and password are both the Server API token |
| SendGrid | `smtp.sendgrid.net` | 587 | User is literally `apikey`; password is an API key |
| Google Workspace | `smtp.gmail.com` | 587 | Requires an app password on an account with 2-step verification |

### Verifying it works

1. Start the app with the variables set.
2. Go to **Settings → Team** and invite an address you control. The invitation
   email is sent through SMTP.
3. If it fails, the API response and the server log contain the error from
   the SMTP server (authentication failure, sender not allowed, connection
   refused). The message `Transactional email is not configured: set ...`
   means a required variable is empty.

For workflow notifications, enable email notifications on an agent and force
a failure in one of its workflows. The worker log shows either
`[Email] Sent via SMTP to ...` or the SMTP error.

## 2. Send Email node

Each Send Email node can select an **SMTP credential** created under
**Credentials**. That is the recommended setup: different workflows can send
from different accounts.

When a node has no credential selected, it falls back to the instance
`SMTP_*` variables above and sends from `SMTP_FROM`. Nothing else is needed
if you already configured transactional email.

## 3. Inbound email triggers (Mailgun)

The email trigger gives each workflow an address of the form
`wf-<workflow id>-<secret>@<your inbound domain>`. Mail sent to it is
received by Mailgun and forwarded to your instance's `/api/email/inbound`
endpoint, which starts the workflow.

You need a Mailgun account (the free tier is enough for low volume) and a
domain or subdomain dedicated to inbound mail, for example
`inbound.example.com`.

### Step 1: Add the domain to Mailgun

In the Mailgun dashboard, add `inbound.example.com` as a domain (receiving
only is fine). Mailgun shows the DNS records to create.

### Step 2: DNS

At your DNS provider, add the MX records Mailgun gives you for that
subdomain. They look like:

```
inbound.example.com.  MX  10  mxa.mailgun.org.
inbound.example.com.  MX  10  mxb.mailgun.org.
```

Add the TXT records Mailgun shows as well. Wait for Mailgun to report the
domain as verified before continuing.

### Step 3: Environment variables

```bash
EMAIL_INBOUND_DOMAIN=inbound.example.com     # the domain from step 1
MAILGUN_WEBHOOK_SIGNING_KEY=...              # Mailgun → Settings → Webhooks → "HTTP webhook signing key"
EMAIL_INBOUND_STATIC_SECRET=...              # any random string: openssl rand -hex 32
MAILGUN_API_KEY=...                          # optional, see below
```

`EMAIL_INBOUND_DOMAIN` is what the app shows users when they enable an email
trigger. `MAILGUN_WEBHOOK_SIGNING_KEY` lets the endpoint verify that each
delivery really came from Mailgun. `EMAIL_INBOUND_STATIC_SECRET` is a second,
independent check carried in the route URL.

`MAILGUN_API_KEY` is only needed if you want calendar invitations (`.ics`
attachments) recovered from the raw message. Without it, ordinary emails and
attachments still work.

### Step 4: Create the Mailgun route

In Mailgun, go to **Receiving → Routes → Create route** and enter:

- **Expression type**: Match Recipient
- **Recipient**: `.*@inbound.example.com`
- **Actions**: Forward, to
  `https://<your falcon host>/api/email/inbound?sig=<EMAIL_INBOUND_STATIC_SECRET>`
- Tick **Stop**.

Use the same secret you set in `EMAIL_INBOUND_STATIC_SECRET`. If you set
`MAILGUN_API_KEY` for calendar recovery, use the **Store and notify** action
with the same URL instead of Forward.

### Step 5: Test

Add an email trigger to a workflow, copy the address it shows, and send a
message to it. The workflow's execution history shows the run. Mailgun's
**Logs** page shows whether the message was accepted and whether the forward
to your endpoint succeeded, with the HTTP status your instance returned.

Common failures:

- **Mailgun shows the message but no forward**: the route expression doesn't
  match, or the route wasn't saved with Stop.
- **Forward returns 401**: `sig` in the route URL doesn't match
  `EMAIL_INBOUND_STATIC_SECRET`, or `MAILGUN_WEBHOOK_SIGNING_KEY` is wrong.
- **Forward returns 400 "Invalid recipient format"**: the address wasn't copied
  from the app, or `EMAIL_INBOUND_DOMAIN` was changed after the trigger was
  created (the local part is what matters; re-copy the address).

## Reference: what each edition uses

| | Cloud (falconbuilder.dev) | Community (self-hosted) |
|---|---|---|
| Transactional email | Resend, operated by Falcon Builder | Your SMTP server, always |
| Send Email node | Node credential, or Falcon's fallback | Node credential, or your `SMTP_*` |
| Inbound triggers | `inbound.falconbuilder.dev`, Falcon's Mailgun | Your Mailgun domain via `EMAIL_INBOUND_DOMAIN` |

The transport choice is made in one place in the application, and the
community edition ignores `EMAIL_TRANSPORT` so it can never be pointed at a
Falcon-owned service.
