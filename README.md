# Infrastructure (Terraform)

This folder provisions one Ubuntu EC2 host prepared to run Docker workloads with `docker compose`.

## What gets created

- 1 EC2 instance running Ubuntu LTS (dynamic AMI lookup by region/version/architecture)
- 1 dedicated security group (SSH + configurable app ports)
- Optional IAM role and instance profile (enabled by default)
- Encrypted root EBS volume (`gp3` by default)
- 1 database EC2 instance (PostgreSQL host) in a private subnet with no public IP; only the API host's security group can reach it (port `db_port` and SSH)
- A private subnet inside the default VPC, with its own route table and a NAT gateway (`enable_nat_gateway`) for outbound internet
- Cloud-init style host bootstrap via `user_data.sh` for Docker Engine + Compose plugin

## Prerequisites

- Terraform >= 1.5.0
- AWS credentials configured for the target account
- Existing VPC/subnet access in the target region

## Usage

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and adjust values.
2. Initialize providers:

```bash
terraform init
```

3. Validate formatting and config:

```bash
terraform fmt -recursive
terraform validate
```

4. Create and review plan:

```bash
terraform plan -var-file=terraform.tfvars
```

## Database snapshots bucket and DR

- The snapshots bucket is replicated to `db_snapshots_replication_region` (default `eu-central-1`), only when applying in the primary region. Set it to `""` to disable.
- Replication is bidirectional: snapshots uploaded to the DR bucket during a failover are replicated back to the primary bucket. Both replication rules are managed by the primary stack.
- Failover: the replica bucket has the name the DR stack gives its own bucket. Before the first DR apply, adopt it:
  `terraform import aws_s3_bucket.db_snapshots <bucket-name>` (see the `db_snapshots_replica_bucket` output of the primary stack). Do not destroy the DR stack afterwards without removing that bucket from its state first (`terraform state rm`), or the shared bucket is deleted.
- Deletes in the primary bucket are not replicated, so the DR copy survives accidental deletion (it still expires after `db_snapshots_retention_days`).
- Replication only copies objects uploaded after it is enabled.

## Notes

- If `subnet_id` is `null`, Terraform uses the first subnet from the default VPC.
- SSH is restricted to `ssh_allowed_cidr`; avoid broad CIDRs.
- Docker is installed from Docker's official Ubuntu apt repository.
- This stack prepares the host only; it does not deploy the application containers.

## Secrets in SSM Parameter Store

Terraform does not create the values (so they never land in the state or `user_data`); it only grants the EC2 roles read access. Create them once per region as `SecureString`:

```bash
P=/coika/auth_service   # output ssm_parameter_prefix
aws ssm put-parameter --type SecureString --name $P/db/POSTGRES_DB       --value '...'
aws ssm put-parameter --type SecureString --name $P/db/POSTGRES_USER     --value '...'
aws ssm put-parameter --type SecureString --name $P/db/POSTGRES_PASSWORD --value '...'
aws ssm put-parameter --type SecureString --name $P/app/JWT_PRIVATE_KEY  --value '...'
```

On the instance, read them with its role (no credentials needed):

```bash
aws ssm get-parameters-by-path --path $P/db --with-decryption \
  --query 'Parameters[].[Name,Value]' --output text
```

- The database host can read `db/*`; the API host can read `db/*` and `app/*`.
- Parameters are regional: the DR region needs its own copy.
