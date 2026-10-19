# Security Policy & Architecture Controls

This document describes the security controls configured in Terraform, the current Checkov baseline, and the limitations of this portfolio lab. Runtime verification is tracked separately in [README.md](README.md#verification-evidence).

## Security Posture Overview

Terraform configures controls across the network, compute, IAM, and state storage layers. CI performs Terraform validation and Checkov static analysis; these checks do not prove that a deployed environment behaves as intended.

```text
[Internet]
    │
    ▼ (HTTP :80)
[ALB Security Group]
    │
    ▼ (HTTP :80 - Referenced SG only)
[EC2 Security Group] (Private Subnets, No Public IP, No NAT GW)
    │
    ▼ (HTTPS :443 - Referenced SG only)
[VPC Endpoints SG] (Interface Endpoints: ssm, ssmmessages)
```

## Implemented Security Controls

### 1. Network Perimeter & Isolation

- **Private Subnets Only**: EC2 instances reside exclusively in private subnets with `map_public_ip_on_launch = false`.
- **No Direct Inbound Internet Access to EC2**: Compute instances have no public IP or direct route to the Internet Gateway. Public application traffic reaches them through the ALB on HTTP port 80.
- **No Direct Internet Egress**: Private route tables have no default route and no NAT Gateway. Management connections use private VPC Interface Endpoints for `ssm` and `ssmmessages`; the application remains reachable through the ALB.
- **Default Security Group Quarantine**: The default VPC security group is adopted by Terraform (`aws_default_security_group.default`) and stripped of all ingress and egress rules to prevent accidental usage.

### 2. Micro-segmentation & Security Groups

- **Referenced Security Groups**: Inter-tier traffic does not use CIDR blocks. Security groups reference each other directly:
  - ALB egress permits traffic *only* to `aws_security_group.ec2.id` on port 80.
  - EC2 ingress permits traffic *only* from `aws_security_group.alb.id` on port 80.
  - EC2 egress permits traffic *only* to `aws_security_group.vpc_endpoints.id` on port 443.
- **No Inbound Port 22**: SSH is entirely absent from all security group definitions.

### 3. Compute Hardening

- **IMDSv2 Enforcement**: Launch template sets `http_tokens = "required"`, mitigating SSRF-based metadata theft attacks.
- **Dynamic AMI Resolution**: Uses AWS Systems Manager parameter (`/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64`) to reference maintained Amazon Linux 2023 images.
- **Service Management**: systemd manages `platform-app.service` and restarts it on failure. The current unit runs as root and has no explicit sandboxing options; service management alone does not provide process isolation.

### 4. Identity & Access Management (IAM)

- **SSM Instance Profile**: EC2 instances assume a role with the AWS-managed `AmazonSSMManagedInstanceCore` policy. No application-specific policy is attached. This managed policy is a functional SSM baseline, not a custom least-privilege policy for this workload.
- **Operator ABAC Scoping**: The administrative policy (`production-platform-ssm-operator`) restricts `ssm:StartSession` via resource tags:
  - `ssm:resourceTag/Project == "AWS_Platform_IaC"`
  - `ssm:resourceTag/Environment == "lab"`
- **Operator Policy Scope**: The policy grants terminate/resume permissions for sessions matching `session/&{aws:userid}-*`. Terraform creates the policy but does not attach it to an operator identity; effective access also depends on that identity's other policies and must be tested.
- **Flow Logs Execution Role**: Log stream creation, delivery, and stream discovery are scoped to the Flow Logs group. `logs:DescribeLogGroups` uses `Resource = "*"`.

### 5. State & Data Protection

- **S3 Bucket Restrictions**: Terraform state bucket enforces:
  - `block_public_acls = true`, `block_public_policy = true`, `ignore_public_acls = true`, `restrict_public_buckets = true`.
  - AES256 server-side encryption enabled by default.
  - S3 object versioning enabled to prevent accidental destruction or corruption.
  - `prevent_destroy = true` lifecycle guard on state bucket.
- **Native State Locking**: Uses `use_lockfile = true` to avoid race conditions during concurrent `terraform apply` operations without external dependencies.

### 6. Observability & Auditing

- **VPC Flow Logs**: Configured with `traffic_type = "ALL"` to record accepted and rejected traffic metadata in the CloudWatch log group `flow_logs`. Flow Logs are network metadata, not packet contents or application audit logs.
- **Metrics & Alarms**: Alarms are configured for `HealthyHostCount < 2` and `HTTPCode_Target_5XX_Count > 0`, each over two 60-second evaluation periods. No alarm notification actions are configured.
- **SSM Session Logging**: This repository does not configure session command/output logging to CloudWatch Logs or S3. Session Manager supports it when session preferences, permissions, and connectivity are configured. See [AWS session logging documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-logging.html).

---

## Static Security Analysis & Checkov Baseline

The CI pipeline runs:

```bash
checkov -d . --framework terraform --baseline .checkov.baseline --output-baseline-as-skipped
```

CI fails on Checkov findings not covered by the baseline. A finding for a resource/check combination already listed can remain suppressed after the configuration changes. Changes affecting existing exceptions require manual review, and baseline regeneration must not automatically accept every finding. See [Checkov baseline options](https://www.checkov.io/2.Basics/CLI%20Command%20Reference.html).

The table inventories every check ID currently in `.checkov.baseline`. It distinguishes intentional lab trade-offs from cleanup and scanner findings that need revalidation. These entries have not been confirmed by a fresh Checkov scan during this documentation review. Check meanings are documented in the [Checkov policy index](https://www.checkov.io/5.Policy%20Index/all.html).

| Check ID | Resource | Current rationale / Architectural trade-off |
| --- | --- | --- |
| `CKV_AWS_2`, `CKV_AWS_103` | `aws_lb_listener.http` | Lab trade-off: public HTTP demonstration; no HTTPS listener or TLS policy configured to avoid custom domain overhead. |
| `CKV2_AWS_20` | `aws_lb.public` | Lab trade-off: HTTP requests forwarded instead of redirected to HTTPS. |
| `CKV_AWS_378` | `aws_lb_target_group.app` | Lab trade-off: internal ALB-to-EC2 traffic uses unencrypted HTTP. |
| `CKV2_AWS_28` | `aws_lb.public` | Lab trade-off: AWS WAF Web ACL omitted to eliminate recurring hourly and inspection charges in lab. |
| `CKV_AWS_91` | `aws_lb.public` | Lab trade-off: ALB access logging and dedicated S3 destination omitted to keep lab footprint minimal. Flow Logs collect L4 metadata. |
| `CKV_AWS_150` | `aws_lb.public` | Lab trade-off: deletion protection is explicitly disabled (`false`) to permit clean lab teardown. |
| `CKV_AWS_145` | `aws_s3_bucket.terraform_state` | Lab trade-off: S3-managed AES256 encryption used instead of customer-managed KMS key. |
| `CKV_AWS_18`, `CKV_AWS_144` | `aws_s3_bucket.terraform_state` | Lab trade-off: S3 access logging and cross-region replication omitted for state bucket. |
| `CKV2_AWS_61`, `CKV2_AWS_62` | `aws_s3_bucket.terraform_state` | Lab trade-off: S3 state bucket lifecycle expiration and event notifications omitted. |
| `CKV_AWS_158` | `aws_cloudwatch_log_group.flow_logs` | Lab trade-off: AWS-managed encryption used instead of customer-managed KMS key (CMK). |
| `CKV_AWS_338` | `aws_cloudwatch_log_group.flow_logs` | Lab trade-off: retention set to 7 days rather than 1-year compliance requirement to optimize storage. |
| `CKV2_AWS_12` | `aws_vpc.main` | Scanner limitation: Terraform adopts default SG in `modules/security` and removes all rules, but graph parser across module boundaries flags VPC resource. |
| `CKV2_AWS_5` | `aws_security_group.alb`, `aws_security_group.ec2` | Scanner limitation: Security groups are attached dynamically across module outputs. |
| `CKV_AWS_260` | `aws_vpc_security_group_ingress_rule.alb_http` | Lab trade-off: public ALB accepts HTTP traffic on port 80 from `0.0.0.0/0`. |
| `CKV_AWS_260` | `aws_vpc_security_group_ingress_rule.ec2_from_alb` | Scanner limitation: Checkov flags ingress on port 80 even though rule restricts source strictly to the ALB security group (`referenced_security_group_id`). |

> [!NOTE]
> Previously flagged `CKV_AWS_23` (missing descriptions on security group rules) has been fully resolved by adding explicit descriptions to all ingress and egress rules, eliminating unnecessary exceptions from the baseline.

Resource names above omit module prefixes for readability; `.checkov.baseline` contains the exact addresses.

---

## Production Readiness Checklist

Before considering a production deployment, assess at least the following controls against workload requirements. This is not an exhaustive production acceptance checklist:

- [ ] Issue and attach a public TLS certificate via AWS Certificate Manager (ACM).
- [ ] Configure ALB HTTP-to-HTTPS redirect (port 80 -> port 443) with TLS 1.3 security policy.
- [ ] Associate an AWS WAF Web ACL to mitigate common web exploits and rate-limit abusive IPs.
- [ ] Enable ALB access logging to an encrypted, dedicated S3 audit bucket.
- [ ] Encrypt CloudWatch Log Groups and S3 state bucket using a Customer Managed Key (CMK) in AWS KMS with rotation enabled.
- [ ] Configure cross-region state replication or automated backup plans for production disaster recovery.
- [ ] Integrate AWS GuardDuty or Security Hub for runtime threat detection.
- [ ] Run the application under a dedicated user and add systemd hardening appropriate to the service.
- [ ] Configure SSM session logging, its IAM permissions, and a private logging destination path.
- [ ] Define and test an AMI refresh / security patching process for instances without internet egress.
- [ ] Configure alarm notifications and verify their delivery.
- [ ] Resolve cleanup findings, revalidate scanner exceptions, and test operator IAM access with allowed and denied cases.

---

## Vulnerability Reporting

If you identify a security issue or configuration flaw within this repository:

1. Do not open a public GitHub issue.
2. Submit findings privately via GitHub Security Advisories or contact the repository owner directly.
