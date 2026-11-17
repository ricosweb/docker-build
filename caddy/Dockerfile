# Caddy mit Cloudflare-DNS-Modul (für DNS-Challenge / Wildcard-Zertifikate)
# Gebaut wird nativ auf dem Build-Rechner und per Go-Cross-Compile für jede
# Zielplattform – schneller als ein Build unter QEMU.

FROM --platform=$BUILDPLATFORM caddy:2-builder AS builder
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH GOARM=${TARGETVARIANT#v} \
    xcaddy build \
      --with github.com/caddy-dns/cloudflare \
      --output /caddy

FROM caddy:2
COPY --from=builder /caddy /usr/bin/caddy

# Kurzer Selbsttest beim Bauen: Modul muss enthalten sein
RUN caddy list-modules | grep -q '^dns.providers.cloudflare$'
