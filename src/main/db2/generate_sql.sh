#!/bin/bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -T) TARGET_TABLE="${2:?}"; shift 2;; # required
    -O) OUT_DIR="${2:?}"; shift 2;;
    -M) MASK_FILE="${2:?}"; shift 2;;
    -C) CHUNK_ROWS="${2:?}"; shift 2;;
  esac
done

# -Tオプション（テーブル名）が指定されていない場合はエラー終了
if [ -z "${TARGET_TABLE:-}" ]; then
  echo "[ERROR] -T オプション（テーブル名）が指定されていません。"
  exit 1
fi

# 件数取得（WITH UR で読み取り）
COUNT_QUERY="SELECT COUNT(*) FROM ${TARGET_TABLE} WITH UR"
COUNT_RESULT=$(db2 -x "$COUNT_QUERY")
DB2_RC=$?
if [ ${DB2_RC} -ne 0 ]; then
  echo "[ERROR] COUNT 実行に失敗しました。テーブル: ${TARGET_TABLE}"
  db2 connect reset
  exit 1
fi
echo "テーブル${TARGET_TABLE}の取得件数：${COUNT_RESULT}"

# カラム一覧取得
COLUMNS_QUERY="SELECT COLNAME
  FROM SYSCAT.COLUMNS
  WHERE TABNAME = '${TARGET_TABLE}'
  ORDER BY COLNO
  WITH UR"
COLUMNS_RESULT=$(db2 -x "$COLUMNS_QUERY")
DB2_RC_COLS=$?
if [ ${DB2_RC_COLS} -ne 0 ]; then
  echo "[ERROR] カラム一覧取得に失敗しました。テーブル: ${TARGET_TABLE}"
  db2 connect reset
  exit 1
fi
# カラム名をカンマ区切りで連結

COLUMNS_CSV=$(echo "$COLUMNS_RESULT" | paste -sd, -)

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

# クエリー分割
CHUNK_COUNT=$(( (COUNT_RESULT + CHUNK_ROWS - 1) / CHUNK_ROWS ))
for ((i=1; i<=CHUNK_COUNT; i++)); do

    # 範囲計算
    START=$(( (i - 1) * CHUNK_ROWS + 1 ))
    END=$(( i * CHUNK_ROWS ))
    # ENDは常にチャンクサイズ分進める（最終チャンクはCOUNT_RESULTを超える場合もあり）
    #echo "[LOOP $i/$CHUNK_COUNT] $COLUMNS_CSV ($START-$END)"


    BASEQUERY="WITH BASE AS ( SELECT $COLUMNS_CSV, ROW_NUMBER() OVER (ORDER BY $COLUMNS_CSV) AS RN FROM ${TARGET_TABLE} )"
    EXEQUERY="SELECT $MASKED_COLUMNS FROM BASE WHERE RN BETWEEN $START AND $END ORDER BY RN WITH UR"

    FULLQUERY="${BASEQUERY} ${EXEQUERY}"
    echo "$FULLQUERY" > output_${TARGET_TABLE}_${START}_${END}.sql
done