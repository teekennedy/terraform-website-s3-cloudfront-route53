################################################################################################################
## Creates a setup to serve a static website from an AWS S3 bucket, with a Cloudfront CDN and
## certificates from AWS Certificate Manager.
##
## Bucket name restrictions:
##    http://docs.aws.amazon.com/AmazonS3/latest/dev/BucketRestrictions.html
## Duplicate Content Penalty protection:
##    Description: https://support.google.com/webmasters/answer/66359?hl=en
##    Solution: http://tuts.emrealadag.com/post/cloudfront-cdn-for-s3-static-web-hosting/
##        Section: Restricting S3 access to Cloudfront
## Deploy remark:
##    Do not push files to the S3 bucket with an ACL giving public READ access, e.g s3-sync --acl-public
##
## 2016-05-16
##    AWS Certificate Manager supports multiple regions. To use CloudFront with ACM certificates, the
##    certificates must be requested in region us-east-1
################################################################################################################

locals {
  tags = merge(
    var.tags,
    {
      "domain" = replace(var.domain, "*", "--wildcard--")
    },
  )
}

################################################################################################################
## Configure the bucket and static website hosting
################################################################################################################
resource "aws_s3_bucket" "website_bucket" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  //  logging {
  //    target_bucket = "${var.log_bucket}"
  //    target_prefix = "${var.log_bucket_prefix}"
  //  }

  tags = local.tags
}

resource "aws_s3_bucket_website_configuration" "website_bucket_website_config" {
  bucket = aws_s3_bucket.website_bucket.id
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "404.html"
  }
}

resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = aws_s3_bucket.website_bucket.id
  policy = templatefile(
    "${path.module}/website_bucket_policy.json", {
      bucket = var.bucket_name
      secret = var.duplicate-content-penalty-secret
  })
}

################################################################################################################
## Configure the credentials and access to the bucket for a deployment user
################################################################################################################
resource "aws_iam_policy" "site_deployer_policy" {
  count = var.deployer != null ? 1 : 0

  name        = "${var.bucket_name}.deployer"
  path        = "/"
  description = "Policy allowing to publish a new version of the website to the S3 bucket"
  policy = templatefile("${path.module}/deployer_role_policy.json",
    {
      bucket = var.bucket_name
    }
  )
}

resource "aws_iam_policy_attachment" "site-deployer-attach-user-policy" {
  count = var.deployer != null ? 1 : 0

  name       = "${var.bucket_name}-deployer-policy-attachment"
  users      = [var.deployer]
  policy_arn = aws_iam_policy.site_deployer_policy.0.arn
}

################################################################################################################
## Create a Cloudfront distribution for the static website
################################################################################################################
resource "aws_cloudfront_distribution" "website_cdn" {
  enabled         = true
  is_ipv6_enabled = var.ipv6
  price_class     = var.price_class
  http_version    = "http2"

  wait_for_deployment = var.wait-for-deployment

  origin {
    origin_id   = "origin-bucket-${aws_s3_bucket.website_bucket.id}"
    domain_name = aws_s3_bucket_website_configuration.website_bucket_website_config.website_endpoint
    origin_path = var.bucket_path

    custom_origin_config {
      origin_protocol_policy = "http-only"
      http_port              = "80"
      https_port             = "443"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }

    custom_header {
      name  = "User-Agent"
      value = var.duplicate-content-penalty-secret
    }
  }

  default_root_object = var.default-root-object

  dynamic "custom_error_response" {
    for_each = var.not-found-response-enabled == true ? [1] : []
    content {
      error_code            = "404"
      error_caching_min_ttl = "360"
      response_code         = var.not-found-response-code
      response_page_path    = var.not-found-response-path
    }
  }

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD", "DELETE", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = var.forward-query-string

      cookies {
        forward = "none"
      }
    }

    trusted_signers = var.trusted_signers

    min_ttl          = "0"
    default_ttl      = "300"  //3600
    max_ttl          = "1200" //86400
    target_origin_id = "origin-bucket-${aws_s3_bucket.website_bucket.id}"

    // This redirects any HTTP request to HTTPS. Security first!
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    dynamic "lambda_function_association" {
      for_each = [for lfa in var.default_cache_behavior_lambda_function_associations : {
        event_type   = lfa.event_type
        lambda_arn   = lfa.lambda_arn
        include_body = lfa.include_body
      }]
      content {
        event_type   = lambda_function_association.value.event_type
        lambda_arn   = lambda_function_association.value.lambda_arn
        include_body = lambda_function_association.value.include_body
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm-certificate-arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = var.minimum_client_tls_protocol_version
  }

  aliases = [var.domain]
  tags    = local.tags

  dynamic "origin" {
    for_each = [for o in var.origins : {
      origin_id                        = o.origin_id
      domain_name                      = o.domain_name
      origin_path                      = o.origin_path
      origin_protocol_policy           = o.origin_protocol_policy
      duplicate_content_penalty_secret = o.duplicate_content_penalty_secret
    }]
    content {
      origin_id   = origin.value.origin_id
      domain_name = origin.value.domain_name
      origin_path = origin.value.origin_path

      custom_origin_config {
        origin_protocol_policy = origin.value.origin_protocol_policy
        http_port              = "80"
        https_port             = "443"
        origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
      }

      dynamic "custom_header" {
        for_each = origin.value.duplicate_content_penalty_secret != "" ? ["present"] : []

        content {
          name  = "User-Agent"
          value = origin.value.duplicate_content_penalty_secret
        }
      }
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = [for b in var.ordered_cache_behaviors : {
      min_ttl              = b.min_ttl
      default_ttl          = b.default_ttl
      max_ttl              = b.max_ttl
      path_pattern         = b.path_pattern
      target_origin_id     = b.target_origin_id
      headers              = b.forwarded_values_headers
      forward              = b.cookies_forward
      event_type           = b.event_type
      lambda_arn           = b.lambda_arn
      include_body         = b.include_body
      forward_query_string = b.forward_query_string
    }]
    content {
      allowed_methods = ["GET", "HEAD", "DELETE", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods  = ["GET", "HEAD"]

      min_ttl     = ordered_cache_behavior.value.min_ttl
      default_ttl = ordered_cache_behavior.value.default_ttl
      max_ttl     = ordered_cache_behavior.value.max_ttl

      path_pattern           = ordered_cache_behavior.value.path_pattern
      target_origin_id       = ordered_cache_behavior.value.target_origin_id
      viewer_protocol_policy = "redirect-to-https"

      forwarded_values {
        query_string = ordered_cache_behavior.value.forward_query_string
        headers      = ordered_cache_behavior.value.headers
        cookies {
          forward = ordered_cache_behavior.value.forward
        }
      }
      # Set lambda_arn to an empty string to skip lambda function association
      dynamic "lambda_function_association" {
        for_each = ordered_cache_behavior.value.lambda_arn != "" ? ["present"] : []

        content {
          event_type   = ordered_cache_behavior.value.event_type
          lambda_arn   = ordered_cache_behavior.value.lambda_arn
          include_body = ordered_cache_behavior.value.include_body
        }
      }
    }
  }
}
