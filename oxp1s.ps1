<#
.SYNOPSIS
    OneXPlayer 1S Utility (Windows 11) - GUI stile Chris Titus WinUtil.
.DESCRIPTION
    Tre schede: Driver (scarica da GitHub Releases o da cartella locale, estrae e installa
    in sequenza silenziosa i driver del OneXPlayer 1S, con rilevamento dello stato, Punto di
    Ripristino e riavvio unico finale), Gioco (installa con winget i programmi per giocare)
    e Schermo (rotazione, blocco rotazione automatica e risoluzione).
.EXAMPLE
    irm 070293.xyz/oxp-win | iex
    irm https://raw.githubusercontent.com/dilfal/onexplayer-1s-drivers/main/oxp1s.ps1 | iex
.NOTES
    Questo file va salvato in ASCII puro, SENZA BOM: con il BOM in testa `irm ... | iex`
    non riconosce piu il blocco param e si ferma con un errore di sintassi.
#>

[CmdletBinding()]
param(
    [string]$ReleaseBaseUrl = "https://github.com/dilfal/onexplayer-1s-drivers/releases/download/v1.0.0",
    [string]$LocalDriversPath = ""
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 1. Auto-elevazione UAC + Verifica thread STA (necessario per WPF)
# ---------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
$isSta = [System.Threading.Thread]::CurrentThread.ApartmentState -eq 'STA'

if (-not $isAdmin -or -not $isSta) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
        $argList += @('-STA', '-File', "`"$PSCommandPath`"")
        if ($LocalDriversPath) { $argList += @('-LocalDriversPath', "`"$LocalDriversPath`"") }
    } else {
        # Esecuzione via irm ... | iex: salva temporaneamente il blocco corrente per riavviarlo elevato
        $tempLauncher = Join-Path $env:TEMP "oxp1s-elevated.ps1"
        if ($MyInvocation.MyCommand.ScriptBlock) {
            $scriptBody = $MyInvocation.MyCommand.ScriptBlock.ToString()
            Set-Content -Path $tempLauncher -Value $scriptBody -Encoding UTF8
            $argList += @('-STA', '-File', "`"$tempLauncher`"")
        } else {
            $cmd = "irm 'https://raw.githubusercontent.com/dilfal/onexplayer-1s-drivers/main/oxp1s.ps1' | iex"
            $argList += @('-STA', '-Command', $cmd)
        }
    }

    try {
        Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList | Out-Null
    } catch {
        Write-Warning "Privilegi di amministratore richiesti per installare i driver."
    }
    return
}

# ---------------------------------------------------------------------------
# 2. Assembly .NET richiesti
# ---------------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Net.Http

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13 } catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# Classe per orientamento e risoluzione dello schermo (user32.dll). C# 5: compatibile con Windows PowerShell 5.1.
if (-not ('OxpDisplay' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class OxpDisplay
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwFlags, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "MessageBoxTimeoutW")]
    private static extern int MessageBoxTimeout(IntPtr hWnd, string text, string caption, uint type, ushort languageId, int milliseconds);

    private const int ENUM_CURRENT_SETTINGS = -1;
    private const int CDS_UPDATEREGISTRY = 1;
    private const int CDS_TEST = 2;
    private const int DM_DISPLAYORIENTATION = 0x80;
    private const int DM_PELSWIDTH = 0x80000;
    private const int DM_PELSHEIGHT = 0x100000;
    private const int DM_DISPLAYFREQUENCY = 0x400000;

    private static DEVMODE NewDevMode()
    {
        DEVMODE dm = new DEVMODE();
        dm.dmDeviceName = new string(' ', 0);
        dm.dmFormName = new string(' ', 0);
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        return dm;
    }

    public static int StructSize()
    {
        return Marshal.SizeOf(typeof(DEVMODE));
    }

    // Restituisce { larghezza, altezza, orientamento (0-3), frequenza } oppure null.
    public static int[] Current()
    {
        DEVMODE dm = NewDevMode();
        if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref dm)) { return null; }
        return new int[] { dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayOrientation, dm.dmDisplayFrequency };
    }

    // Modalita distinte nell'orientamento corrente: { larghezza, altezza, frequenza massima }.
    public static List<int[]> Modes()
    {
        List<int[]> result = new List<int[]>();
        Dictionary<long, int[]> seen = new Dictionary<long, int[]>();
        int i = 0;
        while (true)
        {
            DEVMODE dm = NewDevMode();
            if (!EnumDisplaySettings(null, i, ref dm)) { break; }
            i++;
            long key = ((long)dm.dmPelsWidth << 32) | (long)(uint)dm.dmPelsHeight;
            int[] entry;
            if (seen.TryGetValue(key, out entry))
            {
                if (dm.dmDisplayFrequency > entry[2]) { entry[2] = dm.dmDisplayFrequency; }
            }
            else
            {
                entry = new int[] { dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency };
                seen[key] = entry;
                result.Add(entry);
            }
        }
        return result;
    }

    // Parte dalle impostazioni correnti. Restituisce 0 se riuscito (DISP_CHANGE_SUCCESSFUL).
    public static int Apply(int width, int height, int orientation, int frequency, bool testOnly)
    {
        DEVMODE dm = NewDevMode();
        if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref dm)) { return -99; }
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        dm.dmDisplayOrientation = orientation;
        dm.dmPelsWidth = width;
        dm.dmPelsHeight = height;
        dm.dmFields = DM_DISPLAYORIENTATION | DM_PELSWIDTH | DM_PELSHEIGHT;
        if (frequency > 0)
        {
            dm.dmDisplayFrequency = frequency;
            dm.dmFields = dm.dmFields | DM_DISPLAYFREQUENCY;
        }
        int flags = testOnly ? CDS_TEST : CDS_UPDATEREGISTRY;
        return ChangeDisplaySettingsEx(null, ref dm, IntPtr.Zero, flags, IntPtr.Zero);
    }

    // MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2 | MB_SETFOREGROUND | MB_TOPMOST. 6 = Si, 7 = No, 32000 = tempo scaduto.
    public static int AskKeep(string text, string caption, int seconds)
    {
        uint type = 0x4 | 0x20 | 0x100 | 0x10000 | 0x40000;
        return MessageBoxTimeout(IntPtr.Zero, text, caption, type, 0, seconds * 1000);
    }
}
'@
}

# ---------------------------------------------------------------------------
# 3. Manifest dei 13 driver OneXPlayer 1S (ordine sequenziale ottimale)
# ---------------------------------------------------------------------------
$DriverDefinitions = @(
    [ordered]@{
        Order          = 1
        Id             = 'chipset'
        Name           = 'Intel Chipset Device Software'
        Category       = 'Sistema'
        PackageVersion = '10.1.18460.8229'
        ZipName        = 'chipset-10.1.18460.8229-public-mup.zip'
        SizeMB         = 3.4
        Method         = 'EXE'
        MethodLabel    = 'EXE Silenzioso'
        ExePath        = 'SetupChipset.exe'
        ExeArgs        = '/s /norestart /log "{LOG}"'
        OkCodes        = @(0, 1638)
        RebootCodes    = @(3010, 1641, 350)
        Essential      = $true
        # Gli INF del chipset hanno versioni proprie (es. 10.1.24.x), non confrontabili con quella
        # del pacchetto: la versione installata si legge solo dal registro Disinstallazione.
        RegistryVersionOnly = $true
        MatchNames     = @('Intel.*Chipset', 'Tiger Lake.*LPC', 'Tiger Lake.*SMBus', 'System Interrupt Controller')
        MatchInfs      = @('TigerLake', 'CannonLake', 'CometLake', 'IceLake')
        UninstallMatch = 'Intel\(R\) Chipset Device Software'
    },
    [ordered]@{
        Order          = 2
        Id             = 'serialio'
        Name           = 'Intel Serial IO (GPIO / I2C / SPI / UART)'
        Category       = 'Sistema'
        PackageVersion = '30.100.2013.5'
        ZipName        = 'serialio_30.100.2013.5_pv_tgl-lp_20h1.zip'
        SizeMB         = 2.5
        Method         = 'EXE'
        MethodLabel    = 'EXE Silenzioso'
        ExePath        = 'SerialIO_30.100.2013.5_PV_TGL-LP_20H1\SetupSerialIO.exe'
        ExeArgs        = '/s /report "{LOG}"'
        OkCodes        = @(0, 9999)
        RebootCodes    = @(3010, 1641)
        Essential      = $true
        MatchNames     = @('Intel\(R\) Serial IO')
        MatchInfs      = @('iaLPSS2_')
        UninstallMatch = 'Intel\(R\) Serial IO'
    },
    [ordered]@{
        Order          = 3
        Id             = 'csme'
        Name           = 'Intel Management Engine (MEI + DAL + iCLS)'
        Category       = 'Sistema'
        PackageVersion = '2108.100.0.1053'
        ZipName        = 'me_2108.100.0.1053_tgl.zip'
        SizeMB         = 17.9
        Method         = 'INF'
        MethodLabel    = 'INF (pnputil)'
        InfTargets     = @(
            @{ Path = 'MEI\win10\heci.inf'; Subdirs = $false },
            @{ Path = 'JHI\win10\DAL.inf'; Subdirs = $false },
            @{ Path = 'ICLS\iclsClient.inf'; Subdirs = $false }
        )
        Essential      = $true
        MatchNames     = @('Intel\(R\) Management Engine Interface')
        MatchInfs      = @('heci\.inf')
        UninstallMatch = 'Intel\(R\) Management Engine'
    },
    [ordered]@{
        Order          = 4
        Id             = 'gna'
        Name           = 'Intel GNA Scoring Accelerator'
        Category       = 'Sistema'
        PackageVersion = '02.00.00.1010'
        ZipName        = 'intel(r)gna_pvcandidate_02.00.00.1010.zip'
        AssetName      = 'intel.r.gna_pvcandidate_02.00.00.1010.zip'
        SizeMB         = 0.5
        Method         = 'INF'
        MethodLabel    = 'INF (pnputil)'
        InfTargets     = @(
            @{ Path = 'Intel(R)GNA_PVCandidate_02.00.00.1010\gna.inf'; Subdirs = $false }
        )
        Essential      = $false
        MatchNames     = @('Intel\(R\) GNA')
        MatchInfs      = @('gna\.inf')
        UninstallMatch = ''
    },
    [ordered]@{
        Order          = 5
        Id             = 'dtt'
        Name           = 'Intel Dynamic Tuning Technology (DTT)'
        Category       = 'Sistema'
        PackageVersion = '8.7.10400.15556'
        ZipName        = 'intel(r)_dtt_8.7.10400.15556.zip'
        AssetName      = 'intel.r._dtt_8.7.10400.15556.zip'
        SizeMB         = 41.3
        Method         = 'EXE'
        MethodLabel    = 'EXE Silenzioso (Core)'
        ExePath        = 'driver\Dtt_8.7.10400.15556_Install.exe'
        ExeArgs        = '/s /report "{LOG}"'
        OkCodes        = @(0, 7)
        RebootCodes    = @(14, 15, 3010, 1641)
        Essential      = $true
        MatchNames     = @('Intel\(R\) Dynamic Tuning')
        MatchInfs      = @('dptf_acpi\.inf', 'dptf_cpu\.inf')
        UninstallMatch = 'Intel\(R\) Dynamic Tuning'
    },
    [ordered]@{
        Order          = 6
        Id             = 'igfx'
        Name           = 'Intel Iris Xe Graphics'
        Category       = 'Grafica & Audio'
        PackageVersion = '27.20.100.9616'
        ZipName        = 'igfx_win10_100.9616.zip'
        SizeMB         = 445.1
        Method         = 'INF'
        MethodLabel    = 'INF (pnputil)'
        InfTargets     = @(
            @{ Path = 'Graphics\iigd_dch.inf'; Subdirs = $false },
            @{ Path = 'Graphics\HdBusExt.inf'; Subdirs = $false },
            @{ Path = 'Graphics\cui_dch.inf'; Subdirs = $false },
            @{ Path = 'Graphics\igcc_dch.inf'; Subdirs = $false },
            @{ Path = 'Graphics\GSCAuxDriver.inf'; Subdirs = $false },
            @{ Path = 'Graphics\gscheci.inf'; Subdirs = $false },
            @{ Path = 'Graphics\memcntrl.inf'; Subdirs = $false },
            @{ Path = 'Graphics\MSHdaDac.inf'; Subdirs = $false },
            @{ Path = 'Graphics\MiniCtaDriver\MiniCtaDriver.inf'; Subdirs = $false },
            @{ Path = 'Graphics\DisplayAudio\11.2\IntcDAud.inf'; Subdirs = $false }
        )
        Essential      = $true
        MatchNames     = @('Intel\(R\) Iris\(R\) Xe', 'Intel\(R\) UHD Graphics')
        MatchInfs      = @('iigd_dch\.inf')
        UninstallMatch = ''
    },
    [ordered]@{
        Order          = 7
        Id             = 'audio'
        Name           = 'Realtek High Definition Audio'
        Category       = 'Grafica & Audio'
        PackageVersion = '6.0.1.7541'
        ZipName        = 'Audio_2015.6.18_6.0.1.7541.zip'
        SizeMB         = 196.5
        Method         = 'INF'
        MethodLabel    = 'INF (pnputil)'
        InfTargets     = @(
            @{ Path = 'Audio_2015.6.18_6.0.1.7541\Setup\Vista64\*.inf'; Subdirs = $false }
        )
        Essential      = $false
        MatchNames     = @('Realtek.*Audio')
        MatchInfs      = @('hdx.*\.inf')
        UninstallMatch = ''
    },
    [ordered]@{
        Order          = 8
        Id             = 'wifi'
        Name           = 'Intel Wi-Fi (UWD Win64)'
        Category       = 'Connettivita'
        PackageVersion = '21.110.1.1'
        ZipName        = 'wifi-phwfw01690_21.110.1.1_g.zip'
        SizeMB         = 66.0
        Method         = 'INF'
        MethodLabel    = 'INF (pnputil)'
        InfTargets     = @(
            @{ Path = 'UWD\Win64\Drivers\*.INF'; Subdirs = $false }
        )
        Essential      = $true
        MatchNames     = @('Intel\(R\) Wi-Fi')
        MatchInfs      = @('netwtw0[468]\.inf')
        UninstallMatch = ''
    },
    [ordered]@{
        Order          = 9
        Id             = 'bt'
        Name           = 'Intel Wireless Bluetooth (UWD x64)'
        Category       = 'Connettivita'
        PackageVersion = '21.110.0.3'
        ZipName        = 'bt-phbtw12144_21.110.0.3g.zip'
        SizeMB         = 95.7
        Method         = 'INF'
        MethodLabel    = 'INF (pnputil)'
        InfTargets     = @(
            @{ Path = 'INF_INSTALL\Win10_UWD\x64\*.inf'; Subdirs = $true }
        )
        Essential      = $true
        MatchNames     = @('Intel\(R\) Wireless Bluetooth')
        MatchInfs      = @('ibtusb\.inf', 'ibtuart\.inf')
        UninstallMatch = ''
    },
    [ordered]@{
        Order          = 10
        Id             = 'tbt'
        Name           = 'Intel Thunderbolt DCH'
        Category       = 'Porte & Sensori'
        PackageVersion = '1.41.1054.0'
        ZipName        = 'tbt_dch_1.41.1054.0.zip'
        SizeMB         = 1.4
        Method         = 'INF'
        MethodLabel    = 'INF (pnputil)'
        InfTargets     = @(
            @{ Path = 'ThunderboltWindowsDchSetup\TbtHostController.inf'; Subdirs = $false },
            @{ Path = 'ThunderboltWindowsDchSetup\TbtP2pNdisDrv.inf'; Subdirs = $false },
            @{ Path = 'ThunderboltApplicationLauncherSetup\TbtHostControllerExtension.inf'; Subdirs = $false }
        )
        Essential      = $false
        MatchNames     = @('Thunderbolt\(TM\) Controller')
        MatchInfs      = @('tbthostcontroller\.inf')
        UninstallMatch = ''
    },
    [ordered]@{
        Order          = 11
        Id             = 'cardreader'
        Name           = 'Realtek PCIE / USB Card Reader'
        Category       = 'Porte & Sensori'
        PackageVersion = 'RtsUer'
        DetectVersion  = '10.0.19041.31261' # DriverVer di RtsUer.inf
        ZipName        = '9.Cardreader.zip'
        SizeMB         = 2.0
        Method         = 'INF'
        MethodLabel    = 'INF (pnputil)'
        InfTargets     = @(
            @{ Path = '9.Cardreader\Drivers\RtsUer.inf'; Subdirs = $false }
        )
        Essential      = $false
        MatchNames     = @('Realtek.*CardReader', 'Realtek.*Card Reader')
        MatchInfs      = @('rtsuer\.inf')
        UninstallMatch = ''
    },
    [ordered]@{
        Order          = 12
        Id             = 'bosch'
        Name           = 'Bosch BMA2x2 Accelerometer'
        Category       = 'Porte & Sensori'
        PackageVersion = '1.0.1.2'
        ZipName        = 'boschaccelerometer.zip'
        SizeMB         = 0.5
        Method         = 'INF'
        MethodLabel    = 'INF (pnputil)'
        InfTargets     = @(
            @{ Path = 'boschaccelerometer\UMDF_2.0_BMA2x2_1.0.1.2_RS5_signed\package\BoschAccelerometer.inf'; Subdirs = $false }
        )
        Essential      = $false
        MatchNames     = @('Bosch.*Accelerometer', 'BMA2x2')
        MatchInfs      = @('boschaccelerometer\.inf')
        UninstallMatch = ''
    },
    [ordered]@{
        Order          = 13
        Id             = 'fingerprint'
        Name           = 'FocalTech Fingerprint Reader'
        Category       = 'Porte & Sensori'
        PackageVersion = '2.0.3.71'
        ZipName        = 'fingerprint_focaltech_2.0.3.71.zip'
        SizeMB         = 0.5
        Method         = 'INF'
        MethodLabel    = 'INF (pnputil)'
        InfTargets     = @(
            @{ Path = 'ftWbioUmdfDriverV2.inf'; Subdirs = $false }
        )
        Essential      = $false
        MatchNames     = @('FocalTech.*Fingerprint')
        MatchInfs      = @('ftwbioumdfdriverv2\.inf')
        UninstallMatch = ''
    }
)

# ---------------------------------------------------------------------------
# 3b. Manifest dei programmi per giocare (installati con winget)
# ---------------------------------------------------------------------------
$AppDefinitions = @(
    [ordered]@{ Order = 1;  Id = 'Microsoft.VCRedist.2015+.x64'; Source = 'winget'; Name = 'Visual C++ 2015-2022 (x64)'; Category = 'Librerie'
        Purpose = 'Libreria richiesta da moltissimi giochi e programmi'; Recommended = $true },
    [ordered]@{ Order = 2;  Id = 'Microsoft.VCRedist.2015+.x86'; Source = 'winget'; Name = 'Visual C++ 2015-2022 (x86)'; Category = 'Librerie'
        Purpose = 'Come sopra, per i programmi a 32 bit'; Recommended = $true },
    [ordered]@{ Order = 3;  Id = 'Microsoft.DirectX'; Source = 'winget'; Name = 'DirectX End-User Runtime'; Category = 'Librerie'
        Purpose = 'Componenti DirectX storici che servono a molti giochi'; Recommended = $true },
    [ordered]@{ Order = 4;  Id = 'Microsoft.DotNet.DesktopRuntime.8'; Source = 'winget'; Name = '.NET Desktop Runtime 8'; Category = 'Librerie'
        Purpose = 'Serve a Playnite, Handheld Companion e altri programmi'; Recommended = $true },
    [ordered]@{ Order = 5;  Id = 'Intel.IntelDriverAndSupportAssistant'; Source = 'winget'; Name = 'Intel Driver & Support Assistant'; Category = 'Grafica'
        Purpose = 'Aggiorna grafica Iris Xe, Wi-Fi e Bluetooth alle versioni Intel correnti'; Recommended = $true },
    [ordered]@{ Order = 6;  Id = '9PLFNLNT3G5G'; Source = 'msstore'; Name = 'Intel Graphics Command Center'; Category = 'Grafica'
        Purpose = 'Scalatura a numeri interi per giocare a 1280x800 senza sfocature'; Recommended = $true
        AppxName = 'AppUp.IntelGraphicsExperience' },
    [ordered]@{ Order = 7;  Id = 'Valve.Steam'; Source = 'winget'; Name = 'Steam'; Category = 'Negozi'
        Purpose = 'Negozio e libreria di giochi Valve, con modalita Big Picture'; Recommended = $true },
    [ordered]@{ Order = 8;  Id = 'Playnite.Playnite'; Source = 'winget'; Name = 'Playnite'; Category = 'Negozi'
        Purpose = 'Libreria unica a schermo intero per tutti i negozi e gli emulatori'; Recommended = $true },
    [ordered]@{ Order = 9;  Id = 'HeroicGamesLauncher.HeroicGamesLauncher'; Source = 'winget'; Name = 'Heroic Games Launcher'; Category = 'Negozi'
        Purpose = 'Epic, GOG e Amazon Games in un solo programma leggero'; Recommended = $false },
    [ordered]@{ Order = 10; Id = 'GOG.Galaxy'; Source = 'winget'; Name = 'GOG Galaxy'; Category = 'Negozi'
        Purpose = 'Negozio e libreria dei giochi GOG'; Recommended = $false },
    [ordered]@{ Order = 11; Id = 'EpicGames.EpicGamesLauncher'; Source = 'winget'; Name = 'Epic Games Launcher'; Category = 'Negozi'
        Purpose = 'Negozio Epic, con i giochi gratuiti della settimana'; Recommended = $false },
    [ordered]@{ Order = 12; Id = 'ElectronicArts.EADesktop'; Source = 'winget'; Name = 'EA app'; Category = 'Negozi'
        Purpose = 'Negozio e libreria dei giochi Electronic Arts'; Recommended = $false },
    [ordered]@{ Order = 13; Id = 'Ubisoft.Connect'; Source = 'winget'; Name = 'Ubisoft Connect'; Category = 'Negozi'
        Purpose = 'Negozio e libreria dei giochi Ubisoft'; Recommended = $false },
    [ordered]@{ Order = 14; Id = 'Guru3D.RTSS'; Source = 'winget'; Name = 'RivaTuner Statistics Server'; Category = 'Prestazioni'
        Purpose = 'Limite di FPS per allungare la batteria e contatore a schermo'; Recommended = $true },
    [ordered]@{ Order = 15; Id = 'Guru3D.Afterburner'; Source = 'winget'; Name = 'MSI Afterburner'; Category = 'Prestazioni'
        Purpose = 'Monitoraggio a schermo di temperature, FPS e carico'; Recommended = $false },
    [ordered]@{ Order = 16; Id = 'REALiX.HWiNFO'; Source = 'winget'; Name = 'HWiNFO'; Category = 'Prestazioni'
        Purpose = 'Sensori dettagliati: temperature, consumi e frequenze'; Recommended = $false },
    [ordered]@{ Order = 17; Id = 'BenjaminLSR.HandheldCompanion'; Source = 'winget'; Name = 'Handheld Companion'; Category = 'Prestazioni'
        Purpose = 'Controllo TDP e giroscopio. Il 1S non e tra i dispositivi elencati: da provare'; Recommended = $false },
    [ordered]@{ Order = 18; Id = 'TechPowerUp.ThrottleStop'; Source = 'winget'; Name = 'ThrottleStop'; Category = 'Prestazioni'
        Purpose = 'Limiti di potenza della CPU, da regolare a mano con cautela'; Recommended = $false },
    [ordered]@{ Order = 19; Id = 'Nvidia.GeForceNow'; Source = 'winget'; Name = 'GeForce NOW'; Category = 'Streaming'
        Purpose = 'Giochi in streaming dal cloud NVIDIA'; Recommended = $false },
    [ordered]@{ Order = 20; Id = 'MoonlightGameStreamingProject.Moonlight'; Source = 'winget'; Name = 'Moonlight'; Category = 'Streaming'
        Purpose = 'Giochi in streaming da un PC di casa (Sunshine o NVIDIA)'; Recommended = $false },
    [ordered]@{ Order = 21; Id = 'Libretro.RetroArch'; Source = 'winget'; Name = 'RetroArch'; Category = 'Emulazione'
        Purpose = 'Emulatore multi-sistema per i giochi retro'; Recommended = $false },
    [ordered]@{ Order = 22; Id = 'PCSX2Team.PCSX2'; Source = 'winget'; Name = 'PCSX2'; Category = 'Emulazione'
        Purpose = 'Emulatore di PlayStation 2'; Recommended = $false },
    [ordered]@{ Order = 23; Id = '7zip.7zip'; Source = 'winget'; Name = '7-Zip'; Category = 'Utilita'
        Purpose = 'Apre e crea archivi ZIP, 7z, RAR e altri'; Recommended = $true }
)

# ---------------------------------------------------------------------------
# 4. Rilevamento stato driver sul sistema Windows 11
# ---------------------------------------------------------------------------
function Get-SystemDriverSnapshot {
    $signedDrivers = @()
    $pnpErrors     = @()
    $uninstallApps = @()

    try { $signedDrivers = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction SilentlyContinue) } catch {}

    # Solo dispositivi presenti e davvero in errore: senza -PresentOnly entrano nel conto anche
    # tutti quelli scollegati (Status 'Unknown'). Quelli disattivati a mano non sono errori.
    try {
        $pnpErrors = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
            ($_.Status -eq 'Error' -or $_.Status -eq 'Degraded') -and "$($_.Problem)" -ne 'CM_PROB_DISABLED'
        })
    } catch {}

    # Win32_PnPSignedDriver.InfName riporta il nome pubblicato (oemNN.inf) e non quello originale:
    # la corrispondenza oemNN.inf -> nome originale sta nel registro del Driver Store.
    $infOriginal = @{}
    try {
        foreach ($k in @(Get-ChildItem -Path 'HKLM:\SYSTEM\DriverDatabase\DriverInfFiles' -ErrorAction SilentlyContinue)) {
            $active = [string]$k.GetValue('Active')
            if ($active -match '^(.+?\.inf)_') { $infOriginal[$k.PSChildName.ToLowerInvariant()] = $Matches[1] }
        }
    } catch {}

    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($rp in $regPaths) {
        try {
            $uninstallApps += Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } |
                Select-Object DisplayName, DisplayVersion
        } catch {}
    }

    return [PSCustomObject]@{
        SignedDrivers = $signedDrivers
        PnpErrors     = $pnpErrors
        UninstallApps = $uninstallApps
        InfOriginal   = $infOriginal
    }
}

function Compare-DriverVersionSafe {
    param([string]$Installed, [string]$Package)
    if (-not $Installed -or -not $Package) { return 0 }
    try {
        $vInst = [version]($Installed -replace '[^\d\.]', '')
        $vPkg  = [version]($Package   -replace '[^\d\.]', '')
        if ($vInst -gt $vPkg) { return 1 }
        if ($vInst -lt $vPkg) { return -1 }
        return 0
    } catch {
        return 0
    }
}

function Update-DriverDetection {
    param([System.Collections.ObjectModel.ObservableCollection[object]]$Items)

    $snap = Get-SystemDriverSnapshot

    foreach ($item in $Items) {
        $def = $item.Def
        $foundVer = $null
        $matchedIds = @{}

        # 1) Cerca tra i driver firmati attivi (per nome INF originale, poi per nome del dispositivo)
        foreach ($d in $snap.SignedDrivers) {
            $hit = $false
            if ($d.InfName) {
                $infName = $snap.InfOriginal[$d.InfName.ToLowerInvariant()]
                if (-not $infName) { $infName = $d.InfName }
                foreach ($rx in $def.MatchInfs) {
                    if ($infName -imatch $rx) { $hit = $true; break }
                }
            }
            if (-not $hit -and $d.DeviceName) {
                foreach ($rx in $def.MatchNames) {
                    if ($d.DeviceName -imatch $rx) { $hit = $true; break }
                }
            }
            if ($hit) {
                if ($d.DeviceID) { $matchedIds[$d.DeviceID.ToUpperInvariant()] = $true }
                if (-not $foundVer -and $d.DriverVersion -and -not $def.RegistryVersionOnly) {
                    $foundVer = $d.DriverVersion
                }
            }
        }

        # 2) Fallback su registro Disinstallazione (es. Chipset INF che non ha un unico device driver)
        if (-not $foundVer -and $def.UninstallMatch) {
            foreach ($app in $snap.UninstallApps) {
                if ($app.DisplayName -imatch $def.UninstallMatch) {
                    $foundVer = if ($app.DisplayVersion) { $app.DisplayVersion } else { 'Installato' }
                    break
                }
            }
        }

        # 3) Controlla se ci sono errori PnP correlati (stesso dispositivo trovato sopra, o stesso nome)
        $hasError = $false
        foreach ($pe in $snap.PnpErrors) {
            if ($pe.InstanceId -and $matchedIds.ContainsKey($pe.InstanceId.ToUpperInvariant())) { $hasError = $true; break }
            foreach ($rx in $def.MatchNames) {
                if ($pe.FriendlyName -imatch $rx) { $hasError = $true; break }
            }
            if ($hasError) { break }
        }

        if ($hasError) {
            $item.SystemStatus = "Errore dispositivo (!)"
            $item.NeedsInstall = $true
        } elseif ($foundVer) {
            $pkgVer = if ($def.DetectVersion) { $def.DetectVersion } else { $def.PackageVersion }
            $cmp = Compare-DriverVersionSafe -Installed $foundVer -Package $pkgVer
            if ($cmp -lt 0) {
                $item.SystemStatus = "Aggiornabile ($foundVer)"
                $item.NeedsInstall = $true
            } else {
                $item.SystemStatus = "Installato ($foundVer)"
                $item.NeedsInstall = $false
            }
        } else {
            $item.SystemStatus = "Non rilevato"
            $item.NeedsInstall = $true
        }
    }

    return $snap.PnpErrors.Count
}

# ---------------------------------------------------------------------------
# 5. Costruzione Modello Dati per la GUI
# ---------------------------------------------------------------------------
$BaseScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$DriverItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'

foreach ($d in $DriverDefinitions) {
    $DriverItems.Add([PSCustomObject]@{
        IsSelected     = $true
        Order          = $d.Order
        Id             = $d.Id
        Name           = $d.Name
        Category       = $d.Category
        PackageVersion = $d.PackageVersion
        SizeLabel      = "{0:N1} MB" -f $d.SizeMB
        MethodLabel    = $d.MethodLabel
        SystemStatus   = "Analisi..."
        RunStatus      = "In attesa"
        NeedsInstall   = $true
        Def            = $d
    })
}

$pnpErrCount = Update-DriverDetection -Items $DriverItems

$AppItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[object]'
foreach ($a in $AppDefinitions) {
    $AppItems.Add([PSCustomObject]@{
        IsSelected   = [bool]$a.Recommended
        Order        = $a.Order
        Id           = $a.Id
        Name         = $a.Name
        Category     = $a.Category
        Purpose      = $a.Purpose
        SystemStatus = "Analisi..."
        RunStatus    = "In attesa"
        Def          = $a
    })
}

# Pre-seleziona di default quelli mancanti/aggiornabili se almeno uno manca, altrimenti tutti deselezionati?
# L'utente ha chiesto la possibilita di installarli tutti uno dopo l'altro: lasciamo selezionati i mancanti o tutti.
# Se tutti risultano mancanti (fresh install) sono gia tutti selezionati.

# ---------------------------------------------------------------------------
# 6. Definizione Interfaccia WPF (XAML stile Chris Titus WinUtil)
# ---------------------------------------------------------------------------
[xml]$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OneXPlayer 1S - Utility (Windows 11)"
        Width="1080" Height="780"
        MinWidth="900" MinHeight="620"
        WindowStartupLocation="CenterScreen"
        Background="#0F172A" Foreground="#F8FAFC"
        FontFamily="Segoe UI"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
    <Window.Resources>
        <Style TargetType="Button" x:Key="ToolbarBtn">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="BorderBrush" Value="#334155"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Margin" Value="0,0,8,0"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#334155"/>
                                <Setter Property="BorderBrush" Value="#38BDF8"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="Button" x:Key="PrimaryBtn" BasedOn="{StaticResource ToolbarBtn}">
            <Setter Property="Background" Value="#16A34A"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#22C55E"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="18,8"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#15803D"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="Button" x:Key="DangerBtn" BasedOn="{StaticResource ToolbarBtn}">
            <Setter Property="Background" Value="#DC2626"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#EF4444"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="16,8"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#B91C1C"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#CBD5E1"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Margin" Value="0,0,16,0"/>
        </Style>

        <!-- Schede (TabControl) a tema scuro -->
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabControl">
                        <Grid KeyboardNavigation.TabNavigation="Local">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TabPanel Grid.Row="0" IsItemsHost="True" Margin="0,0,0,8" Background="Transparent"/>
                            <ContentPresenter Grid.Row="1" ContentSource="SelectedContent"/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="TabBd" Background="#1E293B" BorderBrush="#334155" BorderThickness="1"
                                CornerRadius="6" Padding="24,8" Margin="0,0,6,0">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="TabBd" Property="Background" Value="#334155"/>
                                <Setter Property="Foreground" Value="#F8FAFC"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="TabBd" Property="Background" Value="#0C4A6E"/>
                                <Setter TargetName="TabBd" Property="BorderBrush" Value="#38BDF8"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Stili condivisi dalle due griglie (Driver e Gioco) -->
        <Style x:Key="GridHeaderStyle" TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#0F172A"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="8,7"/>
            <Setter Property="BorderBrush" Value="#334155"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
        </Style>

        <Style x:Key="GridCellStyle" TargetType="DataGridCell">
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="6,2"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#25344D"/>
                    <Setter Property="Foreground" Value="#FFFFFF"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="CellText" TargetType="TextBlock">
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="2,0"/>
        </Style>

        <Style x:Key="CellTextWrap" TargetType="TextBlock" BasedOn="{StaticResource CellText}">
            <Setter Property="TextWrapping" Value="Wrap"/>
            <Setter Property="Margin" Value="2,4"/>
        </Style>

        <Style x:Key="CellCheck" TargetType="CheckBox">
            <Setter Property="HorizontalAlignment" Value="Center"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="0"/>
        </Style>

        <Style x:Key="DarkGrid" TargetType="DataGrid">
            <Setter Property="AutoGenerateColumns" Value="False"/>
            <Setter Property="CanUserAddRows" Value="False"/>
            <Setter Property="CanUserDeleteRows" Value="False"/>
            <Setter Property="CanUserReorderColumns" Value="False"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="GridLinesVisibility" Value="Horizontal"/>
            <Setter Property="HorizontalGridLinesBrush" Value="#334155"/>
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="RowBackground" Value="#1E293B"/>
            <Setter Property="AlternatingRowBackground" Value="#162032"/>
            <Setter Property="Foreground" Value="#F8FAFC"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="SelectionMode" Value="Single"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="MinRowHeight" Value="30"/>
            <Setter Property="ColumnHeaderStyle" Value="{StaticResource GridHeaderStyle}"/>
            <Setter Property="CellStyle" Value="{StaticResource GridCellStyle}"/>
        </Style>

        <Style x:Key="CardTitle" TargetType="TextBlock">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="#38BDF8"/>
            <Setter Property="Margin" Value="0,0,0,6"/>
        </Style>

        <Style x:Key="CardHint" TargetType="TextBlock">
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
        </Style>

        <!-- Barre di scorrimento scure -->
        <SolidColorBrush x:Key="{x:Static SystemColors.ControlBrushKey}" Color="#0F172A"/>
        <Style x:Key="ScrollThumbStyle" TargetType="Thumb">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border Background="#475569" CornerRadius="4" Margin="2"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScrollPageStyle" TargetType="RepeatButton">
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton">
                        <Border Background="Transparent"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="#0F172A"/>
            <Setter Property="Width" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Border Background="#0F172A">
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageUpCommand" Style="{StaticResource ScrollPageStyle}"/>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Style="{StaticResource ScrollThumbStyle}"/>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageDownCommand" Style="{StaticResource ScrollPageStyle}"/>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Horizontal">
                    <Setter Property="Width" Value="Auto"/>
                    <Setter Property="Height" Value="12"/>
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="ScrollBar">
                                <Border Background="#0F172A">
                                    <Track x:Name="PART_Track" IsDirectionReversed="False">
                                        <Track.DecreaseRepeatButton>
                                            <RepeatButton Command="ScrollBar.PageLeftCommand" Style="{StaticResource ScrollPageStyle}"/>
                                        </Track.DecreaseRepeatButton>
                                        <Track.Thumb>
                                            <Thumb Style="{StaticResource ScrollThumbStyle}"/>
                                        </Track.Thumb>
                                        <Track.IncreaseRepeatButton>
                                            <RepeatButton Command="ScrollBar.PageRightCommand" Style="{StaticResource ScrollPageStyle}"/>
                                        </Track.IncreaseRepeatButton>
                                    </Track>
                                </Border>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="140"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- HEADER -->
        <Border Grid.Row="0" Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="16,12" Margin="0,0,0,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="OneXPlayer 1S - Utility" FontSize="20" FontWeight="Bold" Foreground="#38BDF8"/>
                    <TextBlock x:Name="TxtSubtitle" Text="Driver, programmi per giocare e impostazioni dello schermo per Windows 11"
                               FontSize="12" Foreground="#94A3B8" Margin="0,2,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" VerticalAlignment="Center" HorizontalAlignment="Right">
                    <TextBlock x:Name="TxtSystemInfo" Text="Admin OK" FontSize="12" FontWeight="SemiBold" Foreground="#4ADE80" HorizontalAlignment="Right"/>
                    <TextBlock x:Name="TxtPnpWarnings" Text="Dispositivi con errori: 0" FontSize="11" Foreground="#94A3B8" HorizontalAlignment="Right" Margin="0,2,0,0"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- SCHEDE: DRIVER / GIOCO / SCHERMO -->
        <TabControl x:Name="MainTabs" Grid.Row="1" Grid.RowSpan="2" Margin="0,0,0,10">

            <!-- ===================== SCHEDA DRIVER ===================== -->
            <TabItem Header="Driver">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- TOOLBAR PRESET E OPZIONI -->
                    <Border Grid.Row="0" Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="12,10" Margin="0,0,0,10">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <WrapPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
                                <Button x:Name="BtnSelectAll" Content="Seleziona Tutti (13)" Style="{StaticResource ToolbarBtn}"/>
                                <Button x:Name="BtnSelectMissing" Content="Solo Mancanti / Aggiornabili" Style="{StaticResource ToolbarBtn}"/>
                                <Button x:Name="BtnSelectEssential" Content="Solo Essenziali (Core + Rete + GPU)" Style="{StaticResource ToolbarBtn}"/>
                                <Button x:Name="BtnSelectNone" Content="Deseleziona Tutto" Style="{StaticResource ToolbarBtn}"/>
                                <Button x:Name="BtnRefresh" Content="Aggiorna Rilevamento" Style="{StaticResource ToolbarBtn}"/>
                                <Button x:Name="BtnDevMgmt" Content="Gestione Dispositivi" Style="{StaticResource ToolbarBtn}"/>
                            </WrapPanel>
                            <WrapPanel Grid.Row="1" Orientation="Horizontal">
                                <CheckBox x:Name="ChkRestorePoint" Content="Crea Punto di Ripristino prima di iniziare" IsChecked="True"/>
                                <CheckBox x:Name="ChkUseLocal" Content="Usa .zip locali se presenti (cartella 'drivers' o corrente)" IsChecked="True"/>
                                <CheckBox x:Name="ChkCleanup" Content="Elimina file temporanei al termine" IsChecked="True"/>
                            </WrapPanel>
                        </Grid>
                    </Border>

                    <!-- LISTA DRIVER -->
                    <Border Grid.Row="1" Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="4">
                        <DataGrid x:Name="GridDrivers" Style="{StaticResource DarkGrid}" RowHeight="30">
                            <DataGrid.Columns>
                                <DataGridCheckBoxColumn Header="Sel." Binding="{Binding IsSelected, UpdateSourceTrigger=PropertyChanged}" Width="46"
                                                        ElementStyle="{StaticResource CellCheck}" EditingElementStyle="{StaticResource CellCheck}"/>
                                <DataGridTextColumn Header="#" Binding="{Binding Order}" IsReadOnly="True" Width="32" ElementStyle="{StaticResource CellText}"/>
                                <DataGridTextColumn Header="Driver" Binding="{Binding Name}" IsReadOnly="True" Width="290" ElementStyle="{StaticResource CellText}"/>
                                <DataGridTextColumn Header="Categoria" Binding="{Binding Category}" IsReadOnly="True" Width="105" ElementStyle="{StaticResource CellText}"/>
                                <DataGridTextColumn Header="Versione" Binding="{Binding PackageVersion}" IsReadOnly="True" Width="110" ElementStyle="{StaticResource CellText}"/>
                                <DataGridTextColumn Header="Metodo" Binding="{Binding MethodLabel}" IsReadOnly="True" Width="130" ElementStyle="{StaticResource CellText}"/>
                                <DataGridTextColumn Header="Stato sul PC" Binding="{Binding SystemStatus}" IsReadOnly="True" Width="170" ElementStyle="{StaticResource CellText}"/>
                                <DataGridTextColumn Header="Avanzamento" Binding="{Binding RunStatus}" IsReadOnly="True" Width="*" ElementStyle="{StaticResource CellText}"/>
                            </DataGrid.Columns>
                        </DataGrid>
                    </Border>
                </Grid>
            </TabItem>

            <!-- ===================== SCHEDA GIOCO ===================== -->
            <TabItem Header="Gioco">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="12,10" Margin="0,0,0,10">
                        <WrapPanel Orientation="Horizontal">
                            <Button x:Name="BtnAppRecommended" Content="Consigliati" Style="{StaticResource ToolbarBtn}"/>
                            <Button x:Name="BtnAppAll" Content="Tutti" Style="{StaticResource ToolbarBtn}"/>
                            <Button x:Name="BtnAppNone" Content="Nessuno" Style="{StaticResource ToolbarBtn}"/>
                            <Button x:Name="BtnAppRefresh" Content="Aggiorna stato" Style="{StaticResource ToolbarBtn}"/>
                            <TextBlock Text="Installazione con winget (serve la connessione a Internet)." VerticalAlignment="Center"
                                       FontSize="11.5" Foreground="#94A3B8" Margin="4,0,0,0"/>
                        </WrapPanel>
                    </Border>

                    <Border Grid.Row="1" Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="4">
                        <DataGrid x:Name="GridApps" Style="{StaticResource DarkGrid}">
                            <DataGrid.Columns>
                                <DataGridCheckBoxColumn Header="Sel." Binding="{Binding IsSelected, UpdateSourceTrigger=PropertyChanged}" Width="46"
                                                        ElementStyle="{StaticResource CellCheck}" EditingElementStyle="{StaticResource CellCheck}"/>
                                <DataGridTextColumn Header="Programma" Binding="{Binding Name}" IsReadOnly="True" Width="215" ElementStyle="{StaticResource CellTextWrap}"/>
                                <DataGridTextColumn Header="Categoria" Binding="{Binding Category}" IsReadOnly="True" Width="95" ElementStyle="{StaticResource CellText}"/>
                                <DataGridTextColumn Header="A cosa serve" Binding="{Binding Purpose}" IsReadOnly="True" Width="*" ElementStyle="{StaticResource CellTextWrap}"/>
                                <DataGridTextColumn Header="Stato sul PC" Binding="{Binding SystemStatus}" IsReadOnly="True" Width="115" ElementStyle="{StaticResource CellText}"/>
                                <DataGridTextColumn Header="Avanzamento" Binding="{Binding RunStatus}" IsReadOnly="True" Width="125" ElementStyle="{StaticResource CellText}"/>
                            </DataGrid.Columns>
                        </DataGrid>
                    </Border>
                </Grid>
            </TabItem>

            <!-- ===================== SCHEDA SCHERMO ===================== -->
            <TabItem Header="Schermo">
                <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                    <Grid Margin="0,0,4,0">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <Border Grid.Row="0" Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="14,8" Margin="0,0,0,8">
                            <StackPanel>
                                <TextBlock Text="Schermo attuale" Style="{StaticResource CardTitle}"/>
                                <TextBlock x:Name="TxtDisplayInfo" Text="Lettura in corso..." FontSize="13" Foreground="#F8FAFC" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Grid Grid.Row="1">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Column="0" Margin="0,0,4,0">
                                <Border Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="14,8" Margin="0,0,0,8">
                                    <StackPanel>
                                        <TextBlock Text="Orientamento" Style="{StaticResource CardTitle}"/>
                                        <TextBlock Style="{StaticResource CardHint}"
                                                   Text="Rotazioni relative all'orientamento attuale: se non e quello giusto, prova un altro pulsante."/>
                                        <WrapPanel Orientation="Horizontal">
                                            <Button x:Name="BtnRotate90" Content="Ruota di 90 gradi" Style="{StaticResource ToolbarBtn}" Margin="0,0,8,4"/>
                                            <Button x:Name="BtnRotate180" Content="Capovolgi (180 gradi)" Style="{StaticResource ToolbarBtn}" Margin="0,0,8,4"/>
                                            <Button x:Name="BtnRotate270" Content="Ruota di 270 gradi" Style="{StaticResource ToolbarBtn}" Margin="0,0,8,4"/>
                                        </WrapPanel>
                                    </StackPanel>
                                </Border>
                                <Border Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="14,8">
                                    <StackPanel>
                                        <TextBlock Text="Touch" Style="{StaticResource CardTitle}"/>
                                        <TextBlock x:Name="TxtTouchInfo" Text="Diagnosi in corso..." FontSize="12" Foreground="#F8FAFC" TextWrapping="Wrap" Margin="0,0,0,6"/>
                                        <WrapPanel Orientation="Horizontal">
                                            <Button x:Name="BtnTouchDiag" Content="Diagnosi touch" Style="{StaticResource ToolbarBtn}" Margin="0,0,8,4"/>
                                            <Button x:Name="BtnTouchRepair" Content="Ripara touch" Style="{StaticResource ToolbarBtn}" Margin="0,0,8,4"/>
                                        </WrapPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <StackPanel Grid.Column="1" Margin="4,0,0,0">
                                <Border Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="14,8" Margin="0,0,0,8">
                                    <StackPanel>
                                        <TextBlock Text="Risoluzione" Style="{StaticResource CardTitle}"/>
                                        <TextBlock Style="{StaticResource CardHint}"
                                                   Text="1280 x 800 e la meta esatta della nativa: con la scalatura a numeri interi di Intel Graphics Command Center resta nitida e i giochi girano molto piu leggeri."/>
                                        <WrapPanel Orientation="Horizontal">
                                            <Button x:Name="BtnResNative" Content="Nativa" Style="{StaticResource ToolbarBtn}" Margin="0,0,8,4"/>
                                            <Button x:Name="BtnRes1920" Content="1920 x 1200" Style="{StaticResource ToolbarBtn}" Margin="0,0,8,4"/>
                                            <Button x:Name="BtnRes1280" Content="1280 x 800" Style="{StaticResource ToolbarBtn}" Margin="0,0,8,4"/>
                                        </WrapPanel>
                                        <TextBlock Style="{StaticResource CardHint}" Margin="0,2,0,0"
                                                   Text="Ogni cambio chiede conferma per 15 secondi, altrimenti torna allo stato precedente."/>
                                    </StackPanel>
                                </Border>
                                <Border Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="14,8">
                                    <StackPanel>
                                        <TextBlock Text="Rotazione automatica" Style="{StaticResource CardTitle}"/>
                                        <TextBlock x:Name="TxtRotationLock" Text="Stato: lettura in corso..." FontSize="12" Foreground="#F8FAFC" TextWrapping="Wrap" Margin="0,0,0,6"/>
                                        <WrapPanel Orientation="Horizontal">
                                            <Button x:Name="BtnRotationLock" Content="Blocca rotazione automatica" Style="{StaticResource ToolbarBtn}" Margin="0,0,8,4"/>
                                        </WrapPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Grid>
                    </Grid>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- BARRA DI AVANZAMENTO -->
        <Border Grid.Row="3" Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="12,10" Margin="0,0,0,10">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid Grid.Row="0" Margin="0,0,0,6">
                    <TextBlock x:Name="TxtProgressTitle" Text="Pronto per l'installazione." FontSize="12.5" FontWeight="SemiBold" Foreground="#E2E8F0"/>
                    <TextBlock x:Name="TxtProgressCount" Text="0 / 0" FontSize="12" Foreground="#94A3B8" HorizontalAlignment="Right"/>
                </Grid>
                <ProgressBar x:Name="ProgressTotal" Grid.Row="1" Height="14" Minimum="0" Maximum="100" Value="0"
                             Background="#0F172A" Foreground="#22C55E" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,6"/>
                <Grid Grid.Row="2">
                    <ProgressBar x:Name="ProgressStep" Height="8" Minimum="0" Maximum="100" Value="0"
                                 Background="#0F172A" Foreground="#38BDF8" BorderBrush="#334155" BorderThickness="1"/>
                </Grid>
            </Grid>
        </Border>

        <!-- LOG IN TEMPO REALE -->
        <Border Grid.Row="4" Background="#090D16" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="8" Margin="0,0,0,10">
            <TextBox x:Name="TxtLog" IsReadOnly="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                     Background="Transparent" Foreground="#CBD5E1" BorderThickness="0"
                     FontFamily="Consolas" FontSize="11.5" TextWrapping="NoWrap"/>
        </Border>

        <!-- FOOTER PULSANTI -->
        <Grid Grid.Row="5">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="TxtFooterInfo" Grid.Column="0" VerticalAlignment="Center" FontSize="11.5" Foreground="#64748B"
                       Text="Nota: Intel PCH Chipset Init Kit (.bin OEM) escluso perche non installabile da Windows."/>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
                <Button x:Name="BtnCancel" Content="Annulla" Style="{StaticResource DangerBtn}" IsEnabled="False"/>
                <Button x:Name="BtnInstall" Content="Installa Driver Selezionati" Style="{StaticResource PrimaryBtn}" Margin="0" MinWidth="230"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)

$Ctrl = @{}
@(
    'TxtSubtitle', 'TxtSystemInfo', 'TxtPnpWarnings',
    'BtnSelectAll', 'BtnSelectMissing', 'BtnSelectEssential', 'BtnSelectNone', 'BtnRefresh', 'BtnDevMgmt',
    'ChkRestorePoint', 'ChkUseLocal', 'ChkCleanup',
    'GridDrivers', 'TxtProgressTitle', 'TxtProgressCount', 'ProgressTotal', 'ProgressStep',
    'TxtLog', 'TxtFooterInfo', 'BtnCancel', 'BtnInstall',
    'MainTabs', 'GridApps', 'BtnAppRecommended', 'BtnAppAll', 'BtnAppNone', 'BtnAppRefresh',
    'TxtDisplayInfo', 'BtnRotate90', 'BtnRotate180', 'BtnRotate270', 'TxtRotationLock', 'BtnRotationLock',
    'BtnResNative', 'BtnRes1920', 'BtnRes1280', 'TxtTouchInfo', 'BtnTouchDiag', 'BtnTouchRepair'
) | ForEach-Object { $Ctrl[$_] = $Window.FindName($_) }

$Ctrl.GridDrivers.ItemsSource = $DriverItems
$Ctrl.GridApps.ItemsSource = $AppItems

$osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$osLabel = if ($osInfo) { "$($osInfo.Caption) ($($osInfo.BuildNumber))" } else { "Windows 11" }
$Ctrl.TxtSystemInfo.Text = "Admin OK | $osLabel"
$Ctrl.TxtPnpWarnings.Text = "Dispositivi con errori/mancanti rilevati: $pnpErrCount"
$Ctrl.TxtPnpWarnings.Foreground = if ($pnpErrCount -gt 0) { '#FBBF24' } else { '#94A3B8' }

# ---------------------------------------------------------------------------
# 7. Stato condiviso per esecuzione asincrona (non blocca la UI WPF)
# ---------------------------------------------------------------------------
$Sync = [hashtable]::Synchronized(@{
    IsRunning       = $false
    CancelRequested = $false
    DirtyGrid       = $false
    DirtyApps       = $false
    Mode            = 'drivers'
    AppsDetected    = $false
    AppDetectRunning = $false
    DisplayShown    = $false
    LogQueue       = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    ProgressTitle   = "Pronto per l'installazione."
    ProgressCount   = "0 / 0"
    TotalPct        = 0
    StepPct         = 0
    Finished        = $false
    RebootNeeded    = $false
    SuccessCount    = 0
    ErrorCount      = 0
    LogFilePath     = ""
    Items           = $DriverItems
    AppItems        = $AppItems
    Runners         = @{}
})

function Write-UiLog {
    param([string]$Message)
    $ts = (Get-Date).ToString("HH:mm:ss")
    $Sync.LogQueue.Enqueue("[$ts] $Message")
}

Write-UiLog "Utility avviata. Rilevati $($DriverItems.Count) pacchetti driver e $($AppItems.Count) programmi per OneXPlayer 1S."
Write-UiLog "Dispositivi PnP con problemi sul sistema: $pnpErrCount"

# ---------------------------------------------------------------------------
# 7b. Funzioni comuni: pulsanti, rilevamento programmi, schermo, touch
# ---------------------------------------------------------------------------
$FooterDrivers = "Nota: Intel PCH Chipset Init Kit (.bin OEM) escluso perche non installabile da Windows."
$FooterApps    = "I programmi si installano con winget; la grafica aggiornata arriva da Intel Driver & Support Assistant."
$FooterScreen  = "Ogni modifica dello schermo chiede conferma entro 15 secondi, altrimenti torna allo stato precedente."

function Set-PresetButtons {
    param([bool]$Enabled)
    foreach ($n in @('BtnSelectAll', 'BtnSelectMissing', 'BtnSelectEssential', 'BtnSelectNone', 'BtnRefresh',
                     'BtnAppRecommended', 'BtnAppAll', 'BtnAppNone', 'BtnAppRefresh')) {
        $Ctrl[$n].IsEnabled = $Enabled
    }
}

# Testo e stato di BtnInstall secondo la scheda attiva e la coda in corso.
function Update-InstallButton {
    $running = [bool]$Sync.IsRunning
    switch ($Ctrl.MainTabs.SelectedIndex) {
        0 { $Ctrl.BtnInstall.Content = "Installa Driver Selezionati"; $Ctrl.BtnInstall.IsEnabled = (-not $running); $Ctrl.TxtFooterInfo.Text = $FooterDrivers }
        1 { $Ctrl.BtnInstall.Content = "Installa Programmi Selezionati"; $Ctrl.BtnInstall.IsEnabled = (-not $running); $Ctrl.TxtFooterInfo.Text = $FooterApps }
        default { $Ctrl.BtnInstall.Content = "Installa"; $Ctrl.BtnInstall.IsEnabled = $false; $Ctrl.TxtFooterInfo.Text = $FooterScreen }
    }
}

# --- Rilevamento programmi (asincrono: winget export impiega circa 30 secondi) ---
function Start-AppDetection {
    if ($Sync.AppDetectRunning) { return }
    $Sync.AppDetectRunning = $true

    $wingetPath = $null
    $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wingetCmd) { $wingetPath = [string]$wingetCmd.Source }

    foreach ($i in $AppItems) { $i.SystemStatus = "Analisi..." }
    try { $Ctrl.GridApps.Items.Refresh() } catch {}
    Write-UiLog "Rilevamento programmi avviato (winget export, circa 30 secondi)..."

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Sync', $Sync)
    $rs.SessionStateProxy.SetVariable('AppItems', $AppItems)
    $rs.SessionStateProxy.SetVariable('WingetPath', $wingetPath)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        function Log-Det([string]$Msg) { $Sync.LogQueue.Enqueue("[" + (Get-Date).ToString("HH:mm:ss") + "] " + $Msg) }
        try {
            $installed = $null
            if ($WingetPath) {
                $dir = Join-Path $env:TEMP "OXP1S-Drivers"
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                $json = Join-Path $dir "winget_export.json"
                if (Test-Path -LiteralPath $json) { Remove-Item -LiteralPath $json -Force -ErrorAction SilentlyContinue }

                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $WingetPath
                $psi.Arguments = "export -o `"$json`" --source winget --accept-source-agreements --disable-interactivity"
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
                $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
                $proc = New-Object System.Diagnostics.Process
                $proc.StartInfo = $psi
                [void]$proc.Start()
                $outTask = $proc.StandardOutput.ReadToEndAsync()
                $errTask = $proc.StandardError.ReadToEndAsync()
                if (-not $proc.WaitForExit(240000)) {
                    try { $proc.Kill() } catch {}
                    Log-Det "winget export: tempo scaduto (4 minuti)."
                }
                try { [void]$outTask.Wait(5000) } catch {}
                try { [void]$errTask.Wait(5000) } catch {}

                if (Test-Path -LiteralPath $json) {
                    $data = Get-Content -LiteralPath $json -Raw -Encoding UTF8 | ConvertFrom-Json
                    $set = @{}
                    foreach ($s in @($data.Sources)) {
                        foreach ($p in @($s.Packages)) {
                            if ($p.PackageIdentifier) { $set[([string]$p.PackageIdentifier).ToLowerInvariant()] = $true }
                        }
                    }
                    $installed = $set
                    Log-Det "winget export: $($set.Count) pacchetti letti."
                } else {
                    Log-Det "winget export non ha prodotto il file elenco."
                }
            }

            foreach ($item in $AppItems) {
                $def = $item.Def
                if ($def.AppxName) {
                    $found = $false
                    try { $found = [bool](Get-AppxPackage -Name $def.AppxName -ErrorAction SilentlyContinue) } catch {}
                    $item.SystemStatus = if ($found) { "Installato" } else { "Non installato" }
                } elseif (-not $WingetPath) {
                    $item.SystemStatus = "winget assente"
                } elseif ($null -eq $installed) {
                    $item.SystemStatus = "Non determinato"
                } elseif ($installed.ContainsKey(([string]$def.Id).ToLowerInvariant())) {
                    $item.SystemStatus = "Installato"
                } else {
                    $item.SystemStatus = "Non installato"
                }
            }
            Log-Det "Rilevamento programmi completato."
        } catch {
            foreach ($item in $AppItems) { if ($item.SystemStatus -eq "Analisi...") { $item.SystemStatus = "Non determinato" } }
            Log-Det "Errore nel rilevamento programmi: $($_.Exception.Message)"
        } finally {
            $Sync.DirtyApps = $true
            $Sync.AppDetectRunning = $false
        }
    })
    $Sync.Runners['Detect'] = $ps
    $null = $ps.BeginInvoke()
}

# --- Schermo ---
$AutoRotKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AutoRotation'

function Update-DisplayInfo {
    $c = $null
    try { $c = [OxpDisplay]::Current() } catch {}
    if (-not $c) { $Ctrl.TxtDisplayInfo.Text = "Impossibile leggere le impostazioni dello schermo."; return }
    $deg = [int]$c[2] * 90
    $Ctrl.TxtDisplayInfo.Text = "Risoluzione: $($c[0]) x $($c[1])   |   Orientamento: $deg gradi   |   Frequenza: $($c[3]) Hz"
}

function Get-RotationLocked {
    try {
        $v = (Get-ItemProperty -LiteralPath $AutoRotKey -Name 'Enable' -ErrorAction Stop).Enable
        return ([int]$v -eq 0)
    } catch { return $false }
}

function Update-RotationLockInfo {
    if (Get-RotationLocked) {
        $Ctrl.TxtRotationLock.Text = "Stato: rotazione automatica BLOCCATA."
        $Ctrl.BtnRotationLock.Content = "Sblocca rotazione automatica"
    } else {
        $Ctrl.TxtRotationLock.Text = "Stato: rotazione automatica attiva."
        $Ctrl.BtnRotationLock.Content = "Blocca rotazione automatica"
    }
}

function Invoke-ToggleRotationLock {
    $newValue = if (Get-RotationLocked) { 1 } else { 0 }
    try {
        if (-not (Test-Path -LiteralPath $AutoRotKey)) { New-Item -Path $AutoRotKey -Force | Out-Null }
        New-ItemProperty -LiteralPath $AutoRotKey -Name 'Enable' -PropertyType DWord -Value $newValue -Force | Out-Null
        $what = if ($newValue -eq 0) { "bloccata" } else { "attiva" }
        Write-UiLog "Rotazione automatica: ora $what (Enable=$newValue). Potrebbe servire uscire e rientrare in Windows perche abbia effetto."
    } catch {
        Write-UiLog "Impossibile cambiare il blocco rotazione: $($_.Exception.Message)"
    }
    Update-RotationLockInfo
}

# Unico punto di modifica dello schermo: prova, applica, chiede conferma (15 s), altrimenti ripristina.
function Invoke-DisplayChange {
    param([string]$Description, [int]$W, [int]$H, [int]$Orient, [int]$Freq)

    $old = [OxpDisplay]::Current()
    if (-not $old) { Write-UiLog "Schermo: impossibile leggere lo stato attuale. Nessuna modifica."; return }
    Write-UiLog "Schermo: $Description (richiesto $W x $H, orientamento $($Orient * 90) gradi)."

    $useFreq = $Freq
    $r = [OxpDisplay]::Apply($W, $H, $Orient, $useFreq, $true)
    if ($r -ne 0 -and $useFreq -gt 0) {
        $useFreq = 0
        $r = [OxpDisplay]::Apply($W, $H, $Orient, 0, $true)
    }
    if ($r -ne 0) {
        Write-UiLog "Schermo: il driver non accetta questa modalita (codice $r). Nessuna modifica."
        return
    }

    $r = [OxpDisplay]::Apply($W, $H, $Orient, $useFreq, $false)
    if ($r -ne 0) {
        Write-UiLog "Schermo: applicazione non riuscita (codice $r)."
        Update-DisplayInfo
        return
    }
    Write-UiLog "Schermo: modifica applicata, attendo la conferma (15 secondi)..."

    $ans = [OxpDisplay]::AskKeep("Mantenere questa impostazione dello schermo?", "OneXPlayer 1S - Schermo", 15)
    if ($ans -eq 6) {
        Write-UiLog "Schermo: impostazione confermata."
    } else {
        $why = if ($ans -eq 32000) { "nessuna risposta entro 15 secondi" } else { "risposta No" }
        $rr = [OxpDisplay]::Apply($old[0], $old[1], $old[2], $old[3], $false)
        if ($rr -ne 0) { $rr = [OxpDisplay]::Apply($old[0], $old[1], $old[2], 0, $false) }
        Write-UiLog "Schermo: $why, ripristino di $($old[0]) x $($old[1]) a $($old[2] * 90) gradi (codice $rr)."
    }
    Update-DisplayInfo
}

function Invoke-Rotate {
    param([int]$Steps)
    $c = [OxpDisplay]::Current()
    if (-not $c) { Write-UiLog "Schermo: impossibile leggere lo stato attuale."; return }
    $newO = ([int]$c[2] + $Steps) % 4
    $w = [int]$c[0]; $h = [int]$c[1]
    if (($newO % 2) -ne ([int]$c[2] % 2)) { $w = [int]$c[1]; $h = [int]$c[0] }
    Invoke-DisplayChange -Description "rotazione di $($Steps * 90) gradi" -W $w -H $h -Orient $newO -Freq ([int]$c[3])
}

function Invoke-SetResolution {
    param([ValidateSet('native', '1920', '1280')][string]$Which)
    $c = [OxpDisplay]::Current()
    if (-not $c) { Write-UiLog "Schermo: impossibile leggere lo stato attuale."; return }
    $modes = @([OxpDisplay]::Modes())
    $landscape = ([int]$c[0] -ge [int]$c[1])

    $long = 0; $short = 0
    switch ($Which) {
        'native' {
            $best = $null
            foreach ($m in $modes) {
                if (-not $best -or ([long]$m[0] * [long]$m[1]) -gt ([long]$best[0] * [long]$best[1])) { $best = $m }
            }
            if ($best) { $long = [Math]::Max([int]$best[0], [int]$best[1]); $short = [Math]::Min([int]$best[0], [int]$best[1]) }
        }
        '1920' { $long = 1920; $short = 1200 }
        '1280' { $long = 1280; $short = 800 }
    }
    if ($long -eq 0) { Write-UiLog "Schermo: nessuna modalita elencata dal driver video."; return }

    $w = if ($landscape) { $long } else { $short }
    $h = if ($landscape) { $short } else { $long }

    $available = $false
    foreach ($m in $modes) { if ([int]$m[0] -eq $w -and [int]$m[1] -eq $h) { $available = $true; break } }
    if (-not $available) {
        Write-UiLog "Schermo: la risoluzione $w x $h non e disponibile con il driver video attuale (con il driver video di base ne compaiono poche). Nessuna modifica."
        return
    }
    if ([int]$c[0] -eq $w -and [int]$c[1] -eq $h) {
        Write-UiLog "Schermo: la risoluzione $w x $h e gia impostata."
        return
    }
    Invoke-DisplayChange -Description "risoluzione $w x $h" -W $w -H $h -Orient ([int]$c[2]) -Freq ([int]$c[3])
}

# --- Touch: diagnosi (sola lettura) e riparazione ---
$TouchPciRegex = '^PCI\\VEN_8086&DEV_(A0C5|A0C6|A0D8|A0D9|A0E8|A0E9|A0EA|A0EB)'
$TouchGateKey  = 'HKCU:\Software\Microsoft\Wisp\Touch'

# Logica pura dei verdetti: riceve gli elenchi e il valore di TouchGate, non tocca il sistema.
function Get-TouchVerdict {
    param($I2cControllers, $I2cHid, $TouchScreens, $TouchGate)
    $ctrl  = @($I2cControllers)
    $hid   = @($I2cHid)
    $touch = @($TouchScreens)

    $pciBad = @($ctrl | Where-Object { ([string]$_.PNPDeviceID) -match $TouchPciRegex -and [int]$_.ConfigManagerErrorCode -ne 0 })
    $ctrlOk = @($ctrl | Where-Object { [int]$_.ConfigManagerErrorCode -eq 0 })
    if ($pciBad.Count -gt 0 -or $ctrlOk.Count -eq 0) {
        return [PSCustomObject]@{ Verdict = 'SerialIoMissing'
            Message = "Manca il driver Intel Serial IO (controller I2C assente o in errore). Installa il driver n. 2 dalla scheda Driver e riavvia." }
    }
    if ($null -ne $TouchGate -and [int]$TouchGate -eq 0) {
        return [PSCustomObject]@{ Verdict = 'TouchDisabledByUser'
            Message = "Il touch e disattivato nelle impostazioni dell'utente (TouchGate = 0). Usa Ripara touch per riattivarlo." }
    }
    $touchOk = @($touch | Where-Object { [int]$_.ConfigManagerErrorCode -eq 0 })
    if ($touchOk.Count -gt 0) {
        return [PSCustomObject]@{ Verdict = 'TouchOk'
            Message = "Per Windows il touch e attivo. Se non risponde, prova Ripara touch e poi uno spegnimento completo." }
    }
    $bad = @($hid | Where-Object { [int]$_.ConfigManagerErrorCode -ne 0 }) + @($touch | Where-Object { [int]$_.ConfigManagerErrorCode -ne 0 })
    if ($bad.Count -gt 0) {
        return [PSCustomObject]@{ Verdict = 'TouchDeviceError'
            Message = "Un dispositivo del touch e in errore o disattivato. Usa Ripara touch." }
    }
    return [PSCustomObject]@{ Verdict = 'TouchNotEnumerated'
        Message = "Il touchscreen non viene elencato dal firmware. Spegni del tutto il dispositivo (non riavviare), riaccendi e ripeti la diagnosi; se resta cosi controlla il BIOS o il cavo dello schermo." }
}

function Get-TouchDiagnosis {
    $all = @()
    try { $all = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop) } catch {}
    $i2c = @(); $gpio = @(); $hid = @(); $touch = @()
    foreach ($d in $all) {
        $id  = [string]$d.PNPDeviceID
        $svc = [string]$d.Service
        $compat = (@($d.CompatibleID) -join ';')
        $hw     = (@($d.HardwareID) -join ';')
        if ($id -match $TouchPciRegex -or $svc -like 'iaLPSS2_I2C*') { $i2c += $d }
        if ($id -like 'ACPI\INT34C5*' -or $svc -like 'iaLPSS2_GPIO*') { $gpio += $d }
        if ($compat -match 'ACPI\\PNP0C50') { $hid += $d }
        if ($hw -match 'HID_DEVICE_UP:000D_U:0004') { $touch += $d }
    }
    $gate = $null
    try { $gate = (Get-ItemProperty -LiteralPath $TouchGateKey -Name 'TouchGate' -ErrorAction Stop).TouchGate } catch {}

    $v = Get-TouchVerdict -I2cControllers $i2c -I2cHid $hid -TouchScreens $touch -TouchGate $gate
    return [PSCustomObject]@{
        I2cControllers = $i2c
        Gpio           = $gpio
        I2cHid         = $hid
        TouchScreens   = $touch
        TouchGate      = $gate
        Verdict        = $v.Verdict
        Message        = $v.Message
    }
}

function Write-TouchGroup {
    param([string]$Title, $Devices)
    $list = @($Devices)
    Write-UiLog "  $Title ($($list.Count)):"
    foreach ($d in $list) {
        Write-UiLog "    - $($d.Name) | stato $($d.Status) | codice $($d.ConfigManagerErrorCode)"
    }
}

function Invoke-TouchDiag {
    $diag = Get-TouchDiagnosis
    Write-UiLog "Diagnosi touch:"
    Write-TouchGroup -Title "Controller I2C (Serial IO)" -Devices $diag.I2cControllers
    Write-TouchGroup -Title "Controller GPIO" -Devices $diag.Gpio
    Write-TouchGroup -Title "Dispositivi HID su I2C" -Devices $diag.I2cHid
    Write-TouchGroup -Title "Touch screen" -Devices $diag.TouchScreens
    $gateText = if ($null -eq $diag.TouchGate) { "non impostato" } else { [string]$diag.TouchGate }
    Write-UiLog "  TouchGate: $gateText"
    Write-UiLog "  Esito: $($diag.Verdict) - $($diag.Message)"
    $Ctrl.TxtTouchInfo.Text = $diag.Message
    return $diag
}

function Repair-Touch {
    if ($Sync.IsRunning) { Write-UiLog "Touch: attendi la fine della coda di installazione."; return }
    $diag = Invoke-TouchDiag

    if ($diag.Verdict -eq 'SerialIoMissing') {
        $res = [System.Windows.MessageBox]::Show(
            "Manca il driver Intel Serial IO, da cui dipende il touch.`n`nVuoi preparare l'installazione di Intel Serial IO? Verra selezionato solo quel driver nella scheda Driver: poi premi Installa Driver Selezionati.",
            "Touch", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
            foreach ($i in $DriverItems) { $i.IsSelected = ($i.Id -eq 'serialio') }
            $Ctrl.GridDrivers.Items.Refresh()
            $Ctrl.MainTabs.SelectedIndex = 0
            Write-UiLog "Touch: selezionato solo Intel Serial IO. Premi Installa Driver Selezionati e poi riavvia."
        }
        return
    }

    Write-UiLog "Riparazione touch avviata."
    if ($null -ne $diag.TouchGate -and [int]$diag.TouchGate -eq 0) {
        try {
            if (-not (Test-Path -LiteralPath $TouchGateKey)) { New-Item -Path $TouchGateKey -Force | Out-Null }
            New-ItemProperty -LiteralPath $TouchGateKey -Name 'TouchGate' -PropertyType DWord -Value 1 -Force | Out-Null
            Write-UiLog "  TouchGate impostato a 1 (touch riattivato)."
        } catch { Write-UiLog "  TouchGate non modificato: $($_.Exception.Message)" }
    }

    foreach ($d in (@($diag.I2cHid) + @($diag.TouchScreens))) {
        if ([int]$d.ConfigManagerErrorCode -eq 22) {
            try {
                Enable-PnpDevice -InstanceId $d.PNPDeviceID -Confirm:$false -ErrorAction Stop
                Write-UiLog "  Riattivato: $($d.Name)"
            } catch { Write-UiLog "  Riattivazione non riuscita ($($d.Name)): $($_.Exception.Message)" }
        }
    }

    foreach ($d in @($diag.I2cHid)) {
        try {
            Disable-PnpDevice -InstanceId $d.PNPDeviceID -Confirm:$false -ErrorAction Stop
            Enable-PnpDevice -InstanceId $d.PNPDeviceID -Confirm:$false -ErrorAction Stop
            Write-UiLog "  Riavviato: $($d.Name)"
        } catch { Write-UiLog "  Riavvio non riuscito ($($d.Name)): $($_.Exception.Message)" }
    }

    try {
        $scan = & pnputil.exe /scan-devices 2>&1 | Out-String
        Write-UiLog "  pnputil /scan-devices: $($scan.Trim())"
    } catch { Write-UiLog "  pnputil /scan-devices non riuscito: $($_.Exception.Message)" }

    Start-Sleep -Seconds 2
    $after = Invoke-TouchDiag
    Write-UiLog "Riparazione touch terminata. Nuovo esito: $($after.Verdict)"
}

# ---------------------------------------------------------------------------
# 8. Gestori pulsanti Toolbar
# ---------------------------------------------------------------------------
$Ctrl.BtnSelectAll.Add_Click({
    foreach ($i in $DriverItems) { $i.IsSelected = $true }
    $Ctrl.GridDrivers.Items.Refresh()
})

$Ctrl.BtnSelectNone.Add_Click({
    foreach ($i in $DriverItems) { $i.IsSelected = $false }
    $Ctrl.GridDrivers.Items.Refresh()
})

$Ctrl.BtnSelectMissing.Add_Click({
    foreach ($i in $DriverItems) { $i.IsSelected = [bool]$i.NeedsInstall }
    $Ctrl.GridDrivers.Items.Refresh()
})

$Ctrl.BtnSelectEssential.Add_Click({
    foreach ($i in $DriverItems) { $i.IsSelected = [bool]$i.Def.Essential }
    $Ctrl.GridDrivers.Items.Refresh()
})

$Ctrl.BtnRefresh.Add_Click({
    if ($Sync.IsRunning) { return }
    $errCnt = Update-DriverDetection -Items $DriverItems
    $Ctrl.TxtPnpWarnings.Text = "Dispositivi con errori/mancanti rilevati: $errCnt"
    $Ctrl.TxtPnpWarnings.Foreground = if ($errCnt -gt 0) { '#FBBF24' } else { '#94A3B8' }
    $Ctrl.GridDrivers.Items.Refresh()
    Write-UiLog "Rilevamento aggiornato. Dispositivi con problemi: $errCnt"
})

$Ctrl.BtnDevMgmt.Add_Click({
    Start-Process "devmgmt.msc"
})

$Ctrl.BtnAppRecommended.Add_Click({
    foreach ($i in $AppItems) { $i.IsSelected = [bool]$i.Def.Recommended }
    $Ctrl.GridApps.Items.Refresh()
})

$Ctrl.BtnAppAll.Add_Click({
    foreach ($i in $AppItems) { $i.IsSelected = $true }
    $Ctrl.GridApps.Items.Refresh()
})

$Ctrl.BtnAppNone.Add_Click({
    foreach ($i in $AppItems) { $i.IsSelected = $false }
    $Ctrl.GridApps.Items.Refresh()
})

$Ctrl.BtnAppRefresh.Add_Click({
    if ($Sync.IsRunning) { return }
    $Sync.AppsDetected = $true
    Start-AppDetection
})

$Ctrl.BtnRotate90.Add_Click({ Invoke-Rotate -Steps 1 })
$Ctrl.BtnRotate180.Add_Click({ Invoke-Rotate -Steps 2 })
$Ctrl.BtnRotate270.Add_Click({ Invoke-Rotate -Steps 3 })
$Ctrl.BtnRotationLock.Add_Click({ Invoke-ToggleRotationLock })
$Ctrl.BtnResNative.Add_Click({ Invoke-SetResolution -Which 'native' })
$Ctrl.BtnRes1920.Add_Click({ Invoke-SetResolution -Which '1920' })
$Ctrl.BtnRes1280.Add_Click({ Invoke-SetResolution -Which '1280' })
$Ctrl.BtnTouchDiag.Add_Click({ [void](Invoke-TouchDiag) })
$Ctrl.BtnTouchRepair.Add_Click({ Repair-Touch })

# Cambio scheda: testo del pulsante principale, primo rilevamento programmi, stato dello schermo e del touch.
$Ctrl.MainTabs.Add_SelectionChanged({
    if ($args[1].OriginalSource -isnot [System.Windows.Controls.TabControl]) { return }
    Update-InstallButton
    $idx = $Ctrl.MainTabs.SelectedIndex
    if ($idx -eq 1 -and -not $Sync.AppsDetected) {
        $Sync.AppsDetected = $true
        Start-AppDetection
    }
    if ($idx -eq 2) {
        Update-DisplayInfo
        Update-RotationLockInfo
        if (-not $Sync.DisplayShown) {
            $Sync.DisplayShown = $true
            [void](Invoke-TouchDiag)
        }
    }
})

$Ctrl.BtnCancel.Add_Click({
    if ($Sync.IsRunning) {
        $Sync.CancelRequested = $true
        $Ctrl.BtnCancel.IsEnabled = $false
        Write-UiLog "Annullamento richiesto... attendo il completamento del passo corrente."
    }
})

# ---------------------------------------------------------------------------
# 9. Timer Dispatcher per aggiornare la UI senza freeze
# ---------------------------------------------------------------------------
$UiTimer = New-Object System.Windows.Threading.DispatcherTimer
$UiTimer.Interval = [TimeSpan]::FromMilliseconds(120)
$UiTimer.Add_Tick({
    $line = $null
    $sb = New-Object System.Text.StringBuilder
    while ($Sync.LogQueue.TryDequeue([ref]$line)) {
        [void]$sb.AppendLine($line)
    }
    if ($sb.Length -gt 0) {
        $Ctrl.TxtLog.AppendText($sb.ToString())
        $Ctrl.TxtLog.ScrollToEnd()
    }

    if ($Sync.DirtyGrid) {
        $Sync.DirtyGrid = $false
        $Ctrl.GridDrivers.Items.Refresh()
    }

    if ($Sync.DirtyApps) {
        $Sync.DirtyApps = $false
        try { $Ctrl.GridApps.Items.Refresh() } catch {}
    }

    $Ctrl.TxtProgressTitle.Text = $Sync.ProgressTitle
    $Ctrl.TxtProgressCount.Text = $Sync.ProgressCount
    $Ctrl.ProgressTotal.Value   = $Sync.TotalPct
    $Ctrl.ProgressStep.Value    = $Sync.StepPct

    if ($Sync.Finished) {
        $Sync.Finished = $false
        $Sync.IsRunning = $false

        $Ctrl.BtnCancel.IsEnabled  = $false
        Set-PresetButtons $true
        Update-InstallButton

        $summary = "Operazione completata.`nCompletati: $($Sync.SuccessCount) | Errori: $($Sync.ErrorCount)`nLog: $($Sync.LogFilePath)"

        if ($Sync.Mode -eq 'apps') {
            try { $Ctrl.GridApps.Items.Refresh() } catch {}
            [System.Windows.MessageBox]::Show(
                $summary,
                "Installazione Programmi Completata",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
            Start-AppDetection
            return
        }

        $errCnt = Update-DriverDetection -Items $DriverItems
        $Ctrl.TxtPnpWarnings.Text = "Dispositivi con errori/mancanti rilevati: $errCnt"
        $Ctrl.TxtPnpWarnings.Foreground = if ($errCnt -gt 0) { '#FBBF24' } else { '#94A3B8' }
        $Ctrl.GridDrivers.Items.Refresh()

        if ($Sync.RebootNeeded) {
            $res = [System.Windows.MessageBox]::Show(
                "$summary`n`nAlmeno un driver richiede il riavvio per essere attivo. Vuoi riavviare il OneXPlayer ora?",
                "Riavvio Richiesto",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question
            )
            if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
                Restart-Computer -Force
            }
        } else {
            [System.Windows.MessageBox]::Show(
                $summary,
                "Installazione Completata",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
        }
    }
})
$UiTimer.Start()

# ---------------------------------------------------------------------------
# 10. Avvio coda sequenziale in Background Runspace
# ---------------------------------------------------------------------------
function Start-DriverInstall {
    if ($Sync.IsRunning) { return }

    $selected = @($DriverItems | Where-Object { $_.IsSelected } | Sort-Object Order)
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Seleziona almeno un driver da installare.", "Nessuna selezione", "OK", "Warning") | Out-Null
        return
    }

    $Sync.Mode            = 'drivers'
    $Sync.IsRunning       = $true
    $Sync.CancelRequested = $false
    $Sync.Finished        = $false
    $Sync.RebootNeeded    = $false
    $Sync.SuccessCount    = 0
    $Sync.ErrorCount      = 0
    $Sync.TotalPct        = 0
    $Sync.StepPct         = 0

    foreach ($i in $DriverItems) {
        $i.RunStatus = if ($i.IsSelected) { "In coda" } else { "Saltato" }
    }
    $Ctrl.GridDrivers.Items.Refresh()

    $Ctrl.BtnCancel.IsEnabled  = $true
    Set-PresetButtons $false
    Update-InstallButton

    $opts = @{
        CreateRestorePoint = [bool]$Ctrl.ChkRestorePoint.IsChecked
        UseLocal           = [bool]$Ctrl.ChkUseLocal.IsChecked
        Cleanup            = [bool]$Ctrl.ChkCleanup.IsChecked
        ReleaseBaseUrl     = $ReleaseBaseUrl.TrimEnd('/')
        BaseScriptDir      = $BaseScriptDir
        LocalDriversPath   = $LocalDriversPath
        CurrentDir         = (Get-Location).Path
    }

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Sync', $Sync)
    $rs.SessionStateProxy.SetVariable('SelectedItems', $selected)
    $rs.SessionStateProxy.SetVariable('Opts', $opts)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        Add-Type -AssemblyName System.Net.Http

        $workRoot   = Join-Path $env:TEMP "OXP1S-Drivers"
        $zipDir     = Join-Path $workRoot "zips"
        $extractDir = Join-Path $workRoot "extracted"
        $logDir     = Join-Path $workRoot "logs"
        New-Item -ItemType Directory -Path $zipDir, $extractDir, $logDir -Force | Out-Null

        $mainLog = Join-Path $logDir ("oxp1s_install_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
        $Sync.LogFilePath = $mainLog

        function Log-Step([string]$Msg) {
            $ts = (Get-Date).ToString("HH:mm:ss")
            $line = "[$ts] $Msg"
            $Sync.LogQueue.Enqueue($line)
            Add-Content -Path $mainLog -Value $line -Encoding UTF8
        }

        function Find-LocalZip([string]$ZipName) {
            if (-not $Opts.UseLocal) { return $null }
            $candidates = @()
            if ($Opts.LocalDriversPath) { $candidates += (Join-Path $Opts.LocalDriversPath $ZipName) }
            $candidates += @(
                (Join-Path $Opts.BaseScriptDir "drivers\$ZipName"),
                (Join-Path $Opts.BaseScriptDir $ZipName),
                (Join-Path $Opts.CurrentDir "drivers\$ZipName"),
                (Join-Path $Opts.CurrentDir $ZipName),
                (Join-Path $zipDir $ZipName)
            )
            foreach ($c in $candidates) {
                if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
                    if ((Get-Item -LiteralPath $c).Length -gt 0) { return $c }
                }
            }
            return $null
        }

        function Download-FileWithProgress([string]$Url, [string]$DestPath, [string]$Label) {
            $client = New-Object System.Net.Http.HttpClient
            $client.Timeout = [TimeSpan]::FromMinutes(30)
            try {
                $resp = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                if (-not $resp.IsSuccessStatusCode) {
                    throw "HTTP $([int]$resp.StatusCode) ($($resp.ReasonPhrase)) su $Url"
                }
                $totalBytes = $resp.Content.Headers.ContentLength
                $inStream   = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $outStream  = [System.IO.File]::Create($DestPath)
                try {
                    $buffer = New-Object byte[] 65536
                    $readTotal = [long]0
                    $lastTick = [Environment]::TickCount
                    while (($read = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        if ($Sync.CancelRequested) { throw "Annullato dall'utente durante il download." }
                        $outStream.Write($buffer, 0, $read)
                        $readTotal += $read
                        if (([Environment]::TickCount - $lastTick) -ge 200) {
                            $lastTick = [Environment]::TickCount
                            if ($totalBytes -and $totalBytes -gt 0) {
                                $pct = [int][Math]::Min(100, ($readTotal * 100 / $totalBytes))
                                $Sync.StepPct = $pct
                                $mbDone = [Math]::Round($readTotal / 1MB, 1)
                                $mbTot  = [Math]::Round($totalBytes / 1MB, 1)
                                $Sync.ProgressTitle = "Download $Label... $pct% ($mbDone / $mbTot MB)"
                            } else {
                                $mbDone = [Math]::Round($readTotal / 1MB, 1)
                                $Sync.ProgressTitle = "Download $Label... $mbDone MB"
                            }
                        }
                    }
                    $Sync.StepPct = 100
                } finally {
                    $outStream.Dispose()
                    $inStream.Dispose()
                }
            } finally {
                $client.Dispose()
            }
        }

        function Run-ProcessCaptured([string]$FilePath, [string]$Arguments, [string]$WorkingDir) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $FilePath
            $psi.Arguments = $Arguments
            $psi.WorkingDirectory = $WorkingDir
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true

            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo = $psi
            [void]$proc.Start()
            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit()
            return [PSCustomObject]@{
                ExitCode = $proc.ExitCode
                StdOut   = $stdout
                StdErr   = $stderr
            }
        }

        Log-Step "=== Avvio sessione installazione OneXPlayer 1S ($($SelectedItems.Count) driver) ==="

        # Punto di ripristino iniziale
        if ($Opts.CreateRestorePoint) {
            $Sync.ProgressTitle = "Creazione Punto di Ripristino di sistema..."
            $Sync.StepPct = 20
            Log-Step "Tentativo creazione Punto di Ripristino..."
            try {
                Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
                Checkpoint-Computer -Description "Pre-OXP1S-Drivers" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
                Log-Step "Punto di Ripristino 'Pre-OXP1S-Drivers' creato."
            } catch {
                Log-Step "Avviso Punto di Ripristino non creato (es. limite 24h di Windows): $($_.Exception.Message)"
            }
            $Sync.StepPct = 100
        }

        $total = $SelectedItems.Count
        $idx = 0

        foreach ($item in $SelectedItems) {
            if ($Sync.CancelRequested) {
                $item.RunStatus = "Annullato"
                $Sync.DirtyGrid = $true
                Log-Step "Coda interrotta dall'utente prima di: $($item.Name)"
                break
            }

            $idx++
            $def = $item.Def
            $Sync.ProgressCount = "$idx / $total"
            $Sync.TotalPct = [int]((($idx - 1) * 100) / $total)
            $Sync.StepPct  = 0

            Log-Step "--- [$idx/$total] $($def.Name) ($($def.ZipName)) ---"

            try {
                # 1. Acquisizione ZIP (locale o download)
                $remoteName = if ($def.AssetName) { $def.AssetName } else { $def.ZipName }
                $zipPath = Find-LocalZip -ZipName $def.ZipName
                if (-not $zipPath -and $remoteName -ne $def.ZipName) {
                    $zipPath = Find-LocalZip -ZipName $remoteName
                }
                if ($zipPath) {
                    $item.RunStatus = "Locale trovato"
                    $Sync.DirtyGrid = $true
                    Log-Step "Uso archivio locale: $zipPath"
                } else {
                    $item.RunStatus = "Download..."
                    $Sync.DirtyGrid = $true
                    $url = "$($Opts.ReleaseBaseUrl)/$remoteName"
                    $destZip = Join-Path $zipDir $remoteName
                    $partZip = "$destZip.part"
                    if (Test-Path -LiteralPath $partZip) { Remove-Item -LiteralPath $partZip -Force }
                    Log-Step "Download da: $url"
                    Download-FileWithProgress -Url $url -DestPath $partZip -Label $def.Name
                    Move-Item -LiteralPath $partZip -Destination $destZip -Force
                    $zipPath = $destZip
                }

                # 2. Estrazione
                $item.RunStatus = "Estrazione..."
                $Sync.ProgressTitle = "Estrazione $($def.Name)..."
                $Sync.StepPct = 35
                $Sync.DirtyGrid = $true

                $pkgExtract = Join-Path $extractDir $def.Id
                if (Test-Path -LiteralPath $pkgExtract) { Remove-Item -LiteralPath $pkgExtract -Recurse -Force }
                [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $pkgExtract)
                $Sync.StepPct = 60

                # 3. Installazione silenziosa
                $item.RunStatus = "Installazione..."
                $Sync.ProgressTitle = "Installazione silenziosa $($def.Name)..."
                $Sync.DirtyGrid = $true

                $pkgReboot = $false
                $pkgFailed = $false

                if ($def.Method -eq 'EXE') {
                    $exeFull = Join-Path $pkgExtract $def.ExePath
                    if (-not (Test-Path -LiteralPath $exeFull)) {
                        throw "Eseguibile non trovato nell'archivio: $($def.ExePath)"
                    }
                    $pkgLog = Join-Path $logDir "$($def.Id)_setup.log"
                    $args = $def.ExeArgs.Replace('{LOG}', $pkgLog)
                    Log-Step "Esecuzione EXE: `"$exeFull`" $args"
                    $res = Run-ProcessCaptured -FilePath $exeFull -Arguments $args -WorkingDir (Split-Path -Parent $exeFull)
                    $code = $res.ExitCode
                    Log-Step "ExitCode EXE ($($def.Id)): $code"

                    if ($def.RebootCodes -contains $code) {
                        $pkgReboot = $true
                    } elseif ($def.OkCodes -notcontains $code) {
                        $pkgFailed = $true
                        Log-Step "Errore EXE ($($def.Id)) codice $code. $($res.StdErr)"
                    }
                } else {
                    foreach ($t in $def.InfTargets) {
                        $targetFull = Join-Path $pkgExtract $t.Path
                        $pnpArgs = "/add-driver `"$targetFull`""
                        if ($t.Subdirs) { $pnpArgs += " /subdirs" }
                        $pnpArgs += " /install"

                        Log-Step "Esecuzione pnputil $pnpArgs"
                        $res = Run-ProcessCaptured -FilePath "pnputil.exe" -Arguments $pnpArgs -WorkingDir $pkgExtract
                        $code = $res.ExitCode
                        Log-Step "ExitCode pnputil: $code"

                        if ($code -eq 3010 -or $code -eq 1641) {
                            $pkgReboot = $true
                        } elseif ($code -ne 0 -and $code -ne 259) {
                            $pkgFailed = $true
                            Log-Step "Output pnputil: $($res.StdOut) $($res.StdErr)"
                        }
                    }
                }

                $Sync.StepPct = 100
                if ($pkgFailed) {
                    $item.RunStatus = "Errore"
                    $Sync.ErrorCount++
                } elseif ($pkgReboot) {
                    $item.RunStatus = "OK (Riavvio)"
                    $Sync.RebootNeeded = $true
                    $Sync.SuccessCount++
                } else {
                    $item.RunStatus = "Completato"
                    $Sync.SuccessCount++
                }
            } catch {
                $item.RunStatus = "Errore"
                $Sync.ErrorCount++
                Log-Step "ECCEZIONE su $($def.Name): $($_.Exception.Message)"
            }

            $Sync.DirtyGrid = $true
            $Sync.TotalPct = [int](($idx * 100) / $total)
        }

        if ($Opts.Cleanup) {
            Log-Step "Pulizia file temporanei in $extractDir e $zipDir..."
            try {
                if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
                if (Test-Path -LiteralPath $zipDir)     { Remove-Item -LiteralPath $zipDir     -Recurse -Force -ErrorAction SilentlyContinue }
            } catch {}
        }

        $Sync.ProgressTitle = if ($Sync.CancelRequested) { "Operazione annullata." } else { "Sequenza terminata." }
        $Sync.StepPct = 100
        Log-Step "=== Fine sessione: OK=$($Sync.SuccessCount), Errori=$($Sync.ErrorCount), RebootNeeded=$($Sync.RebootNeeded) ==="
        $Sync.Finished = $true
    })

    $Sync.Runners['Drivers'] = $ps
    $null = $ps.BeginInvoke()
}

# ---------------------------------------------------------------------------
# 10b. Coda di installazione programmi (winget) in Background Runspace
# ---------------------------------------------------------------------------
function Start-AppInstall {
    if ($Sync.IsRunning) { return }

    $selected = @($AppItems | Where-Object { $_.IsSelected } | Sort-Object Order)
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Seleziona almeno un programma da installare.", "Nessuna selezione", "OK", "Warning") | Out-Null
        return
    }

    $wingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wingetCmd) {
        $msg = 'winget non trovato su questo PC. Aggiorna "Programma di installazione app" dal Microsoft Store e riprova. Sulle edizioni LTSC winget non e incluso e va installato a parte.'
        Write-UiLog $msg
        [System.Windows.MessageBox]::Show($msg, "winget assente", "OK", "Warning") | Out-Null
        return
    }
    $wingetPath = [string]$wingetCmd.Source

    $Sync.Mode            = 'apps'
    $Sync.IsRunning       = $true
    $Sync.CancelRequested = $false
    $Sync.Finished        = $false
    $Sync.RebootNeeded    = $false
    $Sync.SuccessCount    = 0
    $Sync.ErrorCount      = 0
    $Sync.TotalPct        = 0
    $Sync.StepPct         = 0

    foreach ($i in $AppItems) {
        $i.RunStatus = if ($i.IsSelected) { "In coda" } else { "Saltato" }
    }
    try { $Ctrl.GridApps.Items.Refresh() } catch {}

    $Ctrl.BtnCancel.IsEnabled = $true
    Set-PresetButtons $false
    Update-InstallButton

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Sync', $Sync)
    $rs.SessionStateProxy.SetVariable('SelectedItems', $selected)
    $rs.SessionStateProxy.SetVariable('WingetPath', $wingetPath)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        $workRoot = Join-Path $env:TEMP "OXP1S-Drivers"
        $logDir   = Join-Path $workRoot "logs"
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $mainLog = Join-Path $logDir ("oxp1s_apps_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
        $Sync.LogFilePath = $mainLog

        function Log-Step([string]$Msg) {
            $ts = (Get-Date).ToString("HH:mm:ss")
            $line = "[$ts] $Msg"
            $Sync.LogQueue.Enqueue($line)
            Add-Content -Path $mainLog -Value $line -Encoding UTF8
        }

        # Legge stdout e stderr in modo asincrono (evita lo stallo con due flussi) e aggiorna la barra del passo.
        function Run-WingetCaptured([string]$FilePath, [string]$Arguments) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $FilePath
            $psi.Arguments = $Arguments
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

            $proc = New-Object System.Diagnostics.Process
            $proc.StartInfo = $psi
            [void]$proc.Start()
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $pct = 5
            $timedOut = $false
            while (-not $proc.WaitForExit(500)) {
                if ($pct -lt 90) { $pct++ }
                $Sync.StepPct = $pct
                if ($sw.Elapsed.TotalMinutes -gt 30) {
                    $timedOut = $true
                    try { $proc.Kill() } catch {}
                    break
                }
            }
            $stdout = ""; $stderr = ""
            try { if ($outTask.Wait(10000)) { $stdout = [string]$outTask.Result } } catch {}
            try { if ($errTask.Wait(10000)) { $stderr = [string]$errTask.Result } } catch {}
            $code = if ($timedOut) { -1 } else { $proc.ExitCode }
            return [PSCustomObject]@{ ExitCode = $code; StdOut = $stdout; StdErr = $stderr; TimedOut = $timedOut }
        }

        # Solo righe con lettere: l'output di winget e pieno di caratteri della barra di avanzamento.
        function Get-UsefulLines([string]$Text, [int]$Max) {
            $lines = @(($Text -split "[\r\n]+") | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '[A-Za-z]' })
            if ($lines.Count -gt $Max) { $lines = @($lines[($lines.Count - $Max)..($lines.Count - 1)]) }
            return $lines
        }

        $okCodes = @(0, -1978335189, -1978335135)
        $total = $SelectedItems.Count
        $idx = 0

        try {
            Log-Step "=== Avvio installazione programmi ($total) con winget: $WingetPath ==="

            foreach ($item in $SelectedItems) {
                if ($Sync.CancelRequested) {
                    Log-Step "Coda interrotta dall'utente prima di: $($item.Name)"
                    break
                }
                $idx++
                $def = $item.Def
                $Sync.ProgressCount = "$idx / $total"
                $Sync.TotalPct = [int]((($idx - 1) * 100) / $total)
                $Sync.StepPct = 0
                $Sync.ProgressTitle = "Installazione di $($def.Name) ($idx/$total)..."
                $item.RunStatus = "Installazione..."
                $Sync.DirtyApps = $true

                $wargs = "install --id `"$($def.Id)`" --exact --source $($def.Source) --silent --accept-package-agreements --accept-source-agreements --disable-interactivity"
                Log-Step "--- [$idx/$total] $($def.Name) ---"
                Log-Step "winget $wargs"

                try {
                    $res = Run-WingetCaptured -FilePath $WingetPath -Arguments $wargs
                    $code = [int]$res.ExitCode
                    Log-Step "ExitCode winget ($($def.Id)): $code"
                    if ($okCodes -contains $code) {
                        $item.RunStatus = "Completato"
                        $Sync.SuccessCount++
                    } else {
                        $item.RunStatus = "Errore ($code)"
                        $Sync.ErrorCount++
                        if ($res.TimedOut) { Log-Step "Installazione interrotta: superati i 30 minuti." }
                        $useful = @(Get-UsefulLines -Text ($res.StdOut + "`n" + $res.StdErr) -Max 8)
                        foreach ($l in $useful) { Log-Step "    $l" }
                    }
                } catch {
                    $item.RunStatus = "Errore"
                    $Sync.ErrorCount++
                    Log-Step "ECCEZIONE su $($def.Name): $($_.Exception.Message)"
                }

                $Sync.StepPct = 100
                $Sync.DirtyApps = $true
                $Sync.TotalPct = [int](($idx * 100) / $total)
            }

            foreach ($item in $SelectedItems) {
                if ($item.RunStatus -eq "In coda") { $item.RunStatus = "Annullato" }
            }
            $Sync.DirtyApps = $true
            $Sync.ProgressTitle = if ($Sync.CancelRequested) { "Operazione annullata." } else { "Sequenza terminata." }
            Log-Step "=== Fine sessione programmi: OK=$($Sync.SuccessCount), Errori=$($Sync.ErrorCount) ==="
        } catch {
            Log-Step "ERRORE nella coda programmi: $($_.Exception.Message)"
        } finally {
            $Sync.StepPct = 100
            $Sync.Finished = $true
        }
    })
    $Sync.Runners['Apps'] = $ps
    $null = $ps.BeginInvoke()
}

$Ctrl.BtnInstall.Add_Click({
    if ($Sync.IsRunning) { return }
    switch ($Ctrl.MainTabs.SelectedIndex) {
        0 { Start-DriverInstall }
        1 { Start-AppInstall }
        default { }
    }
})

# Stato iniziale del pulsante principale e delle informazioni dello schermo (sola lettura).
$Ctrl.MainTabs.SelectedIndex = 0
Update-InstallButton
Update-DisplayInfo
Update-RotationLockInfo

# Avvia finestra WPF
$Window.Add_Closed({ $UiTimer.Stop() })
[void]$Window.ShowDialog()
