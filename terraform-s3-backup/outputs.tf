output "bucket_name" {
  value = aws_s3_bucket.jenkins_backup.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.jenkins_backup.arn
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.jenkins_instance_profile.name
}
