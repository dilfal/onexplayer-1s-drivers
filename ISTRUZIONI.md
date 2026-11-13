# Istruzioni d'uso — OneXPlayer 1S Utility (Windows 11)

Guida pratica per installare automaticamente e in modo silenzioso tutti i driver del **OneXPlayer 1S** dopo un'installazione pulita di **Windows 11** (o per aggiornare/ripristinare i driver mancanti), installare i programmi per giocare e sistemare lo schermo.

---

## 1. Avvio rapido (con connessione Internet)

1. Su Windows 11 apri **PowerShell** (o **Terminale Windows**): puoi aprirlo anche come utente normale, perché lo script richiede automaticamente i privilegi di amministratore (UAC).
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

Se stai configurando un OneXPlayer 1S senza Wi-Fi ancora funzionante o preferisci non riscaricare i pacchetti (~0,9 GB):

1. Copia il contenuto di questa cartella su chiavetta USB o sul desktop.
2. Crea una sottocartella chiamata `drivers` accanto a `oxp1s.ps1` (oppure metti i file direttamente accanto allo script) e copiaci i 13 archivi `.zip`.
   - Lo script riconosce sia i nomi originali (es. `intel(r)_dtt_8.7.10400.15556.zip`) sia i nomi sanitizzati di GitHub Releases (es. `intel.r._dtt_8.7.10400.15556.zip`).
3. Fai doppio click su **`Avvia.cmd`** (avvia PowerShell con `-ExecutionPolicy Bypass -STA` e chiede l'UAC automaticamente).

Oppure, da PowerShell indicando una cartella specifica:

```powershell
.\oxp1s.ps1 -LocalDriversPath "D:\Drivers (1S)"
```

Gli archivi servono solo alla scheda **Driver**. I programmi della scheda **Gioco** si scaricano con winget e richiedono Internet.

---

## 3. Come usare l'interfaccia grafica

La finestra ha tre schede, **Driver**, **Gioco** e **Schermo**. Intestazione, barre di avanzamento, log e pulsanti in basso sono comuni. Il pulsante principale cambia con la scheda: **`Installa Driver Selezionati`** nella scheda Driver, **`Installa Programmi Selezionati`** nella scheda Gioco, disattivato nella scheda Schermo. Mentre una coda è in corso non se ne può avviare un'altra e i pulsanti dei preset sono disattivati. **`Annulla`** ferma la coda corrente tra un elemento e l'altro.

### Scheda Driver

All'apertura, lo script analizza automaticamente il sistema (`Win32_PnPSignedDriver`, `Get-PnpDevice` e registro programmi installati) e mostra lo stato attuale di ciascun driver nella colonna **Stato sul PC**:

- **`Non rilevato`**: driver non presente o non attivo sul sistema.
- **`Errore dispositivo (!)`**: dispositivo presente e segnalato in errore in Gestione Dispositivi (non contano quelli scollegati né quelli disattivati a mano).
- **`Aggiornabile (...)`**: versione installata più vecchia di quella nel pacchetto.
- **`Installato (...)`**: versione uguale o più recente già presente.

#### Pulsanti rapidi (Toolbar)

- **`Seleziona Tutti (13)`**: seleziona tutti i pacchetti per l'installazione sequenziale completa (utile su Windows appena formattato).
- **`Solo Mancanti / Aggiornabili`**: seleziona automaticamente solo ciò che manca, ha errori o ha versione più vecchia.
- **`Solo Essenziali (Core + Rete + GPU)`**: seleziona Chipset, Serial IO, Management Engine, DTT, Iris Xe Graphics, Wi-Fi e Bluetooth.
- **`Deseleziona Tutto`**: svuota la selezione per scegliere manualmente singoli driver.
- **`Aggiorna Rilevamento`**: riesegue la scansione del sistema.
- **`Gestione Dispositivi`**: apre `devmgmt.msc` per un controllo visivo rapido.

#### Opzioni prima di avviare

- **`Crea Punto di Ripristino prima di iniziare`** *(attivo di default)*: tenta di abilitare Ripristino configurazione di sistema sul disco di Windows e crea `Pre-OXP1S-Drivers`. *(Se fallisce, ad esempio per il limite di Windows di 1 punto ogni 24 ore, registra un avviso nel log ma prosegue regolarmente).*
- **`Usa .zip locali se presenti`** *(attivo di default)*: controlla `drivers\` e la cartella corrente prima di scaricare da GitHub Releases.
- **`Elimina file temporanei al termine`** *(attivo di default)*: rimuove la cartella estratta e gli `.zip` scaricati da `%TEMP%\OXP1S-Drivers\` (non tocca mai eventuali `.zip` locali in `drivers\` o `-LocalDriversPath`).

#### Avvio e riavvio finale

1. Premi **`Installa Driver Selezionati`**.
2. I driver selezionati vengono scaricati (se non locali), estratti ed eseguiti **uno dopo l'altro in modalità 100% silenziosa** nell'ordine delle dipendenze (`1` → `13`).
3. Durante la sequenza puoi seguire la doppia barra di avanzamento (totale e passo corrente) e il log scorrevole in basso. Con **`Annulla`** la coda si ferma al termine del driver in corso.
4. I riavvii intermedi sono soppressi: se almeno un pacchetto restituisce codice di riavvio (`3010`, `1641`, `350`, `14`, `15`), al termine dell'intera sequenza apparirà **un'unica richiesta di riavvio finale**.

### Scheda Gioco

Elenca 23 programmi con categoria, a cosa servono, stato sul PC e avanzamento. Lo stato si legge in background la prima volta che apri la scheda (circa 30 secondi, con `winget export`; Intel Graphics Command Center si controlla come app dello Store), con **`Aggiorna stato`** e alla fine di ogni installazione. Valori: `Analisi...`, `Installato`, `Non installato`, `winget assente`.

- **`Consigliati`**: seleziona i programmi marcati come consigliati (sono anche quelli selezionati all'avvio): Visual C++ 2015-2022 (x64 e x86), DirectX End-User Runtime, .NET Desktop Runtime 8, Intel Driver & Support Assistant, Intel Graphics Command Center, Steam, Playnite, RivaTuner Statistics Server e 7-Zip.
- **`Tutti`** / **`Nessuno`**: seleziona o svuota l'intero elenco.
- Gli altri programmi (Heroic, GOG Galaxy, Epic, EA app, Ubisoft Connect, MSI Afterburner, HWiNFO, Handheld Companion, ThrottleStop, GeForce NOW, Moonlight, RetroArch, PCSX2) sono facoltativi. Handheld Companion non elenca il 1S tra i dispositivi supportati: da provare. ThrottleStop va regolato a mano con cautela.

Premendo **`Installa Programmi Selezionati`** i programmi vengono installati uno alla volta, in ordine, con `winget install --exact --silent`. Se `winget` non c'è, la coda non parte: aggiorna «Programma di installazione app» dal Microsoft Store (sulle edizioni LTSC winget non è incluso e va installato a parte). Un errore su una voce non ferma le altre: nel log compaiono il codice di uscita e le ultime righe dell'output. Al termine appare un riepilogo (completati, errori, percorso del log), **senza richiesta di riavvio**.

**Grafica aggiornata:** il driver Iris Xe della scheda Driver è quello del produttore. Per tenere aggiornati grafica, Wi-Fi e Bluetooth alle versioni Intel correnti installa **Intel Driver & Support Assistant** da questa scheda.

### Scheda Schermo

In alto vedi risoluzione, orientamento (0, 90, 180, 270 gradi) e frequenza attuali.

- **Orientamento**: `Ruota di 90 gradi`, `Capovolgi (180 gradi)`, `Ruota di 270 gradi`. Sono rotazioni **relative** all'orientamento attuale: se lo schermo non è come vuoi, prova un altro pulsante.
- **Rotazione automatica**: `Blocca` / `Sblocca rotazione automatica` (scrive il valore `Enable` in `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AutoRotation`). Può servire uscire e rientrare in Windows perché abbia effetto.
- **Risoluzione**: `Nativa`, `1920 x 1200`, `1280 x 800`. 1280 x 800 è la metà esatta della risoluzione nativa: con la scalatura a numeri interi di Intel Graphics Command Center resta nitida e i giochi girano molto più leggeri. Se il driver video non elenca la modalità richiesta (succede con il driver video di base, prima di installare il driver Iris Xe) non viene cambiato nulla e il log lo segnala.
- **Conferma a 15 secondi**: dopo ogni cambio compare «Mantenere questa impostazione dello schermo?». Se non rispondi **Sì** entro 15 secondi (o rispondi No) lo schermo torna da solo alle impostazioni di prima.
- **Touch**: `Diagnosi touch` controlla controller Intel Serial IO, dispositivi HID su I2C e touch screen e scrive nel log l'elenco dei dispositivi e l'esito. `Ripara touch` riattiva il touch se disattivato, riavvia i dispositivi HID su I2C e riesegue la scansione; se manca Serial IO propone di selezionare solo quel driver nella scheda Driver. La diagnosi parte anche alla prima apertura della scheda.

### Schermo capovolto e touch che non funziona dopo un'installazione pulita

Dopo un'installazione pulita di Windows lo schermo può comparire capovolto o ruotato e il touch può non rispondere. Il touch dipende da **Intel Serial IO** (driver n. 2), la rotazione automatica dall'**accelerometro Bosch** (driver n. 12) e la rotazione manuale dal **driver grafico** (driver n. 6). Installa tutti i 13 driver dalla scheda **Driver**, riavvia, poi usa la scheda **Schermo** per orientare lo schermo e, se il touch non risponde, `Diagnosi touch` e `Ripara touch`. Se la diagnosi dice che il touchscreen non viene elencato dal firmware, spegni del tutto il dispositivo (non basta riavviare), riaccendilo e ripeti la diagnosi.

---

## 4. Elenco e ordine dei 13 pacchetti driver

| # | Driver | Versione | Metodo silenzioso |
|---|---|---|---|
| 1 | Intel Chipset Device Software | `10.1.18460.8229` | `SetupChipset.exe /s /norestart` |
| 2 | Intel Serial IO (GPIO / I2C / SPI / UART) | `30.100.2013.5` | `SetupSerialIO.exe /s` |
| 3 | Intel Management Engine (MEI + DAL + iCLS) | `2108.100.0.1053` | `heci.inf`, `DAL.inf`, `iclsClient.inf` via `pnputil` |
| 4 | Intel GNA Scoring Accelerator | `02.00.00.1010` | `pnputil /add-driver ... /install` |
| 5 | Intel Dynamic Tuning Technology (DTT) | `8.7.10400.15556` | `Dtt_8.7.10400.15556_Install.exe /s` |
| 6 | Intel Iris Xe Graphics (+ DisplayAudio 11.2) | `27.20.100.9616` | INF diretti via `pnputil` |
| 7 | Realtek High Definition Audio | `6.0.1.7541` | INF `Vista64` via `pnputil` |
| 8 | Intel Wi-Fi (UWD Win64) | `21.110.1.1` | INF `UWD\Win64\Drivers` via `pnputil` |
| 9 | Intel Wireless Bluetooth (UWD x64) | `21.110.0.3` | INF `INF_INSTALL\Win10_UWD\x64` (`pnputil /subdirs`) |
| 10 | Intel Thunderbolt DCH | `1.41.1054.0` | INF driver via `pnputil` (senza app Appx) |
| 11 | Realtek PCIE / USB Card Reader | `RtsUer` | `RtsUer.inf` via `pnputil` |
| 12 | Bosch BMA2x2 Accelerometer | `1.0.1.2` | `UMDF_2.0_BMA2x2_1.0.1.2_RS5_signed` via `pnputil` |
| 13 | FocalTech Fingerprint Reader | `2.0.3.71` | `ftWbioUmdfDriverV2.inf` via `pnputil` |

> **Origine dei pacchetti**: Management Engine (3), Thunderbolt (10) e lettore di impronte (13) vengono dal pacchetto del produttore «ONEXPLAYER 8.4 Drivers V1.0» (maggio 2021), più recente per questi tre componenti; gli altri dieci dal pacchetto del 1S.

> **Nota sul 14° archivio originale (`intel(r) pch chipset_init kit`)**: è escluso perché contiene esclusivamente file binari `.bin` e PDF per l'integrazione BIOS/SPI da parte del produttore (OEM), non è un driver installabile da Windows.

---

## 5. Log e diagnostica

Tutti i log dettagliati vengono salvati automaticamente in:

```text
%TEMP%\OXP1S-Drivers\logs\
```

- `oxp1s_install_YYYYMMDD_HHMMSS.log`: riepilogo completo di download, estrazioni, comandi eseguiti ed exit code dei driver.
- `oxp1s_apps_YYYYMMDD_HHMMSS.log`: installazione dei programmi (comando winget, codice di uscita, righe finali in caso di errore).
- `<id>_setup.log`: log nativi dei singoli installer EXE (Chipset, Serial IO, DTT).

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
- **`oxp1s.ps1` va salvato in ASCII puro, senza BOM, con fine riga LF** (niente lettere accentate né simboli): con il BOM in testa `irm ... | iex` si ferma con un errore di sintassi sul blocco `param`, mentre `Avvia.cmd` continua a funzionare e nasconde il problema.
- La scorciatoia `070293.xyz/oxp-win` (nel repo `dilfal/070293`) punta sempre al ramo `main` di `dilfal/onexplayer-1s-drivers`, quindi non va modificata quando aggiorni `oxp1s.ps1`.
