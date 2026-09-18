# bluefin-initial-setup

Automação (Ansible) para o setup inicial de um desktop Fedora Atomic
(Bluefin, uBlue, Silverblue, Kinoite...) recém-instalado, **sem usar
`rpm-ostree install`** em nenhum momento — só Flatpak, Homebrew (linuxbrew)
e arquivos de configuração graváveis (`~/.config`, `/usr/local`, `/etc`).
Também cobre o [Bluefin Dakota](https://docs.projectbluefin.io/dakota/)
(GNOME OS, sem RPMs/`rpm-ostree`) via `site-dakota.yml` — veja a seção
["Bluefin Dakota"](#bluefin-dakota) abaixo.

Cada automação é um playbook próprio em `playbooks/` (ou um submódulo git
em `external/`), importado por `site.yml` via `ansible.builtin.import_playbook`
— todas rodam dentro do mesmo `--ask-become-pass`, mas cada uma tem sua
própria tag: rode só uma com `--tags <tag>`, ou pule uma com
`--skip-tags <tag>`.

## O que este playbook faz

1. **Bitwarden** (`playbooks/bitwarden.yml`, tag `bitwarden`, **não roda por padrão** — tag `never`,
   só sob pedido explícito: `--tags bitwarden` / `just bitwarden` / `just bitwarden-dakota`) — instala o Flatpak (`com.bitwarden.desktop`, via Flathub)
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
     do sistema*. Essa tarefa específica tem a sub-tag `bitwarden-polkit`
     (`--tags bitwarden-polkit`), usada pelas receitas `just
     bitwarden-setup-polkit`/`bitwarden-remove-polkit` do
     [lbssousa/dotfiles](https://github.com/lbssousa/dotfiles) — que
     hoje chamam este Ansible em vez de um script próprio.
2. **Homebrew tap `ublue-os` + VSCode/Zed** (`playbooks/homebrew.yml`, tag
   `homebrew`) — adiciona e marca como confiável (`trust: true`) o tap
   [ublue-os/homebrew-tap](https://github.com/ublue-os/homebrew-tap),
   que publica casks de apps GUI empacotados especificamente para
   desktops imutáveis (sem depender do cask oficial, que assume macOS),
   e instala `visual-studio-code-linux` e `zed-linux` (casks desse tap)
   em vez de layering via rpm-ostree.
3. **Zed — Podman como runtime de dev containers** (`playbooks/zed.yml`, tag
   `zed`) — configura `"use_podman": true` em `~/.config/zed/settings.json`
   ([zed.dev/docs/dev-containers](https://zed.dev/docs/dev-containers)),
   já que nas imagens uBlue/Bluefin só o Podman vem pré-instalado (sem
   Docker). Configuração de referência (pacote stow `zed`) em
   [lbssousa/dotfiles](https://github.com/lbssousa/dotfiles). Mesmo
   raciocínio do Neovim abaixo: se o arquivo já existir — por
   dotfiles/stow ou edição manual —, nunca é sobrescrito, já que tende a
   acumular preferências pessoais (tema, fonte, keybindings) ao longo do
   tempo.
4. **YubiKey FIDO2/U2F** (`playbooks/yubikey.yml`, tag `yubikey`) —
   migrado das receitas `yubikey-*` do `just/.justfile` de
   [lbssousa/dotfiles](https://github.com/lbssousa/dotfiles) (fluxo
   atual, baseado em `authselect` gerenciado — não do script
   `security/yubikey/setup.sh`, legado, que editava
   `/etc/pam.d/system-auth` via `sed` e desativava o `authselect`).
   Cada etapa é selecionável com sua própria tag, para rodar isolada
   (`ansible-playbook site.yml --ask-become-pass --tags
   yubikey-enroll`):
   - `yubikey-enroll` — registra a primeira YubiKey em
     `~/.config/Yubico/u2f_keys` (pula se já existir).
   - `yubikey-setup-pam` / `yubikey-mode-replace` — aplicam o mesmo
     perfil `authselect` (YubiKey substitui a senha); duas tags para a
     mesma ação, espelhando as duas receitas equivalentes do Justfile.
   - `yubikey-setup-pcscd` — drop-in systemd que evita uma race
     condition entre o `pcscd` e o `udev` no boot.
   - `yubikey-mode-2fa` — perfil `authselect` com YubiKey + senha
     obrigatórios.
   - `yubikey-test` — testa a autenticação via `sudo`.
   - `yubikey-reset` — restaura o backup `authselect` mais antigo do
     YubiKey (ou o perfil base, se não houver backup).

   **A instalação do pacote `pam-u2f` fica fora do escopo**: o feature
   nativo `with-pam-u2f` do `authselect` espera o `pam_u2f.so` no
   caminho padrão do sistema, só alcançável via `rpm-ostree install` —
   o que violaria a regra deste repositório de nunca usar rpm-ostree.
   Instale antes, manualmente (`just yubikey-install` no dotfiles, ou
   `rpm-ostree install pam-u2f` + `brew install libfido2` + reboot).
5. **Usuários adicionais** (`playbooks/users.yml`, tag `users`) — cria as contas listadas em
   `group_vars/all/local_users.yml` (arquivo local, fora do git — veja a
   seção [Dados privados](#dados-privados-usuários-adicionais) abaixo).
   Nenhuma senha é definida: cada conta nova é marcada com
   `PasswordMode=1` via `accountsservice` (o mesmo mecanismo de
   Configurações → Usuários → *"Permitir que o usuário defina uma senha
   no próximo login"* do GNOME), então o GDM mostra a tela de definição
   de senha no primeiro login em vez do prompt normal. A marcação só é
   aplicada na criação da conta — reexecutar o playbook não reseta a
   senha de um usuário que já a definiu.
6. **Impressora EPSON L4160** (`playbooks/printer.yml`, tag `printer`) — cria a fila CUPS `L4160` em modo
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
7. **Neovim + LazyVim** (`playbooks/neovim.yml`, tag `neovim`) — instala o `neovim` via Homebrew e, se
   `~/.config/nvim` ainda não existir, clona ali o
   [starter oficial do LazyVim](https://github.com/LazyVim/starter),
   removendo o histórico git do template (recomendação oficial do
   LazyVim, deixa o diretório livre para o dotfiles/stow sobrepor
   plugins depois — veja `nvim/lua/plugins/*.lua` em
   [lbssousa/dotfiles](https://github.com/lbssousa/dotfiles)). Uma
   config já existente nunca é sobrescrita.
8. **libfprint (goodix538d)** (submódulo `external/bluefin-distrobox-libfprint`, tag `libfprint`) — compila e instala o driver do leitor de
   digitais Goodix 27c6:538d, executando a automação do repositório
   separado [lbssousa/bluefin-distrobox-libfprint](https://github.com/lbssousa/bluefin-distrobox-libfprint)
   (trazido aqui como submódulo git, via `ansible.builtin.import_playbook`,
   então roda dentro do mesmo `--ask-become-pass`). Em máquinas sem esse
   leitor, pule com `ansible-playbook site.yml --ask-become-pass
   --skip-tags libfprint` (ou `just setup-no-libfprint`).
9. **Caps Lock via kanata** (`playbooks/capslock.yml`, tag `capslock`) — instala o
   [kanata](https://github.com/jtroo/kanata) via Homebrew e remapeia o
   Caps Lock a nível evdev: toque rápido vira `Esc`, segurado vira
   `Ctrl`, e Shift+toque preserva o Caps Lock original. Por operar em
   evdev (não em X11/Xorg), funciona igual em TTY e em sessão
   GNOME/Wayland — ao contrário do `setxkbmap`/"Origens de entrada" do
   GNOME, que só alcança o compositor gráfico. Roda como serviço de
   sistema (`systemd`, unidade própria em `/etc/systemd/system/`, não
   via `brew services`) porque `/dev/uinput` neste sistema é
   `root:root` e não tem grupo de acesso. Configuração de referência em
   [lbssousa/nix-config](https://github.com/lbssousa/nix-config)
   (`modules/system/core/localization.nix`). Mesmo raciocínio do Neovim
   e do Zed acima: `~/.config/kanata/kanata.kbd` só é copiado se ainda
   não existir, nunca sobrescrito.
10. **KeePassXC** (`playbooks/keepassxc.yml`, tag guarda-chuva `keepassxc`) — dois blocos independentes,
    cada um com sua própria sub-tag:
    - `keepassxc-yubikey-lock` — instala uma regra udev que trava todas
      as bases do KeePassXC (via D-Bus,
      `org.keepassxc.KeePassXC.MainWindow.lockAllDatabases`) sempre que a
      YubiKey é desconectada da porta USB. A regra casa qualquer YubiKey
      pelo vendor ID da Yubico (`1050`), não um modelo específico —
      desvio proposital da configuração de referência em
      [lbssousa/nix-config](https://github.com/lbssousa/nix-config)
      (`modules/system/security/keepassxc-yubikey-lock.nix`), que trava
      num único modelo.
    - `keepassxc-browser` — ponte de *native messaging* entre o Flatpak
      do KeePassXC e os Flatpaks dos navegadores suportados (Firefox,
      Chrome, Brave, Chromium, Edge — lista em
      `keepassxc_native_messaging_targets` em `group_vars/all/main.yml`),
      para a extensão [KeePassXC-Browser](https://github.com/keepassxreboot/keepassxc-browser)
      funcionar. Cada Flatpak só enxerga o próprio diretório de dados
      (`~/.var/app/<id>/...`) e não consegue spawnar diretamente um
      processo de outro Flatpak; por isso instala, DENTRO do diretório
      de dados de cada navegador já instalado, um manifesto de native
      messaging e um script wrapper que usa `flatpak-spawn --host` para
      rodar o `keepassxc-proxy` do Flatpak do KeePassXC no host, e
      concede a permissão `--talk-name=org.freedesktop.Flatpak`
      necessária para isso. Roda igual no Fedora e no Dakota (mecanismo
      100% Flatpak/D-Bus, independente da base do sistema) — ainda não
      validado em hardware real.

    **A instalação do KeePassXC fica fora do escopo** dos dois blocos
    (mesmo raciocínio do `pam-u2f` no item YubiKey acima): pressupõem o
    app já instalado, com a integração D-Bus habilitada (ativa por
    padrão em Ferramentas → Configurações → Geral).

Mais automações devem ser adicionadas a este repositório com o tempo.

> **Máquinas que já usam [lbssousa/dotfiles](https://github.com/lbssousa/dotfiles):**
> `~/.config/environment.d/20-bitwarden-ssh-agent.conf` e as unidades em
> `~/.config/systemd/user/` (`bitwarden-ssh-agent.path`,
> `bitwarden-ssh-agent-env.service`) só são copiados se ainda não
> existirem — se já forem symlinks criados pelo `stow` desse repositório,
> o Ansible não mexe neles (`force: false`, veja `playbooks/bitwarden.yml`).
> É seguro rodar os dois na mesma máquina.

## Bluefin Dakota

O [Bluefin Dakota](https://docs.projectbluefin.io/dakota/) é uma base
radicalmente diferente do Bluefin/uBlue clássico: GNOME OS compilado via
Apache BuildStream, publicado como imagem `bootc` sobre backend
**composefs-oci** — **sem RPMs, sem `rpm-ostree`, sem `authselect`** (a
ferramenta do stack Fedora/RHEL que `playbooks/yubikey.yml` usa para
PAM). Ainda em alpha. Por isso existe `site-dakota.yml`, espelhando
`site.yml` tag por tag, com duas diferenças:

- **YubiKey** (`playbooks/dakota/yubikey.yml`) — sem `authselect` no
  Dakota (e sem substituto documentado ainda), este arquivo **não mexe
  em PAM**. Mantém só o que é OS-agnóstico: o fix de race condition do
  `pcscd` (tag `yubikey-setup-pcscd`) e uma tarefa nova, `yubikey-gpg-import`,
  que importa a chave pública OpenPGP do cartão da YubiKey
  (`gpg --card-status` + `gpg --edit-card fetch`) para o keyring local.
  As etapas de PAM/authselect de `playbooks/yubikey.yml`
  (`yubikey-enroll`, `yubikey-setup-pam`, `yubikey-mode-replace`,
  `yubikey-mode-2fa`, `yubikey-test`, `yubikey-reset`) **não têm
  equivalente no Dakota por enquanto**.
- **libfprint** (`playbooks/dakota/libfprint.yml`) — build e instalação
  autocontidos neste repositório, sem depender do submódulo
  `external/bluefin-distrobox-libfprint` (cujo README fala
  explicitamente de "desktop Fedora Atomic"). Mesma estratégia (compilar
  o fork [lbssousa/libfprint](https://github.com/lbssousa/libfprint) num
  container distrobox descartável — `playbooks/files/dakota-libfprint-distrobox.ini`
  — e instalar só em `/usr/local`, gravável tanto em rpm-ostree quanto
  no bootc/composefs-oci do Dakota), reimplementada para não depender de
  um repositório rotulado para Fedora.

Todos os outros playbooks (`zed`, `users`, `printer`, `neovim`,
`capslock`, `keepassxc`, e o próprio `bitwarden`, que também não roda
por padrão no Dakota) são os **mesmos arquivos** usados pelo `site.yml`
clássico — Homebrew e Podman já vêm pré-instalados nas imagens Dakota,
então nenhuma adaptação de conteúdo foi necessária.

`site-dakota.yml` **não importa** `playbooks/homebrew.yml` (tag
`homebrew`, sem receita `homebrew-dakota` correspondente): no Dakota, a
instalação do VSCode e do Zed já é gerenciada pelo `ujust` da própria
imagem, então esse playbook (tap `ublue-os` + casks do VSCode/Zed) seria
redundante ali. `playbooks/zed.yml` continua rodando normalmente — ele
só configura o Podman como runtime de dev containers do Zed
(`~/.config/zed/settings.json`), não instala o app.

```bash
just setup-dakota                    # tudo, exceto Bitwarden — como o `just setup` clássico
just <tag>-dakota                    # uma automação isolada, ex.: just libfprint-dakota
ansible-playbook site-dakota.yml --ask-become-pass --tags yubikey-gpg-import
```

Não depende do submódulo git (`external/bluefin-distrobox-libfprint`) —
o libfprint no Dakota é autocontido. **Nada aqui foi validado em
hardware Dakota real ainda** (o Dakota é alpha e a documentação oficial
ainda não cobre CUPS, `accountsservice`, `fprintd` ou o layout completo
de `/etc` nessa imagem); trate como ponto de partida a testar, não como
garantia.

## Desinstalação

`uninstall.yml`, na raiz do repositório, é um playbook independente de
`site.yml` (mesmo padrão do `external/bluefin-distrobox-libfprint/uninstall.yml`)
para reverter automações específicas:

```bash
ansible-playbook uninstall.yml --ask-become-pass --tags bitwarden-polkit
```

Cobre a remoção da polkit action do Bitwarden (equivalente ao antigo
`bitwarden/uninstall.sh` do
[lbssousa/dotfiles](https://github.com/lbssousa/dotfiles), que agora
invoca este playbook em vez de um script próprio), do serviço/unidade
systemd do kanata (tag `capslock`), da regra udev/script do
KeePassXC (tag `keepassxc-yubikey-lock`), da ponte de native messaging
do KeePassXC com os navegadores Flatpak (tag `keepassxc-browser` —
remove o manifesto, o wrapper e a permissão `talk-name` concedida a
cada navegador) e, no Dakota, do install em `/usr/local` +
`fprintd.service` do libfprint (tag `libfprint-dakota`) — em todos os
casos, sem remover a config pessoal (`kanata.kbd`) nem desinstalar
pacotes via Homebrew. Mais automações de desinstalação devem ser
adicionadas aqui com o tempo.

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
| `site.yml`               | Índice: importa cada `playbooks/*.yml` com sua tag (Fedora Atomic clássico) |
| `site-dakota.yml`        | Mesmo índice para o Bluefin Dakota — veja a seção "Bluefin Dakota" acima |
| `uninstall.yml`          | Desinstalação — playbook independente, tags por automação        |
| `playbooks/bitwarden.yml` | Bitwarden — Flatpak + agente SSH + polkit (tag `bitwarden`, não roda por padrão) |
| `playbooks/homebrew.yml`  | Tap `ublue-os` + VSCode/Zed (tag `homebrew`)                    |
| `playbooks/zed.yml`       | Podman como runtime de dev containers no Zed (tag `zed`)         |
| `playbooks/yubikey.yml`   | YubiKey FIDO2/U2F — etapas selecionáveis (tags `yubikey-*`), Fedora/authselect |
| `playbooks/users.yml`     | Usuários adicionais (tag `users`)                                |
| `playbooks/printer.yml`   | Impressora EPSON L4160 driverless (tag `printer`)                |
| `playbooks/neovim.yml`    | Neovim + LazyVim (tag `neovim`)                                  |
| `playbooks/capslock.yml`  | Caps Lock via kanata (tag `capslock`)                            |
| `playbooks/keepassxc.yml` | KeePassXC — trava ao remover a YubiKey + ponte de native messaging (tags `keepassxc-yubikey-lock`/`keepassxc-browser`) |
| `playbooks/dakota/yubikey.yml`   | YubiKey no Dakota — só `yubikey-setup-pcscd` + `yubikey-gpg-import`, sem PAM |
| `playbooks/dakota/libfprint.yml` | libfprint no Dakota — build/install autocontidos, sem o submódulo |
| `playbooks/files/`        | Arquivos estáticos copiados como estão (unidades systemd, polkit action, environment.d, manifesto/wrapper do KeePassXC-Browser, distrobox.ini/drop-in do libfprint no Dakota) — compartilhado pelos playbooks acima |
| `group_vars/all/main.yml` | Variáveis públicas de todas as automações (IDs de Flatpak, nome do tap, casks, caminhos, alvos do KeePassXC-Browser, vars do libfprint no Dakota) |
| `group_vars/all/local_users.yml.example` | Template dos usuários adicionais (copie para `local_users.yml`) |
| `group_vars/all/local_users.yml` | Dados reais dos usuários adicionais — local, fora do git    |
| `requirements.yml`       | Collections Ansible necessárias (`community.general`)           |
| `external/bluefin-distrobox-libfprint` | Submódulo git com a automação do libfprint para Fedora (repo separado, tag `libfprint`) — não usado pelo Dakota |
| `.gitmodules`             | Declaração do submódulo acima                                    |
| `Justfile`               | Atalhos (`just setup`, `just setup-dakota`, `just <tag>`/`just <tag>-dakota` por automação) |

## Créditos

- Configuração do Bitwarden (agente SSH + polkit biométrico) baseada em
  [lbssousa/dotfiles](https://github.com/lbssousa/dotfiles).
- Automação do YubiKey FIDO2/U2F migrada das receitas `yubikey-*` do
  `just/.justfile` de [lbssousa/dotfiles](https://github.com/lbssousa/dotfiles).
- Estrutura da fila da impressora EPSON L4160 baseada em
  [lbssousa/nix-config](https://github.com/lbssousa/nix-config).
- Automação do libfprint (goodix538d) do repositório separado
  [lbssousa/bluefin-distrobox-libfprint](https://github.com/lbssousa/bluefin-distrobox-libfprint).
- Remapeamento do Caps Lock via kanata baseado em
  [lbssousa/nix-config](https://github.com/lbssousa/nix-config)
  (`modules/system/core/localization.nix`).
- Trava do KeePassXC ao remover a YubiKey baseada em
  [lbssousa/nix-config](https://github.com/lbssousa/nix-config)
  (`modules/system/security/keepassxc-yubikey-lock.nix`).
