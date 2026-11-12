# scripts perso

Collection de scripts Bash personnels (GPLv3), principalement orientés diagnostic,
monitoring et administration Linux. Aucun installateur commun : chaque script est
autonome et s'exécute directement.

> **Lire avant exécution.** Plusieurs scripts touchent au système, au matériel, au
> réseau ou à des données personnelles. Ils sont fournis tels quels, sans garantie.
> Vérifiez le contenu et adaptez les chemins avant de les lancer.

## Prérequis

Les dépendances varient d'un script à l'autre. Les principales sont :

- `bash`, `coreutils`, `awk`, `grep`, `sed`
- `procps-ng` (`ps`), `util-linux`
- `curl`, `jq`, `git`
- `gum` (interface interactive)
- `sensors` (`lm_sensors`), `upower`
- `chkrootkit`, `rkhunter`, `s-nail`/`mailx` (scan rootkit)
- `openssl` (wanip, si géolocalisation activée)
- `gh` authentifié (`gh-pr-watch`)
- `stress-ng`, `fio`, `iperf3` (`omastress`, `nvme-sched-bench3.sh`)
- `power-profiles-daemon` (`powerprofilesctl`, `cpufreq-boost-test.sh`)
- `ufw` et accès en lecture au journal noyau (`ufw-watch`, groupe `wheel`)

Sous Arch : `pacman -S --needed curl jq git gum lm_sensors upower chkrootkit rkhunter s-nail stress-ng fio iperf3 power-profiles-daemon ufw github-cli`.
Certains paquets peuvent être dans AUR selon les dépôts activés.

## Scripts

| Script | Rôle | Remarques |
| --- | --- | --- |
| `bpf-check.sh` | Détection de processus suspects de type BPFDoor. | À lancer en root. Lecture seule. |
| `cachyos.sh` | Définit le dernier noyau CachyOS par défaut via `grubby`. | **Fedora/CachyOS uniquement** (GRUB + `grubby`). |
| `cachyoschiffrement.sh` | Hook de signature Secure Boot d'un noyau CachyOS. | **Fedora/CachyOS uniquement** (MOK, `pesign`, NSS). |
| `check-my-git.sh` | État de synchronisation des dépôts Git de `~/Projects`. | Accès réseau (`git fetch`). |
| `color.sh` | Palette des 256 couleurs du terminal. | Sans effet de bord. |
| `cpu` | Moniteur d'usage CPU par cœur. | Terminal interactif. |
| `cpufreq-boost-test.sh` | Mesure si le boost cpufreq d'`apple-cpufreq` suit les profils power-profiles-daemon. | Root. Change governors et profil, restaurés par `trap`. |
| `crypto.sh` | Tableau des principales cryptomonnaies (CoinGecko). | Réseau + `gum`, `jq`, `awk`. |
| `dnstest.sh` | Test de fuite DNS via `bash.ws`. | Réseau. |
| `freeim` | Affichage détaillé RAM/swap (zram, zswap). | Sans dépendance externe. |
| `gh-pr-watch` | Notifie les nouvelles réponses sur vos PR/issues GitHub, mentions et citations. | `gh` authentifié + `jq`. État dans `~/.local/state/gh-pr-watch`. `--dry-run`. |
| `kernel_clean.sh` | Suppression interactive d'anciens noyaux de `/boot`. | Root. Arch (`pacman`) et Fedora (`dnf`). Le noyau en cours est détecté par contenu. |
| `nvme-sched-bench3.sh` | Bench `fio` des schedulers NVMe (kyber, mq-deadline, none), ordre contrôlé. | Root. Vide `/var/tmp/nvme-sched-bench3` à chaque passage. |
| `omastress` | Session de stress CPU / disque / réseau / RAM, interface `gum`, arrêt thermique. | `stress-ng`, `fio`, `iperf3`. `--demo` pour un essai sans charge. |
| `psim` | Mise en forme/monitoring des processus. | `ps` + `awk`, lecture seule. |
| `rootkit_scan.sh` | Scan `chkrootkit` + `rkhunter` et alerte. | Root. E-mail optionnel via `ROOTKIT_ALERT_EMAIL`. |
| `sensors-HP-645-G9.sh` | Températures CPU/GPU/NVMe/Wi-Fi d'un HP EliteBook 645 G9. | Sondes matérielles codées en dur. |
| `shmem-parts` | Répartit la mémoire « Shmem » de `/proc/meminfo` par origine (GPU `shmemfs`, tmpfs, mlocks). | Lecture seule. `-n` masque le détail par processus. |
| `timers-journal.sh` | Timers `systemd --user` et journal du boot courant de chaque service. | Lecture seule. `-a`, `-n LIGNES`, `-t`, `-h`. |
| `ufw-watch` | Notifie les paquets bloqués par UFW venant d'Internet (hors LAN, link-local, multicast). | Suit `journalctl -kf` ; `--dry-run`, `--test`. |
| `update-bpc.sh` | Met à jour l'extension Bypass Paywalls Clean (dépôt tiers) dans le profil Helium. | Réseau + `git`. Écrase `~/.local/share/bpc`. |
| `wanip.sh` | IP WAN + géolocalisation. | Clé API via `WANIP_API_KEY` (voir ci-dessous). |

## Configuration sensible

### `wanip.sh`

La clé API n'est plus stockée dans le script. Fournissez-la par variable
d'environnement :

```bash
export WANIP_API_KEY='votre-cle'
```

ou dans un fichier local non versionné :

```bash
install -d -m 700 ~/.config/wanip
printf '%s\n' 'votre-cle' > ~/.config/wanip/apikey
chmod 600 ~/.config/wanip/apikey
```

Sans clé, le script affiche l'IP WAN mais désactive la géolocalisation.

### `rootkit_scan.sh`

L'adresse d'alerte n'est plus codée en dur :

```bash
export ROOTKIT_ALERT_EMAIL='vous@example.org'
```

Sans cette variable, le scan s'exécute et journalise les résultats, mais n'envoie
aucun e-mail. Les rapports restent dans `/var/log/rootkit_scanning/`.

## Sécurité

- Les scripts marqués **root** doivent être relus avant exécution.
- `kernel_clean.sh` supprime des fichiers de `/boot` : conservez toujours le noyau
  en cours d'exécution et un noyau de secours.
- `check-my-git.sh` effectue un `git fetch` sur chaque dépôt trouvé.
- Aucun secret ne doit être commité. Utilisez les variables d'environnement ou des
  fichiers locaux ignorés par Git.

## Licence

GPLv3.
