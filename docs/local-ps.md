# Execução local no Windows (PowerShell)

Este guia resume os passos para Windows 11 usando PowerShell 7+ (pwsh).

## Pré‑requisitos
- PowerShell 7+ (pwsh)
- Docker Desktop
- Java 21 (Temurin), Maven
- Git, kubectl, (opcional) k3d

## Comandos rápidos

### Build e smoke local (Docker)
```powershell
pwsh -File scripts/ps/build-local.ps1
```

### Subir cluster k3d local e ajustar hosts
```powershell
pwsh -File scripts/ps/k3d-up.ps1
```

### Build, importar imagem no k3d, renderizar e aplicar YAMLs (DES e opcional PRD)
```powershell
pwsh -File scripts/ps/build-deploy-local.ps1 -Org <org> -Repo <repo>
```
OU inferindo do git remoto:
```powershell
pwsh -File scripts/ps/build-deploy-local.ps1
```

### Derrubar cluster k3d e limpar hosts
```powershell
pwsh -File scripts/ps/k3d-down.ps1
```

## Notas
- Rodar o PowerShell como Administrador para editar o arquivo de hosts.
- O deploy aplica os manifests de deploy/base e overlays de deploy/des e deploy/prd. O namespace é substituído automaticamente.
- Imagens taggeadas como ghcr.io/<org>/<repo>:<sha> e alias :des.
- Endpoints de health: /q/health e /q/health/ready.
