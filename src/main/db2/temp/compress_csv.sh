#!/bin/bash
# このスクリプトは、エクスポート済みCSVのファイル圧縮（gzip）を行います。
# パラメータ仕様は export_csv.sh と同一です。
#
# 必須パラメータ:
#   -I 入力ディレクトリ（CSVファイル置き場）
#   -T テーブル名（検索キー）
#   -O 出力（複数モード=ONのときは出力ディレクトリ、OFFのときは圧縮ファイルパス）
#   -M 複数モードフラグ（ON/OFF, 1/0, true/false, yes/no を受け付け）
#
# 仕様:
# - 複数モード(-M ON): 入力ディレクトリの「テーブル名*.csv」および
#   「output_テーブル名_*.csv」に一致する全CSVを、-Oで指定したディレクトリに
#   <元ファイル名>.gz として作成（元CSVは残す）。
# - 単一モード(-M OFF): 入力ディレクトリ/テーブル名.csv を、-Oで指定した
#   出力パスに作成（gzip）。
#
# 注意: 本スクリプトはDB接続を行いません。

set -o pipefail

usage() {
  cat <<EOF
使い方: compress_csv.sh -I 入力ディレクトリ -T テーブル名 -O 出力 -M ON|OFF
  -I  入力ディレクトリ（必須）
  -T  テーブル名（必須）
  -O  出力（複数モード=ONのときは出力ディレクトリ、OFFのときは圧縮ファイルパス）（必須）
  -M  複数モードフラグ（ON/OFF, 1/0, true/false, yes/no）（必須）
  -h, --help  このヘルプを表示
EOF
}

die() {
  echo "[ERROR] $*" 1>&2
  exit 1
}

is_on() {
  case "${1:-}" in
    ON|On|on|TRUE|True|true|YES|Yes|yes|1) return 0;;
    *) return 1;;
  esac
}

INPUT_DIR=""
TABLE_NAME=""
OUTPUT_SPEC=""
MULTI_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -I) INPUT_DIR="${2:?}"; shift 2;;
    -T) TABLE_NAME="${2:?}"; shift 2;;
    -O) OUTPUT_SPEC="${2:?}"; shift 2;;
    -M) MULTI_FLAG="${2:?}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "不明なオプション: $1";;
  esac
done

# 必須チェック
[[ -n "$INPUT_DIR" ]] || die "-I 入力ディレクトリは必須です"
[[ -n "$TABLE_NAME" ]] || die "-T テーブル名は必須です"
[[ -n "$OUTPUT_SPEC" ]] || die "-O 出力指定は必須です"
[[ -n "$MULTI_FLAG" ]] || die "-M 複数モードフラグは必須です (ON/OFF)"

# 入力ディレクトリ存在
[[ -d "$INPUT_DIR" ]] || die "入力ディレクトリが存在しません: $INPUT_DIR"

MULTI_ON=0
if is_on "$MULTI_FLAG"; then
  MULTI_ON=1
fi

compress_one() {
  local src_csv="$1" dst_gz="$2"
  local dst_dir
  dst_dir="$(dirname "$dst_gz")"
  [[ -d "$dst_dir" ]] || die "出力ディレクトリが存在しません: $dst_dir"

  echo "[INFO] 圧縮: $src_csv -> $dst_gz" >&2
  # 元ファイルを残すため -c を使用
  gzip -c -- "$src_csv" > "$dst_gz"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    die "gzip に失敗しました: $src_csv"
  fi
}

if [[ $MULTI_ON -eq 1 ]]; then
  # 出力は既存ディレクトリ
  [[ -d "$OUTPUT_SPEC" ]] || die "複数モードでは -O は既存ディレクトリで指定してください: $OUTPUT_SPEC"

  shopt -s nullglob
  files=("$INPUT_DIR/${TABLE_NAME}"*.csv)
  files+=("$INPUT_DIR/output_${TABLE_NAME}_"*.csv)
  shopt -u nullglob

  # 重複排除
  declare -A seen
  unique=()
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    if [[ -z "${seen[$f]:-}" ]]; then
      unique+=("$f")
      seen[$f]=1
    fi
  done

  if [[ ${#unique[@]} -eq 0 ]]; then
    die "対象CSVが見つかりませんでした: $INPUT_DIR/${TABLE_NAME}*.csv または output_${TABLE_NAME}_*.csv"
  fi

  IFS=$'\n' read -r -d '' -a sorted < <(printf '%s\n' "${unique[@]}" | sort && printf '\0')

  total=${#sorted[@]}
  idx=0
  for csv in "${sorted[@]}"; do
    idx=$((idx+1))
    base="$(basename "$csv")"
    dst="$OUTPUT_SPEC/$base.gz"
    echo "[INFO] ($idx/$total) 処理中: $csv" >&2
    compress_one "$csv" "$dst"
  done
  echo "[INFO] 完了: ${total}件を圧縮しました" >&2
else
  # 単一モード
  csv="${INPUT_DIR}/${TABLE_NAME}.csv"
  [[ -f "$csv" ]] || die "単一モード: 入力ファイルが存在しません: $csv"

  out_dir="$(dirname "$OUTPUT_SPEC")"
  [[ -d "$out_dir" ]] || die "出力先ディレクトリが存在しません: $out_dir"

  compress_one "$csv" "$OUTPUT_SPEC"
  echo "[INFO] 完了: $OUTPUT_SPEC を作成しました" >&2
fi
