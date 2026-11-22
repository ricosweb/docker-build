#!/usr/bin/env bash
# Liest nach dem Build die Versionen aus einem PHP-Image, setzt einen Versions-Tag
# (z. B. :8.5.3) und legt ein GitHub-Release an – aber nur, wenn sich die PHP-Version
# geändert hat. Reine Neubauten (neues Alpine-Basis-Image) erzeugen kein Release.
#
# Aufruf: php-release.sh <image> <serie>   z. B. ghcr.io/ricosweb/custom_php8.5_image 8.5
# Ausgaben (GITHUB_OUTPUT): php, alpine, tag, neu=true|false
set -euo pipefail
IMAGE="$1"; SERIE="$2"

docker pull -q "$IMAGE:latest" >/dev/null
run() { docker run --rm --entrypoint sh "$IMAGE:latest" -c "$1"; }

php=$(run 'php -r "echo PHP_VERSION;"')
alpine=$(run 'cat /etc/alpine-release')
if [ -z "$php" ]; then echo "::error::PHP-Version nicht ermittelt"; exit 1; fi

# Erweiterungen und Bibliotheken
module=$(run 'php -m' | grep -v '^\[' | grep -v '^$' | sort -f | paste -sd ',' - | sed 's/,/, /g')
details=$(run 'php -r '"'"'
  $gd = function_exists("gd_info") ? gd_info()["GD Version"] : "-";
  $zip = class_exists("ZipArchive") ? ZipArchive::LIBZIP_VERSION : "-";
  $mysql = function_exists("mysqli_get_client_info") ? mysqli_get_client_info() : "-";
  $jit = ini_get("opcache.jit") ?: "-";
  echo "| GD | `$gd` |\n| libzip | `$zip` |\n| mysqlnd | `$mysql` |\n| OPcache JIT | `$jit` |\n";
'"'")
pakete=$(run 'apk list --installed 2>/dev/null' | grep -E '^(libpng|libjpeg-turbo|libwebp|freetype|libzip|openssl|curl|icu-libs)-[0-9]' \
  | awk '{print $1}' | sort | sed -E 's/^(.+)-([0-9][^-]*-r[0-9]+)$/| \1 | `\2` |/')
digest=$(docker buildx imagetools inspect "$IMAGE:latest" --format '{{json .Manifest.Digest}}' | tr -d '"')

tag="php-${php}"
echo "php=$php" >> "$GITHUB_OUTPUT"
echo "alpine=$alpine" >> "$GITHUB_OUTPUT"
echo "tag=$tag" >> "$GITHUB_OUTPUT"

# Zusätzlicher Image-Tag mit genauer Version, zum gezielten Zurückgehen
docker buildx imagetools create -t "$IMAGE:$php" "$IMAGE:latest"

if gh release view "$tag" >/dev/null 2>&1; then
  echo "Release $tag gibt es schon – nur Neubau (z. B. neues Basis-Image), kein neues Release."
  echo "neu=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

vorher=$(gh release list --limit 100 --json tagName \
  --jq "[.[] | select(.tagName | startswith(\"php-${SERIE}.\"))][0].tagName // \"\"")
minor=$(echo "$php" | cut -d. -f1-3)
{
  echo "PHP $SERIE (FPM, Alpine) mit mysqli, pdo_mysql, gd und zip, gebaut am $(date -u +%d.%m.%Y)."
  echo
  echo "| Komponente | Version |"
  echo "|---|---|"
  echo "| PHP | [\`$php\`](https://www.php.net/ChangeLog-${SERIE%%.*}.php#$minor) |"
  echo "| Alpine (Basis) | \`$alpine\` |"
  echo "$details"
  echo "$pakete"
  echo
  echo "**Geladene Erweiterungen:** $module"
  echo
  [ -n "$vorher" ] && echo "Vorheriges Release: \`$vorher\`" && echo
  echo "**Image:** \`$IMAGE:latest\` · fest: \`$IMAGE:$php\`"
  echo
  echo "Digest: \`$digest\`"
} > notes.md
cat notes.md
gh release create "$tag" --title "PHP $php" --notes-file notes.md --target "$GITHUB_SHA"
echo "neu=true" >> "$GITHUB_OUTPUT"
