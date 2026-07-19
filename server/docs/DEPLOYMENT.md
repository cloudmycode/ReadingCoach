# ReadingCoach Server Deployment

## Overview

This project includes a lightweight deployment script for the Go server.

- Binary name: `readingcoach-server`
- Default port: `18081`
- Production domain: `readingcoach.jingjiangke.com`
- Reason for port choice: keep it separate from common local service ports and reduce the chance of conflicting with `photocleaner-ios`

## Directory Layout

The deployment script creates these directories automatically:

```text
server/release/build
server/release/dist
server/release/runtime
```

Runtime files:

- binary: `server/release/dist/readingcoach-server`
- env: `server/release/runtime/.env.production`
- log: `server/release/runtime/readingcoach-server.log`
- pid: `server/release/runtime/readingcoach-server.pid`

## First-Time Setup

```bash
cd server
chmod +x scripts/deploy.sh scripts/install-systemd.sh
./scripts/deploy.sh build
```

Then edit:

```bash
server/release/runtime/.env.production
```

Minimum required values:

- `DATABASE_DSN`
- `JWT_SECRET`
- `DEEPSEEK_API_KEY`
- `MICROSOFT_TTS_KEY`
- `MICROSOFT_TTS_REGION`

## Manual Run

```bash
cd server
./scripts/deploy.sh start
./scripts/deploy.sh status
./scripts/deploy.sh stop
./scripts/deploy.sh restart
```

## Systemd Setup

On Linux servers that use `systemd`:

```bash
cd server
sudo ./scripts/install-systemd.sh
```

Useful commands:

```bash
sudo systemctl status readingcoach-server
sudo systemctl restart readingcoach-server
sudo journalctl -u readingcoach-server -f
```

## Nginx Reverse Proxy

Recommended production topology:

- `nginx` listens on `80` and `443`
- `readingcoach-server` listens on `127.0.0.1:18081`
- public domain: `readingcoach.jingjiangke.com`

Example nginx site config:

```nginx
server {
    listen 80;
    server_name readingcoach.jingjiangke.com;

    client_max_body_size 20m;

    location / {
        proxy_pass http://127.0.0.1:18081;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

HTTPS can be added with Certbot after DNS is pointed to the server:

```bash
sudo certbot --nginx -d readingcoach.jingjiangke.com
```

If you want the Go service to be internal-only, set:

```bash
SERVER_HOST=127.0.0.1
SERVER_PORT=18081
```

## Notes

- The script builds a Linux `amd64` binary by default.
- Audio and other attachment files are stored under `ATTACHMENTS_DIR`.
- The current client flow uploads text only, so no image upload service is required anymore.
- For local config-file mode, a simple default attachment path is `server/attachments`.
