# Quarkus Getting Started — Deploy Automatizado (k3d)

Repositório com a aplicação Quarkus "Getting Started" preparada para build, containerização e deploy local em k3d.

[![CI](https://github.com/vitoriapena/hackathon-2025/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/vitoriapena/hackathon-2025/actions/workflows/ci.yaml)
[![CD DES](https://github.com/vitoriapena/hackathon-2025/actions/workflows/cd.yaml/badge.svg?branch=main)](https://github.com/vitoriapena/hackathon-2025/actions/workflows/cd.yaml)
[![CD PRD](https://github.com/vitoriapena/hackathon-2025/actions/workflows/cd.yaml/badge.svg?branch=main)](https://github.com/vitoriapena/hackathon-2025/actions/workflows/cd.yaml)

## Sumário

- [Visão geral](#visão-geral)
- [Pipeline Local](#pipeline-local)
- [Guia para Executar o Pipeline Local](#guia-para-executar-o-pipeline-local)

## Visão geral

A solução oferece duas formas de execução do pipeline: local e GitHub Actions (automação CI/CD). Ambas compartilham os mesmos artefatos e ambientes k3d, diferindo apenas em alguns  mecanismos de execução.

## Pipeline Local
O pipeline local automatiza o processo completo desde o build da aplicação Quarkus até o deploy nos ambientes DES e PRD do cluster k3d.

<img width="1898" height="915" alt="image" src="https://github.com/user-attachments/assets/4946556a-6db8-427f-9629-0eda5591ee83" />


## Guia para Executar o Pipeline Local

**Pré-requisitos:**

- **PowerShell** 7+
- **Java** 21 (preferencialmente Eclipse Temurin)
- **Maven** 3.8+
- **Docker Desktop**
- **kubectl** (cliente Kubernetes)
- **k3d** (para cluster Kubernetes local)
- **Trivy** (scanner de vulnerabilidades)
- **Git**

**Configuração Inicial**

1. Clone o repositório
```bash
git clone https://github.com/vitoriapena/hackathon-2025.git
cd hackathon-2025
```

2. Verifique as ferramentas
```bash
# Confirme as instalações e versões
java -version            
mvn -version              
docker --version          
kubectl version --client  
k3d version               
trivy --version    
```

3. Configure permissões de execução dos scripts PowerShell
```bash
# Torna apenas os scripts PowerShell da pasta scripts/ps/ executáveis
Get-ChildItem -Path "scripts\ps\*.ps1" -Recurse | Unblock-File
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

4. Crie o cluster k3d
```bash
# Use o script automatizado para criar o cluster
pwsh -File scripts/ps/k3d-up.ps1
```

5. Build + Deploy completo
```bash
# Execute o pipeline completo e acompanhe os logs
pwsh -File scripts/ps/build-deploy-local.ps1
```

6. Configure arquivos de hosts para acessar a aplicação via browser
```bash
# Execute como Administrador
pwsh -File scripts/ps/setup-hosts.ps1
```

7. Teste o acesso (Só funciona se o etc/hosts foi configurado corretamente)

| Ambiente | Aplicação | Health Check |
| --- | --- | --- |
| DES | http://app.des.local/hello | http://app.des.local/q/health |
| PRD | http://app.prd.local/hello | http://app.prd.local/q/health |

