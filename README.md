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
— todas compartilham a mesma escalação de privilégio (`run0`, veja a seção
["Privilégio: run0 --empower"](#privilégio-run0---empower) abaixo), mas
cada uma tem sua própria tag: rode só uma com `--tags <tag>`, ou pule uma
com `--skip-tags <tag>`.

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
4. **YubiKey FIDO2/U2F** (`playbooks/yubikey.yml`, tag guarda-chuva `yubikey`) —
   migrado das receitas `yubikey-*` do `just/.justfile` de
   [lbssousa/dotfiles](https://github.com/lbssousa/dotfiles) (fluxo
   atual, baseado em `authselect` gerenciado — não do script
   `security/yubikey/setup.sh`, legado, que editava
   `/etc/pam.d/system-auth` via `sed` e desativava o `authselect`).
   Cada etapa é selecionável com sua própria tag, para rodar isolada
   (`ansible-playbook site.yml --tags yubikey-enroll`):
   - `yubikey-enroll` — registra a primeira YubiKey em
     `~/.config/Yubico/u2f_keys` (pula se já existir).
   - `yubikey-setup-pam` / `yubikey-mode-replace` — aplicam o mesmo
     perfil `authselect` (YubiKey substitui a senha); duas tags para a
     mesma ação, espelhando as duas receitas equivalentes do Justfile.
   - `yubikey-setup-pcscd` — corrige a YubiKey ficando invisível para o
     GnuPG (`gpg --card-status` sem cartão) até reiniciar o `pcscd` na
     mão — bug conhecido do `pcsc-lite`, não específico deste
     repositório, que afeta Fedora Atomic, Bluefin, Dakota e outras
     distros. Duas automações: um drop-in systemd
     (`ExecStartPre=udevadm settle`) que evita uma race condition entre
     o `pcscd` e o `udev` no boot, e uma regra udev que reinicia o
     `pcscd` sempre que uma YubiKey é conectada (`ACTION=="add"`,
     vendor Yubico `1050`) — cobre o caso mais comum na prática:
     plugar a YubiKey depois do boot, trocar de porta USB, ou
     suspender/retomar a máquina com ela conectada.
   - `yubikey-mode-2fa` — perfil `authselect` com YubiKey + senha
     obrigatórios.
   - `yubikey-test` — testa a autenticação via `run0` (o mecanismo de
     escalação de privilégio deste repositório — veja "Privilégio:
     run0 --empower" abaixo). Rode esta tag isolada, sem
     `run-empowered.sh`, para um teste de verdade: dentro de `just
     yubikey` o processo já está autenticado, e a chamada passaria sem
     exercitar a YubiKey.
   - `yubikey-reset` — restaura o backup `authselect` mais antigo do
     YubiKey (ou o perfil base, se não houver backup).
   - `keepassxc-yubikey-lock` — instala uma regra udev que trava todas
     as bases do KeePassXC (via D-Bus,
     `org.keepassxc.KeePassXC.MainWindow.lockAllDatabases`) sempre que a
     YubiKey é desconectada da porta USB. A regra casa qualquer YubiKey
     pelo vendor ID da Yubico (`1050`), não um modelo específico —
     desvio proposital da configuração de referência em
     [lbssousa/nix-config](https://github.com/lbssousa/nix-config)
     (`modules/system/security/keepassxc-yubikey-lock.nix`), que trava
     num único modelo. Mora aqui (não em `playbooks/keepassxc.yml`)
     porque é disparada pela YubiKey, não por algo específico do
     KeePassXC. **Se o KeePassXC não estiver instalado, a tarefa avisa
     e pula** em vez de falhar — ao contrário do `pam-u2f` abaixo, essa
     ausência não é fatal, já que um `ansible.builtin.fail` aqui
     interromperia o host para as plays seguintes de
     `site.yml`/`site-dakota.yml` (`bash.yml` incluso).

   **A instalação do pacote `pam-u2f` fica fora do escopo** (das etapas
   de PAM acima): o feature nativo `with-pam-u2f` do `authselect`
   espera o `pam_u2f.so` no caminho padrão do sistema, só alcançável
   via `rpm-ostree install` — o que violaria a regra deste repositório
   de nunca usar rpm-ostree. Instale antes, manualmente (`just
   yubikey-install` no dotfiles, ou `rpm-ostree install pam-u2f` +
   `brew install libfido2` + reboot). A instalação do **KeePassXC**
   também fica fora do escopo (mesmo raciocínio) — pressupõe-se o app
   já instalado, com a integração D-Bus habilitada (ativa por padrão em
   Ferramentas → Configurações → Geral).
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
8. **libfprint (goodix538d)** (submódulo `external/bluefin-distrobox-libfprint`, tag `libfprint`, **não roda por padrão** — tag `never`,
   só sob pedido explícito: `--tags libfprint` / `just libfprint` / `just libfprint-dakota`) — compila e instala o driver do leitor de
   digitais Goodix 27c6:538d, executando a automação do repositório
   separado [lbssousa/bluefin-distrobox-libfprint](https://github.com/lbssousa/bluefin-distrobox-libfprint)
   (trazido aqui como submódulo git, via `ansible.builtin.import_playbook`,
   então roda dentro da mesma escalação de privilégio via run0). Requer
   o submódulo inicializado antes (`git submodule update --init
   --recursive`, ou simplesmente `just libfprint`, que faz isso
   sozinho).
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
10. **KeePassXC — ponte de native messaging** (`playbooks/keepassxc.yml`, tag `keepassxc-browser`,
    também coberta pela tag `keepassxc`) — ponte de *native messaging*
    entre o Flatpak do KeePassXC e os Flatpaks dos navegadores
    suportados (Firefox, Chrome, Brave, Chromium, Edge — lista em
    `keepassxc_native_messaging_targets` em `group_vars/all/main.yml`),
    para a extensão [KeePassXC-Browser](https://github.com/keepassxreboot/keepassxc-browser)
    funcionar. Cada Flatpak só enxerga o próprio diretório de dados
    (`~/.var/app/<id>/...`) e não consegue spawnar diretamente um
    processo de outro Flatpak; por isso instala, DENTRO do diretório de
    dados de cada navegador já instalado, um manifesto de native
    messaging e um script wrapper que usa `flatpak-spawn --host` para
    rodar o `keepassxc-proxy` do Flatpak do KeePassXC no host, e
    concede a permissão `--talk-name=org.freedesktop.Flatpak`
    necessária para isso. Roda igual no Fedora e no Dakota (mecanismo
    100% Flatpak/D-Bus, independente da base do sistema) — ainda não
    validado em hardware real.

    A instalação do KeePassXC fica fora do escopo (mesmo raciocínio do
    `pam-u2f` no item YubiKey acima), e aqui **a ausência dele é
    fatal**: se não estiver instalado, esta automação falha com
    orientação em vez de pular — ao contrário da trava ao remover a
    YubiKey (item 4 acima), que agora mora em `playbooks/yubikey.yml` e
    falha graciosamente.
11. **Bash com cara de Fish** (`playbooks/bash.yml`, tag guarda-chuva `bash`) — dois blocos
    independentes, cada um com sua própria sub-tag:
    - `bash-completion` — autocomplete case-insensitive
      (`completion-ignore-case`) e history-substring-search (setas
      cima/baixo filtram o histórico pelo que já foi digitado, igual ao
      plugin `zsh-history-substring-search`), via `~/.inputrc`. Recursos
      nativos do GNU Readline — não dependem do ble.sh abaixo.
    - `blesh` — instala o [ble.sh](https://github.com/akinomyoga/ble.sh)
      ("Bash Line Editor"), que reescreve a edição de linha do Bash e
      traz, de fábrica, *syntax highlighting* e *autosuggestions*
      (sugestão em cinza a partir do histórico enquanto você digita,
      aceita com End/→) — o equivalente mais próximo pro Bash de
      `zsh-syntax-highlighting` + `zsh-autosuggestions` (ou do próprio
      Fish) que existe. Sem *formula* no Homebrew (projeto 100% Bash,
      sem binário pra publicar): compilado a partir do código-fonte via
      `make install`, usando `make`/`gawk` (esses sim via Homebrew) só
      no momento do build. `~/.bashrc` e `~/.inputrc` são editados de
      forma não-destrutiva (`lineinfile`/`blockinfile` com marcador
      próprio), não criados/sobrescritos só se ainda não existirem —
      diferente do Neovim/Zed/kanata, aqui o objetivo é garantir que as
      linhas específicas existam dentro de um arquivo que o usuário já
      tem e continua controlando o resto.

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
  em PAM**. Mantém só o que é OS-agnóstico: o fix da YubiKey ficando
  invisível para o GnuPG até reiniciar o `pcscd` na mão (tag
  `yubikey-setup-pcscd`), uma tarefa nova, `yubikey-gpg-import`,
  que importa a chave pública OpenPGP do cartão da YubiKey
  (`gpg --card-status` + `gpg --edit-card fetch`) para o keyring local,
  e a mesma trava do KeePassXC ao remover a YubiKey (tag
  `keepassxc-yubikey-lock`) de `playbooks/yubikey.yml` — genérica o
  bastante para não precisar de nenhuma adaptação aqui. As etapas de
  PAM/authselect de `playbooks/yubikey.yml` (`yubikey-enroll`,
  `yubikey-setup-pam`, `yubikey-mode-replace`, `yubikey-mode-2fa`,
  `yubikey-test`, `yubikey-reset`) **não têm equivalente no Dakota por
  enquanto**.
- **libfprint** (`playbooks/dakota/libfprint.yml`, **não roda por padrão** —
  tag `never`, só sob pedido explícito: `--tags libfprint` / `just
  libfprint-dakota`) — build e instalação autocontidos neste repositório, sem depender do submódulo
  `external/bluefin-distrobox-libfprint` (cujo README fala
  explicitamente de "desktop Fedora Atomic"). Mesma estratégia (compilar
  o fork [lbssousa/libfprint](https://github.com/lbssousa/libfprint) num
  container distrobox descartável —
  `playbooks/files/dakota-libfprint-distrobox.ini`), mas instalando em
  **`/var/usrlocal`, não `/usr/local`**: verificado em hardware real que,
  ao contrário do OSTree clássico (onde `/usr/local` é um symlink para
  `/var/usrlocal`, logo gravável), no Dakota `/usr/local` é um diretório
  de verdade embutido na imagem somente-leitura de `/usr` — escrever lá
  falha com "Read-only file system". `/var/usrlocal` existe na imagem
  (gravável, no `/var` em btrfs) mas não vem ligado a `/usr/local` por
  nenhum fstab/unit, então a automação usa esse caminho diretamente.

Todos os outros playbooks (`zed`, `users`, `printer`, `neovim`,
`capslock`, `keepassxc`, e o próprio `bitwarden`, que também não roda
por padrão no Dakota) são os **mesmos arquivos** usados pelo `site.yml`
clássico — Homebrew e Podman já vêm pré-instalados nas imagens Dakota,
então nenhuma adaptação de conteúdo foi necessária.

Assim como no `site.yml` clássico, `bitwarden` e `libfprint` têm tag
`never` — nenhum dos dois roda com `just setup-dakota` sem pedido
explícito.

`site-dakota.yml` **não importa** `playbooks/homebrew.yml` (tag
`homebrew`, sem receita `homebrew-dakota` correspondente): no Dakota, a
instalação do VSCode e do Zed já é gerenciada pelo `ujust` da própria
imagem, então esse playbook (tap `ublue-os` + casks do VSCode/Zed) seria
redundante ali. `playbooks/zed.yml` continua rodando normalmente — ele
só configura o Podman como runtime de dev containers do Zed
(`~/.config/zed/settings.json`), não instala o app.

```bash
just setup-dakota                    # tudo, exceto Bitwarden e libfprint — como o `just setup` clássico
just <tag>-dakota                    # uma automação isolada, ex.: just libfprint-dakota
ansible-playbook site-dakota.yml --tags yubikey-gpg-import   # sem become: roda sem run-empowered.sh
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
./run-empowered.sh ansible-playbook uninstall.yml --tags bitwarden-polkit
```

Cobre a remoção da polkit action do Bitwarden (equivalente ao antigo
`bitwarden/uninstall.sh` do
[lbssousa/dotfiles](https://github.com/lbssousa/dotfiles), que agora
invoca este playbook em vez de um script próprio), do serviço/unidade
systemd do kanata (tag `capslock`), da regra udev/script do
KeePassXC (tag `keepassxc-yubikey-lock`), da ponte de native messaging
do KeePassXC com os navegadores Flatpak (tag `keepassxc-browser` —
remove o manifesto, o wrapper e a permissão `talk-name` concedida a
cada navegador) e, no Dakota, do install em `/var/usrlocal` +
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
  automação do libfprint, que não roda por padrão (tag `never`); use
  `--tags libfprint` / `just libfprint` para rodá-la explicitamente.
- [Homebrew](https://brew.sh) instalado em `/home/linuxbrew/.linuxbrew`
  (padrão nas imagens uBlue/Bluefin com o *homebrew module* habilitado).
- [`just`](https://github.com/casey/just) (opcional, mas recomendado —
  também instalável via `brew install just`).
- `run0` (parte do systemd ≥259, veja
  [systemd/run0](https://www.freedesktop.org/software/systemd/man/latest/run0.html))
  e um usuário no grupo `wheel` — veja
  ["Privilégio: run0 --empower"](#privilégio-run0---empower) abaixo.

`ansible` **não** precisa estar pré-instalado: `just setup` instala via
Homebrew automaticamente se faltar, junto da collection `community.general`
(que fornece os módulos de Flatpak e Homebrew usados aqui, além do
become plugin `community.general.run0`).

### Privilégio: run0 --empower

Tarefas privilegiadas escalam via [`run0`](https://www.freedesktop.org/software/systemd/man/latest/run0.html)
(o become plugin `community.general.run0`, definido como `become_method`
em `ansible.cfg`). O run0 autentica via polkit, e o GNOME (Bluefin
clássico e Dakota igualmente) registra um agente polkit gráfico, então
um `run0` isolado abriria um diálogo de autenticação para **cada**
tarefa privilegiada, e o polkit não retém a autorização entre processos
`run0` separados. Uma execução completa tem dezenas de tarefas
privilegiadas.

Por isso, toda receita que precisa de root roda o `ansible-playbook`
através de [`run-empowered.sh`](run-empowered.sh), ou seja, sob `run0
--empower`: o playbook continua rodando como o seu usuário (mesmo
`$HOME`, `systemctl --user`...), mas com todas as capabilities e o
grupo `empower`, para o qual a regra polkit de fábrica do systemd
permite qualquer ação. Você autentica **uma vez**, no diálogo do
polkit que aparece no início (impressão digital ou senha, o que o
diálogo oferecer), e o `run0 --user=root` de cada tarefa `become: true`
passa sem pedir de novo. Não existe `--ask-become-pass`: nenhuma senha
é repassada ao run0.

Nada persiste: nenhuma regra polkit concedendo root sem senha é
instalada, e os privilégios vivem só naquela árvore de processos
enquanto ela roda. Segundo o `run0(1)`, outros processos não
privilegiados do seu usuário têm privilégios sobre um processo
empowered, então evite rodar isso com software não confiável em
execução na sua sessão.

Cuidado com terminais escondidos/não-assistidos: o diálogo precisa de
alguém na tela. Uma chamada sem humano presente deve passar
`ansible_become_flags=--no-ask-password` (ou usar `run0
--no-ask-password`) para falhar rápido em vez de esperar.

## Uso

```bash
git clone https://github.com/lbssousa/bluefin-initial-setup.git
cd bluefin-initial-setup
just setup
```

(`--recurse-submodules` no clone não é necessário: `just setup` não
inclui o libfprint, que é a única automação que depende de submódulo
— veja o item 8 acima. Rodando `just libfprint` depois, o submódulo é
inicializado automaticamente.)

Ou diretamente com Ansible:

```bash
ansible-galaxy collection install -r requirements.yml
./run-empowered.sh ansible-playbook site.yml
# opcional, só para o libfprint (tag `never`, não roda no comando acima):
git submodule update --init --recursive
./run-empowered.sh ansible-playbook site.yml --tags libfprint
```

O playbook é idempotente — rodar de novo é seguro e só aplica o que
ainda não estiver no estado desejado.

## Estrutura

| Arquivo/Diretório      | Papel                                                          |
|-------------------------|-----------------------------------------------------------------|
| `site.yml`               | Índice: importa cada `playbooks/*.yml` com sua tag (Fedora Atomic clássico) |
| `site-dakota.yml`        | Mesmo índice para o Bluefin Dakota — veja a seção "Bluefin Dakota" acima |
| `uninstall.yml`          | Desinstalação — playbook independente, tags por automação        |
| `ansible.cfg`            | Config do Ansible — `become_method = community.general.run0` (veja "Privilégio: run0 --empower" acima) |
| `run-empowered.sh`       | Roda o `ansible-playbook` sob `run0 --empower`: uma autenticação polkit, depois as tarefas privilegiadas passam (veja "Privilégio" acima) |
| `playbooks/bitwarden.yml` | Bitwarden — Flatpak + agente SSH + polkit (tag `bitwarden`, não roda por padrão) |
| `playbooks/homebrew.yml`  | Tap `ublue-os` + VSCode/Zed (tag `homebrew`)                    |
| `playbooks/zed.yml`       | Podman como runtime de dev containers no Zed (tag `zed`)         |
| `playbooks/yubikey.yml`   | YubiKey FIDO2/U2F, Fedora/authselect — etapas selecionáveis (tags `yubikey-*`) + trava do KeePassXC ao remover a YubiKey (tag `keepassxc-yubikey-lock`, falha graciosamente se o KeePassXC não estiver instalado) |
| `playbooks/users.yml`     | Usuários adicionais (tag `users`)                                |
| `playbooks/printer.yml`   | Impressora EPSON L4160 driverless (tag `printer`)                |
| `playbooks/neovim.yml`    | Neovim + LazyVim (tag `neovim`)                                  |
| `playbooks/capslock.yml`  | Caps Lock via kanata (tag `capslock`)                            |
| `playbooks/keepassxc.yml` | KeePassXC — ponte de native messaging para o KeePassXC-Browser (tag `keepassxc-browser`); a trava ao remover a YubiKey está em `playbooks/yubikey.yml` |
| `playbooks/bash.yml`      | Bash com cara de Fish — completion case-insensitive + history-substring-search + ble.sh (tags `bash-completion`/`blesh`) |
| `playbooks/dakota/yubikey.yml`   | YubiKey no Dakota — `yubikey-setup-pcscd` + `yubikey-gpg-import`, sem PAM; + trava do KeePassXC (`keepassxc-yubikey-lock`) |
| `playbooks/dakota/libfprint.yml` | libfprint no Dakota — build/install autocontidos, sem o submódulo |
| `playbooks/files/`        | Arquivos estáticos copiados como estão via `copy` (unidades systemd, polkit action, environment.d, script wrapper do KeePassXC-Browser, distrobox.ini do libfprint no Dakota) — compartilhado pelos playbooks acima |
| `playbooks/templates/`    | Arquivos `.j2` renderizados via `template` (regra udev do KeePassXC-YubiKey-lock, unidade do kanata, manifesto do KeePassXC-Browser). Módulo `template` só busca em `templates/`, não em `files/` — por isso ficam num diretório separado (`dakota-fprintd-override.conf.j2` é a exceção: referenciado por caminho absoluto em `playbooks/dakota/libfprint.yml`, já que aquele playbook não mora em `playbooks/`) |
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
- `run-empowered.sh` e a escalação de privilégio via `run0 --empower`
  portados de [lbssousa/omarchy-setup](https://github.com/lbssousa/omarchy-setup).
