# Execução local no Windows (PowerShell)

Este guia resume os passos para Windows 11 usando PowerShell 7+ (pwsh).

## Pré‑requisitos
- PowerShell 7+ (pwsh)
- Docker Desktop
- Java 21 (Temurin), Maven
- Git, kubectl, (opcional) k3d

## Comandos rápidos

Use estes três comandos no dia a dia:

```powershell
# 1) Subir cluster k3d local e ajustar hosts (executar como Admin para editar hosts)
pwsh -File scripts/ps/k3d-up.ps1

# 2) Build-only (Maven + Docker) e smoke local do container (sem k8s)
pwsh -File scripts/ps/build-deploy-local.ps1 -BuildOnly -RunLocalSmoke

# 3) Build + importar imagem no k3d + renderizar YAMLs + aplicar em DES (PRD sob confirmação)
pwsh -File scripts/ps/build-deploy-local.ps1
```

### Derrubar cluster k3d e limpar hosts
```powershell
pwsh -File scripts/ps/k3d-down.ps1
```

## Notas
- Rodar o PowerShell como Administrador para editar o arquivo de hosts.
- O deploy aplica os manifests de deploy/base e overlays de deploy/des e deploy/prd. O namespace é substituído automaticamente.
- Imagens taggeadas como ghcr.io/<org>/<repo>:<sha> e alias :des; nomes são sanitizados para Docker (lowercase ASCII, sem acentos).
- Endpoints de health: /q/health e /q/health/ready.

## Referência — flags do build-deploy-local.ps1

Parâmetros e comportamento padrão:

- -Org <string>
	- Organização/usuário do registry. Se não informado, tenta inferir do git remote; senão, cai para `git config user.name`/`$env:USERNAME`. É sanitizado (lowercase, sem acentos, [a-z0-9._-]).
- -Repo <string>
	- Nome do repositório. Se não informado, usa a pasta do repo. Também é sanitizado.
- -Tag <string>
	- Tag da imagem. Padrão: `git rev-parse --short HEAD`. Sanitizada.
- -K3dCluster <string> (default: hackathon-k3d)
	- Nome do cluster k3d para import de imagem e troca de contexto (se k3d instalado).
- -DesNamespace <string> (default: des) | -PrdNamespace <string> (default: prd)
	- Namespaces de destino para DES/PRD.
- -ApprovePrd (switch)
	- Se presente, faz deploy no PRD sem pedir confirmação interativa.
- -TimeoutRollout <duration> (default: 120s)
	- Tempo máximo para `kubectl rollout status`. Aceita formatos: `60s`, `2m`, `1h` ou `hh:mm:ss`.
- -TimeoutSmoke <duration> (default: 60s)
	- Timeout do smoke job no cluster e do smoke local (-RunLocalSmoke). Mesmos formatos de duração.
- -RunLocalSmoke (switch)
	- Após o build, sobe um container local com usuário 10001 em `-p 8080:8080` e aguarda `/q/health/ready`.
- -BuildOnly (switch)
	- Executa somente o build (Maven + Docker) e, opcionalmente, `-RunLocalSmoke`. Não renderiza/aplica YAMLs.

Observações:
- Se k3d estiver instalado, a imagem é importada no cluster (`k3d image import ...`). Caso contrário, o script continua, mas o cluster precisará conseguir puxar a imagem do registry.
- `kubectl` só é exigido quando não se usa `-BuildOnly`.
