# kubernetes

## 폴더
- base/: 모든 환경에 공통인 주문서
    - api/: 백엔드(Spring Boot) Deployment·Service
    - web/: 프론트(Nginx) Deployment·Service
    - ai/: (예정) FastAPI·Qdrant
- overlays/local/: 노트북 kind용 (MariaDB, Redis를 Pod로 실행, Traefik Ingress)
- overlays/demo/: AWS EKS용 (ALB Ingress, ECR 이미지, EBS)

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

