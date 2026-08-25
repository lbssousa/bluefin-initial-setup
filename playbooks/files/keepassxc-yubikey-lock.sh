#!/usr/bin/env bash
# Tranca todas as bases do KeePassXC quando a YubiKey é removida (evento
# udev "remove"), via D-Bus. Chamado pela regra
# 70-keepassxc-yubikey-lock.rules com o nome do usuário alvo como $1.
# Portado de lbssousa/nix-config
# (modules/system/security/keepassxc-yubikey-lock.nix) — mesmo
# mecanismo, adaptado para um único usuário (o que roda este Ansible),
# não a lista de usuários configurável do módulo NixOS original.
#
# Sai silenciosamente (exit 0) se: o usuário não tiver sessão D-Bus
# ativa, ou o KeePassXC não estiver rodando nessa sessão.
set -euo pipefail

username="${1:?uso: $(basename "$0") <username>}"
uid="$(id -u "$username")"
runtime_dir="/run/user/${uid}"
bus_address="unix:path=${runtime_dir}/bus"

[[ -S "${runtime_dir}/bus" ]] || exit 0

run_as_user() {
    runuser -u "$username" -- env \
        XDG_RUNTIME_DIR="$runtime_dir" \
        DBUS_SESSION_BUS_ADDRESS="$bus_address" \
        "$@"
}

has_owner="$(run_as_user gdbus call --session \
    --dest org.freedesktop.DBus \
    --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.NameHasOwner \
    org.keepassxc.KeePassXC.MainWindow)"
[[ "$has_owner" == *"(true,"* ]] || exit 0

run_as_user gdbus call --session \
    --dest org.keepassxc.KeePassXC.MainWindow \
    --object-path /keepassxc \
    --method org.keepassxc.KeePassXC.MainWindow.lockAllDatabases >/dev/null
