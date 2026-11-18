# LearnHarness server for the iOS app

The iOS app is a shell around the LearnHarness web UI, so it needs LearnHarness running as a
web server, plus two small extras the desktop app doesn't have:

| Path | What it does |
| --- | --- |
| `/app-login` | After you sign in (in Safari's sign-in sheet), redirects to `learnharness://login?session=…` so the app gets the session cookie |
| `/app-upload/…` | Receives attachments from the app and returns the path the agent can read |

This folder is a complete example: **Caddy** (HTTPS) → **Authelia** (login) → **LearnHarness**,
plus `upload.py` for the two paths above. LearnHarness has no login of its own; do not expose it
without the proxy in front.

## Requirements

- A Linux host with Docker and Docker Compose
- A domain name pointing at that host, ports 80 and 443 open (Caddy gets the certificate)
- About 4 GB of memory for the build (3 GB at run time)
- A Claude account for Claude Code (the model provider used here)

## Set up

```bash
cp .env.example .env            # set LH_DOMAIN
mkdir -p secrets data/data data/auth home/Bijlagen
for f in jwt_secret session_secret storage_encryption_key; do
  (umask 077; openssl rand -hex 64 > "secrets/$f")
done
sudo chown -R 1500:1500 data home   # uid of the LearnHarness and upload containers
docker compose up -d --build
./set-password.sh               # shows your password once
```

Then sign in to Claude Code inside the container, once:

```bash
docker compose exec -it learnharness claude
```

and in LearnHarness: **Settings → Providers → Claude Code**.

Open `https://<your domain>` in a browser to check, then enter the same address in the iOS app.

## Notes

- **Behind a tunnel** (for example Cloudflare Tunnel) instead of open ports: let the tunnel
  terminate HTTPS, change the site address in the `Caddyfile` to `http://{$LH_DOMAIN}`, and add
  the tunnel's address as `trusted_proxies` in Caddy's global options so `X-Forwarded-Proto`
  is believed (Authelia only sets its cookie over HTTPS).
- **Passkeys**: they work in the browser, but signing in on iOS failed with Authelia 4.39.28
  (`Client returned the "appid" extension output which was not requested`). That's why the
  example uses a password with Authelia's brute-force protection.
- **Versions** are pinned. Update LearnHarness (`LH_REF`) and the iOS app together; the app
  uses LearnHarness's internal API, which isn't stable between versions.
- **Back up** `data/`, `authelia/` and `home/`.
