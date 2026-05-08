#!/usr/bin/env python3
"""
Validador de configuración Terraform
Ejecuta pre-checks antes de despliegue
"""

import subprocess
import sys
import json

def run_command(cmd):
    """Ejecutar comando y retornar output"""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, shell=True)
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)

def check_terraform_installed():
    """Verificar que Terraform está instalado"""
    success, _, _ = run_command("terraform version")
    if success:
        print("✓ Terraform instalado")
        return True
    else:
        print("✗ Terraform NO instalado")
        return False

def check_aws_credentials():
    """Verificar que AWS credentials están configuradas"""
    success, output, _ = run_command("aws sts get-caller-identity")
    if success:
        try:
            identity = json.loads(output)
            print(f"✓ AWS credentials OK - Account: {identity.get('Account')}")
            return True
        except:
            print("✗ No se puede parsear AWS credentials")
            return False
    else:
        print("✗ AWS credentials NO configuradas")
        return False

def check_aws_region():
    """Verificar que región está configurada"""
    success, output, _ = run_command("aws configure get region")
    if success and output.strip():
        print(f"✓ AWS region configurada: {output.strip()}")
        return True
    else:
        print("✗ AWS region NO configurada")
        return False

def check_terraform_syntax(env):
    """Validar sintaxis Terraform"""
    success, _, error = run_command(f"cd terraform/environments/{env} && terraform validate")
    if success:
        print(f"✓ Terraform syntax OK para {env}")
        return True
    else:
        print(f"✗ Terraform syntax ERROR en {env}:")
        print(f"  {error}")
        return False

def check_terraform_fmt(env):
    """Verificar formato Terraform"""
    success, _, _ = run_command(f"cd terraform/environments/{env} && terraform fmt -check .")
    if success:
        print(f"✓ Terraform formato OK para {env}")
        return True
    else:
        print(f"⚠ Terraform formato puede requerir ajustes en {env}")
        return True  # No es un error crítico

def main():
    print("=" * 60)
    print("Validador de Configuración Terraform - ISIS2503 ASR")
    print("=" * 60)
    print()

    checks = [
        ("Terraform instalado", check_terraform_installed),
        ("AWS credentials", check_aws_credentials),
        ("AWS region", check_aws_region),
        ("Terraform syntax (dev)", lambda: check_terraform_syntax("dev")),
        ("Terraform syntax (prod)", lambda: check_terraform_syntax("prod")),
        ("Terraform format (dev)", lambda: check_terraform_fmt("dev")),
        ("Terraform format (prod)", lambda: check_terraform_fmt("prod")),
    ]

    results = []
    for name, check_func in checks:
        try:
            result = check_func()
            results.append(result)
        except Exception as e:
            print(f"✗ Error en {name}: {e}")
            results.append(False)

    print()
    print("=" * 60)
    passed = sum(results)
    total = len(results)
    print(f"Resultados: {passed}/{total} checks pasados")
    print("=" * 60)

    if all(results):
        print("\n✓ ¡Listo para desplegar!")
        return 0
    else:
        print("\n✗ Hay problemas que resolver antes de desplegar")
        return 1

if __name__ == "__main__":
    sys.exit(main())
