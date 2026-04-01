#!/usr/bin/env bash
# post-install-fedora.sh
#gstreamer1-plugins-base gstreamer1-plugins-good
#gstreamer1-plugins-bad-freeworld

readonly VER=0.5
set -euo pipefail

# ─── Variables globales ────────────────────────────────────────────────────────
DOTFILES_REPO="https://codeberg.org/jotenakis/dotfiles"
DOTFILES_DIR="${HOME}/dotfiles"
DNF_PACKAGES=(
    zsh wget2 unzip fastfetch util-linux-script sudo-rs foot ghostty kitty eza fzf neovim bat bat-extras grc axel rclone procs
    wl-clipboard glow expect sqlite btop atop glances nvtop gping iftop gdu duf speedtest-cli kate shfmt ShellCheck inxi
    nodejs-bash-language-server golang make mpv vlc dragon libdvdcss foliate imv plasma-login-manager nm-connection-editor
    thunderbird vesktop telegram-desktop qbittorrent brave-browser helium-browser-bin qemu virt-manager virt-viewer
    gum stress-ng libreoffice-langpack-fr nss-tools ldns-utils profile-sync-daemon htop
)
DNF_REMOVE=(
    zram-generator-defaults PackageKit-glib PackageKit google-noto-sans-mono-cjk-vf-fonts akonadi-server kdeconnectd
    libreswan plasma-drkonqi ibus imsettings imsettings-libs maliit-keyboard abrt plasma-discover
)
FONTS=( jetbrainsmono-nerd-fonts iosevka-nerd-fonts )
declare -A CARGO_PACKAGES=(
    [bandwhich]="bandwhich"
    [bat]="bat"
    [bottom]="bottom"
    [cargo-update]="cargo-update"
    [diskus]="diskus"
    [fd-find]="fd-find"
    [hyperfine]="hyperfine"
    [netscanner]="netscanner"
    [parallel-disk-usage]="parallel-disk-usage"
    [resvg]="resvg"
    [ripgrep]="ripgrep"
    [sd]="sd"
    [sheldon]="sheldon"
    [tealdeer]="tealdeer"
    [yazi-build]="yazi-fm"
    [zoxide]="zoxide"
    [zsh-patina]="zsh-patina"
)
declare -A GIT_TOOLS=(
    [fedupdate]="https://codeberg.org/jotenakis/fedupdate/raw/branch/main/fedupdate"
    [backupsystem]="https://codeberg.org/jotenakis/backupsystem/raw/branch/main/backupsystem"
)

# ─── MAIN ──────────────────────────────────────────────────────────────────────
MAIN() {
    INIT
    BANNER
    RUN "Mise à jour du système" sudo dnf upgrade --refresh -y
    CHECK_SHELL
    REMOVE_RPM_PACKAGES
    ADD_REPOS
    INSTALL_RPM_PACKAGES
    INSTALL_FONTS
    INSTALL_CODECS
    INSTALL_RUSTUP
    INSTALL_CARGO_PACKAGES
    INSTALL_GIT_TOOLS
    SET_DEFAULT_SHELL
    SETUP_DOTFILES

    printf "\n%b%b  ✓ Terminé — reboot fortement recommandé.%b\n" "${C_GREEN}" "${C_BOLD}" "${C_RESET}"
    printf "%b  Log complet : %s%b\n\n" "${C_MAGENTA}" "${LOG_FILE}" "${C_RESET}"
}


#################################################################################################################################
#################################################################################################################################
#################################################################################################################################


# ─── Init ─────────────────────────────────────────────────────────────
INIT() {
    LOG_DIR="${HOME}/.local/log"
    LOG_FILE="${LOG_DIR}/post-install-fedora-$(date +%Y%m%d-%H%M%S).log"
    INSTALL_DIR="${HOME}/.local/bin"
    # RUST
    export RUSTUP_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/rustup"
    export CARGO_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/cargo"
    # GO
    export GOPATH="${XDG_DATA_HOME:-${HOME}/.local/share}/go"
    export GOBIN="${XDG_BIN_HOME:-${HOME}/.local/bin}"

    mkdir -p "${LOG_DIR}" "${INSTALL_DIR}" "${RUSTUP_HOME}" "${CARGO_HOME}" "${GOPATH}" "${GOBIN}"

    # PATH
    export PATH="${GOBIN}:${CARGO_HOME}/bin:${INSTALL_DIR}:${PATH}"

    SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    C_RESET='' C_RED='' C_GREEN='' C_YELLOW='' C_MAGENTA='' C_CYAN='' C_BOLD=''

    if [[ -t 1 ]]; then
        C_RESET='\e[0m'
        C_BOLD='\e[1m'
        C_RED='\e[1;31m'
        C_GREEN='\e[1;32m'
        C_YELLOW='\e[1;33m'
        C_MAGENTA='\e[1;35m'
        C_CYAN='\e[1;36m'
    fi
    sudo ls > /dev/null 2>&1 # init pass sudo
}
# ─── Helpers affichage ─────────────────────────────────────────────────────────
BANNER() {
    printf "%b%b\n  ╔════════════════════════════════════╗\n  ║      Post-install Fedora (${VER})     ║\n  ╚════════════════════════════════════╝%b\n  Log : %s\n\n" "${C_CYAN}" "${C_BOLD}" "${C_MAGENTA}" "${LOG_FILE}"
    echo -ne "${C_RESET}"
}

SECTION() { printf "\n%b%b━━━ %s ━━━%b\n" "${C_CYAN}" "${C_BOLD}" "$*" "${C_RESET}" | tee -a "${LOG_FILE}"; }
OK()      { printf " %b✓%b %s\n" "${C_GREEN}"  "${C_RESET}" "$*" | tee -a "${LOG_FILE}"; }
ERR()     { printf " %b✗%b %s\n" "${C_RED}"    "${C_RESET}" "$*" | tee -a "${LOG_FILE}" >&2; }
INFO()    { printf " %b→%b %s\n" "${C_YELLOW}"   "${C_RESET}" "$*" | tee -a "${LOG_FILE}"; }
DIE()     { ERR "$*"; exit 1; }

_SPIN() {
    local pid="$1" msg="$2" i=0
    while kill -0 "${pid}" 2>/dev/null; do
        printf "\r %b%s%b %s" "${C_GREEN}" "${SPIN_FRAMES[$((i % 10))]}" "${C_RESET}" "${msg}"
        sleep 0.05
        (( i++ )) || true
    done
    printf '\r\033[2K'
}

RUN() {
    local msg="$1"; shift
    "$@" >> "${LOG_FILE}" 2>&1 &
    local pid=$!
    _SPIN "${pid}" "${msg}"
    if wait "${pid}"; then
        OK "${msg}"
    else
        ERR "${msg}"
        DIE "Échec — détails : ${LOG_FILE}"
    fi
}

trap 'ERR "Interruption ligne ${LINENO}"; DIE "Log : ${LOG_FILE}"' ERR

# ─── 0. Vérification shell ─────────────────────────────────────────────────────
CHECK_SHELL() {
    SECTION "Vérification environnement"

    [[ -n "${BASH_VERSION:-}" ]]       || DIE "Ce script requiert bash."
    [[ "${BASH_VERSINFO[0]}" -ge 5 ]]  || DIE "Bash >= 5 requis (actuel : ${BASH_VERSION})."
    [[ "${EUID}" -ne 0 ]]              || DIE "Ne pas lancer en root. Le script gère sudo lui-même."
    [[ -f /etc/fedora-release ]]       || DIE "Fedora uniquement."

    sudo ls > /dev/null 2>&1
    RUN "Dépendances initiales" sudo dnf install -y curl git stow pciutils dnf-plugins-core

    local fedora_rel
    fedora_rel=$(cat /etc/fedora-release)
    OK "Environnement valide — ${fedora_rel}"
}

# ─── 1. Suppression paquets indésirables ───────────────────────────────────────
REMOVE_RPM_PACKAGES() {
    SECTION "Suppression paquets indésirables"

    local pkg
    for pkg in "${DNF_REMOVE[@]}"; do
        if rpm -q "${pkg}" &>/dev/null; then
            RUN "Suppression ${pkg}" sudo dnf remove -y "${pkg}"
        else
            OK "${pkg} absent — ignoré."
        fi
    done

    # systemd-networkd : supprimé seulement si NetworkManager est actif
    if systemctl is-active --quiet NetworkManager; then
        if rpm -q systemd-networkd &>/dev/null; then
            RUN "Suppression systemd-networkd (NetworkManager actif)" sudo dnf remove -y systemd-networkd
        else
            OK "systemd-networkd absent — ignoré."
        fi
    else
        INFO "NetworkManager inactif — systemd-networkd conservé."
    fi
}

# ─── 2. Dépôts ─────────────────────────────────────────────────────────────────
ADD_REPOS() {
    SECTION "Dépôts"

    local fedora_ver
    fedora_ver=$(rpm -E '%fedora')

    if ! rpm -q rpmfusion-free-release &>/dev/null; then
        RUN "RPM Fusion free (f${fedora_ver})" sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"${fedora_ver}".noarch.rpm
        RUN "RPM Fusion free tainted (f${fedora_ver})" sudo dnf install -y rpmfusion-free-release-tainted
    else
        OK "RPM Fusion free déjà présent."
    fi

    if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
        RUN "RPM Fusion nonfree (f${fedora_ver})" sudo dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"${fedora_ver}".noarch.rpm
        RUN "RPM Fusion nonfree tainted (f${fedora_ver})" sudo dnf install rpmfusion-nonfree-release-tainted
    else
        OK "RPM Fusion nonfree déjà présent."
    fi

    if rpm -q rpmfusion-free-appstream-data &>/dev/null; then
        RUN "suppression métadonnées appstream free" sudo dnf remove -y rpmfusion-free-appstream-data
    fi
    if rpm -q rpmfusion-nonfree-appstream-data &>/dev/null; then
        RUN "suppression métadonnées appstream nonfree" sudo dnf remove -y rpmfusion-nonfree-appstream-data
    fi

    if ! rpm -q terra-release &>/dev/null; then
        # shellcheck disable=SC2016
        RUN "Terra (f${fedora_ver})" sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
    else
        OK "Terra déjà présent."
    fi

    if ! dnf copr list 2>/dev/null | grep -q "bigmenpixel/profile-sync-daemon"; then
        RUN "COPR profile-sync-daemon" sudo dnf copr enable -y bigmenpixel/profile-sync-daemon
    else
        OK "COPR profile-sync-daemon déjà présent."
    fi

    if ! dnf repolist 2>/dev/null | grep -q "brave-browser"; then
        RUN "Brave Browser Repo" sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
    else
        OK "Brave Browser Repo est déjà présent."
    fi

    RUN "Rafraîchissement des métadonnées" sudo dnf makecache
}

# ─── 3. Nerd Fonts ───────────────────────────────────────────────────────────
INSTALL_FONTS() {
    SECTION "Nerd Fonts"

    local font
    for font in "${FONTS[@]}"; do
        if ! rpm -q "${font}" &>/dev/null; then
            RUN "Installation ${font}" sudo dnf install -y "${font}"
        else
            OK "${font} déjà présente."
        fi
    done
}

# ─── 4. Codecs & Mesa ──────────────────────────────────────────────────────────
INSTALL_CODECS() {
    SECTION "Codecs multimédia"

    if ! rpm -q ffmpeg &>/dev/null; then
        RUN "Swap ffmpeg-free → ffmpeg" sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    else
        OK "ffmpeg (RPM Fusion) déjà présent."
    fi

    #RUN "Groupe multimedia" sudo dnf groupupdate -y multimedia --setopt='install_weak_deps=False' --exclude=PackageKit-gstreamer-plugin
    #RUN "Groupe sound-and-video" sudo dnf groupupdate -y sound-and-video

    local gpu_vendor
    gpu_vendor=$(lspci | grep -iE 'VGA|3D' | head -1 | tr '[:upper:]' '[:lower:]')
    INFO "GPU détecté : ${gpu_vendor}"

    if echo "${gpu_vendor}" | grep -q "amd\|radeon\|advanced micro"; then
        if ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
            RUN "Swap mesa-va-drivers → freeworld (AMD)" sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
        else
            OK "Mesa freeworld déjà présent."
        fi
    elif echo "${gpu_vendor}" | grep -q "intel"; then
        if ! rpm -q intel-media-driver &>/dev/null; then
            RUN "intel-media-driver" sudo dnf install -y intel-media-driver
        else
            OK "intel-media-driver déjà présent."
        fi
    else
        INFO "GPU non AMD/Intel — Mesa swap ignoré."
    fi
}

# ─── 5. Paquets DNF ────────────────────────────────────────────────────────────
INSTALL_RPM_PACKAGES() {
    SECTION "Paquets DNF"

    local pkg
    local -a missing_packages=()

    for pkg in "${DNF_PACKAGES[@]}"; do
        if ! rpm -q "${pkg}" &>/dev/null; then
            missing_packages+=("${pkg}")
        else
            OK "${pkg} est déjà installé — ignoré."
        fi
    done

    if ((${#missing_packages[@]})); then
        RUN "Installation paquets DNF manquants" sudo dnf install -y "${missing_packages[@]}"
    else
        INFO "Tous les paquets DNF sont déjà installés."
    fi
}

# ─── 6. Rustup ─────────────────────────────────────────────────────────────────
INSTALL_RUSTUP() {
    SECTION "Rustup"

    if command -v rustup &>/dev/null; then
        RUN "Mise à jour rustup stable" rustup update stable
    else
        RUN "Installation rustup" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain stable'
    fi
}

# ─── 7. Paquets Cargo ──────────────────────────────────────────────────────────
INSTALL_CARGO_PACKAGES() {
    SECTION "Paquets Cargo"

    # Tableau de mapping : [nom_du_paquet]="binaire1 binaire2 ..."
    local -A BIN_MAPPING=(
        ["yazi-build"]="yazi ya"
        ["tealdeer"]="tldr"
        ["parallel-disk-usage"]="pdu"
        ["fd-find"]="fd"
        ["bottom"]="btm"
        ["ripgrep"]="rg"
        ["cargo-update"]="cargo-install-update cargo-install-update-config"
    )

    local cmd check
    for cmd in "${!CARGO_PACKAGES[@]}"; do
        check="${CARGO_PACKAGES[${cmd}]}"

        # 1. Installation du paquet via Cargo
        if cargo install --list | grep -q "^${check} "; then
            OK "${check} déjà installé."
        elif [[ "${cmd}" == "yazi-build" ]]; then
            RUN "Installation yazi (yazi-build)" cargo install --force "${cmd}"
        else
            RUN "Installation ${cmd}" cargo install "${cmd}"
        fi

        # 2. Création des liens symboliques dans /usr/local/bin
        local bins_to_link
        if [[ -n "${BIN_MAPPING[${cmd}]:-}" ]]; then
            bins_to_link="${BIN_MAPPING[${cmd}]}"
        else
            bins_to_link="${cmd}"
        fi

        local bin_name src_bin dest_link current_target
        for bin_name in ${bins_to_link}; do
            src_bin="${CARGO_HOME}/bin/${bin_name}"
            dest_link="/usr/local/bin/${bin_name}"

            if [[ -x "${src_bin}" ]]; then
                # Résolution de SC2312 : On gère readlink séparément
                current_target=""
                if [[ -L "${dest_link}" ]]; then
                    current_target=$(readlink -f "${dest_link}" || true)
                fi

                if [[ "${current_target}" != "${src_bin}" ]]; then
                    RUN "Lien symbolique : ${bin_name} -> /usr/local/bin" sudo ln -sf "${src_bin}" "${dest_link}"
                else
                    OK "Lien symbolique ${bin_name} déjà présent."
                fi
            else
                ERR "Binaire introuvable : ${src_bin}"
            fi
        done
    done

    # 3. Ajustement des permissions pour l'accès global
    RUN "Permissions : accès global aux binaires Cargo" \
        chmod a+x "${HOME}" \
        "${HOME}/.local" \
        "${HOME}/.local/share" \
        "${CARGO_HOME}" \
        "${CARGO_HOME}/bin"
}

# ─── 8. Outils git  ─────────────────────────────────────────────────────────────
INSTALL_GIT_TOOLS() {
    SECTION "Outils git"

    local tool url

    for tool in "${!GIT_TOOLS[@]}"; do
        url="${GIT_TOOLS[${tool}]}"
        RUN "Installation ${tool}" \
            bash -c "curl -fsSL '${url}' -o '${INSTALL_DIR}/${tool}' && chmod +x '${INSTALL_DIR}/${tool}'"
        OK "${tool} → ${INSTALL_DIR}/${tool}"
    done
}

# ─── 9. Shell par défaut ───────────────────────────────────────────────────────
SET_DEFAULT_SHELL() {
    SECTION "Shell par défaut → zsh"

    local zsh_bin
    zsh_bin=$(command -v zsh)

    if ! grep -qxF "${zsh_bin}" /etc/shells; then
        echo "${zsh_bin}" | sudo tee -a /etc/shells > /dev/null
        OK "${zsh_bin} ajouté à /etc/shells."
    fi

    local user uid current_shell
    while IFS=: read -r user _ uid _ _ _ _; do
        if [[ ( "${uid}" -ge 1000 && "${uid}" -lt 2000 ) || "${uid}" -eq 0 ]]; then # root et users normaux
            current_shell=$(getent passwd "${user}" | cut -d: -f7)
            if [[ "${current_shell}" != "${zsh_bin}" ]]; then
                RUN "chsh ${user} → zsh" sudo chsh -s "${zsh_bin}" "${user}"
            else
                OK "${user} utilise déjà zsh."
            fi
        fi
    done < /etc/passwd
}

# ─── 10. Dotfiles ──────────────────────────────────────────────────────────────
SETUP_DOTFILES() {
    SECTION "Dotfiles (GNU Stow)"

    if [[ ! -d "${DOTFILES_DIR}/.git" ]]; then
        RUN "Clone ${DOTFILES_REPO}" git clone "${DOTFILES_REPO}" "${DOTFILES_DIR}"
    else
        RUN "Mise à jour dotfiles" git -C "${DOTFILES_DIR}" pull --ff-only
    fi

    local pkg name
    for pkg in "${DOTFILES_DIR}"/*/; do
        name=$(basename "${pkg}")
        RUN "stow : ${name}" stow --dir="${DOTFILES_DIR}" --target="${HOME}" --restow "${name}"
    done
}


# ─── 11. Configuration Système & Optimisations ────────────────────────────────
SETUP_SYSTEM() {
    SECTION "Configuration Système (Réseau, Swap, GRUB, Sysctl, Fstab, Brave, Chrony)"

    local tmp_dir
    tmp_dir=$(mktemp -d)

    # --- 1. NetworkManager & systemd-resolved ---
    cat << 'EOF' > "${tmp_dir}/99-global-dns.conf"
[main]
dns=systemd-resolved
EOF

    cat << 'EOF' > "${tmp_dir}/dns_servers.conf"
[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net
FallbackDNS=1.1.1.1#one.one.one.one
Domains=~.
DNSOverTLS=yes
DNSSEC=yes
EOF

    cat << 'EOF' > "${tmp_dir}/10-disable-llmnr.conf"
[Resolve]
LLMNR=no
EOF

    RUN "Déploiement configs DNS" sudo bash -c "
        mkdir -p /etc/NetworkManager/conf.d /etc/systemd/resolved.conf.d &&
        install -m 644 -o root -g root '${tmp_dir}/99-global-dns.conf' /etc/NetworkManager/conf.d/ &&
        install -m 644 -o root -g root '${tmp_dir}/dns_servers.conf' /etc/systemd/resolved.conf.d/ &&
        install -m 644 -o root -g root '${tmp_dir}/10-disable-llmnr.conf' /etc/systemd/resolved.conf.d/ &&
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    "
    RUN "Redémarrage NetworkManager & systemd-resolved" sudo systemctl restart systemd-resolved NetworkManager


    # --- 2. Swapfile BTRFS / Ext4 / XFS ---
    local target_size=$((20 * 1024 * 1024 * 1024)) # 20 GiB en octets
    local recreate_swap=false

    if [[ -f "/var/swap/swapfile" ]]; then
        local current_size
        current_size=$(sudo stat -c %s /var/swap/swapfile 2>/dev/null || echo 0)

        if [[ "${current_size}" -ne "${target_size}" ]]; then
            INFO "Swapfile existant mais taille différente (${current_size} octets). Recréation..."
            sudo swapoff /var/swap/swapfile 2>/dev/null || true
            sudo rm -f /var/swap/swapfile
            recreate_swap=true
        else
            OK "Swapfile existant et à la bonne taille (20GiB)."
        fi
    else
        recreate_swap=true
    fi

    if [[ "${recreate_swap}" == "true" ]]; then
        local fs_type
        fs_type=$(stat -f -c %T /var)

        if [[ "${fs_type}" == "btrfs" ]]; then
            if ! sudo btrfs subvolume show /var/swap >/dev/null 2>&1; then
                RUN "Création du sous-volume BTRFS /var/swap" sudo btrfs subvolume create /var/swap
            else
                OK "Sous-volume BTRFS /var/swap déjà existant."
            fi
            RUN "Création du swapfile BTRFS (20G)" sudo btrfs filesystem mkswapfile --size 20g /var/swap/swapfile
        else
            RUN "Création du dossier /var/swap" sudo mkdir -p /var/swap
            RUN "Allocation du swapfile classique (20G)" sudo fallocate -l 20G /var/swap/swapfile
            RUN "Droits sur le swapfile" sudo chmod 0600 /var/swap/swapfile
            RUN "Formatage du swapfile" sudo mkswap /var/swap/swapfile
        fi
    fi

    if ! swapon --show | grep -q "/var/swap/swapfile"; then
        RUN "Activation du swap" sudo swapon /var/swap/swapfile
    else
        OK "Swap déjà actif en mémoire."
    fi

    if ! grep -q "/var/swap/swapfile" /etc/fstab; then
        RUN "Ajout du swap à /etc/fstab" sudo bash -c 'echo "/var/swap/swapfile none swap defaults 0 0" >> /etc/fstab'
    else
        OK "Swap déjà présent dans /etc/fstab."
    fi


    # --- 3. Configuration GRUB ---
    local luks_param="" target_cmdline="" current_cmdline="" current_default=""

    if grep -q 'rd\.luks\.uuid=' /etc/default/grub; then
        luks_param=$(grep -oP 'rd\.luks\.uuid=\S+' /etc/default/grub | head -n 1)
    fi

    target_cmdline="${luks_param} rhgb loglevel=5 rd.systemd.show_status=1 ipv6.disable=1 zswap.enabled=1 zswap.compressor=lz4 vt.default_red=30,243,166,249,137,245,148,186,88,243,166,249,137,245,148,166 vt.default_grn=30,139,227,226,180,194,226,194,91,139,227,226,180,194,226,173 vt.default_blu=46,168,161,175,250,231,213,222,112,168,161,175,250,231,213,200"
    target_cmdline=$(echo "${target_cmdline}" | xargs)

    current_cmdline=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub | cut -d'"' -f2 || echo "")
    current_default=$(grep '^GRUB_DEFAULT=' /etc/default/grub | cut -d'=' -f2 || echo "")

    if [[ "${current_cmdline}" != "${target_cmdline}" ]] || [[ "${current_default}" != "menu" ]]; then
        RUN "Mise à jour de /etc/default/grub" sudo sed -i -e 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=menu/' -e "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${target_cmdline}\"|" /etc/default/grub
        RUN "Regénération de GRUB" sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        OK "Configuration GRUB déjà à jour."
    fi


    # --- 4. Optimisations Kernel (Sysctl) ---
    cat << 'EOF' > "${tmp_dir}/99-swap.conf"
vm.swappiness = 10
EOF

    cat << 'EOF' > "${tmp_dir}/99-olivier.conf"
# optimisations
vm.vfs_cache_pressure = 100
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.dirty_background_ratio = 2
vm.dirty_ratio = 3
vm.dirty_bytes = 335544320
vm.dirty_background_bytes = 167772160
vm.dirty_writeback_centisecs = 1500
net.core.somaxconn = 8192
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
kernel.task_delayacct = 1
kernel.soft_watchdog = 0
kernel.watchdog = 0
kernel.dmesg_restrict = 0
vm.laptop_mode=5
fs.suid_dumpable=0
kernel.core_pattern=|/bin/false

# hardening
dev.tty.ldisc_autoload = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
kernel.core_uses_pid = 1
kernel.ctrl-alt-del = 0
kernel.perf_event_paranoid = 4
kernel.randomize_va_space = 2
kernel.sysrq = 16
kernel.unprivileged_bpf_disabled = 1
kernel.yama.ptrace_scope = 3
net.core.bpf_jit_harden = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.bootp_relay = 0
net.ipv4.conf.all.forwarding = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.lo.log_martians = 1
net.ipv4.conf.default.forwarding = 0
net.ipv4.conf.all.proxy_arp = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.ip_forward = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 1
#net.ipv4.conf.wlp2s0.log_martians = 1
net.ipv4.conf.default.rp_filter = 1
EOF

    RUN "Déploiement config sysctl" sudo bash -c "
        mkdir -p /etc/sysctl.d &&
        install -m 644 -o root -g root '${tmp_dir}/99-swap.conf' /etc/sysctl.d/ &&
        install -m 644 -o root -g root '${tmp_dir}/99-olivier.conf' /etc/sysctl.d/
    "
    RUN "Application des paramètres sysctl" sudo sysctl --system


    # --- 5. Optimisations Fstab (noatime, lazytime) ---
    local fstab_changed=false
    true > "${tmp_dir}/fstab.new"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*# ]] || [[ -z "${line}" ]]; then
            echo "${line}" >> "${tmp_dir}/fstab.new"
            continue
        fi

        local dev mp fs opts dump pass
        read -r dev mp fs opts dump pass <<< "${line}"

        if [[ "${fs}" =~ ^(btrfs|ext4|xfs)$ ]]; then
            local orig_opts="${opts}"

            if [[ ! ",${opts}," =~ ,noatime, ]]; then
                opts="${opts},noatime"
            fi
            if [[ ! ",${opts}," =~ ,lazytime, ]]; then
                opts="${opts},lazytime"
            fi

            if [[ "${orig_opts}" != "${opts}" ]]; then
                fstab_changed=true
                printf "%-40s %-24s %-8s %-32s %-2s %s\n" "${dev}" "${mp}" "${fs}" "${opts}" "${dump}" "${pass}" >> "${tmp_dir}/fstab.new"
                continue
            fi
        fi

        echo "${line}" >> "${tmp_dir}/fstab.new"
    done < /etc/fstab

    if [[ "${fstab_changed}" == "true" ]]; then
        if [[ ! -f /etc/fstab.origin ]]; then
            RUN "Sauvegarde originale de /etc/fstab" sudo cp -a /etc/fstab /etc/fstab.origin
        fi
        RUN "Sauvegarde de travail dans /etc/fstab.bak" sudo cp -a /etc/fstab /etc/fstab.bak
        RUN "Application de noatime/lazytime dans /etc/fstab" sudo cp -a "${tmp_dir}/fstab.new" /etc/fstab
        RUN "Rechargement du démon systemd" sudo systemctl daemon-reload
    else
        OK "Les options noatime/lazytime sont déjà présentes dans /etc/fstab."
    fi


    # --- 6. Configuration Brave Browser (Policies) ---
    cat << 'EOF' > "${tmp_dir}/brave_debullshitinator-policies.json"
{
    "BraveRewardsDisabled": true,
    "BraveWalletDisabled": true,
    "BraveVPNDisabled": 1,
    "BraveAIChatEnabled": false,
    "TorDisabled": true,
    "PasswordManagerEnabled": false,
    "DnsOverHttpsMode": "automatic"
}
EOF

    if [[ -f /etc/brave/policies/managed/brave_debullshitinator-policies.json ]] && cmp -s "${tmp_dir}/brave_debullshitinator-policies.json" /etc/brave/policies/managed/brave_debullshitinator-policies.json; then
        OK "Policies Brave déjà à jour."
    else
        RUN "Déploiement des policies Brave" sudo bash -c "
            mkdir -p /etc/brave/policies/managed &&
            install -m 644 -o root -g root '${tmp_dir}/brave_debullshitinator-policies.json' /etc/brave/policies/managed/
        "
    fi


    # --- 7. Configuration Chrony (IPv4 only) ---
    cat << 'EOF' > "${tmp_dir}/chronyd"
# Command-line options for chronyd
OPTIONS="-F 2 -4"
EOF

    if [[ -f /etc/sysconfig/chronyd ]] && cmp -s "${tmp_dir}/chronyd" /etc/sysconfig/chronyd; then
        OK "Configuration chronyd déjà à jour (-F 2 -4)."
    else
        RUN "Application de la configuration chronyd" sudo install -m 644 -o root -g root "${tmp_dir}/chronyd" /etc/sysconfig/chronyd
        RUN "Redémarrage du service chronyd" sudo systemctl try-restart chronyd
    fi

     # --- 8. Groupe libvirt ---
    local main_user
    main_user=$(getent passwd 1000 | cut -d: -f1 || true)

    if [[ -n "${main_user}" ]]; then
        if getent group libvirt >/dev/null 2>&1; then
            if id -nG "${main_user}" | grep -qw "libvirt"; then
                OK "L'utilisateur ${main_user} est déjà dans le groupe libvirt."
            else
                RUN "Ajout de l'utilisateur ${main_user} au groupe libvirt" sudo usermod -aG libvirt "${main_user}"
            fi
        else
            INFO "Le groupe libvirt n'existe pas. Ajout ignoré."
        fi
    else
        INFO "Aucun utilisateur avec l'UID 1000 trouvé."
    fi

    # Nettoyage
    rm -rf "${tmp_dir}"
}

#─── Point d'entrée ────────────────────────────────────────────────────────────
MAIN "$@"
