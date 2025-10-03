#!/bin/bash
# シンプル版: 指定したSQLをDB2のEXPORTでCSVに出力するだけのスクリプト
# 接続は外部で実施している前提（CONNECT/CONNECT RESETは行いません）
#
# 使い方:
#   export_csv_simple.sh -I <入力ディレクトリ> -T <テーブル名> -O <出力> -M <ON|OFF>
#   -I: 入力ディレクトリ（必須）
#   -T: テーブル名（検索キー。ファイル名に利用）
#   -O: 複数モード(ON)のときは出力ディレクトリ、単一モード(OFF)のときは出力CSVファイルパス
#   -M: 複数モードフラグ（ON=複数/ファイル群、OFF=単一/1ファイル）
#   -h|--help: ヘルプ
#
# 動作:
#  - 複数モード(ON): 入力ディレクトリ内の「<テーブル名>*.sql」と「output_<テーブル名>_*.sql」を対象に
#    それぞれ <出力ディレクトリ>/<SQLファイル名ベース>.csv を作成
#  - 単一モード(OFF): 入力ディレクトリ/<テーブル名>.sql を <出力CSVパス> にエクスポート
#
# 注意:
#  - .msgや件数集計などの付加機能はありません。エクスポート失敗で即終了します。
#  - SQL末尾にセミコロンが無い場合のみ付与します。

set -o pipefail

usage() {
  cat <<EOF
使い方: export_csv_simple.sh -I 入力ディレクトリ -T テーブル名 -O 出力 -M ON|OFF
  -I  入力ディレクトリ（必須）
  -T  テーブル名（必須）
  -O  出力（複数モード=ONのときは出力ディレクトリ、OFFのときは出力CSVファイルパス）（必須）
  -M  複数モードフラグ（ON/OFF, 1/0, true/false）（必須）
  -h, --help  このヘルプを表示
EOF
}

die() { echo "[ERROR] $*" 1>&2; exit 1; }

is_on() {
  case "${1:-}" in
    ON|On|on|TRUE|True|true|YES|Yes|yes|1) return 0;;
    *) return 1;;
  esac
}

# エクスポート実行関数（ヘルパー）
export_one() {
  local sql_file="$1" csv_path="$2"
  local out_dir clp tmpdir last_line last_trim

  out_dir="$(dirname "$csv_path")"
  [[ -d "$out_dir" ]] || mkdir -p "$out_dir" || die "出力ディレクトリの作成に失敗: $out_dir"

  tmpdir="${TMPDIR:-/tmp}"
  clp="$(mktemp "$tmpdir/export_XXXXXXXX.clp")" || die "一時ファイル作成に失敗"

  {
    echo "EXPORT TO '$csv_path' OF DEL MODIFIED BY COLDEL, NOCHARDEL CODEPAGE=1208"
    cat "$sql_file"
    last_line=$(tail -n 1 "$sql_file" 2>/dev/null || true)
    last_trim=$(echo "$last_line" | tr -d ' \t\r\n')
    if [[ "$last_trim" != *";" ]]; then echo ";"; fi
  } > "$clp"

  echo "[INFO] EXPORT 実行: SQL=$sql_file -> CSV=$csv_path" >&2
  db2 -tvf "$clp"
  local rc=$?
  rm -f "$clp"
  if [[ $rc -ne 0 ]]; then
    die "EXPORT 失敗: $sql_file"
  fi
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

[[ -n "$INPUT_DIR" ]]   || die "-I 入力ディレクトリは必須です"
[[ -n "$TABLE_NAME" ]]   || die "-T テーブル名は必須です"
[[ -n "$OUTPUT_SPEC" ]]  || die "-O 出力指定は必須です"
[[ -n "$MULTI_FLAG" ]]   || die "-M 複数モードフラグは必須です (ON/OFF)"
[[ -d "$INPUT_DIR" ]]    || die "入力ディレクトリが存在しません: $INPUT_DIR"

MULTI_ON=0
if is_on "$MULTI_FLAG"; then MULTI_ON=1; fi

if [[ $MULTI_ON -eq 1 ]]; then
  [[ -d "$OUTPUT_SPEC" ]] || die "複数モードでは -O は既存ディレクトリで指定してください: $OUTPUT_SPEC"

  shopt -s nullglob
  files=("$INPUT_DIR/${TABLE_NAME}"*.sql)
  files+=("$INPUT_DIR/output_${TABLE_NAME}_"*.sql)
  shopt -u nullglob

  # 実在のみ
  list=()
  for f in "${files[@]}"; do [[ -f "$f" ]] && list+=("$f"); done
  [[ ${#list[@]} -gt 0 ]] || die "対象SQLが見つかりませんでした: $INPUT_DIR/${TABLE_NAME}*.sql または output_${TABLE_NAME}_*.sql"

  # 名前順で安定実行
  IFS=$'\n' read -r -d '' -a sorted < <(printf '%s\n' "${list[@]}" | sort && printf '\0')

  total=${#sorted[@]}
  idx=0
  for sql in "${sorted[@]}"; do
    idx=$((idx+1))
    base="$(basename "$sql" .sql)"
    csv="$OUTPUT_SPEC/$base.csv"
    echo "[INFO] ($idx/$total) 処理中: $sql" >&2
    export_one "$sql" "$csv"
  done
  echo "[INFO] 完了: ${total}件のSQLをエクスポートしました" >&2
else
  sql="$INPUT_DIR/$TABLE_NAME.sql"
  [[ -f "$sql" ]] || die "単一モード: 入力ファイルが存在しません: $sql"

  out_dir="$(dirname "$OUTPUT_SPEC")"
  [[ -d "$out_dir" ]] || die "出力先ディレクトリが存在しません: $out_dir"

  export_one "$sql" "$OUTPUT_SPEC"
  echo "[INFO] 完了: $OUTPUT_SPEC にエクスポートしました" >&2
fi
totalCount=$( { cat ${OUTPUT_SPEC}/output_${TABLE_NAME}*.csv 2>/dev/null; } | wc -l )
echo "${TABLE_NAME},${totalCount}" >> "$OUTPUT_SPEC/csvCount.csv"
