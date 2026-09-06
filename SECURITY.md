# Security

To report a vulnerability in Falcon Builder or in this deployment stack,
email **security@neosky.ai** with a description and steps to reproduce.
Please do not open a public issue for security reports. We acknowledge
reports within three business days.

Keeping a self-hosted instance secure:

- Keep `.env` private; it holds every secret the instance uses. `setup.sh`
  sets its mode to `600`.
- Back up `CREDENTIAL_ENCRYPTION_KEY` with your database backups. Every
  stored integration credential is encrypted with it; losing it orphans them.
- Update regularly (`UPGRADING.md`). Release notes flag security fixes.
- Expose only Caddy's ports (80, 443 and the storage port). No other service
  publishes a port.
