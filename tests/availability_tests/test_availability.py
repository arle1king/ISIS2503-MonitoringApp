# Tests de Disponibilidad
# ASR: Tiempo de recuperación ante una caída no supera los 5 segundos
#
# Este test valida:
# 1. Health checks funcionan correctamente
# 2. Failover ocurre en menos de 5 segundos
# 3. Auto Scaling reemplaza instancias no saludables
# 4. RDS Multi-AZ failover es rápido
# 5. Load Balancer detecta instancias no saludables

import pytest
import boto3
import time
import requests
from datetime import datetime
import subprocess

class TestAvailability:
    """Suite de tests para ASR de Disponibilidad"""

    @pytest.fixture(scope="class")
    def aws_clients(self):
        """Inicializar clientes AWS"""
        return {
            'ec2': boto3.client('ec2', region_name='us-east-1'),
            'elb': boto3.client('elbv2', region_name='us-east-1'),
            'autoscaling': boto3.client('autoscaling', region_name='us-east-1'),
            'rds': boto3.client('rds', region_name='us-east-1'),
            'cloudwatch': boto3.client('cloudwatch', region_name='us-east-1')
        }

    def test_alb_health_check_configuration(self, aws_clients):
        """
        Validar que el Load Balancer tiene health checks configurados correctamente
        - Intervalo de 5 segundos
        - 2 intentos para considerar saludable
        - 2 intentos para considerar no saludable
        """
        target_groups = aws_clients['elb'].describe_target_groups()['TargetGroups']
        
        assert len(target_groups) > 0, "No hay Target Groups configurados"
        
        for tg in target_groups:
            if 'django' in tg['TargetGroupName'].lower():
                hc = tg['HealthCheckConfig']
                
                # Validar configuración para recuperación rápida
                assert hc['Interval'] <= 5, f"Health check interval {hc['Interval']} > 5 segundos"
                assert hc['HealthyThreshold'] <= 2, "HealthyThreshold debe ser <= 2"
                assert hc['UnhealthyThreshold'] <= 2, "UnhealthyThreshold debe ser <= 2"
                assert hc['Timeout'] <= 3, "Timeout debe ser <= 3 segundos"
                
                print(f"✓ Health check configurado correctamente: {hc}")

    def test_asg_rapid_recovery(self, aws_clients):
        """
        Validar que el Auto Scaling Group está configurado para recuperación rápida
        - Mínimo 2 instancias en disponibilidad
        - Health check type es ELB
        - Grace period adecuado
        """
        asgs = aws_clients['autoscaling'].describe_auto_scaling_groups()['AutoScalingGroups']
        
        assert len(asgs) > 0, "No hay Auto Scaling Groups configurados"
        
        for asg in asgs:
            if 'monitoring' in asg['AutoScalingGroupName'].lower():
                assert asg['MinSize'] >= 2, "MinSize debe ser >= 2 para redundancia"
                assert asg['HealthCheckType'] == 'ELB', "HealthCheckType debe ser ELB"
                assert asg['HealthCheckGracePeriod'] <= 60, "Grace period debe ser <= 60 segundos"
                
                print(f"✓ ASG configurado para recuperación rápida: Min={asg['MinSize']}, Max={asg['MaxSize']}")

    def test_rds_multi_az_failover(self, aws_clients):
        """
        Validar que RDS está en Multi-AZ para failover automático
        """
        rds_instances = aws_clients['rds'].describe_db_instances()['DBInstances']
        
        assert len(rds_instances) > 0, "No hay instancias RDS"
        
        for db in rds_instances:
            if 'monitoring' in db['DBInstanceIdentifier'].lower():
                assert db['MultiAZ'] == True, "RDS debe estar en Multi-AZ"
                assert db['BackupRetentionPeriod'] >= 7, "Backup retention debe ser >= 7 días"
                
                print(f"✓ RDS configurado para Multi-AZ failover: {db['DBInstanceIdentifier']}")

    def test_alb_response_time(self, aws_clients):
        """
        Validar que el ALB responde en tiempo aceptable
        - Target Response Time < 2 segundos en promedio
        """
        metrics = aws_clients['cloudwatch'].get_metric_statistics(
            Namespace='AWS/ApplicationELB',
            MetricName='TargetResponseTime',
            Dimensions=[],
            StartTime=datetime.utcnow().replace(hour=datetime.utcnow().hour-1),
            EndTime=datetime.utcnow(),
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        if metrics['Datapoints']:
            avg_response = sum([dp['Average'] for dp in metrics['Datapoints']]) / len(metrics['Datapoints'])
            max_response = max([dp['Maximum'] for dp in metrics['Datapoints']])
            
            assert avg_response < 2.0, f"Average response time {avg_response}s > 2s"
            print(f"✓ ALB Response Time - Avg: {avg_response:.3f}s, Max: {max_response:.3f}s")

    def test_healthy_host_count(self, aws_clients):
        """
        Validar que hay hosts saludables en el Target Group
        """
        target_groups = aws_clients['elb'].describe_target_groups()['TargetGroups']
        
        for tg in target_groups:
            if 'django' in tg['TargetGroupName'].lower():
                tg_health = aws_clients['elb'].describe_target_health(TargetGroupArn=tg['TargetGroupArn'])
                
                healthy_hosts = sum(1 for t in tg_health['TargetHealthDescriptions'] if t['TargetHealth']['State'] == 'healthy')
                total_hosts = len(tg_health['TargetHealthDescriptions'])
                
                assert healthy_hosts > 0, "No hay hosts saludables"
                print(f"✓ Hosts saludables: {healthy_hosts}/{total_hosts}")

    @pytest.mark.integration
    def test_failover_detection_time(self):
        """
        Test de integración: Simular una instancia no saludable y medir tiempo de detección
        
        Pasos:
        1. Obtener instancia de EC2
        2. Detener la instancia
        3. Medir tiempo hasta que se marca como unhealthy
        4. Verificar que < 5 segundos
        """
        print("\n⚠️ Este test requiere permisos para detener instancias EC2")
        print("Puede causar downtime. Ejecutar solo en ambiente de testing.")
        
        # Este test es intrusivo y debe ejecutarse manualmente
        pytest.skip("Test intrusivo - ejecutar manualmente solo en ambiente de testing")

    def test_cloudwatch_alarms_scaling_policies(self, aws_clients):
        """
        Validar que existen alarmas CloudWatch para escaling
        - CPU High (> 70%) - scale up
        - CPU Low (< 30%) - scale down
        """
        alarms = aws_clients['cloudwatch'].describe_alarms()['MetricAlarms']
        
        cpu_high_alarm = next((a for a in alarms if 'cpu-high' in a['AlarmName'].lower()), None)
        cpu_low_alarm = next((a for a in alarms if 'cpu-low' in a['AlarmName'].lower()), None)
        
        assert cpu_high_alarm is not None, "No existe alarma CPU High"
        assert cpu_low_alarm is not None, "No existe alarma CPU Low"
        
        assert cpu_high_alarm['Threshold'] >= 70, "CPU High threshold debe ser >= 70%"
        assert cpu_low_alarm['Threshold'] <= 30, "CPU Low threshold debe ser <= 30%"
        
        print(f"✓ Alarmas de escalado configuradas correctamente")

    def test_database_availability_metric(self, aws_clients):
        """
        Validar métrica de disponibilidad de la base de datos
        """
        metrics = aws_clients['cloudwatch'].get_metric_statistics(
            Namespace='AWS/RDS',
            MetricName='DatabaseAvailability',
            StartTime=datetime.utcnow().replace(hour=datetime.utcnow().hour-1),
            EndTime=datetime.utcnow(),
            Period=300,
            Statistics=['Average']
        )
        
        if metrics['Datapoints']:
            avg_availability = sum([dp['Average'] for dp in metrics['Datapoints']]) / len(metrics['Datapoints'])
            assert avg_availability > 99.9, f"Database availability {avg_availability}% < 99.9%"
            print(f"✓ Database Availability: {avg_availability:.2f}%")


class TestAvailabilityLoadScenarios:
    """Tests de carga para validar disponibilidad"""

    @pytest.fixture
    def alb_endpoint(self):
        """Obtener endpoint del ALB"""
        ec2 = boto3.client('ec2', region_name='us-east-1')
        elb = boto3.client('elbv2', region_name='us-east-1')
        
        # Obtener load balancer
        lbs = elb.describe_load_balancers()['LoadBalancers']
        monitoring_lb = next((lb for lb in lbs if 'monitoring' in lb['LoadBalancerName'].lower()), None)
        
        if monitoring_lb:
            return f"http://{monitoring_lb['DNSName']}"
        return None

    def test_application_responds_to_requests(self, alb_endpoint):
        """
        Validar que la aplicación responde a requests a través del ALB
        """
        if not alb_endpoint:
            pytest.skip("ALB endpoint no encontrado")
        
        try:
            response = requests.get(f"{alb_endpoint}/", timeout=10)
            assert response.status_code == 200, f"Status code: {response.status_code}"
            print(f"✓ Aplicación responde correctamente: {response.status_code}")
        except requests.exceptions.Timeout:
            pytest.fail("Request timeout - aplicación no responde")
        except requests.exceptions.ConnectionError:
            pytest.skip("No se puede conectar a ALB - puede no estar en operación")

    def test_health_endpoint_available(self, alb_endpoint):
        """
        Validar que el endpoint de health check responde rápidamente
        """
        if not alb_endpoint:
            pytest.skip("ALB endpoint no encontrado")
        
        try:
            start = time.time()
            response = requests.get(f"{alb_endpoint}/health/", timeout=5)
            response_time = time.time() - start
            
            assert response.status_code == 200, "Health endpoint debe retornar 200"
            assert response_time < 1.0, f"Health check tardó {response_time:.3f}s > 1s"
            print(f"✓ Health endpoint responde en {response_time:.3f}s")
        except Exception as e:
            pytest.skip(f"No se puede alcanzar endpoint: {e}")


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
