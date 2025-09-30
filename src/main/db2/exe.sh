#!/bin/bash
# DB接続
. ./connect.sh || exit 1

# メイン処理
. ./generate_sql.sh || exit 1

# DB接続解除
db2 connect reset >/dev/null 2>&1

exit 0