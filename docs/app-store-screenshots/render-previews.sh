#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
output_dir="$script_dir/previews"

if [ ! -x "$chrome" ]; then
  echo "Google Chromeが見つかりません: $chrome" >&2
  exit 1
fi

mkdir -p "$output_dir"

slide=1
while [ "$slide" -le 6 ]; do
  padded=$(printf '%02d' "$slide")
  "$chrome" \
    --headless=new \
    --disable-gpu \
    --hide-scrollbars \
    --force-device-scale-factor=1 \
    --window-size=1320,2868 \
    --screenshot="$output_dir/$padded.png" \
    "file://$script_dir/template.html?slide=$slide"
  slide=$((slide + 1))
done

echo "プレビューを作成しました: $output_dir"
