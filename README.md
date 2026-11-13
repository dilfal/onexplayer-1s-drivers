# OneXPlayer 1S — Driver Utility (Windows 11 Pro)

Utility grafica WPF in PowerShell ispirata a **Chris Titus WinUtil** per scaricare e installare in sequenza silenziosa tutti i driver del **OneXPlayer 1S** su **Windows 11 Pro**.

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

## Caratteristiche

- **Interfaccia WPF scura in Italiano** con selezione singola o tramite preset (`Seleziona Tutti`, `Solo Mancanti / Aggiornabili`, `Solo Essenziali`).
- **Rilevamento automatico** dei driver già installati e dei dispositivi con errori in Gestione Dispositivi.
- **Punto di Ripristino automatico** prima dell'avvio (disattivabile con checkbox).
- **Installazione 100% silenziosa** in ordine corretto delle dipendenze, con barra di avanzamento e log in tempo reale.
- **Riavvio unico finale**: sopprime i riavvii intermedi e propone un solo reboot al termine della sequenza.

## Driver inclusi (in ordine sequenziale)

1. **Intel Chipset Device Software** (`10.1.18460.8229`) — `SetupChipset.exe /s /norestart`
2. **Intel Serial IO (GPIO / I2C / SPI / UART)** (`30.100.2013.5`) — `SetupSerialIO.exe /s`
3. **Intel CSME / MEI-Only Driver** (`15.0.1.1345`) — `MEISetup.exe /s /drvonly`
4. **Intel GNA Scoring Accelerator** (`02.00.00.1010`) — `pnputil /add-driver ... /install`
5. **Intel Dynamic Tuning Technology (DTT)** (`8.7.10400.15556`) — `Dtt_8.7.10400.15556_Install.exe /s`
6. **Intel Iris Xe Graphics** (`27.20.100.9616`) — INF diretti via `pnputil`
7. **Realtek High Definition Audio** (`6.0.1.7541`) — INF `Vista64` via `pnputil`
8. **Intel Wi-Fi (UWD Win64)** (`21.110.1.1`) — INF `UWD\Win64\Drivers` via `pnputil`
9. **Intel Wireless Bluetooth (UWD x64)** (`21.110.0.3`) — INF `INF_INSTALL\Win10_UWD\x64` via `pnputil`
10. **Intel Thunderbolt DCH** (`1.41.987.0`) — INF driver via `pnputil` (senza app Appx)
11. **Realtek Card Reader** (`RtsUer`) — INF via `pnputil`
12. **Bosch BMA2x2 Accelerometer** (`1.0.1.2`) — INF `UMDF_2.0_BMA2x2_1.0.1.2_RS5_signed` via `pnputil`

*(Escluso: `intel(r) pch chipset_init kit` perché contiene solo file binari `.bin` per flashing BIOS/SPI OEM non installabili da Windows).*

## Pubblicazione su GitHub Releases

Per creare il repository pubblico `dilfal/onexplayer-1s-drivers`, fare il push e caricare i 12 `.zip` su GitHub Releases `v1.0.0`:

```powershell
.\publish-release.ps1
```
