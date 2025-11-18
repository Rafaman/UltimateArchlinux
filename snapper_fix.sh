#!/bin/bash

# =============================================================================
# SNAPPER FIX & INIT SCRIPT (FLAT LAYOUT)
# =============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[FIX]${NC} $1"; }
log_err() { echo -e "${RED}[ERR]${NC} $1"; exit 1; }

# 1. Verifica esistenza del subvolume @snapshots
log_info "Verifica esistenza subvolume @snapshots..."
if btrfs subvolume list / | grep -q "@snapshots"; then
    log_info "Subvolume @snapshots trovato."
else
    log_info "Subvolume @snapshots non trovato. Lo creo ora..."
    btrfs subvolume create /@snapshots
fi

# 2. Creazione del Mountpoint (Il passaggio mancante)
if [ ! -d "/.snapshots" ]; then
    log_info "La cartella /.snapshots non esiste. Creazione in corso..."
    mkdir -p /.snapshots
fi

# 3. Montaggio (Testiamo se fstab è corretto)
log_info "Tento il montaggio basandomi su /etc/fstab..."
# Smonta per sicurezza nel caso fosse montato male
umount /.snapshots 2>/dev/null

# Prova a montare tutto ciò che c'è in fstab
mount -a

if mountpoint -q /.snapshots; then
    log_info "Mount riuscito! @snapshots è montato su /.snapshots."
else
    log_err "Impossibile montare /.snapshots. Controlla che in /etc/fstab ci sia la riga per @snapshots!"
fi

# 4. La "Danza" di inizializzazione Snapper
# Snapper non permette di creare una config se la cartella è già un mountpoint popolato o esistente.
# Dobbiamo ingannarlo.

log_info "Inizializzazione configurazione Snapper..."

# A) Smontiamo il subvolume reale
umount /.snapshots

# B) Rimuoviamo la cartella (deve essere assente perché Snapper la ricrei)
rm -rf /.snapshots

# C) Creiamo la config (Snapper creerà /.snapshots come subvolume annidato)
snapper -c root create-config /

# D) ELIMINIAMO il subvolume annidato che Snapper ha appena creato (non lo vogliamo, vogliamo il layout Flat!)
btrfs subvolume delete /.snapshots

# E) Ricreiamo la cartella vuota
mkdir /.snapshots

# F) Rimontiamo il NOSTRO subvolume @snapshots
mount -a

# 5. Verifica Finale e Permessi
if mountpoint -q /.snapshots; then
    chmod 750 /.snapshots
    chown :users /.snapshots # o :wheel a seconda del tuo gruppo
    log_info "Permessi sistemati."
    
    # Creiamo un primo snapshot di prova
    snapper -c root create --description "Fix Applicato"
    log_info "Snapshot di prova creato."
    
    echo ""
    echo -e "${GREEN}PROBLEMA RISOLTO!${NC}"
    echo "Ora 'snapper list' dovrebbe funzionare e il layout è corretto."
else
    log_err "Qualcosa è andato storto nel rimontaggio finale."
fi
