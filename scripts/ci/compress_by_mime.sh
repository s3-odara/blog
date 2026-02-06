#!/bin/sh
set -eu

ROOT_DIR=${1:-public}

if [ ! -d "$ROOT_DIR" ]; then
  echo "Directory not found: $ROOT_DIR" >&2
  exit 1
fi

# MIME types we consider effective to precompress. 
# Keep this list explicit to avoid compressing already-compressed binaries.
find "$ROOT_DIR" -type f ! \( -name '*.gz' -o -name '*.br' \) -exec sh -c '
  should_compress() {
    case "$1" in
      text/*) return 0 ;;
      application/javascript) return 0 ;;
      application/x-javascript) return 0 ;;
      application/json) return 0 ;;
      application/xml) return 0 ;;
      application/rss+xml) return 0 ;;
      application/atom+xml) return 0 ;;
      application/xhtml+xml) return 0 ;;
      image/svg+xml) return 0 ;;
      application/wasm) return 0 ;;
      *) return 1 ;;
    esac
  }

  mime_type() {
    # GNU file: --mime-type
    # BSD file: -I (例: "text/plain; charset=us-ascii")
    if mime=$(file -b --mime-type -- "$1" 2>/dev/null); then
      :
    else
      mime=$(file -bI -- "$1" 2>/dev/null || file -I -- "$1" 2>/dev/null)
      mime=${mime%%;*}
    fi
    printf "%s\n" "$mime"
  }

  for path do
    mime=$(mime_type "$path")
    if should_compress "$mime"; then
      gzip -f -k -- "$path"
      brotli -f -k -- "$path"
    fi
  done
' sh {} +
