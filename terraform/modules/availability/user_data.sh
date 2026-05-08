#!/bin/bash
set -e

# Configurar variables de entorno
export DB_HOST="${db_host}"
export DB_USER="${db_user}"
export DB_PASSWORD="${db_password}"
export DB_NAME="${db_name}"
export ENVIRONMENT="${environment}"

# Update system
apt-get update
apt-get install -y python3-pip python3-venv git postgresql-client awscli

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E ./amazon-cloudwatch-agent.deb

# Clone repository or setup application
cd /opt
git clone https://github.com/ISIS2503/ISIS2503-MonitoringApp.git || true

cd ISIS2503-MonitoringApp

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install requirements
pip install --upgrade pip
pip install -r requirements.txt
pip install gunicorn
pip install psycopg2-binary

# Configure Django
export PYTHONPATH=/opt/ISIS2503-MonitoringApp:$PYTHONPATH

# Run migrations
python manage.py migrate --noinput || true

# Create health check endpoint
cat > /opt/health_check.py << 'HEALTH_EOF'
from django.http import JsonResponse
from django.views.decorators.http import require_http_methods

@require_http_methods(["GET"])
def health(request):
    return JsonResponse({"status": "healthy"}, status=200)
HEALTH_EOF

# Create systemd service
cat > /etc/systemd/system/django.service << 'SERVICE_EOF'
[Unit]
Description=Django Gunicorn Application
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/ISIS2503-MonitoringApp
Environment="PATH=/opt/ISIS2503-MonitoringApp/venv/bin"
Environment="DB_HOST=${db_host}"
Environment="DB_USER=${db_user}"
Environment="DB_PASSWORD=${db_password}"
Environment="DB_NAME=${db_name}"
ExecStart=/opt/ISIS2503-MonitoringApp/venv/bin/gunicorn \
    --workers 4 \
    --bind 0.0.0.0:8000 \
    --timeout 30 \
    --access-logfile /var/log/gunicorn_access.log \
    --error-logfile /var/log/gunicorn_error.log \
    monitoring.wsgi:application

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Configure CloudWatch Logs
cat > /opt/cloudwatch-config.json << 'CW_EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/gunicorn_access.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/gunicorn-access"
          },
          {
            "file_path": "/var/log/gunicorn_error.log",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "{instance_id}/gunicorn-error"
          }
        ]
      }
    }
  }
}
CW_EOF

# Enable and start services
systemctl daemon-reload
systemctl enable django
systemctl start django

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/cloudwatch-config.json
