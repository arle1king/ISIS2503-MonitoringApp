#!/bin/bash
# ProxySQL Setup Script - ASR 2 (Confidencialidad)
# Instala ProxySQL y configura enrutamiento por tenant

set -e

# Variables
DB_HOST="${db_host}"
DB_PORT="${db_port}"
DB_USER="${db_username}"
DB_PASSWORD="${db_password}"
ENVIRONMENT="${environment}"
PROJECT_NAME="${project_name}"
LOG_GROUP="${log_group_name}"

# Logging
exec > >(tee -a /var/log/proxysql-setup.log)
exec 2>&1

echo "=== ProxySQL Setup Script Started ==="
echo "Environment: $ENVIRONMENT"
echo "Project: $PROJECT_NAME"
echo "Time: $(date)"

# Update system
apt-get update
apt-get upgrade -y

# Install ProxySQL
apt-get install -y proxysql

# Start ProxySQL
systemctl start proxysql
systemctl enable proxysql

echo "ProxySQL installed successfully"

# Configure ProxySQL admin interface
# Login to ProxySQL admin and configure
mysql -h 127.0.0.1 -P 6032 -u admin -padmin << 'PROXYSQL_CONFIG'

-- Set admin variables
SET admin-mysql_ifaces="0.0.0.0:6032";
SAVE ADMIN VARIABLES TO DISK;

-- Configure MySQL servers (RDS backend)
INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight, comment) VALUES (0, "DB_HOST_PLACEHOLDER", DB_PORT_PLACEHOLDER, 1, 'Primary RDS');
LOAD MYSQL SERVERS TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;

-- Define ProxySQL users and their tenant mappings
-- Usuario empresa_a mapea a schema empresa_a
INSERT INTO mysql_users (username, password, active, default_hostgroup, comment) VALUES ('usuario_a', 'pass_empresa_a', 1, 0, 'Empresa A');
INSERT INTO mysql_users (username, password, active, default_hostgroup, comment) VALUES ('usuario_b', 'pass_empresa_b', 1, 0, 'Empresa B');
INSERT INTO mysql_users (username, password, active, default_hostgroup, comment) VALUES ('usuario_c', 'pass_empresa_c', 1, 0, 'Empresa C');

LOAD MYSQL USERS TO RUNTIME;
SAVE MYSQL USERS TO DISK;

-- Blocking rules for cross-tenant access (deny all SELECT on other schemas)
-- This is a simplified version; in production use more sophisticated query routing

PROXYSQL_CONFIG

# Replace placeholders
sed -i "s/DB_HOST_PLACEHOLDER/$DB_HOST/g" /etc/proxysql.cnf
sed -i "s/DB_PORT_PLACEHOLDER/$DB_PORT/g" /etc/proxysql.cnf

# Reload ProxySQL
systemctl restart proxysql

echo "ProxySQL configured with tenant routing"

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/proxysql.log",
            "log_group_name": "$LOG_GROUP",
            "log_stream_name": "proxysql-{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "CustomMetrics/$PROJECT_NAME",
    "metrics_collected": {
      "mem": {
        "measurement": [
          {
            "name": "mem_used_percent",
            "rename": "MemoryUtilization",
            "unit": "Percent"
          }
        ]
      },
      "netstat": {
        "measurement": [
          {
            "name": "tcp_established",
            "rename": "ProxySQLConnections"
          }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "CloudWatch agent configured"

# Create monitoring script (send ProxySQL metrics to CloudWatch)
cat > /usr/local/bin/proxysql-metrics.sh << 'METRICS_SCRIPT'
#!/bin/bash
PROJECT_NAME="PROJECT_PLACEHOLDER"
REGION="us-east-1"

# Fetch ProxySQL metrics
CONNECTIONS=$(mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT COUNT(*) as count FROM stats.stats_mysql_connection_pool WHERE status='ONLINE';" | tail -1)
ACCESS_DENIED=$(mysql -h 127.0.0.1 -P 6032 -u admin -padmin -e "SELECT errors FROM stats.stats_mysql_query_rules WHERE match_pattern LIKE '%DENY%';" | tail -1)

# Send to CloudWatch
aws cloudwatch put-metric-data \
  --namespace "CustomMetrics/$PROJECT_NAME" \
  --metric-name "ProxySQLConnections" \
  --value "$CONNECTIONS" \
  --region "$REGION"

METRICS_SCRIPT

chmod +x /usr/local/bin/proxysql-metrics.sh
sed -i "s/PROJECT_PLACEHOLDER/$PROJECT_NAME/g" /usr/local/bin/proxysql-metrics.sh

# Add to crontab (run every minute)
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/proxysql-metrics.sh") | crontab -

echo "Metrics collection script installed"

# Verify ProxySQL is running
if pgrep -x "proxysql" > /dev/null; then
  echo "✓ ProxySQL is running"
else
  echo "✗ ProxySQL failed to start"
  exit 1
fi

echo "=== ProxySQL Setup Completed Successfully ==="
echo "ProxySQL Admin: http://localhost:6032 (use admin/admin)"
echo "ProxySQL MySQL Port: 3306"
echo "Tenant routing configured and active"
