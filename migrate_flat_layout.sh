#!/bin/bash

# =============================================================================
# ARCH LINUX MIGRATION SCRIPT - FLAT LAYOUT V2 (Expanded)
# =============================================================================
# Description: Migra il sistema corrente (Online) a Layout Flat Esteso.
#              Gestisce: Root, Home, Log, Pkg Cache, Snapshots.
#              Supporta installazioni esistenti (es. Archinstall).
# =============================================================================

# --- Configurazione ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Opzioni Mount: zstd:1 (veloce/SSD), discard=async (SSD Trim), noatime
BTRFS_OPTS="defaults,noatime,compress=zstd:1,discard=async,ssd,space_cache=v2"
# Per la cache pacchetti non serve compressione (i pkg sono già compressi)
PKG_OPTS="defaults,noatime,discard=async,ssd,space_cache=v2"

# --- Funzioni ---
log_info() { echo -e "${BLUE}[INFO]${NC} ${BOLD}$1${NC}"; }
log_success() { echo -e "${GREEN}[OK]${NC} ${BOLD}$1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} ${BOLD}$1${NC}"; }
log_err() { echo -e "${RED}[ERR]${NC} ${BOLD}$1${NC}"; exit 1; }

check_root() {
    if [ "$EUID" -ne 0 ]; then log_err "Serve root (sudo)."; fi
}

check_dependency() {
    local cmd=$1
    echo -ne "   Verifica ${cmd}...\r"
    if ! command -v $cmd &> /dev/null; then
        log_err "Comando mancante: ${cmd}. Installalo prima di procedere."
    else
        echo -e "${GREEN}${ICON_OK} Trovato: ${cmd}           ${NC}"
    fi
}

banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "   ___  ___  ___  ______  ___  _____  _____  _____ "
    echo "   |  \/  | / _ \ | ___ \ |  \/  ||  _  ||  _  | "
    echo "   | .  . |/ /_\ \| |_/ / | .  . || | | || | | | "
    echo "   | |\/| ||  _  ||     / | |\/| || | | || | | | "
    echo "   | |  | || | | || |\ \  | |  | |\ \_/ /\ \_/ / "
    echo "   \_|  |_/\_| |_/\_| \_| \_|  |_/ \___/  \___/  "
    echo -e "            ${YELLOW}GRUB ONLINE MIGRATOR${BLUE}${NC}"
    echo "   Migrazione a Flat Layout (@, @home...) "
    echo "   Eseguibile direttamente dal sistema attivo."
    echo -e "${NC}"
}

# --- MAIN ---

check_root
log_info "Verifica prerequisiti..."
check_dependency "btrfs"
check_dependency "rsync"
check_dependency "grub-mkconfig"
check_dependency "findmnt"
echo ""
banner

echo -n "Sei pronto a migrare il sistema 'Online'? [y/N]: "
read confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then log_err "Annullato."; fi

# 1. Analisi
log_info "Analisi filesystem..."
ROOT_UUID=$(findmnt -n -o UUID /)
BOOT_UUID=$(findmnt -n -o UUID /boot 2>/dev/null)
log_success "Root UUID: $ROOT_UUID"

# 2. Root Snapshot (@)
# Creiamo la nuova root base partendo dal sistema attuale
if [ ! -d "/@" ]; then
    log_info "Creazione snapshot di sistema in /@..."
    btrfs subvolume snapshot / /@ || log_err "Snapshot root fallito."
    log_success "Snapshot /@ creato."
else
    log_warn "Snapshot /@ già esistente. Procedo."
fi

# 3. Gestione Subvolumi Extra
# Definiamo mappa: NomeSubvol -> PercorsoDatiAttuale
declare -A SUBVOLS
SUBVOLS=( 
    ["@home"]="/home" 
    ["@log"]="/var/log" 
    ["@pkg"]="/var/cache/pacman/pkg" 
    ["@snapshots"]="/.snapshots" 
)

log_info "Verifica e creazione subvolumi mancanti..."

for sv in "${!SUBVOLS[@]}"; do
    path="${SUBVOLS[$sv]}"
    
    # Creazione Subvolume se manca
    if [ ! -d "/$sv" ]; then
        btrfs subvolume create "/$sv"
        log_success "Creato /$sv"
    else
        log_info "/$sv esistente, salto creazione."
    fi
    
    # Migrazione Dati (Rsync)
    # Copiamo i dati dal sistema live dentro il subvolume
    # Nota: Escludiamo .snapshots dalla copia rsync per evitare loop
    if [ "$sv" != "@snapshots" ]; then
        if [ -d "$path" ] && [ -n "$(ls -A $path 2>/dev/null)" ]; then
            # Se il subvolume di destinazione è vuoto, sincronizza
            if [ -z "$(ls -A /$sv)" ]; then
                echo -e "   Sync dati: $path -> /$sv ..."
                rsync -aAX "$path/" "/$sv/"
                log_success "Dati migrati in $sv"
            fi
        fi
    fi
done

# 4. Pulizia dentro la NUOVA Root (@)
log_info "Preparazione mountpoint vuoti in /@..."
# I dati ora sono nei subvolumi (@home, @log, etc).
# Dobbiamo svuotare le cartelle corrispondenti DENTRO LO SNAPSHOT @
# affinché funzionino da punti di montaggio puliti.

clean_dir() {
    dir=$1
    if [ -d "/@$dir" ]; then
        # rm -rf su /@/percorso/* cancella il contenuto SOLO nello snapshot
        rm -rf "/@$dir"/*
        log_success "Svuotato /@$dir (Ready for mount)"
    else
        mkdir -p "/@$dir"
    fi
}

clean_dir "/home"
clean_dir "/var/log"
clean_dir "/var/cache/pacman/pkg"
clean_dir "/.snapshots"

# Assicuriamo permessi corretti per cartella snapshots
chmod 750 /@/.snapshots

# 5. Generazione Fstab
log_info "Aggiornamento /@/etc/fstab..."
cp /etc/fstab /@/etc/fstab.bak

# Preservazione entry di boot se separata
BOOT_ENTRY=""
if [ -n "$BOOT_UUID" ] && [ "$BOOT_UUID" != "$ROOT_UUID" ]; then
    BOOT_ENTRY=$(grep "/boot " /etc/fstab)
fi

cat <<EOF > /@/etc/fstab
# /etc/fstab: Generated by Migrator V2

# Root
UUID=$ROOT_UUID  /                      btrfs  subvol=@,$BTRFS_OPTS  0 0

# Dati Utente e Log
UUID=$ROOT_UUID  /home                  btrfs  subvol=@home,$BTRFS_OPTS  0 0
UUID=$ROOT_UUID  /var/log               btrfs  subvol=@log,$BTRFS_OPTS   0 0

# Cache Pacchetti (Escluso da Snapshots)
UUID=$ROOT_UUID  /var/cache/pacman/pkg  btrfs  subvol=@pkg,$PKG_OPTS     0 0

# Snapper
UUID=$ROOT_UUID  /.snapshots            btrfs  subvol=@snapshots,$BTRFS_OPTS 0 0

# Partizioni Extra (Boot/EFI/Swap)
$BOOT_ENTRY
EOF

grep "swap" /etc/fstab >> /@/etc/fstab
log_success "Fstab scritto (include @log e @pkg)."

# 6. Aggiornamento GRUB (Metodo Chroot)
log_info "Configurazione GRUB..."

GRUB_FILE="/@/etc/default/grub"
if [ -f "$GRUB_FILE" ]; then
    if ! grep -q "rootflags=subvol=@" "$GRUB_FILE"; then
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&rootflags=subvol=@ /' "$GRUB_FILE"
        log_success "Iniettato rootflags=subvol=@"
    fi
fi

log_info "Rigenerazione grub.cfg in chroot..."

# Mount API filesystems
mount --bind /dev /@/dev
mount --bind /proc /@/proc
mount --bind /sys /@/sys
mount --bind /run /@/run
if [ -d "/sys/firmware/efi/efivars" ]; then
    mount --bind /sys/firmware/efi/efivars /@/sys/firmware/efi/efivars
fi

# Mount /boot se necessario
if [ -n "$BOOT_ENTRY" ]; then
    mount --bind /boot /@/boot
fi

# Esecuzione
chroot /@ grub-mkconfig -o /boot/grub/grub.cfg

# Cleanup
umount /@/boot 2>/dev/null
umount /@/sys/firmware/efi/efivars 2>/dev/null
umount /@/run /@/sys /@/proc /@/dev

echo ""
echo -e "${BOLD}${GREEN}MIGRAZIONE COMPLETATA.${NC}"
echo "Subvolumi creati e popolati:"
echo " - @ (Root)"
echo " - @home"
echo " - @log (/var/log)"
echo " - @pkg (/var/cache/pacman/pkg)"
echo " - @snapshots"
echo ""
echo "Puoi riavviare: reboot"
