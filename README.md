# Jenkins Ephemeral Infrastructure with S3 Backup (Terraform Monorepo)

This monorepo contains two Terraform projects to deploy a disposable Jenkins server on EC2 using Docker, while preserving Jenkins data in an S3 bucket.

---

## ✅ Prerequisites

Before running the main workflow, you **must** have:

1. **AWS credentials configured** with permissions for S3, IAM, and EC2.  
Test with:

```bash
   aws sts get-caller-identity
```

2. Terraform and AWS CLI installed:
Test with:

```bash
terraform -version
aws --version
```

3. SSH key pair ready.

Terraform will upload your public key to AWS EC2 so you can log in.
By default, we expect:

```bash
~/.ssh/id_rsa     (private key — keep secure)
~/.ssh/id_rsa.pub (public key — shared with AWS)
```

**Note:** If you don’t have a key pair yet:

```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
ls -l ~/.ssh/id_rsa ~/.ssh/id_rsa.pub
```

---

## 📁 Project Structure

![Project directory structure](#)![./images/project-structure.png](https://github.com/endiesworld/ec2-jenkins-server/images/project-structure.png)


---

## Assumptions
The following assumptions simplify the setup. If your environment differs, adjust the noted variables.

1. EC2 default user
- Assumes Amazon Linux 2 → ec2-user.
- If using Ubuntu, set ssh_user = "ubuntu" in Terraform or export SSH_USER=ubuntu before running the backup script.

2. S3 bucket name
- Assumes you provide the bucket via Terraform (-var="backup_bucket=...").
- Object keys default to backups/jenkins-home-<timestamp>.tar.gz.
- Override prefix by S3_PREFIX env var.

3. AWS region consistency
- Assumes EC2 and the S3 bucket are in the same region.
- If not, set AWS_REGION when running the backup script and ensure the instance role allows cross‑region S3 access.

4. Backup object integrity
- Assumes S3 upload succeeds and the object is intact.
- For strict integrity, enable checksums (e.g., upload .sha256) and verify during restore.

5. Jenkins container name
- Assumes the controller container is named jenkins.
- If you renamed it, set CONTAINER_NAME in backup_jenkins.sh or export CONTAINER_NAME=<your-name>.

## 🚀 Step-by-Step Usage

### 1. Deploy S3 Bucket + IAM Role

```bash
cd jenkins-infra/terraform-s3-backup
terraform init
terraform plan
terraform apply -var="bucket_name=jenkins-backup-bucket-<your-unique-name>"
```

***📌 Note:*** Bucket names must be globally unique.

☑️ Copy the output instance_profile_name. You’ll need it for the next step.

### 2. Deploy Jenkins EC2 Instance

Before running this, ensure that you have replaced the bucket name <jenkins-backup-bucket-project-emmanuel> with your project bucket name in the terraform.tfvars and in the user_data.sh files.

```bash
cd ../terraform-ec2-jenkins
terraform init
terraform apply 
```

***📌 Note:*** Jenkins will be available at:
```bash
http://<EC2_PUBLIC_IP>:8080
```

***📌 Note:*** To retrieve the initial admin password:
```bash
ssh -i ~/.ssh/id_rsa ec2-user@<EC2_PUBLIC_IP>
docker exec -it jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

### 3. Trigger Backup + Teardown
To backup Jenkins data before shutdown:

```bash
terraform destroy
```
---

#### Rehydrating Jenkins (Next Launch)
When you re-run terraform apply:
- The user_data.sh will pull the previous backup from S3 and extract it to /var/jenkins_home
- Jenkins will boot up with the exact previous state (jobs, configs, plugins)

#### Notes
Docker image: jenkins/jenkins:lts
- S3 lifecycle rule deletes backups older than 30 days
- IAM role has GetObject, PutObject, ListBucket permissions on this bucket only
- Port 8080 is exposed for Jenkins UI
- Port 50000 is exposed for Jenkins agents (optional)

Infrastructure Configuration
- We are not creating a VPC, but using the default one. CIDR is only needed when you define your own VPC/subnets.
- AZ control: Set the subnet, not an AZ string. The AZ is derived from the subnet.
- Public IPs: associate_public_ip_address = true requires a public subnet (or mapPublicIpOnLaunch) and an Internet Gateway/route to work outside the default VPC.
- var.my_IP must be CIDR, e.g. "203.0.113.45/32"—not just an IP. [Use this link](https://www.showmyip.com/) to get your IP.
- If you move off the default VPC, remember you need the full stack: VPC + subnets + IGW + route tables + SGs (or use the VPC module).