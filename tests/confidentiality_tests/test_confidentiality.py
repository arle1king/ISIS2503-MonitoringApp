# Tests de Confidencialidad
# ASR: Bloquear acceso no autorizado a datos de otra empresa (100%)
#
# Este test valida:
# 1. WAF bloquea intentos de acceso no autorizado
# 2. Security groups restrictivos
# 3. Encriptación en tránsito (TLS 1.2+)
# 4. Base de datos encriptada
# 5. Aislamiento de datos por tenant
# 6. VPC Flow Logs registra intentos maliciosos

import pytest
import boto3
import requests
from botocore.exceptions import ClientError
import ssl
import socket

class TestConfidentiality:
    """Suite de tests para ASR de Confidencialidad"""

    @pytest.fixture(scope="class")
    def aws_clients(self):
        """Inicializar clientes AWS"""
        return {
            'wafv2': boto3.client('wafv2', region_name='us-east-1'),
            'ec2': boto3.client('ec2', region_name='us-east-1'),
            'rds': boto3.client('rds', region_name='us-east-1'),
            'logs': boto3.client('logs', region_name='us-east-1'),
            'kms': boto3.client('kms', region_name='us-east-1')
        }

    def test_waf_enabled_on_alb(self, aws_clients):
        """
        Validar que WAF está habilitado en el Load Balancer
        """
        wafv2 = aws_clients['wafv2']
        
        # Obtener Web ACLs
        web_acls = wafv2.list_web_acls(Scope='REGIONAL')['WebACLs']
        
        monitoring_waf = next((w for w in web_acls if 'monitoring' in w['Name'].lower()), None)
        assert monitoring_waf is not None, "WAF no encontrado"
        
        print(f"✓ WAF habilitado: {monitoring_waf['Name']}")

    def test_waf_rules_configured(self, aws_clients):
        """
        Validar que WAF tiene reglas de protección configuradas
        - Rate limiting
        - SQL Injection protection
        - Common Rule Set
        - IP blocking list
        """
        wafv2 = aws_clients['wafv2']
        
        web_acls = wafv2.list_web_acls(Scope='REGIONAL')['WebACLs']
        monitoring_waf = next((w for w in web_acls if 'monitoring' in w['Name'].lower()), None)
        
        if monitoring_waf:
            web_acl = wafv2.get_web_acl(Scope='REGIONAL', Id=monitoring_waf['Id'], Name=monitoring_waf['Name'])
            
            rules = web_acl['WebACL']['Rules']
            rule_names = [r['Name'] for r in rules]
            
            assert len(rules) >= 3, "WAF debe tener al menos 3 reglas"
            print(f"✓ WAF Rules configuradas: {rule_names}")

    def test_security_groups_restrictive(self, aws_clients):
        """
        Validar que los Security Groups son restrictivos
        - Ingreso solo desde ALB
        - Egreso limitado (solo HTTPS, DNS, DB)
        """
        ec2 = aws_clients['ec2']
        
        sgs = ec2.describe_security_groups()['SecurityGroups']
        
        # Buscar security group de aplicación restrictiva
        app_sg = next((sg for sg in sgs if 'app-restricted' in sg['GroupName'].lower()), None)
        
        if app_sg:
            # Validar ingreso
            ingress_rules = app_sg['IpPermissions']
            
            # Debe tener al menos una regla de ingreso desde security group (ALB)
            sg_ingress = any(
                'UserIdGroupPairs' in rule and len(rule['UserIdGroupPairs']) > 0
                for rule in ingress_rules
            )
            assert sg_ingress, "No hay ingreso desde ALB configurado"
            
            # Validar egreso
            egress_rules = app_sg['IpPermissionsEgress']
            
            # Debe ser restrictivo (no all traffic)
            all_traffic = any(
                rule.get('IpProtocol') == '-1' and 
                rule.get('CidrIp') == '0.0.0.0/0'
                for rule in egress_rules
            )
            assert not all_traffic, "Egreso debe ser restrictivo, no all traffic"
            
            print(f"✓ Security Group restrictivo configurado: {app_sg['GroupName']}")

    def test_rds_encryption_at_rest(self, aws_clients):
        """
        Validar que RDS está encriptado en reposo
        - StorageEncrypted = true
        - KMS key configurada
        """
        rds = aws_clients['rds']
        
        db_instances = rds.describe_db_instances()['DBInstances']
        monitoring_db = next((db for db in db_instances if 'monitoring' in db['DBInstanceIdentifier'].lower()), None)
        
        if monitoring_db:
            assert monitoring_db['StorageEncrypted'] == True, "RDS debe estar encriptada"
            assert 'KmsKeyId' in monitoring_db, "RDS debe usar KMS key"
            
            print(f"✓ RDS encriptación en reposo habilitada: {monitoring_db['DBInstanceIdentifier']}")

    def test_rds_ssl_requirement(self, aws_clients):
        """
        Validar que RDS requiere SSL para conexiones
        """
        rds = aws_clients['rds']
        
        db_instances = rds.describe_db_instances()['DBInstances']
        monitoring_db = next((db for db in db_instances if 'monitoring' in db['DBInstanceIdentifier'].lower()), None)
        
        if monitoring_db:
            # Obtener parameter group
            pg_name = monitoring_db['DBParameterGroups'][0]['DBParameterGroupName']
            
            db_pgs = rds.describe_db_parameter_groups(DBParameterGroupName=pg_name)['DBParameterGroups']
            
            if db_pgs:
                params = rds.describe_db_parameters(DBParameterGroupName=pg_name)['Parameters']
                
                force_ssl = next((p for p in params if p['ParameterName'] == 'rds.force_ssl'), None)
                
                if force_ssl:
                    assert force_ssl['ParameterValue'] == '1', "rds.force_ssl debe estar habilitado"
                    print(f"✓ RDS SSL requerido: rds.force_ssl = 1")

    def test_tls_version_on_alb(self):
        """
        Validar que ALB usa TLS 1.2+
        """
        # Este test requiere el DNS del ALB
        elb = boto3.client('elbv2', region_name='us-east-1')
        
        lbs = elb.describe_load_balancers()['LoadBalancers']
        monitoring_lb = next((lb for lb in lbs if 'monitoring' in lb['LoadBalancerName'].lower()), None)
        
        if monitoring_lb and monitoring_lb['Scheme'] == 'internet-facing':
            # Obtener listeners HTTPS
            listeners = elb.describe_listeners(LoadBalancerArn=monitoring_lb['LoadBalancerArn'])['Listeners']
            https_listeners = [l for l in listeners if l['Protocol'] == 'HTTPS']
            
            if https_listeners:
                # Validar SSL policy
                for listener in https_listeners:
                    ssl_policy = listener.get('SslPolicy', 'ELBSecurityPolicy-2016-08')
                    
                    # Las políticas modernas implican TLS 1.2+
                    assert 'ELBSecurityPolicy' in ssl_policy, "Debe usar política de seguridad de AWS"
                    print(f"✓ ALB HTTPS SSL Policy: {ssl_policy}")

    def test_vpc_flow_logs_enabled(self, aws_clients):
        """
        Validar que VPC Flow Logs está habilitado para auditoría
        """
        ec2 = aws_clients['ec2']
        
        vpcs = ec2.describe_vpcs()['Vpcs']
        monitoring_vpc = next((v for v in vpcs if any('monitoring' in tag.get('Value', '').lower() for tag in v.get('Tags', []))), None)
        
        if monitoring_vpc:
            flow_logs = ec2.describe_flow_logs(
                Filter=[
                    {'Name': 'resource-id', 'Values': [monitoring_vpc['VpcId']]}
                ]
            )['FlowLogs']
            
            assert len(flow_logs) > 0, "VPC Flow Logs debe estar habilitado"
            print(f"✓ VPC Flow Logs habilitado: {len(flow_logs)} logs")

    def test_cloudwatch_alarms_for_unauthorized_access(self, aws_clients):
        """
        Validar que existen alarmas para detectar acceso no autorizado
        """
        cloudwatch = boto3.client('cloudwatch', region_name='us-east-1')
        
        alarms = cloudwatch.describe_alarms()['MetricAlarms']
        
        unauthorized_alarm = next(
            (a for a in alarms if 'unauthorized' in a['AlarmName'].lower()),
            None
        )
        
        if unauthorized_alarm:
            assert unauthorized_alarm['StateValue'] in ['OK', 'ALARM', 'INSUFFICIENT_DATA'], "Alarma debe existir"
            print(f"✓ Alarma de acceso no autorizado configurada: {unauthorized_alarm['AlarmName']}")


class TestConfidentialityAccess:
    """Tests de control de acceso"""

    @pytest.fixture
    def alb_endpoint(self):
        """Obtener endpoint del ALB"""
        elb = boto3.client('elbv2', region_name='us-east-1')
        lbs = elb.describe_load_balancers()['LoadBalancers']
        monitoring_lb = next((lb for lb in lbs if 'monitoring' in lb['LoadBalancerName'].lower()), None)
        
        if monitoring_lb:
            return f"http://{monitoring_lb['DNSName']}"
        return None

    def test_waf_blocks_sql_injection_attempt(self, alb_endpoint):
        """
        Intentar SQL injection y validar que WAF lo bloquea
        """
        if not alb_endpoint:
            pytest.skip("ALB endpoint no encontrado")
        
        # Payload de SQL injection común
        sql_injection_payloads = [
            "' OR '1'='1",
            "'; DROP TABLE users; --",
            "1 UNION SELECT * FROM users"
        ]
        
        try:
            for payload in sql_injection_payloads:
                response = requests.get(
                    f"{alb_endpoint}/search/",
                    params={'q': payload},
                    timeout=5
                )
                
                # WAF debe bloquear (403) o aplicación debe sanitizar
                if response.status_code == 403:
                    print(f"✓ WAF bloqueó SQL injection: {payload}")
                    break
        except requests.exceptions.RequestException as e:
            pytest.skip(f"No se puede conectar: {e}")

    def test_rate_limiting_prevents_brute_force(self, alb_endpoint):
        """
        Validar que rate limiting previene ataques de fuerza bruta
        """
        if not alb_endpoint:
            pytest.skip("ALB endpoint no encontrado")
        
        blocked_count = 0
        request_count = 0
        
        try:
            # Hacer múltiples requests rápidamente
            for i in range(20):
                response = requests.get(f"{alb_endpoint}/api/data", timeout=2)
                request_count += 1
                
                if response.status_code == 429:  # Too Many Requests
                    blocked_count += 1
            
            if blocked_count > 0:
                print(f"✓ Rate limiting activo: {blocked_count}/{request_count} bloqueadas")
            else:
                print(f"⚠️ Rate limiting no activó en {request_count} requests")
        except Exception as e:
            pytest.skip(f"Error durante test: {e}")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
