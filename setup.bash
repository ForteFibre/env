#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
AVAILABLE_PLAYBOOKS=$(find "$SCRIPT_DIR/playbooks" -maxdepth 1 -type f -name "*.yaml" -exec basename {} \; | sort)
# List of default playbook
DEFAULT_PLAYBOOKS="common.yaml"

echo -e "\e[36mInstalling dependencies...\e[m"

# Install sudo
if ! (command -v sudo >/dev/null 2>&1); then
    apt-get -y update
    apt-get -y install sudo
fi

# Install git
if ! (command -v git >/dev/null 2>&1); then
    sudo apt-get -y update
    sudo apt-get -y install git
fi

# Install whiptail
if ! (command -v whiptail >/dev/null 2>&1); then
    sudo apt-get -y update
    sudo apt-get -y install whiptail
fi

# Install pip for ansible
if ! (python3 -m pip --version >/dev/null 2>&1); then
    sudo apt-get -y update
    sudo apt-get -y install python3-pip python3-venv
fi

# Install pipx for ansible
if ! (python3 -m pipx --version >/dev/null 2>&1); then
    sudo apt-get -y update
    python3 -m pip install --user pipx
fi

# Install ansible
python3 -m pipx ensurepath
export PATH="${PIPX_BIN_DIR:=$HOME/.local/bin}:$PATH"
# pipx install --include-deps --force "ansible==6.*"

# Create map for default selected playbook
declare -A PLAYBOOK_MAP
for playbook in $AVAILABLE_PLAYBOOKS; do
    PLAYBOOK_MAP[$playbook]="0"
done
for playbook in $DEFAULT_PLAYBOOKS; do
    PLAYBOOK_MAP[$playbook]="1"
done

# Collect playbook names with whiptail
PLAYBOOKS=$(whiptail --title "Select Playbook" --checklist "Choose a playbook to run:" 15 60 6 \
    $(for playbook in $AVAILABLE_PLAYBOOKS; do echo "$playbook" "$playbook" "${PLAYBOOK_MAP[$playbook]}"; done) 3>&1 1>&2 2>&3)

echo -e "\e[36mRunning playbook: $PLAYBOOKS\e[m"

# Import env
ansible_args=("--ask-become-pass")

for env_name in $(sed -e "s/^\s*//" -e "/^#/d" -e "s/=.*//" <amd64.env); do
    ansible_args+=("--extra-vars" "${env_name}=${!env_name}")
done

for playbook in $PLAYBOOKS; do
    ansible_args+=("$SCRIPT_DIR/playbooks/$playbook")
done

# Run ansible
ansible-playbook -i "localhost," -c local "${ansible_args[@]}"

echo -e "\e[36mDone!\e[m"
