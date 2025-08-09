resource "aws_iam_role" "jenkins_ec2_s3_role" {
  name = "jenkins-ec2-s3-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "jenkins_s3_access_policy" {
  name        = "jenkins-s3-access-policy"
  description = "Allow Jenkins EC2 access to backup bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.jenkins_backup.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.jenkins_backup.bucket}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.jenkins_ec2_s3_role.name
  policy_arn = aws_iam_policy.jenkins_s3_access_policy.arn
}

resource "aws_iam_instance_profile" "jenkins_instance_profile" {
  name = "jenkins-ec2-instance-profile" # Instance profile for Jenkins EC2 intentionally named to avoid confusion
  role = aws_iam_role.jenkins_ec2_s3_role.name
}
