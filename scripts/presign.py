#!/usr/bin/env python3
"""Print an S3 presigned URL, the way the app's AWS SDK builds one.

    scripts/presign.py PUT http://localhost:9000 falcon smoke/x.txt text/plain
    scripts/presign.py GET http://localhost:9000 falcon smoke/x.txt

Reads STORAGE_S3_ACCESS_KEY_ID / STORAGE_S3_SECRET_ACCESS_KEY (and optionally
STORAGE_S3_REGION) from the environment. Path-style addressing, SigV4,
UNSIGNED-PAYLOAD — the same shape @aws-sdk/s3-request-presigner produces.

This exists so scripts/smoke.sh can prove the bundled storage actually serves
presigned uploads. A content type passed here is *signed*, which is the part
that differs between S3 implementations: the browser must then send exactly
that header or the signature does not match. Standard library only.
"""
import datetime
import hashlib
import hmac
import os
import sys
from urllib.parse import quote, urlparse

ALGORITHM = "AWS4-HMAC-SHA256"


def sign(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode(), hashlib.sha256).digest()


def signing_key(secret: str, date: str, region: str, service: str) -> bytes:
    k = sign(("AWS4" + secret).encode(), date)
    k = sign(k, region)
    k = sign(k, service)
    return sign(k, "aws4_request")


def main() -> int:
    if len(sys.argv) < 5:
        print(__doc__, file=sys.stderr)
        return 2
    method, endpoint, bucket, key = sys.argv[1:5]
    content_type = sys.argv[5] if len(sys.argv) > 5 else ""
    expires = int(os.environ.get("PRESIGN_EXPIRES", "600"))

    access = os.environ.get("STORAGE_S3_ACCESS_KEY_ID", "")
    secret = os.environ.get("STORAGE_S3_SECRET_ACCESS_KEY", "")
    region = os.environ.get("STORAGE_S3_REGION") or "us-east-1"
    if not access or not secret:
        print("STORAGE_S3_ACCESS_KEY_ID / _SECRET_ACCESS_KEY not set", file=sys.stderr)
        return 2

    parsed = urlparse(endpoint)
    host = parsed.netloc
    now = datetime.datetime.now(datetime.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date = now.strftime("%Y%m%d")
    scope = f"{date}/{region}/s3/aws4_request"

    # Path-style: /<bucket>/<key>. Slashes in the key stay literal.
    canonical_uri = "/" + quote(f"{bucket}/{key}", safe="/~")

    headers = {"host": host}
    if content_type:
        headers["content-type"] = content_type
    signed_headers = ";".join(sorted(headers))
    canonical_headers = "".join(f"{k}:{headers[k]}\n" for k in sorted(headers))

    params = {
        "X-Amz-Algorithm": ALGORITHM,
        "X-Amz-Credential": f"{access}/{scope}",
        "X-Amz-Date": amz_date,
        "X-Amz-Expires": str(expires),
        "X-Amz-SignedHeaders": signed_headers,
    }
    canonical_qs = "&".join(
        f"{quote(k, safe='-_.~')}={quote(params[k], safe='-_.~')}" for k in sorted(params)
    )

    canonical_request = "\n".join(
        [method.upper(), canonical_uri, canonical_qs, canonical_headers,
         signed_headers, "UNSIGNED-PAYLOAD"]
    )
    to_sign = "\n".join(
        [ALGORITHM, amz_date, scope,
         hashlib.sha256(canonical_request.encode()).hexdigest()]
    )
    signature = hmac.new(
        signing_key(secret, date, region, "s3"), to_sign.encode(), hashlib.sha256
    ).hexdigest()

    print(f"{parsed.scheme}://{host}{canonical_uri}?{canonical_qs}&X-Amz-Signature={signature}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
