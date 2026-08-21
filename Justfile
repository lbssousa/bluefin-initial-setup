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

# Run the initial setup playbook.
setup: _ensure-collections _ensure-submodules
    ansible-playbook site.yml --ask-become-pass

# Same as setup, but skips the libfprint build (for machines without that reader).
setup-no-libfprint: _ensure-collections _ensure-submodules
    ansible-playbook site.yml --ask-become-pass --skip-tags libfprint
