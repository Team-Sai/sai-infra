# kubernetes

## 폴더
- base/: 모든 환경에 공통인 주문서
    - api/: 백엔드(Spring Boot) Deployment·Service
    - web/: 프론트(Nginx) Deployment·Service
    - ai/: (예정) FastAPI·Qdrant
- overlays/local/: 노트북 kind용 (MariaDB, Redis를 Pod로 실행, Traefik Ingress)
- overlays/demo/: AWS EKS용 (ALB Ingress, ECR 이미지, DB·Redis·파일은 RDS·ElastiCache·S3 사용)

> overlays/local은 AWS에 배포되지 않는다. Argo CD는 overlays/demo만 바라본다.

## 실행
- 노트북: kubectl apply -k kubernetes/overlays/local  (아래 "로컬(kind) 실행 방법" 참고)
- AWS:    kubectl apply -k kubernetes/overlays/demo

## 비밀값 규칙 (공개 레포)
- application.yml, secret.yaml은 Git에 올리지 않는다.
- 클러스터를 만들 때마다 kubectl create secret 으로 직접 넣는다.
- 레포에는 값을 비운 예시 파일(*.example.yml, secret.example.yaml)만 올린다.
- 매니페스트에서는 비밀번호를 직접 쓰지 않고 secretKeyRef로 Secret에서 꺼내 쓴다.

### 필요한 Secret (namespace: sai)
| 이름 | 키 | 용도 | 환경 |
|---|---|---|---|
| sai-api-config | application-dev.yml 등 | 백엔드 설정 파일 → /app/config 에 마운트 | 공통 |
| sai-local-db | MARIADB_ROOT_PASSWORD, MARIADB_PASSWORD, REDIS_PASSWORD | 로컬 MariaDB(관리용·앱용)·Redis 비밀번호 | local |

## 로컬(kind) 실행 방법
> ⚠️ overlays/local 은 **로컬 개발 전용**이다. MariaDB·Redis를 Pod로 띄우고 약한 비밀번호를 써도 되는 연습 환경이며,
> AWS(overlays/demo)에는 배포되지 않는다. 실제 데이터를 넣지 않는다.
> 비밀번호는 명령줄 인수·명령 기록에 남지 않게 한다. (Secret 파일 입력, Redis는 설정 파일로 전달)

### 1. 클러스터와 입구(Traefik)
```bash
kind create cluster --config kubernetes/overlays/local/kind-cluster.yaml
kubectl config current-context   # kind-sai 확인
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm install traefik traefik/traefik -n traefik --create-namespace \
  --set service.type=NodePort --set ports.web.nodePort=30080
```

### 2. 이미지 빌드 후 kind에 넣기
```bash
docker build -t sai-backend:local <sai-backend-v2 경로>
docker build -t sai-frontend:local <sai-frontend 경로>
kind load docker-image sai-backend:local sai-frontend:local --name sai
```
- 로컬에서 빌드한 이미지는 어디에도 push하지 않는다. (AWS용 이미지는 CI가 Git 기준으로 빌드)

### 3. Secret 생성
비밀번호는 명령줄에 직접 쓰지 않는다. (명령 기록에 남음)
로컬 전용 파일을 만들고, 이 파일은 Git에 올리지 않는다. (.gitignore의 `kubernetes/**/*.env`)

**1) 비밀번호 파일 만들기** (WSL에서. Windows 편집기로 만들면 줄 끝 CRLF가 비밀번호에 섞일 수 있음)
```bash
vi kubernetes/overlays/local/local-db.env
```
파일 내용 형식:
```
MARIADB_ROOT_PASSWORD=<로컬용 root 비밀번호>
MARIADB_PASSWORD=<로컬용 앱 계정 비밀번호>
REDIS_PASSWORD=<로컬용 Redis 비밀번호>
```

**2) Secret 처음 만들기**
```bash
kubectl create namespace sai
kubectl -n sai create secret generic sai-local-db \
  --from-env-file=kubernetes/overlays/local/local-db.env
kubectl -n sai create secret generic sai-api-config \
  --from-file=application-dev.yml=<로컬 application-dev.yml 경로>
kubectl -n sai get secret   # 2개 보이면 성공
```
- 로컬 DB를 처음 만든 뒤 Spring Batch 저장소 테이블(BATCH_*)을 **한 번** 만든다.
  백엔드가 `@EnableJdbcJobRepository`로 배치를 직접 설정해서, yml의 `spring.batch.jdbc.initialize-schema: always`가 동작하지 않는다.
  (`batch-schema-mariadb.sql` 꺼내는 법은 아래 "DB 초기화 Job" 1번 참고, 두 번 실행하면 "이미 있음" 에러)
```bash
kubectl -n sai exec -i deploy/mariadb -- sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot sai_backend' \
  < ~/sai-db/batch-schema-mariadb.sql
```
- application-dev.yml의 spring.sql.init.schema-locations는 백엔드 src/test/resources/application-test.yml과 **같은 순서**여야 빈 DB에서 테이블이 생성된다.
- DB·Redis 주소와 비밀번호는 overlays/local/api-local-patch.yaml의 환경 변수가 yml 값을 덮어쓴다.

**3) Secret 값을 바꿀 때**
```bash
kubectl -n sai create secret generic sai-local-db \
  --from-env-file=kubernetes/overlays/local/local-db.env \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n sai create secret generic sai-api-config \
  --from-file=application-dev.yml=<로컬 application-dev.yml 경로> \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n sai rollout restart deployment/sai-api
```
- MariaDB 비밀번호는 DB가 처음 만들어질 때만 적용된다. 바꾸려면 mariadb Deployment와 PVC(mariadb-data)를 지우고 다시 만든다. (로컬 데이터 사라짐)

### 4. 배포와 접속
```bash
kubectl apply -k kubernetes/overlays/local
kubectl -n sai get pods -w
```
- 접속: http://localhost:28080
- 처음 기동 시 MariaDB 준비 전에 sai-api가 1~2회 재시작될 수 있다. (정상)
- /actuator는 Ingress로 열지 않는다. 내부 확인:
```bash
  kubectl -n sai exec deploy/sai-web -- wget -qO- http://sai-api:8080/actuator/health
```

### 5. 문제 해결
| 증상 | 확인 |
|---|---|
| Pending | kubectl -n sai describe pod <이름> → Events |
| ImagePullBackOff | kind load docker-image 다시 실행 |
| sai-api 계속 재시작 | kubectl -n sai logs deploy/sai-api --previous |

### 6. 정리
```bash
kind delete cluster --name sai
```

## 작업 규칙
- 파일 작성과 Git(commit/push)은 Windows(IntelliJ·PowerShell)에서 한다.
- kubectl·kind·helm·docker는 WSL에서 실행해도 된다. (WSL에서 git을 쓰면 줄바꿈 차이로 전체 파일이 수정된 것처럼 보임)
- kubectl 명령 전 kubectl config current-context 로 대상 클러스터를 확인한다.

## AWS를 내릴 때
- Ingress를 먼저 지우고 ALB가 삭제된 것을 확인한 뒤 terraform destroy

## AWS(demo) 배포 시 주의
- AWS Load Balancer Controller를 먼저 설치한 뒤 demo를 apply한다. (namespace의 readiness gate 라벨을 Controller가 처리함)
- 워커 노드는 AZ별 1대씩 총 2대 기준이다. api·web 각 2개가 AZ에 나뉘어 배치된다.
- HTTPS 패치(ingress-https-patch.yaml)를 켜기 전에는 브라우저↔ALB 구간이 암호화되지 않는다.
  이 상태에서는 테스트 계정과 가짜 데이터만 사용한다. 실제 계좌·개인정보는 HTTPS 적용 후에만 사용한다.
- HTTPS 적용 조건: 도메인(Route53) + 서울 리전 ACM 인증서 ARN → kustomization.yaml에서 패치 주석 해제
- 이미지 태그는 매번 달라야 한다. (ECR이 같은 태그 덮어쓰기를 막음 → git 커밋 해시 사용)

## DB 초기화 Job (테이블 생성 + 앱 전용 계정)
앱 계정은 데이터 읽기·쓰기(DML) 권한만 있어서 테이블을 만들 수 없다.
배포 전에 이 Job을 관리자 계정으로 **한 번** 실행한다. (다시 실행해도 안전)

하는 일: DB 생성(utf8mb4) → 앱 테이블 21개(application-test.yml 순서) → BATCH_ 테이블(없을 때만) → 앱 계정 생성·DML 권한

### 1. 테이블 SQL을 ConfigMap으로
백엔드는 **배포할 이미지와 같은 커밋**으로 체크아웃되어 있어야 한다.
```bash
# Spring Batch 테이블 SQL을 백엔드 이미지에서 꺼내기 (python3 필요)
mkdir -p ~/sai-db && cd ~/sai-db
docker create --name sai-tmp <백엔드 이미지>
docker cp sai-tmp:/app/app.jar ./app.jar && docker rm sai-tmp
python3 - <<'PY'
import zipfile, io
outer = zipfile.ZipFile("app.jar")
lib = [n for n in outer.namelist() if "spring-batch-core" in n and n.endswith(".jar")][0]
inner = zipfile.ZipFile(io.BytesIO(outer.read(lib)))
sql = [n for n in inner.namelist() if n.endswith("schema-mariadb.sql")][0]
open("batch-schema-mariadb.sql", "wb").write(inner.read(sql))
print(lib, sql)
PY
cd -

kubectl -n sai create configmap sai-db-schema \
  --from-file="<sai-backend-v2 경로>/src/main/resources/db/" \
  --from-file=batch-schema-mariadb.sql="$HOME/sai-db/batch-schema-mariadb.sql"
kubectl -n sai get configmap sai-db-schema -o jsonpath='{.data}' | grep -o '"[^"]*\.sql"' | wc -l   # 20
```
- 경로에 띄어쓰기가 있으면 큰따옴표로 감싼다. (예: `"/mnt/c/Shinhan7 Work/sai-backend-v2/src/main/resources/db/"`)

### 2. 접속 정보를 Secret으로 (비밀번호는 화면·명령 기록에 남기지 않는다)
**kind**
```bash
ROOT_PW=$(grep '^MARIADB_ROOT_PASSWORD=' kubernetes/overlays/local/local-db.env | cut -d= -f2-)
APP_PW=$(openssl rand -hex 16)
cat > kubernetes/jobs/db-init/db-init.env <<EOF
DB_HOST=mariadb
DB_PORT=3306
DB_NAME=sai
DB_ADMIN_USER=root
DB_ADMIN_PASSWORD=${ROOT_PW}
APP_DB_USER=sai_app
APP_DB_PASSWORD=${APP_PW}
DB_CLIENT_OPTS=
EOF
unset ROOT_PW APP_PW
```
**AWS** (RDS master 비밀번호는 Secrets Manager에서 바로 꺼낸다)
```bash
ADMIN_JSON=$(aws secretsmanager get-secret-value --secret-id "<rds_master_secret_arn>" \
  --query SecretString --output text --region ap-northeast-2)
ADMIN_USER=$(printf '%s' "$ADMIN_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["username"])')
ADMIN_PW=$(printf '%s' "$ADMIN_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["password"])')
APP_PW=$(openssl rand -hex 16)
cat > kubernetes/jobs/db-init/db-init.env <<EOF
DB_HOST=<terraform output rds_endpoint>
DB_PORT=3306
DB_NAME=sai
DB_ADMIN_USER=${ADMIN_USER}
DB_ADMIN_PASSWORD=${ADMIN_PW}
APP_DB_USER=sai_app
APP_DB_PASSWORD=${APP_PW}
DB_CLIENT_OPTS=
EOF
unset ADMIN_JSON ADMIN_USER ADMIN_PW APP_PW
```
- AWS에서 TLS 인증서 오류가 나면 `DB_CLIENT_OPTS`에 RDS 인증서 옵션을 넣는다. (첫 배포 때 확인)
- 앱 계정 정보는 Terraform이 만든 빈 금고(`<name_prefix>/database/application`)에도 넣어 둔다.

```bash
kubectl -n sai create secret generic sai-db-init --from-env-file=kubernetes/jobs/db-init/db-init.env
```

### 3. 실행과 확인
```bash
kubectl apply -k kubernetes/jobs/db-init
kubectl -n sai wait --for=condition=complete job/sai-db-init --timeout=180s
kubectl -n sai logs job/sai-db-init          # 마지막 줄: 완료: sai 테이블 30개
```
- 다시 실행: `kubectl -n sai delete job sai-db-init` 후 apply
- 멈춰 있으면(ContainerCreating): ConfigMap `sai-db-schema`와 Secret `sai-db-init`이 둘 다 있는지 확인
- 백엔드에 새 SQL 파일이 생기면 로그에 "순서 목록에 없는 파일" 경고가 나온다 → db-init.sh 의 ORDER에

## AWS 운영 설정(Secret) 만들기
실제 값이 든 파일은 Git에 올리지 않는다. (`kubernetes/**/application*.yml` 제외, `*.example.yml`만 허용)

```bash
cp kubernetes/overlays/demo/application-prod.example.yml kubernetes/overlays/demo/application-prod.yml
git status        # application-prod.yml 이 목록에 "없어야" 함
```
1. `<...>` 칸을 채운다.
  - 주소: `terraform output` 값
  - 비밀 값(jwt, link-*): `openssl rand -base64 32` 로 새로 만든다. dev 값 재사용 금지
  - DB 비밀번호: DB 초기화 Job에 넣은 `APP_DB_PASSWORD`
2. Secret 생성
```bash
kubectl config current-context
kubectl -n sai create secret generic sai-api-config \
  --from-file=application-prod.yml=kubernetes/overlays/demo/application-prod.yml
```
3. 채운 파일은 채팅·메신저·이슈에 붙이지 않는다.
- HTTP 단계에서는 `jwt.cookie.secure: false`, HTTPS 적용 후 `true`
- 테이블은 앱이 만들지 않는다. 배포 전에 "DB 초기화 Job"을 먼저 실행한다.

