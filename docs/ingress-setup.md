# Ingress Setup for Hackathon 2025

Este projeto agora suporta acesso externo via Ingress utilizando o Traefik que vem pré-instalado no k3d.

## Arquivos criados/modificados:

### Novos manifests:
- `deploy/base/ingress.yaml` - Ingress base para Traefik
- `scripts/ps/setup-hosts.ps1` - Script para configurar hosts file

### Manifests atualizados:
- Padronização de labels em todos os manifests
- Smoke test aprimorado com teste interno e externo
- Script principal com informações de acesso

## Como usar:

### 1. Deploy completo:
```powershell
pwsh -File scripts/ps/build-deploy-local.ps1
```

### 2. Configurar hosts file (como Admin) para acessar urls no navegador:
```powershell
pwsh -File scripts/ps/setup-hosts.ps1
```

### 3. Testar endpoints:
- O script principal já executa testes internos e externos automaticamente (smoke test).
- Teste manual rápido via curl (PowerShell):
   ```powershell
   # Health (DES)
   Invoke-WebRequest -UseBasicParsing -Uri http://localhost/q/health -Headers @{ Host = 'app.des.local' }
   # Health (PRD)
   Invoke-WebRequest -UseBasicParsing -Uri http://localhost/q/health -Headers @{ Host = 'app.prd.local' }
   ```

### 4. Acessar aplicação:
- **DES**: http://app.des.local/hello
- **PRD**: http://app.prd.local/hello
- **Health**: http://app.des.local/q/health

## Arquitetura:

```
Browser → app.des.local → Traefik (k3d) → Service → Pod
```

- **Traefik**: Ingress controller padrão do k3d
- **Service**: ClusterIP interno
- **Ingress**: Roteamento por hostname
- **Hosts file**: Resolve domínios locais para 127.0.0.1

## Troubleshooting:

1. **Erro "could not find Traefik nodePort"**:
   - Verifique se o cluster k3d está rodando
   - Execute: `kubectl get svc -n kube-system traefik`

2. **Endpoints não respondem**:
    - Verifique hosts file: `C:\Windows\System32\drivers\etc\hosts`
    - Teste manual com Host header:
       - `Invoke-WebRequest -UseBasicParsing -Uri http://localhost/q/health -Headers @{ Host = 'app.des.local' }`

3. **Pods não iniciam**:
   - Verifique logs: `kubectl logs -n des deployment/app`
   - Verifique imagem: `kubectl describe pod -n des`
