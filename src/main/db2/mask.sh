#!/bin/bash
maskColumns() {
  local cols="$1"
  local mf="$2"

  if [ -z "$mf" ] || [ ! -f "$mf" ]; then
    printf '%s\n' "$cols"
    return 0
  fi

  awk -v cols="$cols" -v mf="$mf" '
function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
function normalize_col_key(s) {
  s = trim(s)
  gsub(/"/, "", s)           # ダブルクォート除去
  sub(/^.*\./, "", s)        # t.col -> col
  gsub(/[[:space:]]+/, "", s)# 空白除去
  return toupper(s)
}
function is_raw_keyword(v, up) {
  up = toupper(v)
  return (up=="NULL" || up=="CURRENT_DATE" || up=="CURRENT_TIMESTAMP")
}
function quote_or_raw(v) {
  v = trim(v)
  if (v ~ /^=/) return substr(v,2)          # =生SQL
  if (v ~ /^'\''.*'\''$/) return v          # 既に単引用で囲み済み
  if (is_raw_keyword(v)) return toupper(v)  # 非クォート系
  gsub(/\047/, "\047\047", v)           # ' -> ''
  return "\047" v "\047"                # 単引用で囲む
}
function load_mask(mf,    line,posComma,posTab,pos,col,val,key) {
  while ((getline line < mf) > 0) {
    sub(/\r$/, "", line)                                   # CR除去
    if (line ~ /^[[:space:]]*$/) continue                    # 空行
    if (line ~ /^[[:space:]]*#/) continue                    # コメント行
    posComma = index(line, ",")
    posTab   = index(line, "\t")
    if (posComma==0 && posTab==0) continue
    if (posComma==0) pos = posTab
    else if (posTab==0) pos = posComma
    else pos = (posComma < posTab ? posComma : posTab)
    col = substr(line, 1, pos-1)
    val = substr(line, pos+1)
    key = normalize_col_key(col)
    mask[key] = trim(val)
  }
  close(mf)
}

BEGIN {
  load_mask(mf)
  n = split(cols, arr, /,/)
  out = ""
  for (i=1; i<=n; i++) {
    disp = trim(arr[i])
    key  = normalize_col_key(disp)
    if (key in mask) {
      m = quote_or_raw(mask[key])
      piece = m " AS " disp
    } else {
      piece = disp
    }
    out = (out=="" ? piece : out "," piece)
  }
  print out
}'
}

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
MASKED_COLUMNS=$(maskColumns "$COLUMNS_CSV" "$MASK_FILE")

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