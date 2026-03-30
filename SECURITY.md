# Security Notes

This repository is public and contains bootstrap examples only.

Do not use the example values in this repository directly in production.

Before deploying to a real VPS, make sure you replace or review at least these items:

- SSH username such as `user`
- SSH port such as `22` or `2222`
- All Xray secrets including `XRAY_UUID`, `REALITY_PRIVATE_KEY`, and `REALITY_SHORT_ID`
- Example destinations such as `www.cloudflare.com:443`
- Any copied `.env` file or shell history containing secrets

Operational recommendations:

- Treat `.env` as local-only and never commit it
- Prefer unique credentials and keys per server
- Verify SSH access in a new terminal before closing the current root session
- Review firewall rules and service ports after every SSH port change

If you reuse this repository publicly, consider forking it and updating the defaults to match your own baseline.
