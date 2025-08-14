provider "aws" {
    region = var.region
}

resource "aws_s3_bucket" "jenkins_backup" {
    bucket = var.bucket_name
    force_destroy = true
}

resource "aws_s3_bucket_versioning" "versioning" {
    bucket = aws_s3_bucket.jenkins_backup.id

    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
    bucket = aws_s3_bucket.jenkins_backup.id

    rule {
        apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
        }
    }
}

resource "aws_s3_bucket_public_access_block" "block" {
    bucket                  = aws_s3_bucket.jenkins_backup.id
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "lifecycle" {
    bucket = aws_s3_bucket.jenkins_backup.id

    rule {
        id     = "expire-backups-30d"
        status = "Enabled"

        # optional: scope to your backup objects
        filter { prefix = "backups/" }

        # delete current version after 30 days
        expiration { days = 30 }

        # delete previous (noncurrent) versions after 30 days too
        noncurrent_version_expiration { noncurrent_days = 30 }

        # avoid stray charges from aborted multipart uploads
        abort_incomplete_multipart_upload { days_after_initiation = 7 }
    }

    # optional: tidy “orphan” delete markers (safe with versioning)
    rule {
        id     = "cleanup-delete-markers"
        status = "Enabled"
        filter { prefix = "backups/" }
        expiration { expired_object_delete_marker = true }
    }

}
