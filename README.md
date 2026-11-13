# OneXPlayer 1S — Utility (Windows 11)

Utility grafica WPF in PowerShell ispirata a **Chris Titus WinUtil** per il **OneXPlayer 1S** su **Windows 11**. Quattro schede:

- **Driver**: scarica e installa in sequenza silenziosa i 13 driver del 1S.
- **Gioco**: installa con winget i programmi utili per giocare (librerie, negozi, strumenti per le prestazioni, streaming, emulatori).
- **Schermo**: orientamento, blocco della rotazione automatica, risoluzione e diagnosi del touch.
- **Sistema**: avvio del dispositivo (desktop, Steam Big Picture o Playnite), ottimizzazioni per touch e gioco, collegamenti alle Impostazioni di Windows.

## Avvio rapido (stile WinUtil)

Apri **PowerShell** (anche non come amministratore, lo script chiede l'elevazione UAC automaticamente) ed esegui:

```powershell
irm 070293.xyz/oxp-win | iex
```

Oppure direttamente da GitHub:

```powershell
irm https://raw.githubusercontent.com/dilfal/onexplayer-1s-drivers/main/oxp1s.ps1 | iex
```

### Uso offline (senza download)

Se hai già copiato gli archivi `.zip` in locale (ad esempio nella sottocartella `drivers\` oppure nella stessa cartella dello script), avvia [Avvia.cmd](Avvia.cmd) oppure passa `-LocalDriversPath`:

```powershell
.\oxp1s.ps1 -LocalDriversPath "C:\Percorso\Drivers"
```

La scheda Gioco e i comandi della scheda Schermo non usano gli archivi: i programmi si scaricano con winget (serve Internet).

## Caratteristiche

- **Interfaccia WPF scura in Italiano** con quattro schede (Driver, Gioco, Schermo, Sistema), barre di avanzamento e log in tempo reale comuni.
- **Scheda Driver**: all'apertura sono selezionati solo i driver mancanti, in errore o più vecchi (Seleziona Tutti li include tutti); selezione singola o tramite preset (`Seleziona Tutti`, `Solo Mancanti / Aggiornabili`, `Solo Essenziali`), rilevamento automatico dei driver già installati e dei dispositivi con errori, Punto di Ripristino automatico (disattivabile), installazione 100% silenziosa in ordine di dipendenza e **riavvio unico finale**.
- **Scheda Gioco**: 25 programmi con categoria, descrizione e stato sul PC (rilevato in background, circa 30 secondi); preset `Consigliati`, `Tutti`, `Nessuno`; installazione con `winget` una voce alla volta.
- **Scheda Schermo**: rotazioni relative (90, 180, 270 gradi), blocco/sblocco della rotazione automatica, risoluzione `Nativa` / `1920 x 1200` / `1280 x 800`, diagnosi e riparazione del touch. **Ogni cambio di schermo chiede conferma per 15 secondi** e, se non rispondi Sì, torna da solo allo stato precedente.
- **Finestra adattiva**: 1080x780 centrata sugli schermi grandi; se l'area di lavoro è più piccola (per esempio 1280x752, 1024x592 o schermo in verticale prima di installare il driver grafico) parte ingrandita, con un layout più compatto e barre di scorrimento sotto 860x520, così il pulsante in fondo resta sempre raggiungibile. Le caselle Sel. cambiano al primo tocco.
- Il pulsante in basso cambia con la scheda: «Installa Driver Selezionati» (Driver), «Installa Programmi Selezionati» (Gioco), disattivato (Schermo), «Applica Ottimizzazioni Selezionate» (Sistema). `Annulla` ferma la coda in corso tra un elemento e l'altro.

## Driver inclusi (in ordine sequenziale)

1. **Intel Chipset Device Software** (`10.1.18460.8229`) — `SetupChipset.exe /s /norestart`
2. **Intel Serial IO (GPIO / I2C / SPI / UART)** (`30.100.2013.5`) — `SetupSerialIO.exe /s`
3. **Intel Management Engine (MEI + DAL + iCLS)** (`2108.100.0.1053`) — `heci.inf`, `DAL.inf`, `iclsClient.inf` via `pnputil`
4. **Intel GNA Scoring Accelerator** (`02.00.00.1010`) — `pnputil /add-driver ... /install`
5. **Intel Dynamic Tuning Technology (DTT)** (`8.7.10400.15556`) — `Dtt_8.7.10400.15556_Install.exe /s`
6. **Intel Iris Xe Graphics** (`27.20.100.9616`) — INF diretti via `pnputil`
7. **Realtek High Definition Audio** (`6.0.1.7541`) — INF `Vista64` via `pnputil`
8. **Intel Wi-Fi (UWD Win64)** (`21.110.1.1`) — INF `UWD\Win64\Drivers` via `pnputil`
9. **Intel Wireless Bluetooth (UWD x64)** (`21.110.0.3`) — INF `INF_INSTALL\Win10_UWD\x64` via `pnputil`
10. **Intel Thunderbolt DCH** (`1.41.1054.0`) — INF driver via `pnputil` (senza app Appx)
11. **Realtek Card Reader** (`RtsUer`) — INF via `pnputil`
12. **Bosch BMA2x2 Accelerometer** (`1.0.1.2`) — INF `UMDF_2.0_BMA2x2_1.0.1.2_RS5_signed` via `pnputil`
13. **FocalTech Fingerprint Reader** (`2.0.3.71`) — `ftWbioUmdfDriverV2.inf` via `pnputil`

Management Engine, Thunderbolt e lettore di impronte vengono dal pacchetto del produttore «ONEXPLAYER 8.4 Drivers V1.0» (maggio 2021), più recente per questi tre componenti; gli altri dieci dal pacchetto del 1S. Il download complessivo è di circa 0,9 GB.

*(Escluso: `intel(r) pch chipset_init kit` perché contiene solo file binari `.bin` per flashing BIOS/SPI OEM non installabili da Windows).*

**Grafica aggiornata:** il driver Iris Xe del pacchetto è quello del produttore. Per averlo sempre aggiornato installa dalla scheda Gioco **Intel Driver & Support Assistant**, che aggiorna grafica Iris Xe, Wi-Fi e Bluetooth alle versioni Intel correnti.

## Programmi della scheda Gioco

I programmi marcati **(C)** sono quelli selezionati con il preset `Consigliati` (e all'avvio).

| Categoria | Programmi |
|---|---|
| Librerie | Visual C++ 2015-2022 x64 **(C)** e x86 **(C)**, DirectX End-User Runtime **(C)**, .NET Desktop Runtime 8 **(C)** |
| Grafica | Intel Driver & Support Assistant **(C)**, Intel Graphics Command Center **(C)** (dallo Store) |
| Negozi | Steam **(C)**, Playnite **(C)**, Heroic Games Launcher, GOG Galaxy, Epic Games Launcher, EA app, Ubisoft Connect |
| Prestazioni | RivaTuner Statistics Server **(C)**, MSI Afterburner, HWiNFO, Handheld Companion (il 1S non è tra i dispositivi elencati: da provare), ThrottleStop |
| Streaming | GeForce NOW, Moonlight |
| Emulazione | RetroArch, PCSX2 |
| Utilità | 7-Zip **(C)** |
| Dischi Linux | DiskInternals Linux Reader **(C)** (ext2/ext3/ext4 in sola lettura), WinBtrfs (dischi btrfs, anche in scrittura: da usare con prudenza) |

Lo stato («Installato» / «Non installato») viene letto con `winget export` (voci winget) e `Get-AppxPackage` (Intel Graphics Command Center). Se `winget` manca, la coda non parte: aggiorna «Programma di installazione app» dal Microsoft Store (sulle edizioni LTSC winget non è incluso e va installato a parte). Al termine della coda compare un riepilogo, senza richiesta di riavvio.

## Scheda Schermo

- **Orientamento**: `Ruota di 90 gradi`, `Capovolgi (180 gradi)`, `Ruota di 270 gradi`. Sono rotazioni relative all'orientamento attuale.
- **Rotazione automatica**: `Blocca` / `Sblocca` (valore `Enable` in `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AutoRotation`); può servire uscire e rientrare in Windows.
- **Risoluzione**: `Nativa`, `1920 x 1200`, `1280 x 800`. 1280 x 800 è la metà esatta della nativa: con la scalatura a numeri interi di Intel Graphics Command Center resta nitida e i giochi girano molto più leggeri. Se il driver video non elenca la modalità richiesta (succede con il driver di base) non viene applicato nulla.
- **Conferma**: ogni cambio chiede «Mantenere questa impostazione dello schermo?» per 15 secondi; senza Sì torna allo stato precedente.
- **Touch**: `Diagnosi touch` controlla Intel Serial IO, i dispositivi HID su I2C e il touch screen e scrive l'esito; `Ripara touch` riattiva e riavvia i dispositivi coinvolti. Se manca Serial IO propone di selezionare solo quel driver nella scheda Driver.

## Scheda Sistema

- **Avvio del dispositivo**: `Desktop normale`, `Steam Big Picture` (`steam.exe -gamepadui`) o `Playnite a schermo intero` (`Playnite.FullscreenApp.exe`). È un **avvio automatico all'accesso, sopra il desktop normale**: si scrive il valore `OXP1S-AvvioGioco` in `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, quindi vale per l'utente che avvia l'utility. Per impostazione predefinita Explorer resta la shell di Windows: uscendo da Big Picture o da Playnite si torna al desktop. In alternativa c'è l'opzione avanzata `Al posto del desktop` (vedi sotto). Se il programma scelto non è installato non viene scritto nulla e la riga di stato rimanda alla scheda Gioco. Con Steam Big Picture il valore `Steam` di `Run` (avvio silenzioso di Steam), se c'è, viene messo da parte in `HKCU\Software\OXP1S-Utility` e rimesso al cambio di modalità.
- **Ottimizzazioni**: elenco con stato attuale (`Attiva` / `Non attiva` / `Non determinato`), preset `Consigliate`, `Tutte`, `Nessuna`, `Aggiorna stato`; il pulsante in basso applica le voci selezionate e `Ripristina selezionate` le riporta allo stato precedente. Le **consigliate** sono marcate **(C)**.

| Regolazione | Categoria | Cosa fa |
|---|---|---|
| Tastiera touch sempre disponibile **(C)** | Touch | Il controller integrato può risultare come tastiera collegata e impedire alla tastiera a schermo di comparire |
| Caselle di selezione in Esplora file **(C)** | Touch | Una casella accanto a ogni file per selezionarlo col tocco (riaprire Esplora file) |
| Spaziatura larga in Esplora file **(C)** | Touch | Elementi più distanziati, più facili da toccare (riaprire Esplora file) |
| Disattiva i gesti dai bordi dello schermo | Touch | Evita di aprire widget e notifiche per sbaglio mentre si gioca (serve un nuovo accesso) |
| Modalità Gioco di Windows **(C)** | Gioco | Dà priorità al gioco in primo piano |
| Tasto di accensione: ibernazione invece di sospensione **(C)** | Gioco | La sospensione moderna consuma batteria nello zaino (`powercfg`) |
| Avvio dei programmi senza attesa dopo l'accesso | Gioco | Può ridurre l'attesa prima che parta il programma scelto per l'avvio |

- **Avvio al posto del desktop (avanzato, non provato sul dispositivo)**: con Steam o Playnite selezionato si può spuntare `Al posto del desktop (avanzato, non provato)`. L'utility scrive il valore `Shell` in `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon` (solo per l'utente corrente, mai `HKLM`, nessun Shell Launcher) che punta a un piccolo avviatore, `%LOCALAPPDATA%\OXP1S-Utility\avvio-shell.ps1`. Finché il programma è aperto non partono desktop, barra delle applicazioni e programmi in avvio automatico. Protezioni: quando Steam o Playnite si chiude compare il desktop (e al prossimo accesso riparte il programma); se si chiude in meno di 45 secondi per due volte di seguito, o se l'eseguibile manca, o in caso di errore, al successivo accesso l'avviatore toglie la shell e torna al desktop normale in modo permanente. Prima di attivarla compare un avviso Sì/No (predefinito No). Per tornare indietro: nell'utility `Desktop normale` e `Applica avvio`; in emergenza `Ctrl+Shift+Esc`, `Esegui nuova attività`, `explorer.exe`. Conviene attivarla solo dopo aver verificato che l'avvio sopra il desktop funziona e che touch o tastiera rispondono.
- **Impostazioni di Windows**: pulsanti che aprono la pagina giusta (scala dello schermo, tastiera touch, accesso con impronta o PIN, gesti touch, Modalità Gioco) e `Apri WinUtil (pulizia di Windows)`, che prima chiede conferma e poi scarica ed esegue lo strumento di Chris Titus da `christitus.com/win`.

## Pubblicazione su GitHub Releases

Per creare il repository pubblico `dilfal/onexplayer-1s-drivers`, fare il push e caricare i 13 `.zip` su GitHub Releases `v1.0.0`:

```powershell
.\publish-release.ps1
```
