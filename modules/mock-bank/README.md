# 선택 모듈: Mock Bank

이 모듈은 기본 Terraform root에서 호출하지 않습니다. 따라서 기본 인프라 구성에는 Mock Bank EC2/VPC 비용이 들어가지 않습니다. 별도 VPC의 단일 EC2에서 현재 Mock Bank 앱과 MariaDB를 Docker Compose로 실행하려는 시점에만 호출하세요.

## 현재 구현 범위와 목표 구성의 차이

현재 모듈은 App Private CIDR에서 EC2의 HTTP 8081 포트로 연결하는 내부 API 시험용 최소 구성입니다. 브라우저에서 접근하는 은행 로그인 화면과 서버 간 API 주소를 분리하지 않으며, Nginx·HTTPS 443/내부 TLS 8443·CloudFront/WAF·DNS·고정 공인 주소는 만들지 않습니다. 백엔드의 화면용/서버용 Bank URL 분리도 앱 코드에서 별도로 필요합니다.

Compose의 MariaDB named volume은 인스턴스의 암호화된 root EBS 안에 저장됩니다. 별도 데이터 EBS와 자동 스냅샷/복원 절차는 없고, EC2 교체·종료 때 DB를 보존한다고 보장할 수 없습니다. 로컬 `sai-mock-bank` Compose와 이 모듈이 부팅 시 생성하는 Compose도 설정이 서로 다를 수 있으므로 배포 전에 비교하세요.

## 연결과 접근

- 주 VPC와 Mock Bank VPC 사이에 VPC peering과 양쪽 route를 구성합니다. 주 VPC의 App Private CIDR에서 Mock Bank 앱 포트(기본 8081)에 접근할 수 있습니다. 현재 제한은 앱 Pod/보안그룹 단위가 아니라 서브넷 CIDR 단위입니다.
- EC2는 public subnet과 공인 IPv4를 사용하지만, security group에는 인터넷 인바운드 규칙이 없습니다. 운영자는 SSM Session Manager로 접속하고 SSH 포트는 열지 않습니다.
- EC2는 IMDSv2만 허용하고 응답 hop limit을 1로 제한합니다. Docker 브리지 네트워크의 앱 컨테이너가 EC2 역할의 자격 증명에 접근하지 못하도록 하기 위한 설정입니다. EC2 호스트에서만 Secret을 읽고 `.env` 파일을 만듭니다.
- 단일 EC2와 Compose DB는 고가용성 구성이 아닙니다. 인스턴스 교체·장애 시 앱과 DB의 복구·백업 절차는 별도입니다.

## 호출 예시

root `locals.tf` 또는 `main.tf`에 모듈 호출을 추가하고 입력을 연결합니다. 아래는 연결 예시이며 실제 ID나 이미지 digest가 아닙니다.

```hcl
module "mock_bank" {
  source = "./modules/mock-bank"

  name_prefix              = local.name_prefix
  aws_region               = var.aws_region
  main_vpc_id              = module.network.vpc_id
  main_vpc_cidr            = var.vpc_cidr
  main_app_route_table_ids = module.network.app_private_route_table_ids
  main_app_subnet_cidrs    = module.network.app_private_subnet_cidrs
  mock_bank_image          = var.mock_bank_image_digest
  mock_bank_secret_arn     = var.mock_bank_secret_arn
}
```

## 팀원이 준비할 값

- ECR 이미지 URI는 변경 가능한 tag 대신 `@sha256:<64자리 digest>`로 고정합니다.
- `mock_bank_secret_arn`은 다음 키를 가진 JSON secret을 가리켜야 합니다: `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`, `DB_ROOT_PASSWORD`, `MOCK_BANK_KEY_HASH_SECRET`, `JWT_SECRET`, `LINK_IDENTITY_HASH_SECRET`, `LINK_STATE_SECRET`, `LINK_CALLBACK_API_KEY`, `PORTONE_IDENTITY_STORE_ID`, `PORTONE_IDENTITY_CHANNEL_KEY`, `PORTONE_IDENTITY_API_SECRET`, `SAI_BACKEND_BASE_URL`.
- Mock Bank VPC CIDR은 주 VPC와 연결된 사내망 CIDR에 겹치지 않아야 합니다.

EC2 역할은 지정한 secret ARN에서만 `GetSecretValue`를 허용하고, ECR image pull과 SSM 관리 권한을 가집니다. Terraform user data에는 secret 값이 없습니다. 인스턴스 부팅 후 secret은 암호화된 root EBS에 root 전용 `.env` 파일로 기록됩니다.
