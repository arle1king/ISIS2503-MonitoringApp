# Arquitectura Visual - ISIS2503 Monitoring App

## 🏢 Vista General de la Infraestructura

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         INTERNET & USERS                                │
│                                                                         │
│                          requests/responses                             │
└────────────────┬────────────────────────────────────────────────────────┘
                 │
                 ▼
        ┌────────────────────┐
        │   AWS WAF Rules    │  ◄─ Disponibilidad  (ASR 1)
        │ ├─ Rate Limiting   │     Confidencialidad (ASR 2)
        │ ├─ SQL Injection   │     Integridad       (ASR 3)
        │ ├─ XSS Rules       │
        │ └─ IP Blocking     │
        └────────────┬───────┘
                     │
                     ▼
    ┌─────────────────────────────────┐
    │   Application Load Balancer     │  HTTP/HTTPS port 80/443
    │   (Cross-Zone, Multi-AZ)        │
    │                                 │
    │  Health Check:                  │
    │  • Every 5 seconds              │
    │  • Timeout: 3 seconds           │
    │  • Unhealthy after: 2 failures  │
    └────────────────┬────────────────┘
                     │
         ┌───────────┼───────────┐
         │           │           │
         ▼           ▼           ▼
    ┌─────────┐ ┌─────────┐ ┌─────────┐
    │   EC2   │ │   EC2   │ │   EC2   │  t3.medium instances
    │ Django │ │ Django │ │ Django │  Auto Scaling Group
    │ Port   │ │ Port   │ │ Port   │  Min: 2, Max: 6
    │ 8000   │ │ 8000   │ │ 8000   │  Desired: 3
    └────┬────┘ └────┬────┘ └────┬────┘
         │           │           │
         │    Security Group     │
         │ (Ingress: ALB:8000)   │
         │ (Egress: HTTPS/DNS)   │
         │                       │
         └───────────┬───────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │   AWS RDS MultiAZ      │
        │  PostgreSQL 15.3       │
        │                        │
        │  Primary → Standby     │
        │  (Auto Failover)       │
        │                        │
        │  Encrypted (KMS)       │
        │  SSL Obligatorio       │
        │  Multi-AZ: Enabled     │
        └────────────────────────┘
```

---

## 🔄 Flujo de Disponibilidad (ASR 1)

```
USER REQUEST
     │
     ▼
   ALB
   (Health Check: OK)
     │
     ├──────────────────────────────────────┐
     │                                      │
     ▼                                      │
   EC2-1 (OK)          FAILURE: EC2-2 dies
   (responds OK)                │
                                ▼
                          EC2-2 (OFFLINE)
                          ▼
                    ALB detects
                    (Health check fails)
                          │
                ┌─────────┼─────────┐
                │         │         │
            Attempt 1  Attempt 2   After 2 failures
            (still OK) (still OK)  (marked UNHEALTHY)
                │         │         │
                └─────────┼─────────┘
                          ▼
                    ASG detects
                    (unhealthy host)
                          │
                          ▼
                    Terminate EC2-2
                          │
                          ▼
                    Launch new EC2
                    (user boots up)
                          │
                          ▼
                    After 3-5 minutes
                    New EC2 ready
                          │
                          ▼
                    ALB includes in
                    rotation

TIMELINE:
├── 0s:   Instance fails
├── 5s:   First health check fails
├── 10s:  Second health check fails
├── 10s:  Marked unhealthy
├── 10s:  Traffic rerouted to other instances
├── 15s:  ASG starts replacement
├── 60s:  New instance boots
├── 120s: Passes health checks
└── 300s: Fully operational (5 min)

RESULT: No user-visible downtime! ✓
```

---

## 🔒 Flujo de Confidencialidad (ASR 2)

```
USER REQUEST with malicious payload
     │
     ▼
   AWS WAF
   ┌────────────────────────────────────────┐
   │ Check 1: Rate Limiting                 │
   │ > 2000 requests/5 minutes?             │
   │ ├─ YES: Return 429 Too Many Requests   │
   │ └─ NO: Continue                        │
   └────────────────────────────────────────┘
         │ (continues if OK)
         ▼
   ┌────────────────────────────────────────┐
   │ Check 2: SQL Injection Rules           │
   │ Contains ' OR '1'='1?                  │
   │ ├─ YES: Return 403 Forbidden           │
   │ └─ NO: Continue                        │
   └────────────────────────────────────────┘
         │ (continues if OK)
         ▼
   ┌────────────────────────────────────────┐
   │ Check 3: XSS & Common Attacks          │
   │ Contains <script> tags?                │
   │ ├─ YES: Return 403 Forbidden           │
   │ └─ NO: Continue                        │
   └────────────────────────────────────────┘
         │ (continues if OK)
         ▼
   ┌────────────────────────────────────────┐
   │ Check 4: IP Blocking                   │
   │ Is from blocked_ip_list?               │
   │ ├─ YES: Return 403 Forbidden           │
   │ └─ NO: Continue                        │
   └────────────────────────────────────────┘
         │ (continues if OK)
         ▼
   Security Group Check
   ├─ From ALB? → ALLOW
   └─ From Internet? → DENY
         │
         ▼
   EC2 Instance
   (protected by WAF + Security Group)

DEFENSE LAYERS:
1. WAF Rate Limiting     ◄─ Prevent DDoS
2. WAF SQL Injection     ◄─ Prevent SQL injection
3. WAF XSS Rules         ◄─ Prevent Cross-Site Scripting
4. WAF IP Blocking       ◄─ Prevent known attackers
5. Security Groups       ◄─ Network-level filtering
6. KMS Encryption        ◄─ Data at rest protected
7. TLS 1.2+              ◄─ Data in transit protected
8. VPC Flow Logs         ◄─ Complete audit trail
```

---

## ✍️ Flujo de Integridad (ASR 3)

```
┌────────────────────────────────────────────────────────────────┐
│               COST REPORT GENERATION FLOW                      │
└────────────────────────────────────────────────────────────────┘

STEP 1: Collect Cost Data
┌──────────────────────────────────┐
│ Django View: /reports/costs/     │
│ SELECT * FROM cost_items         │
│ WHERE period = '2024-01'         │
└───────────┬──────────────────────┘
            │
            ▼
┌──────────────────────────────────────────────────┐
│ Audit Trail Entry Created:                      │
│ ├─ EntityId: RPT-2024-01-001                   │
│ ├─ Timestamp: 2024-01-15 09:00:00             │
│ ├─ Action: CREATE                             │
│ ├─ Actor: system                              │
│ └─ Status: PENDING_VALIDATION                 │
└────────────┬─────────────────────────────────────┘
             │
STEP 2: Generate Checksum
             │
             ▼
    ┌─────────────────────┐
    │ SHA-256 Hash        │
    │ (report data)       │
    │                     │
    │ OLD: "abc123def..."│
    └──────────┬──────────┘
               │
STEP 3: Validate Integrity
               │
               ▼
    ┌─────────────────────┐
    │ Compare Checksums   │
    │                     │
    │ NEW vs OLD          │
    │ "abc123" == "abc123"│
    │         YES ✓       │
    │   (not modified)    │
    └──────────┬──────────┘
               │
STEP 4: Authorization
               │
               ▼
    ┌──────────────────────────────────────┐
    │ Check Permissions                    │
    │ ├─ User has report_approve role?     │
    │ ├─ Within allowed business hours?    │
    │ └─ Amount within spending limits?    │
    │                                      │
    │ Status: APPROVED ✓                   │
    └──────────┬───────────────────────────┘
               │
STEP 5: Generate Report
               │
               ▼
    ┌──────────────────────────────────────┐
    │ PDF Report Generated                 │
    │ + Store Report Checksum in DynamoDB  │
    │ + Update Audit Trail: APPROVED       │
    │ + Send to Finance Team               │
    │                                      │
    │ Status: PUBLISHED ✓                  │
    └──────────────────────────────────────┘


FRAUD ATTEMPT SCENARIO:
═════════════════════════════════════════════════════════════

DATA MODIFICATION DETECTED:
┌───────────────────────────┐
│ Original Report:          │
│ EC2: $500                │
│ RDS: $300                │
│ S3: $700                 │
│ TOTAL: $1500             │
│ Checksum: "abc123"       │
└───────────────┬───────────┘
                │
        HACKER MODIFIES:
                │
                ▼
┌───────────────────────────┐
│ Modified Report:          │
│ EC2: $500                │
│ RDS: $300                │
│ S3: $700                 │
│ TOTAL: $5000 ← FRAUD!    │
│ Checksum: "xyz789"       │
└───────────────┬───────────┘
                │
        VALIDATION DETECTS:
                │
                ▼
    ┌──────────────────────────┐
    │ Compare Checksums        │
    │                          │
    │ "abc123" == "xyz789"?    │
    │        NO ✗              │
    │                          │
    │ Data was MODIFIED!       │
    │ Audit Trail shows:       │
    │ "INTEGRITY_VIOLATION"    │
    │                          │
    │ Report REJECTED ✗        │
    │ Alert: SECURITY TEAM     │
    │ Investigation started    │
    └──────────────────────────┘

CONTINUOUS MONITORING:
┌───────────────────────────────────────────────────────┐
│ EventBridge Rules:                                   │
│                                                      │
│ 1. Rate: Every 5 minutes                            │
│    └─ Lambda validates all new data entries          │
│                                                      │
│ 2. Cron: 0 1 * * MON-FRI (1am weekdays)            │
│    └─ Pre-report validation (before generation)      │
│                                                      │
│ 3. CloudWatch Alarm:                                │
│    └─ UnauthorizedDataModification >= 1 in 5min     │
│       → Alert to Security Team                       │
└───────────────────────────────────────────────────────┘
```

---

## 📊 Componentes por Módulo

### Módulo: COMMON (Base)
```
┌─────────────────────────────────────┐
│         AWS VPC                      │
│    10.0.0.0/16                       │
│                                      │
│  ┌──────────────┐                   │
│  │ us-east-1a   │                   │
│  │              │                   │
│  │ ┌──────────┐ │                   │
│  │ │ Pub Sub  │ │ ← IGW             │
│  │ └──────────┘ │                   │
│  │ ┌──────────┐ │                   │
│  │ │Priv Sub  │ │ ← NAT Gateway    │
│  │ └──────────┘ │                   │
│  └──────────────┘                   │
│  ┌──────────────┐                   │
│  │ us-east-1b   │                   │
│  │   (similar)  │                   │
│  └──────────────┘                   │
│  ┌──────────────┐                   │
│  │ us-east-1c   │                   │
│  │   (similar)  │                   │
│  └──────────────┘                   │
│                                      │
│  Security Groups:                   │
│  ├─ base_sg (SSH only)              │
│  ├─ alb_sg (80/443 from internet)   │
│  └─ db_sg (5432 from app)           │
└─────────────────────────────────────┘
```

### Módulo: AVAILABILITY
```
┌─────────────────────────────────┐
│   Auto Scaling Group             │
│   Min: 2, Max: 6                │
│                                 │
│  ┌──────────────────────┐       │
│  │ Launch Template      │       │
│  │ ├─ t3.medium        │       │
│  │ ├─ Ubuntu 22.04     │       │
│  │ ├─ user_data.sh     │       │
│  │ └─ IAM Role         │       │
│  └──────────────────────┘       │
│                                 │
│  ┌─────────────────────┐        │
│  │ Scaling Policies    │        │
│  │ ├─ Target: CPU 70% │        │
│  │ └─ Scale-down: 30% │        │
│  └─────────────────────┘        │
└─────────────────────────────────┘

┌────────────────────────────────────┐
│   Application Load Balancer        │
│                                    │
│   ┌──────────────────────────┐    │
│   │ Target Group             │    │
│   │ ├─ Port: 8000           │    │
│   │ ├─ Protocol: HTTP       │    │
│   │ ├─ Health Check: 5s     │    │
│   │ └─ Attached to ASG      │    │
│   └──────────────────────────┘    │
│                                    │
│   ┌──────────────────────────┐    │
│   │ Listeners                │    │
│   │ ├─ HTTP 80 → 8000       │    │
│   │ └─ HTTPS 443 → 8000     │    │
│   └──────────────────────────┘    │
└────────────────────────────────────┘

┌────────────────────────────────────┐
│   RDS Database (Multi-AZ)          │
│   PostgreSQL 15.3                  │
│                                    │
│   Primary (us-east-1a)             │
│   ↓↓↓ (sync replication)           │
│   Standby (us-east-1b)             │
│                                    │
│   Auto Failover: YES               │
│   Backup Retention: 7 days         │
│   Enhanced Monitoring: YES         │
└────────────────────────────────────┘
```

### Módulo: CONFIDENTIALITY
```
┌─────────────────────────────────┐
│        AWS WAF                   │
│                                 │
│  ┌────────────────────────┐    │
│  │ IP Set                 │    │
│  │ Rule: Block IPs        │    │
│  └────────────────────────┘    │
│                                 │
│  ┌────────────────────────┐    │
│  │ AWS Managed Rules      │    │
│  │ Rule: Common RuleSet   │    │
│  └────────────────────────┘    │
│                                 │
│  ┌────────────────────────┐    │
│  │ AWS Managed Rules      │    │
│  │ Rule: SQL Injection    │    │
│  └────────────────────────┘    │
│                                 │
│  ┌────────────────────────┐    │
│  │ Custom Rate Limit      │    │
│  │ Rule: 2000 req/5min    │    │
│  └────────────────────────┘    │
│                                 │
│  Attached to: ALB (us-east-1a) │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│       KMS Key                    │
│                                 │
│   Encrypts:                     │
│   ├─ RDS volumes               │
│   ├─ DynamoDB tables           │
│   └─ Lambda environment vars   │
│                                 │
│   Key Rotation: Enabled         │
│   Deletion Window: 10 days      │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│    VPC Flow Logs                │
│                                 │
│   Captures:                     │
│   ├─ Source/Dest IP             │
│   ├─ Ports                      │
│   ├─ Protocol                   │
│   ├─ Accept/Reject              │
│   └─ Bytes transferred          │
│                                 │
│   Destination: CloudWatch       │
│   Retention: 90 days            │
└─────────────────────────────────┘
```

### Módulo: INTEGRITY
```
┌──────────────────────────────┐
│   DynamoDB Audit Trail       │
│                              │
│   PK: EntityId (String)      │
│   SK: Timestamp (Number)     │
│   ├─ Action (CREATE/UPDATE)  │
│   ├─ Actor (user/system)     │
│   ├─ OldValue                │
│   ├─ NewValue                │
│   ├─ Checksum (SHA-256)      │
│   └─ Status (APPROVED/...)   │
│                              │
│   TTL: 2555 days             │
│   PITR: Enabled              │
│   Encryption: KMS            │
└──────────────────────────────┘

┌──────────────────────────────┐
│   DynamoDB Report Checksums  │
│                              │
│   PK: ReportId               │
│   SK: GeneratedAt            │
│   ├─ Checksum (SHA-256)      │
│   ├─ Status (VALID/INVALID)  │
│   └─ Metadata                │
│                              │
│   PITR: Enabled              │
│   Encryption: KMS            │
└──────────────────────────────┘

┌──────────────────────────────┐
│   Lambda: data_validation    │
│                              │
│   Runtime: Python 3.11       │
│   Memory: 512MB              │
│   Timeout: 60 seconds        │
│   Triggered by: EventBridge  │
│                              │
│   Logic:                     │
│   1. Fetch data from DB      │
│   2. Generate checksum       │
│   3. Compare with stored     │
│   4. If match: APPROVE       │
│   5. If diff: ALERT TEAM     │
└──────────────────────────────┘

┌──────────────────────────────┐
│   EventBridge Rules          │
│                              │
│   Rule 1: Every 5 minutes    │
│   └─ Lambda validator        │
│                              │
│   Rule 2: Pre-report cron    │
│   └─ Monthly validation      │
│      (0 1 * * MON-FRI)       │
│                              │
│   Targets: Lambda function   │
│   Retry: Enabled             │
└──────────────────────────────┘
```

---

## 🔄 Ciclo de Vida: Deployment

```
┌──────────────────────────────────────────────────────────────┐
│                 TERRAFORM APPLY WORKFLOW                     │
└──────────────────────────────────────────────────────────────┘

STEP 1: Initialize (terraform init)
┌────────────────────────────┐
│ ├─ Download AWS provider   │
│ ├─ Create .terraform/      │
│ └─ Initialize state file   │
└────────────────────────────┘

STEP 2: Validate (terraform validate)
┌────────────────────────────┐
│ ├─ Syntax check            │
│ ├─ Provider validation     │
│ └─ Module validation       │
└────────────────────────────┘

STEP 3: Plan (terraform plan)
┌────────────────────────────┐
│ ├─ Compare desired vs real │
│ ├─ Generate action plan    │
│ ├─ Show what will change   │
│ └─ (40+ resources to add)  │
└────────────────────────────┘

STEP 4: Apply (terraform apply)
┌────────────────────────────┐
│ ├─ Create VPC              │
│ ├─ Create Subnets (6)      │
│ ├─ Create IGW + NAT        │
│ ├─ Create ALB + TG         │
│ ├─ Create ASG + LC         │
│ ├─ Create RDS instance     │
│ ├─ Create Security Groups  │
│ ├─ Create DynamoDB tables  │
│ ├─ Create Lambda function  │
│ ├─ Create EventBridge rule │
│ ├─ Create KMS key          │
│ ├─ Create WAF + rules      │
│ ├─ Create IAM roles        │
│ ├─ Create CloudWatch logs  │
│ ├─ Create CloudWatch alarms│
│ └─ ... (20+ more resources)│
└────────────────────────────┘

STEP 5: Outputs (terraform output)
┌────────────────────────────┐
│ ├─ ALB DNS Name            │
│ ├─ RDS Endpoint            │
│ ├─ WAF ARN                 │
│ ├─ Audit Trail Table       │
│ └─ Other important IDs     │
└────────────────────────────┘

STEP 6: Tests (pytest tests/)
┌────────────────────────────┐
│ ├─ Test Availability (10)  │
│ ├─ Test Confidentiality(10)│
│ ├─ Test Integrity (10)     │
│ └─ All 30+ tests pass ✓    │
└────────────────────────────┘

STEP 7: Verify (AWS Console)
┌────────────────────────────┐
│ ├─ EC2 running             │
│ ├─ ALB healthy             │
│ ├─ RDS available           │
│ ├─ DynamoDB tables created │
│ ├─ Lambda deployed         │
│ └─ WAF enabled             │
└────────────────────────────┘

RESULT: ✓ Infrastructure Ready for Production!
```

---

## 📈 Monitoreo & Alertas

```
┌─────────────────────────────────────────────────────────┐
│            CloudWatch Dashboards                        │
└─────────────────────────────────────────────────────────┘

Dashboard 1: AVAILABILITY
├─ ALB Response Time (target: < 2s)
├─ Healthy Host Count (target: >= 2)
├─ EC2 CPU Utilization
├─ RDS CPU & Memory
├─ RDS DatabaseAvailability %
└─ Auto Scaling Group Activity

Dashboard 2: CONFIDENTIALITY
├─ WAF Blocked Requests
├─ WAF Allowed Requests
├─ Unauthorized Access Attempts
├─ Security Group Denials
├─ VPC Flow Log Analysis
└─ Failed Login Attempts

Dashboard 3: INTEGRITY
├─ Audit Trail Entry Count
├─ Checksum Mismatches
├─ Lambda Execution Count
├─ Lambda Duration (ms)
├─ DynamoDB Read/Write Capacity
└─ Report Generation Status

┌─────────────────────────────────────────────────────────┐
│            CloudWatch Alarms                            │
└─────────────────────────────────────────────────────────┘

AVAILABILITY ALARMS:
├─ ALB Response Time > 5s → ALERT
├─ Healthy Hosts < 2 → CRITICAL
├─ EC2 CPU > 70% → Scale Up
├─ EC2 CPU < 30% (2x) → Scale Down
└─ RDS Availability < 99% → CRITICAL

CONFIDENTIALITY ALARMS:
├─ WAF Blocked > 100/min → ALERT
├─ Unauthorized Access >= 5/5min → CRITICAL
├─ Security Group Denials > 10/min → ALERT
└─ Failed Logins > 5/min → ALERT

INTEGRITY ALARMS:
├─ Checksum Mismatch >= 1 → CRITICAL
├─ Lambda Failures > 0 → ALERT
├─ DynamoDB Throttling → ALERT
└─ Report Generation Timeout → CRITICAL

All Alarms → SNS Topic → Email/SMS/Slack
```

---

## 🔐 Seguridad: Capas Defensivas

```
LAYER 1: Perimeter (AWS WAF)
┌─────────────────────────────────────────┐
│ • Rate Limiting: 2000 req/5min          │
│ • SQL Injection Detection & Blocking    │
│ • XSS Protection                        │
│ • DDoS Mitigation                       │
│ • IP-based Blocking                     │
│ → Result: 403 Forbidden or 429          │
└─────────────────────────────────────────┘
         ↓ (allowed traffic only)
LAYER 2: Network (VPC)
┌─────────────────────────────────────────┐
│ • Private Subnets (DB, Lambda, etc)     │
│ • VPC Flow Logs (audit trail)           │
│ • Network ACLs (stateless firewall)     │
│ → Result: Traffic stays within VPC      │
└─────────────────────────────────────────┘
         ↓ (trusted traffic only)
LAYER 3: Application Firewall (Security Groups)
┌─────────────────────────────────────────┐
│ • EC2: Only from ALB (port 8000)        │
│ • DB: Only from App (port 5432)         │
│ • Lambda: Only from EventBridge         │
│ → Result: Principle of Least Privilege  │
└─────────────────────────────────────────┘
         ↓ (authorized traffic only)
LAYER 4: Transport (TLS 1.2+)
┌─────────────────────────────────────────┐
│ • HTTPS/443: Client to ALB              │
│ • TLS 1.2+ enforced                     │
│ • Certificate validation                │
│ → Result: Data encrypted in transit     │
└─────────────────────────────────────────┘
         ↓ (encrypted traffic)
LAYER 5: Storage (KMS Encryption)
┌─────────────────────────────────────────┐
│ • RDS: Encrypted volumes                │
│ • DynamoDB: Encrypted tables            │
│ • Lambda: Encrypted env vars            │
│ • KMS key rotation enabled              │
│ → Result: Data encrypted at rest        │
└─────────────────────────────────────────┘
         ↓ (encrypted data only)
LAYER 6: Identity & Access (IAM)
┌─────────────────────────────────────────┐
│ • EC2 Role: logs + KMS decrypt only     │
│ • Lambda Role: DynamoDB + KMS only      │
│ • RDS Role: Enhanced monitoring only    │
│ → Result: Minimal permissions granted   │
└─────────────────────────────────────────┘
         ↓ (authorized actions only)
LAYER 7: Audit & Detection (CloudWatch)
┌─────────────────────────────────────────┐
│ • VPC Flow Logs: 90 days                │
│ • Application Logs: CloudWatch          │
│ • Audit Trail: DynamoDB + Lambda        │
│ • Security Events: CloudWatch Alarms    │
│ → Result: Complete forensic trail       │
└─────────────────────────────────────────┘
```

---

**¡Arquitectura completa lista para producción! 🎉**

Ver documento completo: [INFRAESTRUCTURA.md](INFRAESTRUCTURA.md)

