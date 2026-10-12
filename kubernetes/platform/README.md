# platform: 클러스터 공용 프로그램 설치

AWS EKS를 만든 뒤 앱보다 **먼저** 설치하는 프로그램과, EKS 접속·배포하는 날 순서를 정리한다.
Terraform은 EKS·IAM·Pod Identity 연결까지 만들고, 아래 설치는 쿠버네티스 담당이 한다.

| 프로그램 | 차트 버전 | 앱 버전 | 하는 일 |
|---|---|---|---|
| AWS Load Balancer Controller | 1.14.1 | v2.14.1 | Ingress를 보고 ALB 생성 (Terraform IAM 정책 기준 버전과 같아야 함) |
| Metrics Server | 3.14.0 | 0.9.0 | CPU·메모리 사용량 수집 (`kubectl top`, HPA 기준) |
| Argo CD | 10.10.2 | v3.5.4 | Git(sai-infra)의 매니페스트를 클러스터에 자동 반영 |

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

## 폴더
- aws-load-balancer-controller/values.yaml: clusterName·vpcId는 빈칸 (설치할 때 `--set`으로 넣음)
- metrics-server/values.yaml (EKS), values-kind.yaml (kind에서만 추가)
- argocd/values.yaml: 인터넷에 열지 않음(ClusterIP), SSO·알림 끔, 요청량 작게
- argocd/apps/sai-demo.yaml: AWS용 (**main** 브랜치의 overlays/demo. dev → main PR이 곧 배포)
- argocd/apps/sai-local.yaml: kind 연습용 (dev 브랜치의 overlays/local)
- argocd/projects/sai.yaml: Argo CD 프로젝트. sai-infra 레포 → sai 네임스페이스만 허용 (default 프로젝트 안 씀)

---

## 1. EKS 접속 (Private 전용 → SSM 터널)
EKS API는 인터넷에 열려 있지 않다. 내 PC → SSM 터널(localhost:8443) → EKS API 순서로 연결한다.

필요한 것: AWS CLI v2, Session Manager 플러그인, kubectl, helm,
EKS access entry에 등록된 내 IAM principal, Bastion SSM 접속 정책 (Terraform 담당이 연결)

```bash
# 터미널 1: 터널 열기 (최대 60분, 20분 동안 입력 없으면 끊김 → 다시 실행)
aws ssm start-session --region ap-northeast-2 \
  --target <terraform output bastion_instance_id> \
  --document-name <terraform output eks_api_tunnel_document_name>
```
```bash
# 터미널 2: kubeconfig (처음 한 번)
aws eks update-kubeconfig --region ap-northeast-2 --name <terraform output eks_cluster_name> --alias sai-eks
CLUSTER=$(kubectl config view -o jsonpath='{.contexts[?(@.name=="sai-eks")].context.cluster}')
EKS_HOST=$(aws eks describe-cluster --region ap-northeast-2 --name <eks_cluster_name> \
  --query cluster.endpoint --output text | sed 's#https://##')
# 주소는 터널(localhost:8443), 인증서 이름 검사는 원래 EKS 주소로
kubectl config set-cluster "$CLUSTER" --server=https://localhost:8443 --tls-server-name="$EKS_HOST"

kubectl config use-context sai-eks
kubectl get nodes          # 노드 2대 Ready
```
- kubectl 명령 전 항상 `kubectl config current-context` 로 kind-sai / sai-eks 를 확인한다.

```bash
kubectl config current-context        # sai-eks

# 1) Load Balancer Controller (반드시 앱보다 먼저)
helm install aws-load-balancer-controller eks/aws-load-balancer-controller --version 1.14.1 -n kube-system \
  -f kubernetes/platform/aws-load-balancer-controller/values.yaml \
  --set clusterName=<terraform output eks_cluster_name> \
  --set vpcId=<terraform output vpc_id> \
  --wait --timeout 5m

# 2) Metrics Server (--wait: 파드가 Ready가 될 때까지 기다림)
helm install metrics-server metrics-server/metrics-server --version 3.14.0 -n kube-system \
  -f kubernetes/platform/metrics-server/values.yaml \
  --wait --timeout 5m
kubectl top nodes                     # 처음 수집까지 1분쯤 걸릴 수 있음 → "metrics not available"이면 잠시 후 다시

# 3) Argo CD
helm install argocd argo/argo-cd --version 10.10.2 -n argocd --create-namespace \
  -f kubernetes/platform/argocd/values.yaml \
  --wait --timeout 10m
kubectl -n argocd get pods            # 전부 Running

# 4) Argo CD 프로젝트 (Application보다 반드시 먼저)
kubectl apply -f kubernetes/platform/argocd/projects/sai.yaml
```
- LB Controller 권한은 Pod Identity(kube-system/aws-load-balancer-controller)로 연결된다. 서비스 계정에 annotation을 넣지 않는다.
- 노드 IMDS가 막혀 있어(hop limit 1) region·vpcId를 컨트롤러가 스스로 못 찾는다 → 반드시 지정.
- 최신 차트(3.x, v3)는 IAM 정책이 달라질 수 있어 Terraform 정책을 바꾸기 전까지 1.14.1로 고정한다.

### Argo CD 화면
```bash
kubectl -n argocd port-forward svc/argocd-server 8443:443     # 브라우저: https://localhost:8443 (인증서 경고 → 계속)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo   # admin 비밀번호 (채팅 금지)
kubectl -n argocd delete secret argocd-initial-admin-secret   # 로그인 확인 후 삭제 (권장)
```
- EKS에서 SSM 터널(8443)을 쓰는 중이면 port-forward는 다른 포트(예: 9443:443)를 쓴다.

---

## 3. 배포하는 날 순서
| 순서 | 할 일 | 확인 |
|---|---|---|
| 1 | `terraform apply` (Terraform 담당) → output 공유 | output 값 |
| 2 | SSM 터널 → kubeconfig (위 1번) | `kubectl get nodes` 2대 |
| 3 | LB Controller → Metrics Server → Argo CD → Argo CD 프로젝트 (위 2번, 모두 `--wait`) | 파드 Running |
| 4 | 이미지 ECR push (태그 = git 커밋 해시) | ECR에 태그 |
| 5 | DB 초기화 Job (kubernetes/README.md) → Secret 삭제 | 로그: Ssl_version, 테이블 32개 |
| 6 | 운영 설정 Secret `sai-api-config` | `kubectl -n sai get secret` |
| 7 | overlays/demo의 ECR 주소·태그를 채워 dev에 머지 → **dev → main PR 머지** | `kubectl kustomize kubernetes/overlays/demo` 빈칸 없음 |
| 8 | `kubectl apply -f kubernetes/platform/argocd/apps/sai-demo.yaml` | Application Synced / Healthy, ALB 주소 생성 |
| 9 | 회원가입·로그인·업로드·AI 분석 | 브라우저 |
| 10 | 파드 1개 삭제·롤링 배포 중 요청 | 에러 0번 |
| 11 | `kubectl top pods -n sai` | api 메모리 (kind 482Mi와 비교) |
| 12 | RDS `require_secure_transport=ON` 적용 후 다시 로그인 | 정상 |

- Argo CD가 관리하는 동안 `kubectl rollout restart`는 쓰지 않는다. (selfHeal이 되돌려 재시작이 한 번 더 일어남)
  재시작은 `kubectl -n sai delete pod -l app=sai-api`.
- DB 초기화 Job은 Argo CD 관리 대상이 아니다. (필요할 때 직접 실행)

## 4. 내릴 때
1. `kubectl -n argocd delete application sai-demo` (먼저 지우지 않으면 Argo CD가 다시 만듦)
2. `kubectl delete -k kubernetes/overlays/demo` → `aws elbv2 describe-load-balancers` 에서 `k8s-sai-` ALB가 사라질 때까지 대기
3. 이후 kubernetes/README.md "AWS를 내릴 때" 순서 (S3·ECR 비우기 → terraform destroy → Secret 강제 삭제)

---

```bash
kubectl config current-context        # kind-sai
# Traefik은 아래 "Traefik 설정"대로 설치되어 있어야 sai-local이 Healthy가 된다

helm install metrics-server metrics-server/metrics-server --version 3.14.0 -n kube-system \
  -f kubernetes/platform/metrics-server/values.yaml \
  -f kubernetes/platform/metrics-server/values-kind.yaml \
  --wait --timeout 5m
helm install argocd argo/argo-cd --version 10.10.2 -n argocd --create-namespace \
  -f kubernetes/platform/argocd/values.yaml \
  --wait --timeout 10m

# 프로젝트를 먼저 만들고 → Application (순서가 바뀌면 없는 프로젝트를 참조해 동기화되지 않음)
kubectl apply -f kubernetes/platform/argocd/projects/sai.yaml
kubectl apply -f kubernetes/platform/argocd/apps/sai-local.yaml
kubectl -n argocd get application sai-local -w     # Synced / Healthy 가 되면 Ctrl+C (1~2분)
```
- 연습 끝: `kubectl -n argocd delete application sai-local` (리소스는 남음), `helm uninstall argocd -n argocd`

### Traefik 설정 (Argo CD가 Healthy로 보려면)
Argo CD는 Ingress에 주소가 적혀야 Healthy로 판단한다. kind의 Traefik(NodePort)은 기본값으로는 주소를 안 적어서
Progressing에 머문다 → Ingress 주소를 127.0.0.1로 적게 설정한다. (AWS는 ALB 주소가 자동으로 적힘)

처음 설치할 때:
```bash
helm install traefik traefik/traefik --version 41.7.0 -n traefik --create-namespace \
  --set service.type=NodePort --set ports.web.nodePort=30080 \
  --set providers.kubernetesIngress.publishedService.enabled=false \
  --set "additionalArguments={--providers.kubernetesingress.ingressendpoint.ip=127.0.0.1}"
```
이미 설치돼 있으면:
```bash
helm upgrade traefik traefik/traefik --version 41.7.0 -n traefik --reuse-values \
  --set providers.kubernetesIngress.publishedService.enabled=false \
  --set "additionalArguments={--providers.kubernetesingress.ingressendpoint.ip=127.0.0.1}"
kubectl -n sai get ingress      # ADDRESS 127.0.0.1
```
- `publishedService`(차트 기본값)가 켜져 있으면 그쪽이 먼저 쓰여서 주소가 비어 버린다. 반드시 끈다.
