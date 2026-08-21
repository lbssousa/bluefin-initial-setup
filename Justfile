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

# Run the initial setup playbook.
setup: _ensure-collections
    ansible-playbook site.yml --ask-become-pass
