# docker-build

Eigene Docker-Images für meine Server, automatisch gebaut mit GitHub Actions und veröffentlicht in der GitHub Container Registry (GHCR).

> **English summary:** Personal Docker images, built automatically with GitHub Actions and published on GHCR:
> a Caddy build with the Cloudflare DNS module (for ACME DNS challenges / wildcard certificates) and PHP-FPM images (8.5, 8.6) on Alpine with mysqli, pdo_mysql, gd and zip.
> Images are rebuilt when their base image changes. Every new upstream version gets a [release](../../releases) listing the exact component versions.
> Public and free to use, but maintained for my own setup – no support, no guarantees.

## Übersicht

| Image | Basis | Plattformen | Ordner / Workflow |
|---|---|---|---|
| [`ghcr.io/ricosweb/caddy-cloudflare`](https://github.com/ricosweb/docker-build/pkgs/container/caddy-cloudflare) | `caddy:2` | amd64, arm64, arm/v7 | [`caddy/`](caddy/) · [`caddy-build.yml`](.github/workflows/caddy-build.yml) |
| [`ghcr.io/ricosweb/custom_php8.5_image`](https://github.com/ricosweb/docker-build/pkgs/container/custom_php8.5_image) | `php:8.5-fpm-alpine` | amd64, arm64, arm/v7 | [`Dockerfile`](Dockerfile) · [`docker-build.yml`](.github/workflows/docker-build.yml) |
| [`ghcr.io/ricosweb/custom_php8.6_image`](https://github.com/ricosweb/docker-build/pkgs/container/custom_php8.6_image) | `php:8.6-fpm-alpine` | amd64, arm64 | [`php86/`](php86/) · [`docker-build-php86.yml`](.github/workflows/docker-build-php86.yml) |

Welche Versionen genau in einem Image stecken, steht in den **[Releases](../../releases)**.

## Tags

| Tag | Bedeutung |
|---|---|
| `latest` | aktueller Build – wird bei jedem Neubau überschrieben |
| Caddy: `v2.x.y` | letzter Build mit dieser Caddy-Version |
| Caddy: `v2.x.y-cf-v0.x.y` | Caddy-Version + Version des Cloudflare-Moduls |
| PHP: `8.5.x` / `8.6.x` | letzter Build mit dieser PHP-Version |

Für ein Zurückgehen auf eine ältere Version den festen Tag statt `latest` verwenden.

## Wann wird gebaut?

- **Bei Änderungen** an den Dateien des jeweiligen Images (Push auf `main`) oder von Hand (*Actions → Run workflow*).
- **Täglich** prüft jeder Workflow, ob das offizielle Basis-Image neuer ist als das eigene Image (Vergleich über das OCI-Label `org.opencontainers.image.base.digest`). Nur dann wird neu gebaut – so kommen Sicherheitsupdates von Alpine, PHP und Caddy automatisch mit.
- **Caddy zusätzlich sonntags**, auch ohne neues Basis-Image, damit Updates des Cloudflare-Moduls mitkommen.

Nach jedem Build liest der Workflow die Versionen **aus dem fertigen Image** aus, setzt die festen Tags und legt ein **Release** an – aber nur, wenn sich die Hauptversion geändert hat (Caddy oder Cloudflare-Modul bzw. PHP). Reine Neubauten wegen eines neuen Basis-Images erzeugen kein Release.

---

## Caddy mit Cloudflare-DNS

[Caddy](https://caddyserver.com) mit dem Modul [`caddy-dns/cloudflare`](https://github.com/caddy-dns/cloudflare). Damit kann Caddy Let's-Encrypt-Zertifikate per **DNS-Challenge** holen – auch Wildcard-Zertifikate (`*.example.com`) und für Server, die aus dem Internet nicht erreichbar sind.

**Aufbau** ([`caddy/Dockerfile`](caddy/Dockerfile)):

1. Build-Stufe `caddy:2-builder` baut mit `xcaddy` ein Caddy-Binary inklusive Cloudflare-Modul – nativ per Go-Cross-Compile für jede Zielplattform (schneller als unter QEMU).
2. Das Binary ersetzt `/usr/bin/caddy` im offiziellen `caddy:2`-Image. Alles andere (Pfade, Benutzer, Standard-Befehl) bleibt wie im offiziellen Image.
3. Selbsttest beim Bauen: `caddy list-modules` muss `dns.providers.cloudflare` enthalten, sonst schlägt der Build fehl.

**Benutzung** (Beispiel):

```yaml
services:
  caddy:
    image: ghcr.io/ricosweb/caddy-cloudflare:latest
    restart: unless-stopped
    ports: ["80:80", "443:443"]
    environment:
      - CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}   # Token mit „Zone → DNS → Edit“
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./data:/data
      - ./config:/config
```

```caddyfile
*.example.com {
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
    @app host app.example.com
    handle @app {
        reverse_proxy app:8080
    }
}
```

Prüfen, ob das Modul enthalten ist: `docker run --rm ghcr.io/ricosweb/caddy-cloudflare caddy list-modules | grep cloudflare`

---

## PHP-FPM (8.5 / 8.6)

Offizielles `php:8.x-fpm-alpine` mit den Erweiterungen und Einstellungen, die typische PHP-Websites (z. B. mit MariaDB/MySQL) brauchen. Gedacht als PHP-FPM-Backend hinter nginx oder Caddy.

**Zusätzliche Erweiterungen:**

| Erweiterung | Zweck |
|---|---|
| `mysqli`, `pdo_mysql` | MariaDB/MySQL |
| `gd` (mit FreeType, JPEG, WebP) | Bildbearbeitung |
| `zip` | ZIP-Archive |
| OPcache mit JIT (`tracing`) | Geschwindigkeit |

**Einstellungen** (`/usr/local/etc/php/conf.d/custom-limits.ini`):

| Einstellung | Wert |
|---|---|
| `upload_max_filesize` / `post_max_size` | 256M |
| `memory_limit` | 512M |
| `date.timezone` | Europe/Berlin |
| `expose_php` | Off |
| OPcache | an, 128 MB, `revalidate_freq=0` (Änderungen an PHP-Dateien wirken sofort), JIT-Puffer 64M |

Die vollständige Liste der geladenen Erweiterungen und Bibliotheksversionen (GD, libzip, libpng, libwebp …) steht im jeweiligen [Release](../../releases).

**Benutzung** (Beispiel):

```yaml
services:
  php:
    image: ghcr.io/ricosweb/custom_php8.5_image:latest
    restart: unless-stopped
    volumes:
      - ./website:/var/www/html
  nginx:
    image: nginx:alpine
    # fastcgi_pass php:9000;
```

PHP 8.6 gibt es (noch) nicht für arm/v7, weil das offizielle Basis-Image diese Plattform nicht anbietet.

---

## Hinweise

- Die Images sind öffentlich und dürfen gern genutzt werden, sind aber auf meine eigene Umgebung zugeschnitten. Es gibt keinen Support und keine Garantie.
- Wer sie produktiv nutzt, sollte einen festen Versions-Tag statt `latest` verwenden.
- Basis sind die offiziellen Images [`caddy`](https://hub.docker.com/_/caddy) und [`php`](https://hub.docker.com/_/php); deren Lizenzen gelten entsprechend.
