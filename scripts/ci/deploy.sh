#!/bin/sh
set -euo pipefail

# dist 作成 + _headers
rm -rf dist
mkdir -p dist

# 追跡ファイルだけを展開（除外は .gitattributes の export-ignore で制御）
git archive --format=tar HEAD | tar -x -C dist

cat > dist/_headers <<'HEADERS'
/*
  Cache-Control: public, max-age=180, stale-while-revalidate=86400
HEADERS

# デプロイ（workers.dev の場合）
npx wrangler deploy

# 独自ドメインを使う場合は以下に切り替え:
# npx wrangler deploy --env prod

# 変更されたファイルの URL を Cloudflare キャッシュからパージ
# 必要な変数: CLOUDFLARE_ZONE_ID, CLOUDFLARE_API_TOKEN
CLOUDFLARE_HOSTNAME="https://www.s3-odara.net"
BEFORE_SHA="${CI_COMMIT_BEFORE_SHA:-}"
AFTER_SHA="${CI_COMMIT_SHA:-HEAD}"
if [ -z "$BEFORE_SHA" ] || [ "$BEFORE_SHA" = "0000000000000000000000000000000000000000" ]; then
  echo "BEFORE_SHA is empty/zero. Skip cache purge."
  exit 0
fi

# shallow clone で BEFORE_SHA が無い場合は追加取得
if ! git cat-file -e "$BEFORE_SHA^{commit}" 2>/dev/null; then
  git fetch --depth=200 origin "$BEFORE_SHA"
fi

# export-ignore に寄せてフィルタ
HOST="${CLOUDFLARE_HOSTNAME%/}"
git diff --name-only -z "$BEFORE_SHA" "$AFTER_SHA" -- . \
| git check-attr -z --stdin --source "$AFTER_SHA" export-ignore \
| awk -v RS='\0' '
    NR%3==1 {path=$0}
    NR%3==0 { if ($0 != "set") { printf "%s%c", path, 0 } }
  ' \
| xargs -0 -r -n 100 sh -ceu '
    host="$1"; zone="$2"; token="$3"; shift 3

    json="$(
      jq -n --arg host "$host" --args "$@" '\''
        def encpath:
          ltrimstr("/") | split("/") | map(@uri) | join("/");
        { files: $ARGS.positional | map($host + "/" + (. | encpath)) }
      '\''
    )"

    resp="$(
      curl -sS -X POST "https://api.cloudflare.com/client/v4/zones/${zone}/purge_cache" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        --data "$json"
    )"

    echo "$resp" | jq -e ".success == true" >/dev/null || { echo "$resp" >&2; exit 1; }
  ' sh "$HOST" "$CLOUDFLARE_ZONE_ID" "$CLOUDFLARE_API_TOKEN"
