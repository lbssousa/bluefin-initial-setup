set shell := ["bash", "-uc"]

# Playbooks that need root run under `run0 --empower` (see
# run-empowered.sh): one polkit authentication up front, then every
# `become: true` task's run0 inside passes without prompting again.
# Recipes for user-level-only tags call plain ansible-playbook.
ap := "./run-empowered.sh ansible-playbook"

default:
    @just --list

# Install ansible via Homebrew if it isn't already on PATH (no rpm-ostree layering).
_ensure-ansible:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v ansible-playbook >/dev/null; then
        echo "ansible-playbook não encontrado; instalando via Homebrew..."
        /home/linuxbrew/.linuxbrew/bin/brew install ansible
    fi

# Install collections required by the playbook (community.general).
_ensure-collections: _ensure-ansible
    ansible-galaxy collection install -r requirements.yml

# Initialize/update git submodules — only `just libfprint` needs this.
_ensure-submodules:
    git submodule update --init --recursive

# Run the initial setup playbook. Bitwarden and Proton Pass have tag "never" in site.yml (only via `just bitwarden` / `just proton-pass`); libfprint isn't in site.yml at all — standalone, via `just libfprint`.
setup: _ensure-collections
    {{ ap }} site.yml

# Fedora Atomic (Bluefin/uBlue classic) — run a single automation by its site.yml tag.
bitwarden: _ensure-collections
    {{ ap }} site.yml --tags bitwarden

# No root needed (Homebrew tap + user-level casks).
homebrew: _ensure-collections
    ansible-playbook site.yml --tags homebrew

# No root needed (Homebrew formula + ~/.local/bin + ~/.config/systemd/user).
proton-pass: _ensure-collections
    ansible-playbook site.yml --tags proton-pass

# No root needed (writes to ~/.config/zed only).
zed: _ensure-collections
    ansible-playbook site.yml --tags zed

yubikey: _ensure-collections
    {{ ap }} site.yml --tags yubikey

users: _ensure-collections
    {{ ap }} site.yml --tags users

printer: _ensure-collections
    {{ ap }} site.yml --tags printer

# No root needed (Homebrew install + ~/.config/nvim only).
neovim: _ensure-collections
    ansible-playbook site.yml --tags neovim

# Standalone automation: initializes the submodule and runs its playbook
# directly (not through site.yml).
# libfprint (goodix538d) — build + install.
libfprint: _ensure-collections _ensure-submodules
    {{ ap }} external/bluefin-distrobox-libfprint/site.yml

capslock: _ensure-collections
    {{ ap }} site.yml --tags capslock

keepassxc-yubikey-lock: _ensure-collections
    {{ ap }} site.yml --tags keepassxc-yubikey-lock

# No root needed (writes ~/.config/autostart only).
keepassxc-autostart: _ensure-collections
    ansible-playbook site.yml --tags keepassxc-autostart

# No root needed (writes to ~/.var/app/<browser>/... only).
keepassxc-browser: _ensure-collections
    ansible-playbook site.yml --tags keepassxc-browser

# No root needed (~/.bashrc/~/.inputrc + a Homebrew-adjacent user build).
bash: _ensure-collections
    ansible-playbook site.yml --tags bash

# Bluefin Dakota — same automations via site-dakota.yml (no submodule
# needed there). YubiKey uses its own Dakota-specific playbook under
# playbooks/dakota/ (no authselect/RPMs on Dakota); everything else is
# the exact same file used by the recipes above. libfprint also has a
# Dakota-specific playbook, but it's standalone — see libfprint-dakota.
#
# Run the setup playbook against a Bluefin Dakota host.
setup-dakota: _ensure-collections
    {{ ap }} site-dakota.yml

bitwarden-dakota: _ensure-collections
    {{ ap }} site-dakota.yml --tags bitwarden

# No "homebrew-dakota" recipe: on Dakota, Zed installation is already
# handled by the image's own `ujust` recipe, so playbooks/homebrew.yml
# isn't imported by site-dakota.yml. VSCode is installed via snap
# instead — see vscode-dakota below.

# Needs root (snap install). Assumes snapd is already available on the host.
vscode-dakota: _ensure-collections
    {{ ap }} site-dakota.yml --tags vscode

zed-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --tags zed

# No root needed (Homebrew formula + ~/.local/bin + ~/.config/systemd/user).
proton-pass-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --tags proton-pass

yubikey-dakota: _ensure-collections
    {{ ap }} site-dakota.yml --tags yubikey

users-dakota: _ensure-collections
    {{ ap }} site-dakota.yml --tags users

printer-dakota: _ensure-collections
    {{ ap }} site-dakota.yml --tags printer

neovim-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --tags neovim

# Standalone, self-contained here: no submodule needed, and not imported
# by site-dakota.yml.
# libfprint (goodix538d) no Dakota — build + install em /usr/local.
libfprint-dakota: _ensure-collections
    {{ ap }} playbooks/dakota/libfprint.yml

capslock-dakota: _ensure-collections
    {{ ap }} site-dakota.yml --tags capslock

keepassxc-yubikey-lock-dakota: _ensure-collections
    {{ ap }} site-dakota.yml --tags keepassxc-yubikey-lock

keepassxc-autostart-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --tags keepassxc-autostart

keepassxc-browser-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --tags keepassxc-browser

bash-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --tags bash

# systemd-boot flicker-free (loader.conf na ESP).
systemd-boot: _ensure-collections
    {{ ap }} site.yml --tags systemd-boot

systemd-boot-dakota: _ensure-collections
    {{ ap }} site-dakota.yml --tags systemd-boot

# No root needed (writes ~/.config/environment.d only).
ssh-askpass: _ensure-collections
    ansible-playbook site.yml --tags ssh-askpass

ssh-askpass-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --tags ssh-askpass
