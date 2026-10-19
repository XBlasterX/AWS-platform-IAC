# Runtime Verification Evidence

This document records runtime verification evidence collected on a live deployment of the AWS Platform IaC infrastructure in `eu-north-1`.

- **Date of Verification**: 2026-10-19
- **Environment**: AWS (`eu-north-1`)
- **Target VPC**: `vpc-07d605217a65f6fc4` (`10.40.0.0/16`)

---

## 1. Application Load Balancer HTTP Availability

**Test Execution**:
```bash
curl -i http://production-platform-alb-648879550.eu-north-1.elb.amazonaws.com
```

**Output**:
```http
HTTP/1.1 200 OK
Date: Mon, 19 Oct 2026 08:03:57 GMT
Content-Type: text/html
Content-Length: 45
Connection: keep-alive
Server: SimpleHTTP/0.6 Python/3.9.25
Last-Modified: Mon, 19 Oct 2026 08:03:34 GMT

Production AWS Platform — Instance Running
```

**Target Health Verification**:
```json
{
  "TargetHealthDescriptions": [
    {
      "Target": {
        "Id": "i-0bf48ddb1122915fe",
        "Port": 80
      },
      "TargetHealth": {
        "State": "healthy"
      }
    },
    {
      "Target": {
        "Id": "i-01fa154af362b947d",
        "Port": 80
      },
      "TargetHealth": {
        "State": "healthy"
      }
    }
  ]
}
```

---

## 2. AWS Systems Manager (SSM) Private Connectivity

Instances reside in private subnets with no public IP, no NAT Gateway, and no inbound SSH (port 22). Connectivity is established entirely via private VPC Interface Endpoints (`ssm`, `ssmmessages`).

**SSM Agent Ping Status**:
```json
[
  {
    "InstanceId": "i-01fa154af362b947d",
    "PingStatus": "Online",
    "PlatformName": "Amazon Linux",
    "PlatformVersion": "2023",
    "IPAddress": "10.40.30.18"
  },
  {
    "InstanceId": "i-0bf48ddb1122915fe",
    "PingStatus": "Online",
    "PlatformName": "Amazon Linux",
    "PlatformVersion": "2023",
    "IPAddress": "10.40.40.240"
  }
]
```

**SSM Command Execution (Uptime verification)**:
```json
{
  "CommandId": "c6946b55-7b6a-4011-9bec-37f7acf9858a",
  "InstanceId": "i-01fa154af362b947d",
  "Status": "Success",
  "ResponseCode": 0,
  "StandardOutputContent": " 08:04:20 up 0 min, 0 users, load average: 0.12, 0.04, 0.01\n"
}
```

---

## 3. Compute Hardening & IMDSv2 Enforcement

Direct unauthenticated requests to the Instance Metadata Service (IMDSv1) are rejected. Authenticated session token requests (IMDSv2) succeed.

**Verification command**:
```bash
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id
```

**Result**:
```text
i-01fa154af362b947d
```

---

## 4. Auto Scaling Group Self-Healing & Recovery

To verify resilience, instance `i-0bf48ddb1122915fe` was forcefully terminated.

**Termination Event**:
```json
{
  "InstanceId": "i-0bf48ddb1122915fe",
  "CurrentState": { "Name": "shutting-down" }
}
```

**Auto Scaling Reaction**:
The Auto Scaling Group identified capacity drop and immediately provisioned replacement instance `i-08d308bb2e324b6de`:
```json
[
  [ "i-01fa154af362b947d", "InService", "Healthy" ],
  [ "i-08d308bb2e324b6de", "Pending", "Healthy" ],
  [ "i-0bf48ddb1122915fe", "Terminating", "Unhealthy" ]
]
```
During the transition, HTTP requests through the ALB continued to return `200 OK` without downtime.

---

## 5. VPC Flow Logs Delivery

VPC Flow Logs actively capture network traffic across all Elastic Network Interfaces (ENIs) and deliver metadata to CloudWatch Log Group `flow_logs`:
- Active log streams verified: `eni-012a927a06396b56e-all`, `eni-0281d7f9093819eeb-all`, `eni-0781b4de321d389ec-all`, `eni-0993c341f5ea0c91a-all`, `eni-0a0c8a34e5d625e12-all`, `eni-0b8bcbca82d4c8b39-all`, `eni-0e2110ae1061d616d-all`.

