<#
.SYNOPSIS
    OneXPlayer 1S Driver Utility (Windows 11 Pro) - GUI stile Chris Titus WinUtil.
.DESCRIPTION
    Scarica (da GitHub Releases o da cartella locale), estrae e installa in sequenza
    silenziosa tutti i driver del OneXPlayer 1S con barra di avanzamento, rilevamento
    automatico dello stato sul sistema, Punto di Ripristino e riavvio unico finale.
.EXAMPLE
    irm 070293.xyz/oxp-win | iex
    irm https://raw.githubusercontent.com/dilfal/onexplayer-1s-drivers/main/oxp1s.ps1 | iex
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

# ---------------------------------------------------------------------------
# 3. Manifest dei 12 driver OneXPlayer 1S (ordine sequenziale ottimale)
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
        Name           = 'Intel CSME / MEI-Only Driver'
        Category       = 'Sistema'
        PackageVersion = '15.0.1.1345'
        ZipName        = 'intel_(r)_csme_15.0.1.1345v4.2_b0_consumer.zip'
        AssetName      = 'intel_.r._csme_15.0.1.1345v4.2_b0_consumer.zip'
        SizeMB         = 307.7
        Method         = 'EXE'
        MethodLabel    = 'EXE Silenzioso (MEI-Only)'
        ExePath        = 'Intel_(R)_CSME_15.0.1.1345v4.2_B0_Consumer\Installers\MEI-Only Installer MSI\MEISetup.exe'
        ExeArgs        = '/s /drvonly /report "{LOG}"'
        OkCodes        = @(0)
        RebootCodes    = @(3010, 1641)
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
        PackageVersion = '1.41.987.0'
        ZipName        = 'tbt_dch_sw_rev75.zip'
        SizeMB         = 181.2
        Method         = 'INF'
        MethodLabel    = 'INF (pnputil)'
        InfTargets     = @(
            @{ Path = 'TBT_DCH_SW_Rev75\Drivers\ThunderboltWindowsDchSetup\TbtHostController.inf'; Subdirs = $false },
            @{ Path = 'TBT_DCH_SW_Rev75\Drivers\ThunderboltWindowsDchSetup\TbtP2pNdisDrv.inf'; Subdirs = $false },
            @{ Path = 'TBT_DCH_SW_Rev75\Drivers\ThunderboltApplicationLauncherSetup\TbtHostControllerExtension.inf'; Subdirs = $false }
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
    }
)

# ---------------------------------------------------------------------------
# 4. Rilevamento stato driver sul sistema Windows 11
# ---------------------------------------------------------------------------
function Get-SystemDriverSnapshot {
    $signedDrivers = @()
    $pnpErrors     = @()
    $uninstallApps = @()

    try { $signedDrivers = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction SilentlyContinue) } catch {}
    try { $pnpErrors     = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -and $_.Status -ne 'OK' }) } catch {}

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

        # 1) Cerca tra i driver firmati attivi
        foreach ($d in $snap.SignedDrivers) {
            $hit = $false
            if ($d.InfName) {
                foreach ($rx in $def.MatchInfs) {
                    if ($d.InfName -imatch $rx) { $hit = $true; break }
                }
            }
            if (-not $hit -and $d.DeviceName) {
                foreach ($rx in $def.MatchNames) {
                    if ($d.DeviceName -imatch $rx) { $hit = $true; break }
                }
            }
            if ($hit -and $d.DriverVersion) {
                $foundVer = $d.DriverVersion
                break
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

        # 3) Controlla se ci sono errori PnP correlati
        $hasError = $false
        foreach ($pe in $snap.PnpErrors) {
            foreach ($rx in $def.MatchNames) {
                if ($pe.FriendlyName -imatch $rx) { $hasError = $true; break }
            }
            if ($hasError) { break }
        }

        if ($hasError) {
            $item.SystemStatus = "Errore dispositivo (!)"
            $item.NeedsInstall = $true
        } elseif ($foundVer) {
            $cmp = Compare-DriverVersionSafe -Installed $foundVer -Package $def.PackageVersion
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

# Pre-seleziona di default quelli mancanti/aggiornabili se almeno uno manca, altrimenti tutti deselezionati?
# L'utente ha chiesto la possibilita di installarli tutti uno dopo l'altro: lasciamo selezionati i mancanti o tutti.
# Se tutti risultano mancanti (fresh install) sono gia tutti selezionati.

# ---------------------------------------------------------------------------
# 6. Definizione Interfaccia WPF (XAML stile Chris Titus WinUtil)
# ---------------------------------------------------------------------------
[xml]$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OneXPlayer 1S - Driver Utility (Windows 11 Pro)"
        Width="1040" Height="740"
        MinWidth="880" MinHeight="600"
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
    </Window.Resources>

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="175"/>
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
                    <TextBlock Text="OneXPlayer 1S - Driver Installer Utility" FontSize="20" FontWeight="Bold" Foreground="#38BDF8"/>
                    <TextBlock x:Name="TxtSubtitle" Text="Installazione sequenziale silenziosa per Windows 11 Pro (12 pacchetti ufficiali)"
                               FontSize="12" Foreground="#94A3B8" Margin="0,2,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" VerticalAlignment="Center" HorizontalAlignment="Right">
                    <TextBlock x:Name="TxtSystemInfo" Text="Admin OK" FontSize="12" FontWeight="SemiBold" Foreground="#4ADE80" HorizontalAlignment="Right"/>
                    <TextBlock x:Name="TxtPnpWarnings" Text="Dispositivi con errori: 0" FontSize="11" Foreground="#94A3B8" HorizontalAlignment="Right" Margin="0,2,0,0"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- TOOLBAR PRESET E OPZIONI -->
        <Border Grid.Row="1" Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="12,10" Margin="0,0,0,10">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <WrapPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
                    <Button x:Name="BtnSelectAll" Content="Seleziona Tutti (12)" Style="{StaticResource ToolbarBtn}"/>
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
        <Border Grid.Row="2" Background="#1E293B" BorderBrush="#334155" BorderThickness="1" CornerRadius="8" Padding="4" Margin="0,0,0,10">
            <DataGrid x:Name="GridDrivers"
                      AutoGenerateColumns="False"
                      CanUserAddRows="False"
                      CanUserDeleteRows="False"
                      CanUserReorderColumns="False"
                      HeadersVisibility="Column"
                      GridLinesVisibility="Horizontal"
                      HorizontalGridLinesBrush="#334155"
                      Background="#1E293B"
                      RowBackground="#1E293B"
                      AlternatingRowBackground="#162032"
                      Foreground="#F8FAFC"
                      BorderThickness="0"
                      SelectionMode="Single"
                      FontSize="12.5"
                      RowHeight="30">
                <DataGrid.ColumnHeaderStyle>
                    <Style TargetType="DataGridColumnHeader">
                        <Setter Property="Background" Value="#0F172A"/>
                        <Setter Property="Foreground" Value="#94A3B8"/>
                        <Setter Property="FontWeight" Value="SemiBold"/>
                        <Setter Property="Padding" Value="8,7"/>
                        <Setter Property="BorderBrush" Value="#334155"/>
                        <Setter Property="BorderThickness" Value="0,0,0,1"/>
                    </Style>
                </DataGrid.ColumnHeaderStyle>
                <DataGrid.CellStyle>
                    <Style TargetType="DataGridCell">
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
                </DataGrid.CellStyle>
                <DataGrid.Columns>
                    <DataGridCheckBoxColumn Header="Sel." Binding="{Binding IsSelected, UpdateSourceTrigger=PropertyChanged}" Width="46"/>
                    <DataGridTextColumn Header="#" Binding="{Binding Order}" IsReadOnly="True" Width="36"/>
                    <DataGridTextColumn Header="Driver" Binding="{Binding Name}" IsReadOnly="True" Width="260"/>
                    <DataGridTextColumn Header="Categoria" Binding="{Binding Category}" IsReadOnly="True" Width="115"/>
                    <DataGridTextColumn Header="Versione" Binding="{Binding PackageVersion}" IsReadOnly="True" Width="115"/>
                    <DataGridTextColumn Header="Metodo" Binding="{Binding MethodLabel}" IsReadOnly="True" Width="145"/>
                    <DataGridTextColumn Header="Stato sul PC" Binding="{Binding SystemStatus}" IsReadOnly="True" Width="155"/>
                    <DataGridTextColumn Header="Avanzamento" Binding="{Binding RunStatus}" IsReadOnly="True" Width="*"/>
                </DataGrid.Columns>
            </DataGrid>
        </Border>

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
                <Button x:Name="BtnInstall" Content="Installa Driver Selezionati" Style="{StaticResource PrimaryBtn}" Margin="0"/>
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
    'TxtLog', 'TxtFooterInfo', 'BtnCancel', 'BtnInstall'
) | ForEach-Object { $Ctrl[$_] = $Window.FindName($_) }

$Ctrl.GridDrivers.ItemsSource = $DriverItems

$osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$osLabel = if ($osInfo) { "$($osInfo.Caption) ($($osInfo.BuildNumber))" } else { "Windows 11" }
$Ctrl.TxtSystemInfo.Text = "Admin OK • $osLabel"
$Ctrl.TxtPnpWarnings.Text = "Dispositivi con errori/mancanti rilevati: $pnpErrCount"
$Ctrl.TxtPnpWarnings.Foreground = if ($pnpErrCount -gt 0) { '#FBBF24' } else { '#94A3B8' }

# ---------------------------------------------------------------------------
# 7. Stato condiviso per esecuzione asincrona (non blocca la UI WPF)
# ---------------------------------------------------------------------------
$Sync = [hashtable]::Synchronized(@{
    IsRunning       = $false
    CancelRequested = $false
    DirtyGrid       = $false
    LogQueue        = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
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
})

function Write-UiLog {
    param([string]$Message)
    $ts = (Get-Date).ToString("HH:mm:ss")
    $Sync.LogQueue.Enqueue("[$ts] $Message")
}

Write-UiLog "Utility avviata. Rilevati $($DriverItems.Count) pacchetti driver per OneXPlayer 1S."
Write-UiLog "Dispositivi PnP con problemi sul sistema: $pnpErrCount"

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

    $Ctrl.TxtProgressTitle.Text = $Sync.ProgressTitle
    $Ctrl.TxtProgressCount.Text = $Sync.ProgressCount
    $Ctrl.ProgressTotal.Value   = $Sync.TotalPct
    $Ctrl.ProgressStep.Value    = $Sync.StepPct

    if ($Sync.Finished) {
        $Sync.Finished = $false
        $Sync.IsRunning = $false

        $Ctrl.BtnInstall.IsEnabled = $true
        $Ctrl.BtnCancel.IsEnabled  = $false
        $Ctrl.BtnSelectAll.IsEnabled = $true
        $Ctrl.BtnSelectMissing.IsEnabled = $true
        $Ctrl.BtnSelectEssential.IsEnabled = $true
        $Ctrl.BtnSelectNone.IsEnabled = $true
        $Ctrl.BtnRefresh.IsEnabled = $true

        $errCnt = Update-DriverDetection -Items $DriverItems
        $Ctrl.TxtPnpWarnings.Text = "Dispositivi con errori/mancanti rilevati: $errCnt"
        $Ctrl.TxtPnpWarnings.Foreground = if ($errCnt -gt 0) { '#FBBF24' } else { '#94A3B8' }
        $Ctrl.GridDrivers.Items.Refresh()

        $summary = "Operazione completata.`nCompletati: $($Sync.SuccessCount) | Errori: $($Sync.ErrorCount)`nLog: $($Sync.LogFilePath)"
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
$Ctrl.BtnInstall.Add_Click({
    if ($Sync.IsRunning) { return }

    $selected = @($DriverItems | Where-Object { $_.IsSelected } | Sort-Object Order)
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Seleziona almeno un driver da installare.", "Nessuna selezione", "OK", "Warning") | Out-Null
        return
    }

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

    $Ctrl.BtnInstall.IsEnabled = $false
    $Ctrl.BtnCancel.IsEnabled  = $true
    $Ctrl.BtnSelectAll.IsEnabled = $false
    $Ctrl.BtnSelectMissing.IsEnabled = $false
    $Ctrl.BtnSelectEssential.IsEnabled = $false
    $Ctrl.BtnSelectNone.IsEnabled = $false
    $Ctrl.BtnRefresh.IsEnabled = $false

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
    }) | Out-Null

    $null = $ps.BeginInvoke()
})

# Avvia finestra WPF
$Window.Add_Closed({ $UiTimer.Stop() })
[void]$Window.ShowDialog()
