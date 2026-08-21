# bluefin-initial-setup

Automação (Ansible) para o setup inicial de um desktop Fedora Atomic
(Bluefin, uBlue, Silverblue, Kinoite...) recém-instalado, **sem usar
`rpm-ostree install`** em nenhum momento — só Flatpak, Homebrew (linuxbrew)
e arquivos de configuração graváveis (`~/.config`, `/usr/local`, `/etc`).

## O que este playbook faz

1. **Bitwarden** — instala o Flatpak (`com.bitwarden.desktop`, via Flathub)
   e aplica a configuração de referência do
   [lbssousa/dotfiles](https://github.com/lbssousa/dotfiles):
   - **Agente SSH**: liga `SSH_AUTH_SOCK` ao socket do agente SSH do
     Bitwarden Flatpak, tanto estaticamente
     (`~/.config/environment.d/20-bitwarden-ssh-agent.conf`, lido pelo
     `systemd --user` na sessão inteira — IDEs incluídos) quanto
     dinamicamente (unidades `bitwarden-ssh-agent.path` +
     `bitwarden-ssh-agent-env.service` em `~/.config/systemd/user/`, que
     reexportam a variável quando o socket aparece). O `gcr-ssh-agent` é
     mascarado para não competir pela mesma variável.
   - **Polkit (desbloqueio biométrico)**: instala a *action*
     `com.bitwarden.Bitwarden.policy` em
     `/usr/local/share/polkit-1/actions/` — não em `/usr/share/`, que é
     somente leitura em sistemas ostree. Depois de aplicado, ative em
     Bitwarden → Configurações → Segurança → *Desbloquear com autenticação
     do sistema*.
2. **Homebrew tap `ublue-os`** — adiciona e marca como confiável
   (`trust: true`) o tap [ublue-os/homebrew-tap](https://github.com/ublue-os/homebrew-tap),
   que publica casks de apps GUI empacotados especificamente para
   desktops imutáveis (sem depender do cask oficial, que assume macOS).
3. **VSCode e Zed** — instala `visual-studio-code-linux` e `zed-linux`
   (casks do tap acima) via Homebrew, em vez de layering via rpm-ostree.

Mais automações devem ser adicionadas a este repositório com o tempo.

> **Atenção — máquinas que já usam [lbssousa/dotfiles](https://github.com/lbssousa/dotfiles):**
> se `~/.config/environment.d/20-bitwarden-ssh-agent.conf` e as unidades em
> `~/.config/systemd/user/` já forem symlinks criados pelo `stow` desse
> repositório, rodar este playbook substitui os symlinks por arquivos
> normais (o módulo `copy` do Ansible não segue symlinks por padrão). Não
> rode os dois em conjunto na mesma máquina sem restaurar o `stow` depois
> (`cd dotfiles && ./install.sh -r`).

## Pré-requisitos

- Um desktop Fedora Atomic (`rpm-ostree status` funciona), com sessão
  gráfica ativa (D-Bus/systemd de usuário rodando — necessário para as
  unidades `systemd --user` do agente SSH).
- [Homebrew](https://brew.sh) instalado em `/home/linuxbrew/.linuxbrew`
  (padrão nas imagens uBlue/Bluefin com o *homebrew module* habilitado).
- [`just`](https://github.com/casey/just) (opcional, mas recomendado —
  também instalável via `brew install just`).
- `sudo` com senha interativa (a instalação da polkit action e o reload
  do polkit pedem confirmação).

`ansible` **não** precisa estar pré-instalado: `just setup` instala via
Homebrew automaticamente se faltar, junto da collection `community.general`
(que fornece os módulos de Flatpak e Homebrew usados aqui).

## Uso

```bash
git clone https://github.com/lbssousa/bluefin-initial-setup.git
cd bluefin-initial-setup
just setup
```

Ou diretamente com Ansible:

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml --ask-become-pass
```

O playbook é idempotente — rodar de novo é seguro e só aplica o que
ainda não estiver no estado desejado.

## Estrutura

| Arquivo/Diretório      | Papel                                                          |
|-------------------------|-----------------------------------------------------------------|
| `site.yml`               | Playbook principal                                               |
| `group_vars/all.yml`     | Variáveis (IDs de Flatpak, nome do tap, casks, caminhos)         |
| `files/`                 | Arquivos estáticos copiados como estão (unidades systemd, polkit action, environment.d) |
| `requirements.yml`       | Collections Ansible necessárias (`community.general`)           |
| `Justfile`               | Atalho (`just setup`)                                            |

## Créditos

Configuração do Bitwarden (agente SSH + polkit biométrico) baseada em
[lbssousa/dotfiles](https://github.com/lbssousa/dotfiles).
