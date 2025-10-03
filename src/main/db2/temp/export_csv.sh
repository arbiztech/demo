#!/bin/bash
# このスクリプトは、指定ディレクトリ内のSQLファイルを読み取り、
# DB2のEXPORT機能でCSV出力します。
# 注意: DB接続は本スクリプトの外側（別シェル）で実施してください。
#       本スクリプトは接続/切断を行いません（exe.sh と同等の使い方を想定）。
#
# 必須パラメータ:
#   -I 入力ディレクトリ（SQLファイル置き場）
#   -T テーブル名（検索キー）
#   -O 出力ファイルパス（単一モード）/ 出力ディレクトリ（複数モード）
#   -M 複数モードフラグ（ON/OFF, 1/0, true/false など）
#
# 仕様:
# - 複数モード(-M ON)のとき:
#   入力ディレクトリ内の「テーブル名*.sql」をすべて対象にし、
#   それぞれに対して CSV を作成します。出力先は -O で指定したディレクトリ配下に
#   <SQLファイル名ベース>.csv を作成します。
#   併せて generate_sql.sh の成果物に合わせ、output_<テーブル名>_*.sql も対象に含めます。
#
# - 単一モード(-M OFF)のとき:
#   入力ディレクトリ/テーブル名.sql を対象にし、-O で指定したパスにCSVを1本出力します。
#
# count.csv の出力:
# - 複数モードのとき: -O で指定した出力ディレクトリ配下に count.csv を「追記」します。
# - 単一モードのとき: -O の親ディレクトリに count.csv を「追記」します。
#   形式は 「テーブル名,エクスポート合計件数」。複数モードでは全対象SQLの合算値になります。
#
# 注意: このスクリプトは DB2 クライアントが利用できる環境で実行してください。

set -o pipefail

usage() {
  cat <<EOF
使い方: export_csv.sh -I 入力ディレクトリ -T テーブル名 -O 出力 -M ON|OFF
  -I  入力ディレクトリ（必須）
  -T  テーブル名（必須）
  -O  出力（複数モード=ONのときは出力ディレクトリ、OFFのときは出力CSVファイルパス）（必須）
  -M  複数モードフラグ（ON/OFF, 1/0, true/false）（必須）
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

# パス存在チェック
[[ -d "$INPUT_DIR" ]] || die "入力ディレクトリが存在しません: $INPUT_DIR"

MULTI_ON=0
if is_on "$MULTI_FLAG"; then
  MULTI_ON=1
fi

# ユーティリティ: 一時CLPを作って実行し、エクスポート件数を標準出力へ返す
run_export() {
  local sql_file="$1" csv_path="$2"
  local out_dir msg_path clp_path tmpdir

  out_dir="$(dirname "$csv_path")"
  msg_path="${csv_path%.*}.msg"

  # 出力先ディレクトリがなければ作成
  if [[ ! -d "$out_dir" ]]; then
    mkdir -p "$out_dir" || die "出力ディレクトリの作成に失敗: $out_dir"
  fi

  tmpdir="${TMPDIR:-/tmp}"
  clp_path="$(mktemp "$tmpdir/export_XXXXXXXX.clp")" || die "一時ファイル作成に失敗"

  {
    echo "EXPORT TO '$csv_path' OF DEL MODIFIED BY COLDEL, NOCHARDEL CODEPAGE=1208 MESSAGES '$msg_path'"
    cat "$sql_file"
    echo ";"
  } > "$clp_path"

  echo "[INFO] EXPORT 実行: SQL=$sql_file -> CSV=$csv_path" >&2
  db2 -tvf "$clp_path"
  local rc=$?
  rm -f "$clp_path"
  if [[ $rc -ne 0 ]]; then
    die "EXPORT 失敗: $sql_file (詳細: $msg_path を確認)"
  fi

  # メッセージファイルからエクスポート件数を抽出
  local count=0
  if [[ -f "$msg_path" ]]; then
    # 代表的な2パターンを許容: 
    # - "rows were exported" を含む英語メッセージ
    # - "Number of rows exported" を含む英語メッセージ
    local line
    line=$(grep -Ei "rows were exported|Number of rows exported" "$msg_path" | tail -n1)
    if [[ -n "$line" ]]; then
      count=$(echo "$line" | grep -Eo '[0-9]+' | tail -n1)
    fi
  fi
  if [[ -z "$count" || "$count" == "" ]]; then
    count=0
    echo "[WARN] エクスポート件数を特定できませんでした: $msg_path" >&2
  fi
  echo "$count"
}

if [[ $MULTI_ON -eq 1 ]]; then
  # 複数モード: -O はディレクトリである必要
  if [[ ! -d "$OUTPUT_SPEC" ]]; then
    die "複数モードでは -O は既存ディレクトリで指定してください: $OUTPUT_SPEC"
  fi

  shopt -s nullglob
  # 指定仕様: <テーブル名>*.sql
  files=("$INPUT_DIR/${TABLE_NAME}"*.sql)
  # 生成規約互換: output_<テーブル名>_*.sql も対象
  files+=("$INPUT_DIR/output_${TABLE_NAME}_"*.sql)
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
    die "対象SQLが見つかりませんでした: $INPUT_DIR/${TABLE_NAME}*.sql または output_${TABLE_NAME}_*.sql"
  fi

  # ファイル名順で安定実行
  IFS=$'\n' read -r -d '' -a sorted < <(printf '%s\n' "${unique[@]}" | sort && printf '\0')

  total=${#sorted[@]}
  idx=0
  total_count=0
  for sql in "${sorted[@]}"; do
    idx=$((idx+1))
    base="$(basename "$sql" .sql)"
    csv="$OUTPUT_SPEC/$base.csv"
    echo "[INFO] ($idx/$total) 処理中: $sql" >&2
    c=$(run_export "$sql" "$csv") || die "エクスポートに失敗しました: $sql"
    # 数値であれば加算
    if [[ "$c" =~ ^[0-9]+$ ]]; then
      total_count=$(( total_count + c ))
    fi
  done
  echo "[INFO] 完了: ${total}件のSQLをエクスポートしました (合計件数=${total_count})" >&2

  # count.csv 追記
  count_csv="$OUTPUT_SPEC/count.csv"
  echo "${TABLE_NAME},${total_count}" >> "$count_csv"
else
  # 単一モード
  sql="${INPUT_DIR}/${TABLE_NAME}.sql"
  if [[ ! -f "$sql" ]]; then
    die "単一モード: 入力ファイルが存在しません: $sql"
  fi

  # -O はファイルパス（親ディレクトリが存在すること）
  out_dir="$(dirname "$OUTPUT_SPEC")"
  [[ -d "$out_dir" ]] || die "出力先ディレクトリが存在しません: $out_dir"

  c=$(run_export "$sql" "$OUTPUT_SPEC") || die "エクスポートに失敗しました: $sql"
  echo "[INFO] 完了: $OUTPUT_SPEC にエクスポートしました (件数=${c})" >&2

  # count.csv 追記（-O の親ディレクトリ）
  count_csv="$out_dir/count.csv"
  echo "${TABLE_NAME},${c}" >> "$count_csv"
fi
