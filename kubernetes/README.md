# kubernetes

## 폴더
- base/: 모든 환경에 공통인 주문서
  - api/: 백엔드(Spring Boot) Deployment·Service
  - web/: 프론트(Nginx) Deployment·Service
  - ai/: (예정) FastAPI·Qdrant
- overlays/local/: 노트북 kind용 (MariaDB, Redis를 Pod로 실행, Traefik Ingress)
- overlays/demo/: AWS EKS용 (ALB Ingress, ECR 이미지, DB·Redis·파일은 RDS·ElastiCache·S3 사용)
- jobs/db-init/: DB 초기화 Job (테이블 생성 + 앱 전용 계정). 배포와 따로 필요할 때만 실행
- certs/: AWS RDS 공개 CA 인증서 → ConfigMap `rds-ca-bundle` (앱·Job이 RDS 인증서 검증에 사용)

> overlays/local은 AWS에 배포되지 않는다. Argo CD는 overlays/demo만 바라본다.

## 실행
- 노트북: kubectl apply -k kubernetes/overlays/local  (아래 "로컬(kind) 실행 방법" 참고)
- AWS:    kubectl apply -k kubernetes/overlays/demo   (아래 "AWS(demo) 배포 순서" 참고)

## 비밀값 규칙 (공개 레포)
- application-*.yml, secret.yaml, *.env 는 Git에 올리지 않는다. (`*.example.yml`만 허용)
- 클러스터를 만들 때마다 kubectl create secret 으로 직접 넣는다.
- 매니페스트에서는 비밀번호를 직접 쓰지 않고 secretKeyRef로 Secret에서 꺼내 쓴다.
- 비밀번호는 명령줄 인수·명령 기록에 남기지 않는다. (파일로 입력)
- 비밀번호 파일은 WSL 홈의 잠긴 폴더(`~/.sai-secrets`, chmod 700)에 만들고 쓰고 나면 지운다.
  (저장소 폴더는 C: 드라이브라 파일 권한 제한이 안 됨)

### 필요한 Secret (namespace: sai)
| 이름 | 키 | 용도 | 환경 |
|---|---|---|---|
| sai-api-config | application-dev.yml / application-prod.yml | 백엔드 설정 파일 → /app/config 에 마운트 | 공통 |
| sai-local-db | MARIADB_ROOT_PASSWORD, MARIADB_PASSWORD, REDIS_PASSWORD | 로컬 MariaDB(관리용·앱용)·Redis 비밀번호 | local |
| sai-db-init | DB_HOST, DB_ADMIN_*, APP_DB_* 등 | DB 초기화 Job 접속 정보 (**Job 끝나면 삭제**) | 공통 |

---

## 로컬(kind) 실행 방법
> ⚠️ overlays/local 은 **로컬 개발 전용**이다. MariaDB·Redis를 Pod로 띄우고 약한 비밀번호를 써도 되는 연습 환경이며,
> AWS(overlays/demo)에는 배포되지 않는다. 실제 데이터를 넣지 않는다.

### 1. 클러스터와 입구(Traefik)
```bash
kind create cluster --config kubernetes/overlays/local/kind-cluster.yaml
kubectl config current-context   # kind-sai 확인
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm install traefik traefik/traefik --version 41.7.0 -n traefik --create-namespace \
  --set service.type=NodePort --set ports.web.nodePort=30080 \
  --set providers.kubernetesIngress.publishedService.enabled=false \
  --set "additionalArguments={--providers.kubernetesingress.ingressendpoint.ip=127.0.0.1}"
```

### 2. 이미지 빌드 후 kind에 넣기
```bash
docker build -t sai-backend:local <sai-backend-v2 경로>
docker build -t sai-frontend:local <sai-frontend 경로>
kind load docker-image sai-backend:local sai-frontend:local --name sai
```
- 로컬에서 빌드한 이미지는 어디에도 push하지 않는다. (AWS용 이미지는 CI가 Git 기준으로 빌드)

### 3. Secret 생성
**1) 비밀번호 파일 만들기** (WSL에서. Windows 편집기로 만들면 줄 끝 CRLF가 비밀번호에 섞일 수 있음)
```bash
vi kubernetes/overlays/local/local-db.env      # .gitignore(kubernetes/**/*.env)로 Git 제외
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
- application-dev.yml의 `spring.sql.init.schema-locations`는 아래 "DB 초기화 Job"의 테이블 순서와 **같아야** 빈 DB에서 테이블이 생성된다.
  (`notification.sql` 다음에 `preparation_proposal.sql`, `repayment_preparation_event.sql`, 마지막에 `shedlock.sql`)
- DB·Redis 주소와 비밀번호는 overlays/local/api-local-patch.yaml의 환경 변수가 yml 값을 덮어쓴다.
- 로컬 DB를 처음 만든 뒤 Spring Batch 저장소 테이블(BATCH_*)을 **한 번** 만든다.
  백엔드가 `@EnableJdbcJobRepository`로 배치를 직접 설정해서, yml의 `spring.batch.jdbc.initialize-schema: always`가 동작하지 않는다.
  (`batch-schema-mariadb.sql` 꺼내는 법은 아래 "DB 초기화 Job" 1번 참고, 두 번 실행하면 "이미 있음" 에러)
```bash
kubectl -n sai exec -i deploy/mariadb -- sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot sai_backend' \
  < ~/sai-db/batch-schema-mariadb.sql
```

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
| kubectl: command not found (WSL) | Docker Desktop 실행 확인 |

### 6. 끄기와 정리
```bash
docker stop sai-control-plane      # 잠깐 끄기 (데이터·Secret 유지). 다시 켜기: docker start sai-control-plane
kind delete cluster --name sai     # 완전히 삭제
```

---

## DB 초기화 Job (테이블 생성 + 앱 전용 계정)
앱 계정은 데이터 읽기·쓰기(DML) 권한만 있어서 테이블을 만들 수 없다.
배포 전에 이 Job을 관리자 계정으로 **한 번** 실행한다. (다시 실행해도 안전)

하는 일: 접속 확인(TLS 버전 출력) → DB 생성(utf8mb4) → 앱 테이블 23개(정해진 순서) → BATCH_ 테이블(없을 때만) → 앱 계정 생성·DML 권한

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

kubectl -n sai delete configmap sai-db-schema --ignore-not-found
kubectl -n sai create configmap sai-db-schema \
  --from-file="<sai-backend-v2 경로>/src/main/resources/db/" \
  --from-file=batch-schema-mariadb.sql="$HOME/sai-db/batch-schema-mariadb.sql"
```
- 경로에 띄어쓰기가 있으면 큰따옴표로 감싼다. (예: `"/mnt/c/Shinhan7 Work/sai-backend-v2/src/main/resources/db/"`)

### 2. 접속 정보를 Secret으로
비밀번호 파일은 **WSL 홈의 잠긴 폴더**에 만들고, 끝나면 지운다.
```bash
mkdir -p ~/.sai-secrets && chmod 700 ~/.sai-secrets     # 나만 들어갈 수 있는 폴더
umask 077                                              # 이후 만드는 파일은 나만 읽기
```
**앱 DB 비밀번호의 원본은 AWS Secrets Manager(`application_db_secret_arn`) 하나**다.
Job과 앱 설정(application-prod.yml)은 여기서 꺼내 쓰고, 다른 곳에 따로 보관하지 않는다.

**kind** (연습용, Secrets Manager 없음)
```bash
ROOT_PW=$(grep '^MARIADB_ROOT_PASSWORD=' kubernetes/overlays/local/local-db.env | cut -d= -f2-)
APP_PW=$(openssl rand -hex 16)
cat > ~/.sai-secrets/db-init.env <<EOF
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
**AWS**
```bash
# 관리자: RDS가 관리하는 master secret에서 바로 꺼냄
ADMIN_JSON=$(aws secretsmanager get-secret-value --secret-id "<rds_master_secret_arn>" \
  --query SecretString --output text --region ap-northeast-2)
ADMIN_USER=$(printf '%s' "$ADMIN_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["username"])')
ADMIN_PW=$(printf '%s' "$ADMIN_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["password"])')

# 앱 계정: 새로 만들어 Secrets Manager(원본)에 먼저 저장
APP_PW=$(openssl rand -hex 16)
printf '{"username":"sai_app","password":"%s"}' "$APP_PW" | \
  aws secretsmanager put-secret-value --secret-id "<application_db_secret_arn>" \
  --secret-string file:///dev/stdin --region ap-northeast-2

cat > ~/.sai-secrets/db-init.env <<EOF
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
- RDS 주소(`*.rds.amazonaws.com`)면 Job이 자동으로 TLS + 서버 인증서·호스트 이름 검증을 켠다. (`/certs/global-bundle.pem`)
- 주소는 IP로 바꾸지 않는다. (인증서의 이름과 맞아야 검증됨)

```bash
kubectl -n sai create secret generic sai-db-init --from-env-file="$HOME/.sai-secrets/db-init.env"
```

### 3. 실행과 확인
```bash
kubectl apply -k kubernetes/jobs/db-init
kubectl -n sai wait --for=condition=complete job/sai-db-init --timeout=180s
kubectl -n sai logs job/sai-db-init
```
- 로그 확인: `Ssl_version` 줄에 TLS 버전(예: TLSv1.3), 마지막 줄 `완료: sai 테이블 32개` (앱 23 + Batch 9)
- 다시 실행: `kubectl -n sai delete job sai-db-init` 후 apply
- 멈춰 있으면(ContainerCreating): ConfigMap `sai-db-schema`와 Secret `sai-db-init`이 둘 다 있는지 확인
- 백엔드에 새 SQL 파일이 생기면 로그에 "순서 목록에 없는 파일" 경고가 나온다 → db-init.sh 의 ORDER에 추가

### 4. 정리 (꼭)
```bash
kubectl -n sai delete secret sai-db-init       # 관리자 비밀번호가 클러스터에 남지 않게
rm -f ~/.sai-secrets/db-init.env               # PC에도 남기지 않음
```
- Secret을 읽거나 Job을 실행할 수 있는 사람: EKS 접근 권한(access entry)에 등록된 운영자만. 앱 파드의 서비스 계정에는 Secret 읽기 권한(RBAC)을 주지 않는다.
- 앱 비밀번호가 다시 필요하면 Secrets Manager에서 꺼낸다. (kind는 Job을 다시 실행하면 새 비밀번호로 바뀜)

---

## AWS 운영 설정(Secret) 만들기
```bash
cp kubernetes/overlays/demo/application-prod.example.yml kubernetes/overlays/demo/application-prod.yml
git status        # application-prod.yml 이 목록에 "없어야" 함
```
1. `<...>` 칸을 채운다.
  - 주소·ID: `terraform output` 값 (rds_endpoint, redis_primary_endpoint, redis_replication_group_id, redis_iam_user_name, s3_bucket_name)
  - DB 비밀번호: `aws secretsmanager get-secret-value --secret-id <application_db_secret_arn>` 의 password
  - 비밀 값(jwt, link-*): `openssl rand -base64 32` 로 새로 만든다. dev 값 재사용 금지
  - OpenAI API 키: 팀에서 받은 값 (AI 기능을 안 쓰면 `spring.ai.model.chat: none`)
2. Secret 생성
```bash
kubectl config current-context
kubectl -n sai create secret generic sai-api-config \
  --from-file=application-prod.yml=kubernetes/overlays/demo/application-prod.yml
```
3. 채운 파일은 채팅·메신저·이슈에 붙이지 않는다. Secret을 만든 뒤 지운다. (`rm kubernetes/overlays/demo/application-prod.yml`)

- HTTP 단계에서는 `jwt.cookie.secure: false`, HTTPS 적용 후 `true`
- 테이블은 앱이 만들지 않는다. 배포 전에 "DB 초기화 Job"을 먼저 실행한다.

### RDS TLS (인증서 검증)
- 앱: `sslMode=verify-full&serverSslCert=/certs/global-bundle.pem` / Job: RDS 주소면 자동 검증
- 인증서 경로: `kubernetes/certs/rds-global-bundle.pem` → ConfigMap `rds-ca-bundle` → 파드 `/certs/global-bundle.pem`
- 순서: 앱·Job의 TLS 설정을 먼저 배포·확인한 뒤 RDS의 `require_secure_transport=ON`을 적용한다. (반대로 하면 접속이 끊김)
- 인증서 묶음 갱신: AWS 공식 주소(https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem)에서 다시 받아 같은 파일을 교체하고 커밋한다.
- Redis(ElastiCache) TLS 인증서는 Java 기본 신뢰 목록에 있어 별도 파일이 필요 없다.

---

## AWS(demo) 배포 순서
1. SSM 터널로 EKS에 kubectl 연결 → `kubectl config current-context` 확인
2. AWS Load Balancer Controller 설치 (먼저. namespace의 readiness gate 라벨을 Controller가 처리함)
3. DB 초기화 Job 실행 → Secret 삭제
4. 운영 설정 Secret(sai-api-config) 생성
5. `kubectl kustomize kubernetes/overlays/demo` 로 빈칸(ECR 주소·태그) 확인 → apply
6. 회원가입·로그인·업로드 확인 → RDS TLS 강제 적용 → 다시 확인

### 주의
- 워커 노드는 AZ별 1대씩 총 2대 기준이다. api·web 각 2개가 AZ에 나뉘어 배치된다.
- HTTPS 패치(ingress-https-patch.yaml)를 켜기 전에는 브라우저↔ALB 구간이 암호화되지 않는다.
  이 상태에서는 테스트 계정과 가짜 데이터만 사용한다. 실제 계좌·개인정보는 HTTPS 적용 후에만 사용한다.
- HTTPS 적용 조건: 도메인(Route53) + 서울 리전 ACM 인증서 ARN → kustomization.yaml에서 패치 주석 해제
- 이미지 태그는 매번 달라야 한다. (ECR이 같은 태그 덮어쓰기를 막음 → git 커밋 해시 사용)

## AWS를 내릴 때
1. Argo CD 앱 삭제 → `kubectl delete -k kubernetes/overlays/demo` → ALB가 삭제된 것을 확인
2. S3 버킷 비우기(콘솔 "비우기", 이전 버전 포함), ECR 이미지 삭제
3. `terraform destroy`
4. `aws secretsmanager delete-secret --secret-id <name_prefix>/database/application --force-delete-without-recovery`
   (지운 뒤 7일 동안 같은 이름으로 다시 못 만드는 문제 방지)
5. 남는 것 정리 (Terraform이 만들지 않아 destroy 후에도 남고 비용이 나감)
  - 목뱅크 EBS 자동 스냅샷(DLM): EC2 콘솔 → 스냅샷 → 태그 `BackupPolicy = <name_prefix>-mock-bank-database` 삭제
  - RDS 최종 스냅샷(`rds_final_snapshot_identifier`): 필요 없으면 RDS 콘솔 → 스냅샷에서 삭제
  - CloudFront 배포 삭제는 10분 이상 걸릴 수 있다 (destroy가 오래 걸려도 정상)

## 작업 규칙
- 파일 작성과 Git(commit/push)은 Windows(IntelliJ·PowerShell)에서 한다.
- kubectl·kind·helm·docker는 WSL에서 실행해도 된다. (WSL에서 git을 쓰면 줄바꿈 차이로 전체 파일이 수정된 것처럼 보임)
- kubectl 명령 전 kubectl config current-context 로 대상 클러스터를 확인한다.
- `--dry-run=server` 없이 demo를 kind에 apply하지 않는다.