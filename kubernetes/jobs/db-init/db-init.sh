#!/bin/bash
# DB 초기 설정 (1회성, 여러 번 실행해도 안전)
#   1) 접속 확인  2) DB 생성  3) 앱 테이블  4) BATCH_ 테이블(없을 때만)  5) 앱 계정(DML만)
set -euo pipefail

: "${DB_HOST:?DB_HOST 필요}" "${DB_NAME:?DB_NAME 필요}"
: "${DB_ADMIN_USER:?DB_ADMIN_USER 필요}" "${DB_ADMIN_PASSWORD:?DB_ADMIN_PASSWORD 필요}"
: "${APP_DB_USER:?APP_DB_USER 필요}" "${APP_DB_PASSWORD:?APP_DB_PASSWORD 필요}"
DB_PORT="${DB_PORT:-3306}"

# 이름·비밀번호는 SQL 문장 안에 들어가므로 안전한 글자만 허용
[[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]]        || { echo "DB_NAME은 영문·숫자·_ 만"; exit 1; }
[[ "$APP_DB_USER" =~ ^[A-Za-z0-9_]+$ ]]    || { echo "APP_DB_USER는 영문·숫자·_ 만"; exit 1; }
[[ "$APP_DB_PASSWORD" =~ ^[A-Za-z0-9]{16,}$ ]] || { echo "APP_DB_PASSWORD는 영문·숫자 16자 이상"; exit 1; }

# 관리자 비밀번호는 명령 인수(-p)로 넘기지 않는다. (ps로 보임)
# 소유자만 읽을 수 있는 임시 설정 파일에 적어서 전달 → 클라이언트가 비밀번호로 서버 TLS 인증서도 확인함
umask 077
CNF="$(mktemp)"
trap 'rm -f "$CNF"' EXIT
ESCAPED_PW=$(printf '%s' "$DB_ADMIN_PASSWORD" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
printf '[client]\npassword="%s"\n' "$ESCAPED_PW" > "$CNF"
unset ESCAPED_PW
# DB_CLIENT_OPTS: TLS 옵션 등이 필요할 때만 (예: AWS RDS 인증서 옵션)
read -r -a EXTRA <<< "${DB_CLIENT_OPTS:-}"
# --defaults-extra-file 은 반드시 첫 번째 옵션이어야 함
db() { mariadb --defaults-extra-file="$CNF" --host="$DB_HOST" --port="$DB_PORT" --user="$DB_ADMIN_USER" "${EXTRA[@]}" "$@"; }

# 백엔드 src/test/resources/application-test.yml 과 같은 순서 (외래 키 때문에 순서 중요)
ORDER=(
  user.sql linked_bank_account.sql account_link_operation.sql bank_transaction.sql
  bank_transaction_match_candidate.sql identity.sql
  01_loancontract.sql 02_repayment_schedule.sql 03_contractchange.sql 04_contractaccount.sql
  recurring_settlement.sql settlement.sql payment.sql settlement_account.sql
  settlement_invitation.sql settlement_participant.sql settlement_abandonment_alert.sql
  notification.sql shedlock.sql
)

echo "[1/5] 접속 확인: $DB_HOST:$DB_PORT"
db -N -e "SELECT VERSION();"

echo "[2/5] DB 생성: $DB_NAME"
db -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

echo "[3/5] 앱 테이블 생성"
for f in "${ORDER[@]}"; do
  [[ -f "/schema/$f" ]] || { echo "  파일 없음: $f (ConfigMap sai-db-schema 확인)"; exit 1; }
  echo "  - $f"
  db "$DB_NAME" < "/schema/$f"
done
# 백엔드에 새 SQL 파일이 생겼는데 목록에 없으면 알려 줌
for p in /schema/*.sql; do
  n="$(basename "$p")"
  [[ "$n" == "batch-schema-mariadb.sql" ]] && continue
  [[ " ${ORDER[*]} " == *" $n "* ]] || echo "  ⚠️ 순서 목록에 없는 파일: $n (application-test.yml 확인 후 ORDER에 추가)"
done

echo "[4/5] Spring Batch 테이블 (BATCH_)"
if [[ -f /schema/batch-schema-mariadb.sql ]]; then
  exists="$(db -N "$DB_NAME" -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME' AND table_name='BATCH_JOB_INSTANCE';")"
  if [[ "$exists" == "0" ]]; then
    db "$DB_NAME" < /schema/batch-schema-mariadb.sql
    echo "  생성함"
  else
    echo "  이미 있음 → 건너뜀"
  fi
else
  echo "  ⚠️ batch-schema-mariadb.sql 없음 → 건너뜀 (README 참고)"
fi

echo "[5/5] 앱 계정: $APP_DB_USER (SELECT, INSERT, UPDATE, DELETE)"
# SQL은 표준 입력으로 전달 → 비밀번호가 명령 인수에 안 남음
db <<SQL
CREATE USER IF NOT EXISTS '$APP_DB_USER'@'%' IDENTIFIED BY '$APP_DB_PASSWORD';
ALTER USER '$APP_DB_USER'@'%' IDENTIFIED BY '$APP_DB_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE ON \`$DB_NAME\`.* TO '$APP_DB_USER'@'%';
FLUSH PRIVILEGES;
SQL

count="$(db -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';")"
echo "완료: $DB_NAME 테이블 ${count}개"