# File storage on a self-hosted Falcon Builder

A self-hosted (Community edition) instance keeps its files in an
**S3-compatible bucket you operate**. Nothing is stored in Falcon Builder's
Supabase project, and there is no fallback to it: if storage is not
configured, uploads fail with an error that names the missing variables.

What lives in this bucket:

- Knowledge-base documents: files people upload to an agent, and pages
  scraped or synced from URL, Google Drive, SharePoint, and similar sources
- Media attached to messages in published interfaces (images, documents)
- Attachments on inbound emails that start email-trigger workflows

Not affected: an agent's optional **AWS S3 storage mode**, where a customer's
own bucket is connected through a credential for HIPAA-style isolation. That
feature is unchanged and separate.

## Choosing a store

Any service that speaks the S3 API works. The common choices:

| Store | When to pick it | Notes |
|---|---|---|
| **MinIO** | Running everything on your own hardware or a single VM | Ships as one container; the Docker Compose below includes it |
| **AWS S3** | Already on AWS | Use an IAM role or an access key scoped to one bucket |
| **Cloudflare R2** | Want zero egress fees | S3-compatible endpoint; set `STORAGE_S3_REGION=auto` |
| **Backblaze B2, Wasabi, DigitalOcean Spaces, Hetzner** | Cost-sensitive hosted storage | All expose an S3 endpoint; path-style is usually required |

## Environment variables

Set these for **both** the web app and the worker. The web app issues upload
and download links and stores interface media; the worker stages scraped
pages and reads documents back for processing.

```bash
STORAGE_S3_BUCKET=falcon                # required — one bucket for everything
STORAGE_S3_ENDPOINT=http://minio:9000   # unset for AWS S3; set for everything else
STORAGE_S3_REGION=us-east-1             # default us-east-1; "auto" for R2
STORAGE_S3_ACCESS_KEY_ID=...            # optional as a pair (IAM role on AWS)
STORAGE_S3_SECRET_ACCESS_KEY=...
STORAGE_S3_FORCE_PATH_STYLE=            # default: true when an endpoint is set
STORAGE_S3_PUBLIC_URL=                  # optional, see "Public links" below
STORAGE_S3_PUBLIC_ENDPOINT=             # optional, see "The endpoint browsers reach" below
```

Inside the bucket, Falcon uses two key prefixes, `agent-knowledge/` and
`workflow-files/`. You don't create them; they appear with the first upload.

### MinIO with Docker Compose

A minimal service definition to sit next to the Falcon containers:

```yaml
services:
  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: change-me
    volumes:
      - minio-data:/data
    ports:
      - "9000:9000"   # S3 API
      - "9001:9001"   # web console

volumes:
  minio-data:
```

Then, once:

1. Open the console at `http://<host>:9001`, sign in with the root user.
2. Create a bucket named `falcon`.
3. Create an access key (Identity → Access Keys) rather than using the root
   credentials in the app.
4. Set the variables above with `STORAGE_S3_ENDPOINT=http://minio:9000` (the
   Compose service name resolves inside the network).

## The endpoint browsers reach

Upload and download links are **presigned URLs**: the app signs them and the
browser talks to the bucket directly. A presigned URL names the bucket's host,
and the signature covers it, so the host the app signs for must be one the
browser can open.

That is a problem when the app and the store share a private network. In the
Compose stack the app reaches MinIO as `http://minio:9000`, which no browser
can resolve. `STORAGE_S3_PUBLIC_ENDPOINT` is the answer: set it to the
address browsers use (for example `https://falcon.example.com:9000`, or
`http://localhost:9000` on a laptop) and presigned URLs are signed against
that host, while every server-side operation keeps using
`STORAGE_S3_ENDPOINT`. Both must front the same bucket. Leave it unset when
the store is already public (AWS S3, R2), where the two are the same.

## Browser uploads and CORS

Knowledge-base uploads go **directly from the browser to the bucket** using a
short-lived signed URL, so large files never pass through the app server.
That means the bucket must accept cross-origin `PUT` requests from the
Falcon web app's origin.

**MinIO** allows this by default. Nothing to do.

**AWS S3** needs a CORS configuration on the bucket (Permissions → CORS):

```json
[
  {
    "AllowedOrigins": ["https://falcon.example.com"],
    "AllowedMethods": ["PUT", "GET"],
    "AllowedHeaders": ["Content-Type"],
    "MaxAgeSeconds": 3000
  }
]
```

Replace the origin with your instance's URL. **R2** and the other hosted
stores have an equivalent CORS setting in their dashboards; the same three
values (origin, `PUT`/`GET`, `Content-Type`) are all that's needed.

The symptom of missing CORS is an upload that fails in the browser after the
app returned an upload URL successfully. The browser console shows a CORS
error on the `PUT`.

## Public links

Most files are read back by Falcon itself and never need a public URL.
One exception: attachments on inbound emails are handed to the workflow as
links, so the workflow (or whatever it forwards them to) can fetch them.

- **Default**: Falcon issues a presigned URL valid for 7 days, the longest
  S3 signatures allow. No bucket configuration needed.
- **`STORAGE_S3_PUBLIC_URL`**: if you would rather serve those objects from a
  public prefix (a CDN in front of the bucket, or a bucket with public read
  on `workflow-files/`), set this to the base URL and Falcon builds plain
  links as `<base>/workflow-files/<path>`. You are responsible for making
  that prefix readable.

## Verifying it works

1. Start the app with the variables set.
2. Open any agent's **Knowledge** tab and upload a small text file. It should
   move from *Pending* to *Ready* within a minute; that round-trip exercises
   the signed upload from the browser, the existence check, and the worker's
   download for processing.
3. Look in the bucket: the file is under `agent-knowledge/<workspace
   id>/<agent id>/`.

If the upload URL request fails with `Platform object storage is not
configured: set ...`, a required variable is empty. If the browser upload
fails, see CORS above. If the document stays *Pending*, the worker cannot
reach the endpoint: confirm the worker container has the same variables and
network access to the store.

## Reference: what each edition uses

| | Cloud (falconbuilder.dev) | Community (self-hosted) |
|---|---|---|
| Platform files | Supabase Storage, operated by Falcon Builder | Your S3-compatible bucket, always |
| Per-agent AWS S3 mode | Available | Available (unchanged) |

The backend choice is made in one place in the application, and the
community edition ignores `STORAGE_BACKEND` so it can never be pointed at
Supabase Storage.
