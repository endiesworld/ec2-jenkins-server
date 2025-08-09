variable "region" {
  default = "us-west-2"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name"
  type        = string
}
