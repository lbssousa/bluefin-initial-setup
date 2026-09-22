set shell := ["bash", "-uc"]

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
    ansible-playbook site.yml --ask-become-pass

# Fedora Atomic (Bluefin/uBlue classic) — run a single automation by its site.yml tag.
bitwarden: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags bitwarden

homebrew: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags homebrew

zed: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags zed

yubikey: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags yubikey

users: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags users

printer: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags printer

neovim: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags neovim

libfprint: _ensure-collections _ensure-submodules
    ansible-playbook site.yml --ask-become-pass --tags libfprint

capslock: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags capslock

keepassxc-yubikey-lock: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags keepassxc-yubikey-lock

keepassxc-browser: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags keepassxc-browser

bash: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags bash

# Bluefin Dakota — same automations via site-dakota.yml (no submodule
# needed there). YubiKey and libfprint use their own Dakota-specific
# playbooks under playbooks/dakota/ (no authselect/RPMs on Dakota);
# everything else is the exact same file used by the recipes above.
#
# Run the setup playbook against a Bluefin Dakota host.
setup-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --ask-become-pass

bitwarden-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --ask-become-pass --tags bitwarden

# No "homebrew-dakota" recipe: on Dakota, VSCode/Zed installation is
# already handled by the image's own `ujust` recipes, so
# playbooks/homebrew.yml isn't imported by site-dakota.yml.

zed-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --ask-become-pass --tags zed

yubikey-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --ask-become-pass --tags yubikey

users-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --ask-become-pass --tags users

printer-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --ask-become-pass --tags printer

neovim-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --ask-become-pass --tags neovim

libfprint-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --ask-become-pass --tags libfprint

capslock-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --ask-become-pass --tags capslock

keepassxc-yubikey-lock-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --ask-become-pass --tags keepassxc-yubikey-lock

keepassxc-browser-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --ask-become-pass --tags keepassxc-browser

bash-dakota: _ensure-collections
    ansible-playbook site-dakota.yml --ask-become-pass --tags bash
