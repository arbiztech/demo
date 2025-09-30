#!/bin/ksh
###############################################################################
# db_count.ksh
# 目的: 既存の接続方式(mask_db_export.kshと同等)でDB2に接続し、
#       引数のテーブルに対して SELECT COUNT(*) を実行して結果を出力する。
# 使い方: db_count.ksh テーブル名(スキーマ.テーブル も可)
# 戻り値: 0 正常 / 100 DBエラー / 200 スクリプトエラー
###############################################################################

# 共通設定ロード
MASK_HOME=/home/db2inst1 #`dirname $0`/..
#. `dirname $0`/mask_db_env.ksh

USAGE="使用方法：db_count.ksh テーブル名(例: APP.CUSTOMER)"

if [ -z "$1" ]; then
  echo "$USAGE"
  exit $RC_SCRIPT_ERROR
fi

TARGET_TABLE="$1"

# 設定ファイル読み込み（DB接続情報）
. ${MASK_HOME}/conf/mask_db.conf

# DB名チェック
if [ -z "${EXPORT_DATABASE}" ]; then
  echo "[ERROR] 抽出元データベース名(EXPORT_DATABASE)が未設定です。"
  exit $RC_SCRIPT_ERROR
fi

# 接続文字列組み立て（mask_db_export.ksh と同等方針）
CONNECT="connect to ${EXPORT_DATABASE}"
if [ ! -z "${EXPORT_USER}" ]; then
  CONNECT="${CONNECT} user ${EXPORT_USER}"
  if [ ! -z "${EXPORT_PASSWORD}" ]; then
    CONNECT="${CONNECT} using ${EXPORT_PASSWORD}"
  fi
fi

# 接続実行（パスワードコマンド対応）
RC=0
if [ ! -z "${EXPORT_USER}" -a ! -z "${GET_PASSWORD_COMMAND}" -a -z "${EXPORT_PASSWORD}" ]; then
  db2 "${CONNECT} using $(${GET_PASSWORD_COMMAND} ${EXPORT_USER})"
  RC=$?
else
  db2 "${CONNECT}"
  RC=$?
fi

if [ ${RC} -ne 0 ]; then
  echo "[ERROR] DB接続に失敗しました。"
  exit $RC_DB_ERROR
fi

# スキーマ設定（任意）
if [ ! -z "${EXPORT_SCHEMA}" ]; then
  db2 "set schema ${EXPORT_SCHEMA}"
  if [ $? -ne 0 ]; then
    echo "[ERROR] スキーマ設定に失敗しました。"
    db2 connect reset
    exit $RC_DB_ERROR
  fi
fi
