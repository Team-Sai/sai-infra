# 이 사설 Hosted Zone은 API FQDN만 관리하므로 팀 도메인의 다른 DNS 레코드를 가리지 않습니다.
resource "aws_route53_zone" "api_private" {
  name = var.mock_bank_api_hostname

  vpc {
    vpc_id = aws_vpc.mock_bank.id
  }

  vpc {
    vpc_id = var.main_vpc_id
  }

  comment = "Private Mock Bank API name for SAI VPC peering"
}

resource "aws_route53_record" "api_private" {
  zone_id = aws_route53_zone.api_private.zone_id
  name    = var.mock_bank_api_hostname
  type    = "A"
  ttl     = 60
  records = [aws_instance.mock_bank.private_ip]
}

# 사용자 지정 브라우저 도메인은 선택 사항입니다. 미지정 시 CloudFront 기본 HTTPS 도메인을 사용합니다.
resource "aws_route53_record" "viewer_alias" {
  for_each = var.viewer_domain_name == null ? toset([]) : toset(["A", "AAAA"])

  zone_id = var.public_hosted_zone_id
  name    = var.viewer_domain_name
  type    = each.value

  alias {
    name                   = aws_cloudfront_distribution.mock_bank.domain_name
    zone_id                = aws_cloudfront_distribution.mock_bank.hosted_zone_id
    evaluate_target_health = false
  }
}
