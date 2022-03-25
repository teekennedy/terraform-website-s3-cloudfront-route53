variable "region" {
  default = "us-east-1"
}

variable "domain" {
  type = string
}

variable "bucket_name" {
  type        = string
  description = "The name of the S3 bucket to create."
}

variable "bucket_path" {
  type        = string
  description = "The folder in the S3 bucket to serve the website from."
  default     = null
}

variable "duplicate-content-penalty-secret" {
  type = string
}

variable "acm-certificate-arn" {
  type = string
}

variable "deployer" {
  type    = string
  default = null
}

variable "default-root-object" {
  type    = string
  default = "index.html"
}

variable "not-found-response-enabled" {
  type    = bool
  default = false
}

variable "not-found-response-path" {
  type    = string
  default = "/404.html"
}

variable "not-found-response-code" {
  type    = string
  default = "200"
}

variable "wait-for-deployment" {
  type    = bool
  default = true
}

variable "tags" {
  type        = map(string)
  description = "Optional Tags"
  default     = {}
}

variable "trusted_signers" {
  type    = list(string)
  default = []
}

variable "forward-query-string" {
  type        = bool
  description = "Forward the query string to the origin"
  default     = false
}

variable "price_class" {
  type        = string
  description = "CloudFront price class"
  default     = "PriceClass_200"
}

variable "default_cache_behavior_lambda_function_associations" {
  description = "Optional Lambda@Edge function associations for the Default Cache Behavior (S3 bucket)"
  default     = []
  type = list(object({
    event_type   = string
    lambda_arn   = string
    include_body = bool
  }))
}

variable "origins" {
  description = "Additional origins, supplementary to the default origin created from the S3 bucket"
  default     = []
  type = list(object({
    origin_id                        = string
    domain_name                      = string
    origin_path                      = string
    origin_protocol_policy           = string
    duplicate_content_penalty_secret = string
  }))
}

variable "ordered_cache_behaviors" {
  description = "Additional routing behaviors"
  default     = []
  type = list(object({
    min_ttl                  = string
    default_ttl              = string
    max_ttl                  = string
    path_pattern             = string
    target_origin_id         = string
    forwarded_values_headers = list(string)
    cookies_forward          = string
    event_type               = string
    lambda_arn               = string
    include_body             = bool
    forward_query_string     = bool
  }))
}

variable "ipv6" {
  type        = bool
  description = "Enable IPv6 on CloudFront distribution"
  default     = false
}

variable "minimum_client_tls_protocol_version" {
  type        = string
  description = "CloudFront viewer certificate minimum protocol version"
  default     = "TLSv1"
}

variable "force_destroy" {
  type        = bool
  description = "A boolean that indicates all objects (including any locked objects) should be deleted from the bucket so that the bucket can be destroyed without error. These objects are not recoverable."
  default     = false
}
