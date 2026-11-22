param([switch]$SmokeTest,[switch]$SmokeTestMini)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$collect = {
    param($drive)
    $cpu = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -OperationTimeoutSec 3 -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3 -ErrorAction SilentlyContinue
    $disk = Get-CimInstance Win32_PerfFormattedData_PerfDisk_LogicalDisk -Filter "Name='$drive'" -OperationTimeoutSec 3 -ErrorAction SilentlyContinue
    $volume = [IO.DriveInfo]::new($drive)
    $battery = [Windows.Forms.SystemInformation]::PowerStatus
    if (!$script:thermalRefresh -or [datetime]::UtcNow -ge $script:thermalRefresh) {
        $script:thermalRefresh = [datetime]::UtcNow.AddSeconds(5)
        $script:thermalReading = Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -OperationTimeoutSec 3 -ErrorAction SilentlyContinue |
            ForEach-Object {
                $kelvin = if ($_.HighPrecisionTemperature -gt 0) { $_.HighPrecisionTemperature / 10 } else { $_.Temperature }
                if ($kelvin -ge 233 -and $kelvin -le 423) {
                    [pscustomobject]@{ Celsius = $kelvin - 273.15; Zone = ($_.Name -split '\.')[-1] }
                }
            } | Sort-Object Celsius -Descending | Select-Object -First 1
    }

    [pscustomobject]@{
        CPU = $cpu.PercentProcessorTime
        RAM = $(if ($os.TotalVisibleMemorySize) { [math]::Round(100 * (1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize)) })
        RamUsed = $(if ($os.TotalVisibleMemorySize) { ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB })
        RamTotal = $(if ($os.TotalVisibleMemorySize) { $os.TotalVisibleMemorySize / 1MB })
        Disk = $disk.PercentDiskTime
        DiskRead = $disk.DiskReadBytesPersec
        DiskWrite = $disk.DiskWriteBytesPersec
        Free = $(if ($volume.IsReady) { $volume.AvailableFreeSpace / 1GB })
        Capacity = $(if ($volume.IsReady) { $volume.TotalSize / 1GB })
        Temp = $script:thermalReading.Celsius
        TempZone = $script:thermalReading.Zone
        Battery = $(if ($battery.BatteryLifePercent -ge 0 -and $battery.BatteryChargeStatus -ne 'Unknown' -and -not ($battery.BatteryChargeStatus -band 128)) { [math]::Round(100 * $battery.BatteryLifePercent) })
        Power = $(if ($battery.PowerLineStatus -eq 'Online') { 'SECTEUR' } else { 'BATTERIE' })
    }
}

$script:folder = $PSScriptRoot
$script:settingsPath = Join-Path (Join-Path $env:LOCALAPPDATA 'PixelMonitor') 'settings.json'
$settings = [ordered]@{ Theme='Menthe'; Interval=3000; Scale=100; Mini=$false; History=$true; Animation=$false; Alerts='Standard'; Topmost=$false; Drive=$env:SystemDrive; X=$null; Y=$null; Visible=@('CPU','RAM','DISQUE','TEMP','BATTERIE') }
if (Test-Path -LiteralPath $script:settingsPath) {
    try {
        $loaded = Get-Content -Raw -LiteralPath $script:settingsPath | ConvertFrom-Json
        foreach ($key in @($settings.Keys)) {
            if ($loaded.PSObject.Properties[$key]) { $settings[$key] = $loaded.$key }
        }
    } catch { }
}
$themes = [ordered]@{ Menthe='#8CF5B0'; Ambre='#FFC46B'; Lavande='#D5A8FF'; Glacier='#80DCFF'; Rose='#FF91BC'; Arcade='#D9FB66' }
if (!$themes.Contains($settings.Theme)) { $settings.Theme = 'Menthe' }
$script:history = @{}
$script:pulse = 0
$thresholds = @{
    Prudent = @{ CPU=85; RAM=80; TEMP=75 }
    Standard = @{ CPU=95; RAM=90; TEMP=85 }
    Intensif = @{ CPU=99; RAM=95; TEMP=90 }
}

function Get-MetricValue($reading, $label) {
    if ($reading) {
        $key = switch ($label) {
            DISQUE { 'Disk' }
            BATTERIE { 'Battery' }
            default { $label }
        }
        $reading.$key
    }
}

function Add-MetricHistory($reading) {
    foreach ($label in @('CPU','RAM','DISQUE','TEMP','BATTERIE')) {
        if (!$script:history.ContainsKey($label)) {
            $script:history[$label] = [Collections.Generic.Queue[object]]::new()
        }
        $queue = $script:history[$label]
        if ($queue.Count -ge 60) { [void]$queue.Dequeue() }
        $queue.Enqueue((Get-MetricValue $reading $label))
    }
}

function Test-Threshold($label, $value) {
    $preset = $thresholds[$settings.Alerts]
    return ($null -ne $value -and $preset -and $preset.ContainsKey($label) -and $value -ge $preset[$label])
}

function Draw-History($graphics, $points, $brush, $left, $top, $width, $height) {
    if (!$points -or $points.Count -eq 0) { return }
    $indent = 60 - $points.Count
    $step = $width / 60.0
    foreach ($point in $points) {
        if ($null -ne $point) {
            $bar = [math]::Max(1,[math]::Round($height * [math]::Min(100,[math]::Max(0,$point)) / 100))
            $graphics.FillRectangle($brush,[single]($left + $indent * $step),[single]($top + $height - $bar),[single]([math]::Max(1,$step-1)),[single]$bar)
        }
        $indent++
    }
}

$sample = $null
$form = [Windows.Forms.Form]::new()
$form.Text = 'Pixel Monitor'
$windowIcon = Join-Path $folder 'PixelMonitor.ico'
if (Test-Path -LiteralPath $windowIcon) { $form.Icon = [Drawing.Icon]::new($windowIcon) }
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.ShowInTaskbar = $false
$form.TopMost = [bool]$settings.Topmost
$form.BackColor = [Drawing.ColorTranslator]::FromHtml('#111721')
$form.KeyPreview = $true
[Windows.Forms.Control].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($form, $true)

function Save-Settings {
    if ($SmokeTest) { return $true }
    $settings.X = $form.Left
    $settings.Y = $form.Top
    try {
        $directory = [IO.Path]::GetDirectoryName($script:settingsPath)
        [void][IO.Directory]::CreateDirectory($directory)
        $json = $settings | ConvertTo-Json
        [IO.File]::WriteAllText($script:settingsPath, $json, [Text.UTF8Encoding]::new($false))
        return $true
    } catch {
        Write-Warning "Pixel Monitor : impossible de sauvegarder les reglages. $($_.Exception.Message)"
        return $false
    }
}

function Resize-Widget {
    $factor = $settings.Scale / 100
    $count = @($settings.Visible).Count
    $width, $height = if ($settings.Mini) { 220; 42 + 22 * $count } else { 352; 81 + 56 * $count }
    $form.ClientSize = [Drawing.Size]::new([int]($width * $factor), [int]($height * $factor))
    if ($form.Visible) {
        $work = [Windows.Forms.Screen]::FromControl($form).WorkingArea
        $form.Left = [math]::Max($work.Left,[math]::Min($form.Left,$work.Right-$form.Width))
        $form.Top = [math]::Max($work.Top,[math]::Min($form.Top,$work.Bottom-$form.Height))
    }
    $form.Invalidate()
}

$form.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $factor = [single]($settings.Scale / 100)
    $g.ScaleTransform($factor,$factor)
    $g.TextRenderingHint = 'SingleBitPerPixelGridFit'
    $accent = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml($themes[$settings.Theme]))
    $muted = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#9CAEC5'))
    $track = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#2A384A'))
    $alert = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#FF9A80'))
    $bright = [Drawing.Brushes]::White
    $title = [Drawing.Font]::new('Consolas',17,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
    $small = [Drawing.Font]::new('Consolas',12,[Drawing.GraphicsUnit]::Pixel)
    $frame = [Drawing.Pen]::new($track,2)
    try {
        $secondPixel = if ($settings.Animation -and $script:pulse -eq 0) { $muted } else { $accent }
        if ($settings.Mini) {
            $g.DrawRectangle($frame,1,1,218,($form.ClientSize.Height / $factor)-2)
            $g.FillRectangle($accent,12,10,5,5)
            $g.FillRectangle($secondPixel,17,15,5,5)
            $g.DrawString('PIXEL MONITOR',$small,$bright,29,10)
            $g.DrawString('[+]',$small,$accent,181,10)
            $y = 33
            foreach ($label in $settings.Visible) {
                $meter = Get-MetricValue $sample $label
                $primary = if ($null -eq $meter) { '--' } elseif ($label -eq 'TEMP') { '{0:N0} °C' -f $meter } else { '{0:N0} %' -f [math]::Min(100,$meter) }
                $name = if ($label -eq 'TEMP') { 'ACPI' } else { $label }
                $g.DrawString($name,$small,$bright,12,$y)
                $ink = if (Test-Threshold $label $meter) { $alert } else { $accent }
                if ($settings.History) {
                    $g.FillRectangle($track,76,$y+2,78,12)
                    Draw-History $g $script:history[$label] $ink 76 ($y+2) 78 12
                } else {
                    for ($index=0; $index -lt 8; $index++) {
                        $fill = if ($null -ne $meter -and $index -lt [math]::Round($meter*8/100)) { $ink } else { $track }
                        $g.FillRectangle($fill,76+10*$index,$y+4,8,6)
                    }
                }
                if (Test-Threshold $label $meter) { $primary = '! ' + $primary }
                $g.DrawString($primary,$small,$ink,208-$g.MeasureString($primary,$small).Width,$y)
                $y += 22
            }
            return
        }
        $g.DrawRectangle($frame,1,1,350,($form.ClientSize.Height / $factor)-2)
        $g.FillRectangle($accent,16,15,8,8)
        $g.FillRectangle($secondPixel,24,23,8,8)
        $g.DrawString('PIXEL MONITOR',$title,$bright,40,14)
        $g.DrawString('[-]',$small,$accent,246,18)
        $g.DrawString('[ MENU ]',$small,$accent,276,18)
        $y = 48
        foreach ($label in $settings.Visible) {
            $meter = $null
            $primary = '--'
            $detail = 'Chargement...'
            if ($sample) {
                $detail = 'Mesure indisponible'
                switch ($label) {
                    CPU { $meter=$sample.CPU; if ($null -ne $meter) { $detail='Charge totale' } }
                    RAM { $meter=$sample.RAM; if ($null -ne $meter) { $detail='{0:N1} / {1:N1} Gio' -f $sample.RamUsed,$sample.RamTotal } }
                    DISQUE { $meter=$sample.Disk; if ($null -ne $meter) { $detail='{0}  L {1:N1} / E {2:N1} Mio/s' -f $settings.Drive,($sample.DiskRead/1MB),($sample.DiskWrite/1MB) } }
                    TEMP { if ($null -ne $sample.Temp) { $meter=$sample.Temp; $primary='{0:N0} °C' -f $meter; $detail='Zone ACPI ' + $sample.TempZone } else { $detail='Zone thermique indisponible' } }
                    BATTERIE { $meter=$sample.Battery; if ($null -ne $meter) { $detail=$sample.Power } }
                }
                if ($label -eq 'DISQUE' -and $null -ne $sample.Free) {
                    $detail += ('  |  {0:N0} Gio libres' -f $sample.Free)
                }
                if ($null -ne $meter -and $label -ne 'TEMP') { $primary='{0:N0} %' -f [math]::Min(100,$meter) }
            }
            $g.DrawString($label,$small,$bright,16,$y)
            $warn = Test-Threshold $label $meter
            $ink = if ($warn) { $alert } else { $accent }
            if ($warn) { $primary = '! ' + $primary }
            $g.DrawString($primary,$small,$ink,334-$g.MeasureString($primary,$small).Width,$y)
            if ($settings.History) {
                $g.FillRectangle($track,16,$y+16,317,12)
                Draw-History $g $script:history[$label] $ink 16 ($y+16) 317 12
            } else {
                for ($index=0; $index -lt 20; $index++) {
                    $fill = if ($null -ne $meter -and $index -lt [math]::Round($meter/5)) { $ink } else { $track }
                    $g.FillRectangle($fill,16+16*$index,$y+18,13,7)
                }
            }
            $g.DrawString($detail,$small,$muted,16,$y+29)
            $y += 56
        }
        $footer = if ($sample) { '{0:g} s  /  {1:HH:mm:ss}' -f ($settings.Interval/1000),$script:lastSample } else { 'Connexion aux compteurs Windows...' }
        $g.DrawString($footer,$small,$muted,16,$y+5)
    } finally {
        foreach ($resource in @($frame,$title,$small,$accent,$muted,$track,$alert)) { $resource.Dispose() }
    }
})

$timer = [Windows.Forms.Timer]::new()
$worker = [PowerShell]::Create()
$null = $worker.AddScript('Add-Type -AssemblyName System.Windows.Forms').Invoke()
$worker.Commands.Clear()
$script:pending = $null
$script:nextSample = [datetime]::MinValue
$timer.Interval = 250
$timer.Add_Tick({
    if ($settings.Animation -and $form.Visible) {
        $script:pulse = ($script:pulse + 1) % 4
        if ($script:pulse -le 1) {
            $factor = $settings.Scale / 100
            $form.Invalidate([Drawing.Rectangle]::new(0,0,[int](40*$factor),[int](36*$factor)))
        }
    }
    if ($script:pending -and $script:pending.IsCompleted) {
        try {
            $result = $worker.EndInvoke($script:pending)
            if ($result.Count -gt 0 -and $script:sampleDrive -eq $settings.Drive) {
                $script:sample = $result[-1]
                $script:lastSample = Get-Date
                Add-MetricHistory $script:sample
                $form.Invalidate()
            }
        } finally {
            $worker.Commands.Clear()
            $worker.Streams.ClearStreams()
            $script:pending = $null
        }
    }
    if (!$script:pending -and [datetime]::UtcNow -ge $script:nextSample) {
        $script:sampleDrive = $settings.Drive
        $null = $worker.AddScript($collect.ToString()).AddArgument($script:sampleDrive)
        $script:pending = $worker.BeginInvoke()
        $script:nextSample = [datetime]::UtcNow.AddMilliseconds($settings.Interval)
    }
})

$menu = [Windows.Forms.ContextMenuStrip]::new()
foreach ($group in @(
    @{ Label='Couleur'; Key='Theme'; Values=@($themes.Keys) },
    @{ Label='Alertes'; Key='Alerts'; Values=@('Désactivées','Prudent','Standard','Intensif') },
    @{ Label='Intervalle'; Key='Interval'; Values=@(1000,3000,5000,10000) },
    @{ Label='Taille'; Key='Scale'; Values=@(85,100,125,150) },
    @{ Label='Lecteur'; Key='Drive'; Values=@([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' } | ForEach-Object { $_.Name.TrimEnd('\') }) }
)) {
    $parent = $menu.Items.Add($group.Label)
    foreach ($value in $group.Values) {
        $label = switch ($group.Key) { Interval { "$($value/1000) s" }; Scale { "$value %" }; default { "$value" } }
        $option = $parent.DropDownItems.Add($label)
        $option.Tag = @($group.Key,$value)
        $option.Add_Click({
            param($sender,$e)
            $key,$value = $sender.Tag
            $settings[$key] = $value
            if ($key -eq 'Drive') { $script:sample = $null; $script:history.Remove('DISQUE') }
            $script:nextSample = [datetime]::MinValue
            Resize-Widget
            Save-Settings
        })
    }
    $parent.Add_DropDownOpening({
        param($sender,$e)
        foreach ($option in $sender.DropDownItems) { $option.Checked = $settings[$option.Tag[0]] -eq $option.Tag[1] }
    })
}
$miniItem = $menu.Items.Add('Mode miniature')
$miniItem.Checked = [bool]$settings.Mini
function Switch-WidgetLayout {
    $settings.Mini = !$settings.Mini
    $miniItem.Checked = $settings.Mini
    Resize-Widget
    [void](Save-Settings)
}
$miniItem.Add_Click({ Switch-WidgetLayout })
foreach ($toggle in @(@{Label='Historique (60 relevés)';Key='History'},@{Label='Animation du logo';Key='Animation'})) {
    $item = $menu.Items.Add($toggle.Label)
    $item.Tag = $toggle.Key
    $item.Checked = [bool]$settings[$toggle.Key]
    $item.Add_Click({
        param($sender,$e)
        $key = $sender.Tag
        $settings[$key] = !$settings[$key]
        $sender.Checked = $settings[$key]
        $form.Invalidate()
        [void](Save-Settings)
    })
}
$metrics = $menu.Items.Add('Mesures visibles')
$allMetrics = @('CPU','RAM','DISQUE','TEMP','BATTERIE')
foreach ($metric in $allMetrics) {
    $option = $metrics.DropDownItems.Add($metric)
    $option.Add_Click({
        param($sender,$e)
        if ($sender.Text -in $settings.Visible) {
            if (@($settings.Visible).Count -gt 1) { $settings.Visible = @($settings.Visible | Where-Object { $_ -ne $sender.Text }) }
        } else { $settings.Visible = @($allMetrics | Where-Object { $_ -eq $sender.Text -or $_ -in $settings.Visible }) }
        Resize-Widget
        Save-Settings
    })
}
$metrics.Add_DropDownOpening({ foreach ($option in $metrics.DropDownItems) { $option.Checked = $option.Text -in $settings.Visible } })
$pin = $menu.Items.Add('Toujours au premier plan')
$pin.Checked = $form.TopMost
$pin.Add_Click({ $form.TopMost = !$form.TopMost; $pin.Checked = $form.TopMost; $settings.Topmost = $form.TopMost; Save-Settings })
$null = $menu.Items.Add('Fermer', $null, { $form.Close() })
$form.ContextMenuStrip = $menu
$form.Add_MouseDown({
    param($sender,$e)
    if ($e.Button -eq 'Left') {
        $x = $e.X * 100 / $settings.Scale
        $y = $e.Y * 100 / $settings.Scale
        if ($settings.Mini -and $y -lt 30 -and $x -ge 174) { Switch-WidgetLayout }
        elseif (!$settings.Mini -and $y -lt 40 -and $x -ge 270) { $menu.Show($form,$e.Location) }
        elseif (!$settings.Mini -and $y -lt 40 -and $x -ge 241) { Switch-WidgetLayout }
        else { $script:anchor = $e.Location }
    }
})
$form.Add_MouseMove({
    param($sender,$e)
    if ($script:anchor -and $e.Button -eq 'Left') {
        $form.Left += $e.X - $script:anchor.X
        $form.Top += $e.Y - $script:anchor.Y
    }
})
$form.Add_MouseUp({ if ($script:anchor) { $script:anchor = $null; Save-Settings } })
$form.Add_FormClosed({
    $timer.Stop()
    $script:settingsSaved = Save-Settings
    try {
        if ($script:pending) { $worker.Stop() }
    } finally {
        $worker.Dispose()
        $timer.Dispose()
        $menu.Dispose()
    }
})
Resize-Widget
$area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = [Drawing.Point]::new(($area.Right-$form.Width-18),($area.Bottom-$form.Height-18))
if ($null -ne $settings.X -and $null -ne $settings.Y) {
    $candidate = [Drawing.Point]::new([int]$settings.X,[int]$settings.Y)
    $work = [Windows.Forms.Screen]::FromPoint($candidate).WorkingArea
    if ($work.Contains($candidate)) {
        $form.Left = [math]::Max($work.Left,[math]::Min($candidate.X,$work.Right-$form.Width))
        $form.Top = [math]::Max($work.Top,[math]::Min($candidate.Y,$work.Bottom-$form.Height))
    }
}

$form.Add_Shown({
    $form.BeginInvoke([Action]{
        $form.Hide()
        $form.Show()
    }) | Out-Null
})

if ($SmokeTest) {
    $settings.Mini = [bool]$SmokeTestMini
    Resize-Widget
    $expectedWidth = if ($settings.Mini) { 220 } else { 352 }
    if ($form.ClientSize.Width -ne [int]($expectedWidth * $settings.Scale / 100)) { throw 'Largeur du widget incorrecte' }
    $form.Show()
    $timer.Start()
    $deadline = [datetime]::UtcNow.AddSeconds(18)
    while ((!$sample -or $null -eq $sample.CPU -or $null -eq $sample.RAM -or $null -eq $sample.Disk) -and [datetime]::UtcNow -lt $deadline) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 40
    }
    if (!$sample -or $null -eq $sample.CPU -or $null -eq $sample.RAM -or $null -eq $sample.Disk) { throw 'Compteurs indisponibles' }
    $bitmap = [Drawing.Bitmap]::new($form.Width,$form.Height)
    $form.DrawToBitmap($bitmap,$form.ClientRectangle)
    $bitmap.Save((Join-Path $folder 'preview.png'))
    $bitmap.Dispose()
    $sample | ConvertTo-Json
    $form.Close()
    if (!$script:settingsSaved) { throw 'Sauvegarde des reglages non verifiee' }
    exit
}
$created = $false
$mutex = [Threading.Mutex]::new($true,'Local\PixelMonitorWidget',[ref]$created)
if (!$created) { $mutex.Dispose(); exit }
$timer.Start()
[Windows.Forms.Application]::Run($form)
$mutex.Dispose()
