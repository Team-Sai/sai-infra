# CloudFront는 서울 Mock Bank VPC 안의 private EC2를 원본으로 사용합니다.
resource "terraform_data" "mock_bank_vpc_origin_instance" {
  triggers_replace = [aws_instance.web.id]
}

resource "aws_cloudfront_vpc_origin" "mock_bank" {
  vpc_origin_endpoint_config {
    name                   = "${var.name_prefix}-mock-bank-origin-${substr(aws_instance.web.id, 2, 8)}"
    arn                    = aws_instance.web.arn
    http_port              = var.mock_bank_origin_port
    https_port             = var.mock_bank_api_port
    origin_protocol_policy = "http-only"

    # Provider 스키마가 HTTPS 원본용 허용 프로토콜 설정도 요구합니다. 현재 정책은 HTTP 전용입니다.
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = {
    Name = "${var.name_prefix}-mock-bank-origin"
  }

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [terraform_data.mock_bank_vpc_origin_instance]
  }
}

# AWS가 CloudFront VPC Origin을 위해 생성하는 서비스 관리형 보안 그룹을 원본 허용 출발지로 사용합니다.
data "aws_security_group" "cloudfront_vpc_origin" {
  filter {
    name   = "vpc-id"
    values = [aws_vpc.mock_bank.id]
  }

  filter {
    name   = "group-name"
    values = ["CloudFront-VPCOrigins-Service-SG"]
  }

  depends_on = [aws_cloudfront_vpc_origin.mock_bank]
}

resource "aws_vpc_security_group_ingress_rule" "cloudfront_origin" {
  security_group_id            = aws_security_group.web.id
  referenced_security_group_id = data.aws_security_group.cloudfront_vpc_origin.id
  description                  = "CloudFront VPC Origin access to browser listener"
  ip_protocol                  = "tcp"
  from_port                    = var.mock_bank_origin_port
  to_port                      = var.mock_bank_origin_port
}

resource "aws_wafv2_web_acl" "mock_bank" {
  provider = aws.us_east_1

  name        = "${var.name_prefix}-mock-bank-cloudfront"
  description = "CloudFront WAF for the synthetic Mock Bank demo"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedCommonRules"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-mock-bank-common"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "ViewerRateLimit"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-mock-bank-rate-limit"
      sampled_requests_enabled   = false
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-mock-bank-waf"
    sampled_requests_enabled   = false
  }
}

resource "aws_cloudfront_distribution" "mock_bank" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Mock Bank browser demo through a private VPC Origin"
  price_class     = "PriceClass_200"
  web_acl_id      = aws_wafv2_web_acl.mock_bank.arn
  aliases         = var.viewer_domain_name == null ? [] : [var.viewer_domain_name]

  origin {
    domain_name = aws_instance.web.private_dns
    origin_id   = "${var.name_prefix}-mock-bank-vpc-origin"

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.mock_bank.id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 60
    }
  }

  default_cache_behavior {
    target_origin_id       = "${var.name_prefix}-mock-bank-vpc-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # 로그인 세션, 쿼리 파라미터, 폼/API 요청을 보존하고 응답은 캐시하지 않습니다.
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.viewer_domain_name == null
    acm_certificate_arn            = var.viewer_domain_name == null ? null : var.viewer_certificate_arn
    ssl_support_method             = var.viewer_domain_name == null ? null : "sni-only"
    minimum_protocol_version       = var.viewer_domain_name == null ? null : "TLSv1.2_2021"
  }

  depends_on = [
    aws_vpc_security_group_ingress_rule.cloudfront_origin,
    aws_route53_zone.api_private,
  ]
}
