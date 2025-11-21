#!/bin/bash

# ==============================================================================
#  TPM2 LUKS BINDING TOOL
# ==============================================================================
#  Lega lo sblocco del disco LUKS2 ai registri PCR del TPM.
#  PCR 0 (Firmware), 2 (ROM), 4 (Bootloader), 7 (Secure Boot State).
# ==============================================================================

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ICON_CHIP="[💾]"
ICON_LOCK="[🔒]"
ICON_WARN="[!]"

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}Esegui come root.${NC}"
       exit 1
    fi
}

clear
echo -e "${BLUE}${BOLD}   TPM2 LUKS ENROLLMENT   ${NC}"
echo -e "${BLUE}==========================${NC}"

check_root

# Verifica presenza TPM
if [ ! -c /dev/tpmrm0 ]; then
    echo -e "${RED}Nessun chip TPM 2.0 rilevato (/dev/tpmrm0 mancante).${NC}"
    echo "Assicurati di aver abilitato fTPM/TPM nel BIOS."
    exit 1
fi

# Selezione Device
echo -e "Dispositivi LUKS rilevati:"
lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT | grep crypto_LUKS
echo ""
echo -e -n "${BOLD}Inserisci il path del device LUKS (es. /dev/nvme0n1p2): ${NC}"
read -r LUKS_DEV

if [[ ! -b "$LUKS_DEV" ]]; then
    echo -e "${RED}Device non valido.${NC}"
    exit 1
fi

# Warning Critico
echo -e "${YELLOW}${ICON_WARN} ATTENZIONE CRITICA${NC}"
echo "Stai per legare la chiave di cifratura allo stato attuale del sistema."
echo "Se aggiorni il BIOS, disabiliti Secure Boot o cambi Bootloader,"
echo "lo sblocco automatico fallirà."
echo -e "${BOLD}DEVI conoscere la tua passphrase testuale di backup per accedere.${NC}"
echo ""
echo -e -n "Hai la passphrase a portata di mano? (s/N): "
read -r confirm
if [[ ! "$confirm" =~ ^([sS][iI]|[sS])$ ]]; then
    exit 0
fi

# Enrollment
echo -e "\n${ICON_CHIP} Binding ai PCR 0, 2, 4, 7..."
# Usa systemd-cryptenroll
# wipe-slot=tpm2 pulisce eventuali vecchi binding TPM per evitare duplicati
if systemd-cryptenroll "$LUKS_DEV" --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=0+2+4+7; then
    echo -e "${GREEN}${ICON_LOCK} Successo! Chiave TPM aggiunta all'header LUKS.${NC}"
    
    echo -e "\n${BLUE}Aggiornamento /etc/crypttab...${NC}"
    # Qui facciamo solo un check visivo. 
    # Con UKI e systemd-based initramfs, spesso la configurazione è passata via cmdline (rd.luks.options)
    # oppure crypttab è incluso nell'initramfs.
    
    echo -e "${YELLOW}Nota:${NC} Assicurati che la tua cmdline kernel (configurata prima)"
    echo "contenga opzioni simili a: rd.luks.options=tpm2-device=auto"
    echo "oppure che il tuo /etc/crypttab abbia l'opzione 'tpm2-device=auto'."
else
    echo -e "${RED}Errore durante l'enrollment.${NC}"
    exit 1
fi
