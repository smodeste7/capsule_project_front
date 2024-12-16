terraform {
  backend "http" {
    address         = "${env.TF_STATE_ADDRESS}"
    lock_address    = "${env.TF_STATE_ADDRESS}/lock"
    unlock_address  = "${env.TF_STATE_ADDRESS}/lock"
    lock_method     = "POST"
    unlock_method   = "DELETE"
    username        = "${env.GITLAB_USER_LOGIN}"
    password        = "${env.GITLAB_ACCESS_TOKEN}"
    retry_wait_min  = 5
  }
}

# Provider AWS pour les autres ressources (en Europe)
provider "aws" {
  region = "eu-west-3"
}

# Provider AWS pour ACM dans la région us-east-1 pour le certificat CloudFront
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Variables pour les domaines et certificats
variable "domain_name" {
  description = "Domaine principal"
  type        = string
  default     = "smo4.cloud"
}

variable "front_subdomain" {
  description = "Sous-domaine pour le frontend"
  type        = string
  default     = "front"
}

variable "api_subdomain" {
  description = "Sous-domaine pour l'API"
  type        = string
  default     = "api"
}

variable "ARN_ACM" {
  description = "ARN du certificat ACM existant"
  type        = string
  default     = "arn:aws:acm:us-east-1:463470970455:certificate/46b96f00-7a96-470e-8cb4-d74961b0e03c"  # Valeur en dur de l'ARN du certificat ACM
}

# Récupération de la zone Route53 existante
data "aws_route53_zone" "main" {
  name = var.domain_name
}

# Utilisation du certificat ACM existant pour le frontend (via la valeur en dur de l'ARN)
data "aws_acm_certificate" "frontend_cert" {
  provider        = aws.us_east_1
  domain = var.domain_name
  most_recent = true
  statuses = ["ISSUED"]
}

# Bucket S3
resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "frontbucketmorningnews"
  
  tags = {
    Name        = "Frontend Deployment Bucket"
    Environment = "Production"
  }
}

# Configuration de l'hébergement de site statique S3
resource "aws_s3_bucket_website_configuration" "static_website" {
  bucket = aws_s3_bucket.frontend_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

# Configuration d'accès public pour le bucket S3
resource "aws_s3_bucket_public_access_block" "frontend_bucket_access" {
  bucket = aws_s3_bucket.frontend_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Politique de bucket pour autoriser la lecture publique
resource "aws_s3_bucket_policy" "allow_public_read" {
  bucket = aws_s3_bucket.frontend_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend_bucket_access]
}

# Distribution CloudFront avec support HTTPS et domaine personnalisé
resource "aws_cloudfront_distribution" "frontend_distribution" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.static_website.website_endpoint
    origin_id   = "S3-Website-${aws_s3_bucket.frontend_bucket.id}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = ["${var.front_subdomain}.${var.domain_name}"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Website-${aws_s3_bucket.frontend_bucket.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.frontend_cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Enregistrements Route53 pour CloudFront (front.smo4.cloud)
resource "aws_route53_record" "frontend" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.front_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.frontend_distribution.hosted_zone_id
    evaluate_target_health = true
  }
}

# Enregistrement Route53 pour l'API (api.smo4.cloud) pointant vers l'IP EC2
resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.api_subdomain}.${var.domain_name}"
  type    = "A"
  
  ttl     = 300
  records = ["15.237.130.157"]
}

# Outputs utiles
output "s3_website_endpoint" {
  value = aws_s3_bucket_website_configuration.static_website.website_endpoint
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.frontend_distribution.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.frontend_distribution.id
}

output "frontend_url" {
  value = "https://${var.front_subdomain}.${var.domain_name}"
}
