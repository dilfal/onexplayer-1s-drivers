# Istruzioni d'uso — OneXPlayer 1S Driver Utility (Windows 11 Pro)

Guida pratica per installare automaticamente e in modo silenzioso tutti i driver del **OneXPlayer 1S** dopo un'installazione pulita di **Windows 11 Pro** (o per aggiornare/ripristinare i driver mancanti).

---

## 1. Avvio rapido (con connessione Internet)

1. Su Windows 11 Pro apri **PowerShell** (o **Terminale Windows**): puoi aprirlo anche come utente normale, perché lo script richiede automaticamente i privilegi di amministratore (UAC).
2. Incolla e premi **Invio**:

```powershell
irm 070293.xyz/oxp-win | iex
```

*(In alternativa, link diretto da GitHub)*:

```powershell
irm https://raw.githubusercontent.com/dilfal/onexplayer-1s-drivers/main/oxp1s.ps1 | iex
```

3. Conferma la finestra UAC (**Sì**) per aprire l'interfaccia grafica.

---

## 2. Avvio offline (da chiavetta USB o cartella locale)

Se stai configurando un OneXPlayer 1S senza Wi-Fi ancora funzionante o preferisci non riscaricare i pacchetti (~1,34 GB):

1. Copia il contenuto di questa cartella su chiavetta USB o sul desktop.
2. Crea una sottocartella chiamata `drivers` accanto a `oxp1s.ps1` (oppure metti i file direttamente accanto allo script) e copiaci i 12 archivi `.zip` originali.
   - Lo script riconosce sia i nomi originali di OneDrive (es. `intel(r)_dtt_8.7.10400.15556.zip`) sia i nomi sanitizzati di GitHub Releases (es. `intel.r._dtt_8.7.10400.15556.zip`).
3. Fai doppio click su **`Avvia.cmd`** (avvia PowerShell con `-ExecutionPolicy Bypass -STA` e chiede l'UAC automaticamente).

Oppure, da PowerShell indicando una cartella specifica:

```powershell
.\oxp1s.ps1 -LocalDriversPath "D:\Drivers (1S)"
```

---

## 3. Come usare l'interfaccia grafica

All'apertura, lo script analizza automaticamente il sistema (`Win32_PnPSignedDriver`, `Get-PnpDevice` e registro programmi installati) e mostra lo stato attuale di ciascun driver nella colonna **Stato sul PC**:

- **`Non rilevato`**: driver non presente o non attivo sul sistema.
- **`Errore dispositivo (!)`**: dispositivo rilevato in Gestione Dispositivi con stato diverso da `OK`.
- **`Aggiornabile (...)`**: versione installata più vecchia di quella nel pacchetto.
- **`Installato (...)`**: versione uguale o più recente già presente.

### Pulsanti rapidi (Toolbar)

- **`Seleziona Tutti (12)`**: seleziona tutti i pacchetti per l'installazione sequenziale completa (utile su Windows appena formattato).
- **`Solo Mancanti / Aggiornabili`**: seleziona automaticamente solo ciò che manca, ha errori o ha versione più vecchia.
- **`Solo Essenziali (Core + Rete + GPU)`**: seleziona Chipset, Serial IO, CSME, DTT, Iris Xe Graphics, Wi-Fi e Bluetooth.
- **`Deseleziona Tutto`**: svuota la selezione per scegliere manualmente singoli driver.
- **`Aggiorna Rilevamento`**: riesegue la scansione del sistema.
- **`Gestione Dispositivi`**: apre `devmgmt.msc` per un controllo visivo rapido.

### Opzioni prima di avviare

- **`Crea Punto di Ripristino prima di iniziare`** *(attivo di default)*: tenta di abilitare Ripristino configurazione di sistema sul disco di Windows e crea `Pre-OXP1S-Drivers`. *(Se fallisce, ad esempio per il limite di Windows di 1 punto ogni 24 ore, registra un avviso nel log ma prosegue regolarmente).*
- **`Usa .zip locali se presenti`** *(attivo di default)*: controlla `drivers\` e la cartella corrente prima di scaricare da GitHub Releases.
- **`Elimina file temporanei al termine`** *(attivo di default)*: rimuove la cartella estratta e gli `.zip` scaricati da `%TEMP%\OXP1S-Drivers\` (non tocca mai eventuali `.zip` locali in `drivers\` o `-LocalDriversPath`).

### Avvio e riavvio finale

1. Premi **`Installa Driver Selezionati`**.
2. I driver selezionati vengono scaricati (se non locali), estratti ed eseguiti **uno dopo l'altro in modalità 100% silenziosa** nell'ordine delle dipendenze (`1` → `12`).
3. Durante la sequenza puoi seguire la doppia barra di avanzamento (totale e passo corrente) e il log scorrevole in basso. Con **`Annulla`** la coda si ferma al termine del driver in corso.
4. I riavvii intermedi sono soppressi: se almeno un pacchetto restituisce codice di riavvio (`3010`, `1641`, `350`, `14`, `15`), al termine dell'intera sequenza apparirà **un'unica richiesta di riavvio finale**.

---

## 4. Elenco e ordine dei 12 pacchetti installati

| # | Driver | Versione | Metodo silenzioso |
|---|---|---|---|
| 1 | Intel Chipset Device Software | `10.1.18460.8229` | `SetupChipset.exe /s /norestart` |
| 2 | Intel Serial IO (GPIO / I2C / SPI / UART) | `30.100.2013.5` | `SetupSerialIO.exe /s` |
| 3 | Intel CSME / MEI-Only Driver | `15.0.1.1345` | `MEISetup.exe /s /drvonly` |
| 4 | Intel GNA Scoring Accelerator | `02.00.00.1010` | `pnputil /add-driver ... /install` |
| 5 | Intel Dynamic Tuning Technology (DTT) | `8.7.10400.15556` | `Dtt_8.7.10400.15556_Install.exe /s` |
| 6 | Intel Iris Xe Graphics (+ DisplayAudio 11.2) | `27.20.100.9616` | INF diretti via `pnputil` |
| 7 | Realtek High Definition Audio | `6.0.1.7541` | INF `Vista64` via `pnputil` |
| 8 | Intel Wi-Fi (UWD Win64) | `21.110.1.1` | INF `UWD\Win64\Drivers` via `pnputil` |
| 9 | Intel Wireless Bluetooth (UWD x64) | `21.110.0.3` | INF `INF_INSTALL\Win10_UWD\x64` (`pnputil /subdirs`) |
| 10 | Intel Thunderbolt DCH | `1.41.987.0` | INF driver via `pnputil` (senza app Appx) |
| 11 | Realtek PCIE / USB Card Reader | `RtsUer` | `RtsUer.inf` via `pnputil` |
| 12 | Bosch BMA2x2 Accelerometer | `1.0.1.2` | `UMDF_2.0_BMA2x2_1.0.1.2_RS5_signed` via `pnputil` |

> **Nota sul 13° archivio originale (`intel(r) pch chipset_init kit`)**: è escluso perché contiene esclusivamente file binari `.bin` e PDF per l'integrazione BIOS/SPI da parte del produttore (OEM), non è un driver installabile da Windows.

---

## 5. Log e diagnostica

Tutti i log dettagliati vengono salvati automaticamente in:

```text
%TEMP%\OXP1S-Drivers\logs\
```

- `oxp1s_install_YYYYMMDD_HHMMSS.log`: riepilogo completo di download, estrazioni, comandi eseguiti ed exit code.
- `<id>_setup.log`: log nativi dei singoli installer EXE (Chipset, SerialIO, CSME, DTT).

---

## 6. Aggiornare o ripubblicare su GitHub

Se modifichi gli script in questa cartella:

- Per aggiornare lo script `oxp1s.ps1` su GitHub (account `dilfal`):
  ```powershell
  gh auth switch --user dilfal
  git add .
  git commit -m "Descrizione modifica"
  git push origin main
  ```
- Per ricreare/aggiornare la Release `v1.0.0` con gli archivi `.zip`:
  ```powershell
  gh auth switch --user dilfal
  .\publish-release.ps1
  ```
- La scorciatoia `070293.xyz/oxp-win` (nel repo `dilfal/070293`) punta sempre al ramo `main` di `dilfal/onexplayer-1s-drivers`, quindi non va modificata quando aggiorni `oxp1s.ps1`.
