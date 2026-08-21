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
4. **Usuários adicionais** — cria as contas listadas em
   `group_vars/all/local_users.yml` (arquivo local, fora do git — veja a
   seção [Dados privados](#dados-privados-usuários-adicionais) abaixo).
   Nenhuma senha é definida: cada conta nova é marcada com
   `PasswordMode=1` via `accountsservice` (o mesmo mecanismo de
   Configurações → Usuários → *"Permitir que o usuário defina uma senha
   no próximo login"* do GNOME), então o GDM mostra a tela de definição
   de senha no primeiro login em vez do prompt normal. A marcação só é
   aplicada na criação da conta — reexecutar o playbook não reseta a
   senha de um usuário que já a definiu.
5. **Impressora EPSON L4160** — cria a fila CUPS `L4160` em modo
   *driverless* (`lpadmin -m everywhere`, suporte nativo a IPP
   Everywhere), sem instalar o driver ESC/P-R da Epson: o filtro CUPS
   dele não tem como ser alcançado pelo `cupsd` fora de `/usr`
   (somente leitura em sistemas ostree — o `ServerBin` do CUPS não tem
   um fallback de busca como o dos PPDs em `/usr/local/share/ppd`).
   Estrutura da fila (URI resolvida por hostname mDNS, em vez de
   `dnssd://`/`implicitclass://`; `printer-error-policy=abort-job`)
   inspirada em [lbssousa/nix-config](https://github.com/lbssousa/nix-config)
   (`modules/system/hardware/printing.nix`). Ajuste
   `printer_l4160_hostname` em `group_vars/all/main.yml` se a
   impressora for trocada/renomeada na rede. Pule com
   `--skip-tags printer` em máquinas sem essa impressora.
6. **libfprint (goodix538d)** — compila e instala o driver do leitor de
   digitais Goodix 27c6:538d, executando a automação do repositório
   separado [lbssousa/bluefin-distrobox-libfprint](https://github.com/lbssousa/bluefin-distrobox-libfprint)
   (trazido aqui como submódulo git em `external/`, via
   `ansible.builtin.import_playbook`, então roda dentro do mesmo
   `--ask-become-pass`). Em máquinas sem esse leitor, pule com
   `ansible-playbook site.yml --ask-become-pass --skip-tags libfprint`
   (ou `just setup-no-libfprint`).

Mais automações devem ser adicionadas a este repositório com o tempo.

> **Atenção — máquinas que já usam [lbssousa/dotfiles](https://github.com/lbssousa/dotfiles):**
> se `~/.config/environment.d/20-bitwarden-ssh-agent.conf` e as unidades em
> `~/.config/systemd/user/` já forem symlinks criados pelo `stow` desse
> repositório, rodar este playbook substitui os symlinks por arquivos
> normais (o módulo `copy` do Ansible não segue symlinks por padrão). Não
> rode os dois em conjunto na mesma máquina sem restaurar o `stow` depois
> (`cd dotfiles && ./install.sh -r`).

## Dados privados (usuários adicionais)

`username` e nome completo são dados pessoais e não ficam neste
repositório público. Em vez disso:

```bash
cp group_vars/all/local_users.yml.example group_vars/all/local_users.yml
# edite group_vars/all/local_users.yml com os dados reais
```

`group_vars/all/local_users.yml` está no `.gitignore` — o git nunca vai
tentar comitá-lo. Se a automação de usuários não for usada nesta máquina,
basta não criar o arquivo: o bloco correspondente do playbook é pulado
(`when: extra_users is defined`) e o restante do setup roda normalmente.

Como não há senha nenhuma armazenada (nem hash), não é necessário
`ansible-vault` aqui — só o `.gitignore` já resolve. Se uma automação
futura precisar guardar segredos de fato (senhas, tokens), aí sim vale
migrar para `ansible-vault`.

## Pré-requisitos

- Um desktop Fedora Atomic (`rpm-ostree status` funciona), com sessão
  gráfica ativa (D-Bus/systemd de usuário rodando — necessário para as
  unidades `systemd --user` do agente SSH).
- Ambiente GNOME com `accountsservice` e `busctl` (`systemd`) — ambos
  vêm por padrão no Bluefin/uBlue; necessários apenas se a automação de
  usuários adicionais for usada.
- CUPS (`lpadmin`, padrão no Bluefin/uBlue) e a impressora acessível na
  rede via mDNS — necessário apenas para a automação da impressora;
  pule com `--skip-tags printer` se não for usá-la.
- `distrobox` (padrão no Bluefin/uBlue) — necessário apenas para a
  automação do libfprint; pule com `--skip-tags libfprint` se não for
  usá-la.
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
git clone --recurse-submodules https://github.com/lbssousa/bluefin-initial-setup.git
cd bluefin-initial-setup
just setup
```

(`just setup` também roda `git submodule update --init --recursive` sozinho,
então `--recurse-submodules` no clone é só uma otimização.)

Ou diretamente com Ansible:

```bash
git submodule update --init --recursive
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml --ask-become-pass
```

O playbook é idempotente — rodar de novo é seguro e só aplica o que
ainda não estiver no estado desejado.

## Estrutura

| Arquivo/Diretório      | Papel                                                          |
|-------------------------|-----------------------------------------------------------------|
| `site.yml`               | Playbook principal                                               |
| `group_vars/all/main.yml` | Variáveis públicas (IDs de Flatpak, nome do tap, casks, caminhos) |
| `group_vars/all/local_users.yml.example` | Template dos usuários adicionais (copie para `local_users.yml`) |
| `group_vars/all/local_users.yml` | Dados reais dos usuários adicionais — local, fora do git    |
| `files/`                 | Arquivos estáticos copiados como estão (unidades systemd, polkit action, environment.d) |
| `requirements.yml`       | Collections Ansible necessárias (`community.general`)           |
| `external/bluefin-distrobox-libfprint` | Submódulo git com a automação do libfprint (repo separado) |
| `.gitmodules`             | Declaração do submódulo acima                                    |
| `Justfile`               | Atalhos (`just setup`, `just setup-no-libfprint`)                |

## Créditos

- Configuração do Bitwarden (agente SSH + polkit biométrico) baseada em
  [lbssousa/dotfiles](https://github.com/lbssousa/dotfiles).
- Estrutura da fila da impressora EPSON L4160 baseada em
  [lbssousa/nix-config](https://github.com/lbssousa/nix-config).
- Automação do libfprint (goodix538d) do repositório separado
  [lbssousa/bluefin-distrobox-libfprint](https://github.com/lbssousa/bluefin-distrobox-libfprint).
