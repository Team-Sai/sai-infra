# kubernetes

## 폴더
- base/: 모든 환경에 공통인 주문서 (web, api, ai)
- overlays/local/: 노트북 kind용 (MariaDB, Redis를 Pod로 실행)
- overlays/demo/: AWS EKS용 (ALB Ingress, ECR 이미지, EBS)

## 실행
- 노트북: kubectl apply -k kubernetes/overlays/local
- AWS:    kubectl apply -k kubernetes/overlays/demo

## 비밀값 규칙 (공개 레포)
- application.yml, secret.yaml은 Git에 올리지 않는다.
- 클러스터를 만들 때마다 kubectl create secret 으로 직접 넣는다.
- 레포에는 값을 비운 예시 파일(*.example.yml, secret.example.yaml)만 올린다.

## AWS를 내릴 때
- Ingress를 먼저 지우고 ALB가 삭제된 것을 확인한 뒤 terraform destroy
