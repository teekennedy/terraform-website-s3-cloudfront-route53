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
      "domain" = replace(var.domain, "*", "star")
    },
  )
  bucket_name = var.bucket_name != "" ? var.bucket_name : "site.${replace(replace(var.domain, ".", "-"), "*", "star")}"
}

################################################################################################################
## Configure the bucket and static website hosting
################################################################################################################
resource "aws_s3_bucket" "website_bucket" {
  bucket = local.bucket_name

  //  logging {
  //    target_bucket = "${var.log_bucket}"
  //    target_prefix = "${var.log_bucket_prefix}"
  //  }

  tags = local.tags
}

resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = aws_s3_bucket.website_bucket.id
  policy = templatefile("${path.module}/website_redirect_bucket_policy.json",
    {
      bucket = aws_s3_bucket.website_bucket.id
      secret = var.duplicate-content-penalty-secret
    }
  )
}

resource "aws_s3_bucket_website_configuration" "website_bucket_website_config" {
  bucket = aws_s3_bucket.website_bucket.id
  redirect_all_requests_to {
    host_name = var.target
    protocol  = "https"
  }
}

################################################################################################################
## Configure the credentials and access to the bucket for a deployment user
################################################################################################################
resource "aws_iam_policy" "site_deployer_policy" {
  count = var.deployer != null ? 1 : 0

  name        = "${local.bucket_name}.deployer"
  path        = "/"
  description = "Policy allowing to publish a new version of the website to the S3 bucket"
  policy = templatefile("${path.module}/deployer_role_policy.json",
    {
      bucket = local.bucket_name
    }
  )
}

resource "aws_iam_policy_attachment" "staging-site-deployer-attach-user-policy" {
  count = var.deployer != null ? 1 : 0

  name       = "${local.bucket_name}-deployer-policy-attachment"
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

  origin {
    origin_id   = "origin-bucket-${aws_s3_bucket.website_bucket.id}"
    domain_name = aws_s3_bucket_website_configuration.website_bucket_website_config.website_endpoint

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

  default_root_object = var.default_root_object

  custom_error_response {
    error_code            = "404"
    error_caching_min_ttl = "360"
    response_code         = "200"
    response_page_path    = "/404.html"
  }

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD", "DELETE", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl          = "0"
    default_ttl      = "300"  //3600
    max_ttl          = "1200" //86400
    target_origin_id = "origin-bucket-${aws_s3_bucket.website_bucket.id}"

    // This redirects any HTTP request to HTTPS. Security first!
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
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

  tags = local.tags
}
