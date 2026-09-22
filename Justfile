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

# Initialize/update git submodules (e.g. the libfprint automation).
_ensure-submodules:
    git submodule update --init --recursive

# Run the initial setup playbook. Bitwarden and libfprint have tag
# "never" in site.yml, so they don't run here — only via `just bitwarden`
# / `just libfprint` (the latter also needs the submodule, see below).
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

libfprint: _ensure-collections _ensure-submodules
    {{ ap }} site.yml --tags libfprint

capslock: _ensure-collections
    {{ ap }} site.yml --tags capslock

keepassxc-yubikey-lock: _ensure-collections
    {{ ap }} site.yml --tags keepassxc-yubikey-lock

# No root needed (writes to ~/.var/app/<browser>/... only).
keepassxc-browser: _ensure-collections
    ansible-playbook site.yml --tags keepassxc-browser

# No root needed (~/.bashrc/~/.inputrc + a Homebrew-adjacent user build).
bash: _ensure-collections
    ansible-playbook site.yml --tags bash

# Bluefin Dakota — same automations via site-dakota.yml (no submodule
# needed there). YubiKey and libfprint use their own Dakota-specific
# playbooks under playbooks/dakota/ (no authselect/RPMs on Dakota);
# everything else is the exact same file used by the recipes above.
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

libfprint-dakota: _ensure-collections
    {{ ap }} site-dakota.yml --tags libfprint

capslock-dakota: _ensure-collections
    {{ ap }} site-dakota.yml --tags capslock

keepassxc-yubikey-lock-dakota: _ensure-collections
    {{ ap }} site-dakota.yml --tags keepassxc-yubikey-lock

keepassxc-browser-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --tags keepassxc-browser

bash-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --tags bash
