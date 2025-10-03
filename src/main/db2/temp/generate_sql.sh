#!/bin/bash
# 注意: このスクリプトは「DB2に接続済み」であることを前提としています。
# 接続の開始・切断は外側のバッチ（例: exe.sh の trap など）で行ってください。
# 本スクリプト内では接続/切断は行いません。

# ヘルプ表示
usage() {
  cat <<EOF
使い方: generate_sql.sh -T テーブル名 -O 出力ディレクトリ -M マスクCSV -C チャンク行数
  -T  対象テーブル名（必須）
  -O  出力ディレクトリ（必須）
  -M  マスク定義CSV（必須）
  -C  チャンク行数（必須）
  -h, --help  このヘルプを表示
EOF
}
# エラー終了（source実行時はreturn、直接実行時はexit）
die() {
  echo "[ERROR] $*" 1>&2
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 1
  else
    exit 1
  fi
}
# 正常終了のヘルプ（source実行時はreturn 0、直接実行時はexit 0）
help() {
  usage
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
  else
    exit 0
  fi
}

# 処理開始
while [[ $# -gt 0 ]]; do
  case "$1" in
    -T) TARGET_TABLE="${2:?}"; shift 2;; # 必須
    -O) OUT_DIR="${2:?}"; shift 2;;      # 必須
    -M) MASK_FILE="${2:?}"; shift 2;;    # 必須
    -C) CHUNK_ROWS="${2:?}"; shift 2;;   # 必須
    -h|--help) help;;
    *) die "不明なオプション: $1";;
  esac
done

# 必須オプションが指定されていない場合はエラー終了
if [ -z "${TARGET_TABLE:-}" ]; then
  die "-T オプション（テーブル名）が指定されていません。"
fi
if [ -z "${OUT_DIR:-}" ]; then
  die "-O オプション（出力ディレクトリ）が指定されていません。"
fi
if [ -z "${MASK_FILE:-}" ]; then
  die "-M オプション（マスクファイル）が指定されていません。"
fi
if [ -z "${CHUNK_ROWS:-}" ]; then
  die "-C オプション（チャンク行数）が指定されていません。"
fi
# 出力ディレクトリの存在チェック（存在しなければエラー）
if [ ! -d "$OUT_DIR" ]; then
  die "出力ディレクトリが存在しません: $OUT_DIR"
fi

# 件数取得（WITH UR で読み取り）
COUNT_QUERY="SELECT COUNT(*) FROM ${TARGET_TABLE} WITH UR"
COUNT_RESULT=$(db2 -x "$COUNT_QUERY")
DB2_RC=$?
if [ ${DB2_RC} -ne 0 ]; then
  die "COUNT 実行に失敗しました。テーブル: ${TARGET_TABLE}"
fi
echo "テーブル${TARGET_TABLE}の取得件数：${COUNT_RESULT}"
# COUNT_RESULT を CSV に追記（形式: テーブル名,COUNT_RESULT）
echo "${TARGET_TABLE},${COUNT_RESULT}" >> "$OUT_DIR/count.csv"

# カラム一覧取得
COLUMNS_QUERY="SELECT COLNAME
  FROM SYSCAT.COLUMNS
  WHERE TABNAME = '${TARGET_TABLE}'
  ORDER BY COLNO
  WITH UR"
COLUMNS_RESULT=$(db2 -x "$COLUMNS_QUERY")
DB2_RC_COLS=$?
if [ ${DB2_RC_COLS} -ne 0 ]; then
  die "カラム一覧取得に失敗しました。テーブル: ${TARGET_TABLE}"
fi

# カラム名をカンマ区切りで連結
COLUMNS_CSV=""
IFS=$'\n'
for col in $COLUMNS_RESULT; do
    col_trim=$(echo "$col" | xargs)  # 前後のスペースを削除
    COLUMNS_CSV+="$col_trim,"
done
COLUMNS_CSV="${COLUMNS_CSV%,}"  # 末尾のカンマを削除

# MASK_FILEを連想配列maskに読み込む
declare -A mask
if [ -n "$MASK_FILE" ] && [ -f "$MASK_FILE" ]; then
    while IFS=, read -r key value; do
        key=$(echo "$key" | xargs)   # trim
        value=$(echo "$value" | xargs)
        mask["$key"]="$value"
    done < "$MASK_FILE"
fi

# COLUMNS_RESULTをループしてMASKED_COLUMNSを作成
MASKED_COLUMNS=""
IFS=$'\n'
for col in $COLUMNS_RESULT; do
    col_trim=$(echo "$col" | xargs)
    if [[ -n "${mask[$col_trim]}" ]]; then
        MASKED_COLUMNS+="'${mask[$col_trim]}' AS $col_trim,"
    else
        MASKED_COLUMNS+="$col_trim,"
    fi
done
MASKED_COLUMNS="${MASKED_COLUMNS%,}"  # 末尾のカンマを削除
echo "使用カラム: $MASKED_COLUMNS"

# クエリー分割し出力
CHUNK_COUNT=$(( (COUNT_RESULT + CHUNK_ROWS - 1) / CHUNK_ROWS ))
for ((i=1; i<=CHUNK_COUNT; i++)); do
    # 範囲計算
    START=$(( (i - 1) * CHUNK_ROWS + 1 ))
    END=$(( i * CHUNK_ROWS ))

    BASEQUERY="WITH BASE AS ( SELECT $COLUMNS_CSV, ROW_NUMBER() OVER (ORDER BY $COLUMNS_CSV) AS RN FROM ${TARGET_TABLE} )"
    EXEQUERY="SELECT $MASKED_COLUMNS FROM BASE WHERE RN BETWEEN $START AND $END ORDER BY RN WITH UR"

    FULLQUERY="${BASEQUERY} ${EXEQUERY}"
    echo "$FULLQUERY" > "$OUT_DIR/output_${TARGET_TABLE}_${START}_${END}.sql"
    echo "Output File output_${TARGET_TABLE}_${START}_${END}.sql"
done