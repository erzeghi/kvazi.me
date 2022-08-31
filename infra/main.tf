# NOTES:
# - Domain zone is created manually in Route53 and DNSes updated on registrar. ZoneID is needed as variable
# - When destroying infra S3 need to be empty to succeed

provider "aws" {
  region = "us-east-1"
}

variable "root_domain" {
  type = string
}

variable "zone_id" {
  type = string
}

locals {
  www_domain = join(".", ["www",var.root_domain])
  s3_origin_id =  join("-", ["S3", var.root_domain])
}

# ACM

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  domain_name  = var.root_domain
  zone_id      = var.zone_id

  subject_alternative_names = [
    local.www_domain
  ]

  wait_for_validation = true
}

# S3 (empty before destroy)

resource "aws_s3_bucket" "site" {
  bucket = var.root_domain
}

resource "aws_s3_bucket_acl" "acl" {
  bucket = aws_s3_bucket.site.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_website_configuration" "config" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# // after cloudfront creation

resource "aws_route53_record" "root_domain" {
  zone_id = var.zone_id
  name = var.root_domain
  type = "A"

  alias {
    name = aws_cloudfront_distribution.cdn_dist.domain_name
    zone_id = aws_cloudfront_distribution.cdn_dist.hosted_zone_id
    evaluate_target_health = false
  }
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.dist_oai.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

# CLOUDFRONT

resource "aws_cloudfront_origin_access_identity" "dist_oai" {
  comment = join(" ", [var.root_domain, "access identity"])
}

resource "aws_cloudfront_distribution" "cdn_dist" {
  origin {
    domain_name = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.dist_oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = join(" ", [var.root_domain, "distribution"])
  default_root_object = "index.html"


  aliases = [var.root_domain, local.www_domain]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }


  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = module.acm.acm_certificate_arn
    minimum_protocol_version = "TLSv1"
    ssl_support_method = "sni-only"
  }
}

