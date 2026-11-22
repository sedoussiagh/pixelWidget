param([switch]$WithTemperature)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$data = Join-Path $env:LOCALAPPDATA 'PixelMonitor'
[void][IO.Directory]::CreateDirectory($data)
$launcher = Join-Path $repo 'PixelMonitor.exe'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
$icon = Join-Path $repo 'PixelMonitor.ico'
& $compiler /nologo /target:winexe /reference:System.Windows.Forms.dll "/win32icon:$icon" "/out:$launcher" (Join-Path $repo 'PixelMonitorLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw 'La compilation du lanceur a échoué.' }

if ($WithTemperature) {
    $provider = Join-Path $data 'LibreHardwareMonitor'
    if (!(Test-Path -LiteralPath (Join-Path $provider 'LibreHardwareMonitorLib.dll'))) {
        $archive = Join-Path $data 'LibreHardwareMonitor-0.9.6.zip'
        Invoke-WebRequest -Uri 'https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v0.9.6/LibreHardwareMonitor.zip' -OutFile $archive -UseBasicParsing
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne '086d9f1b5a99e643edc2cfaaac16051685b551e4c5ac0b32a57c58c0e529c001') {
            throw 'Empreinte de Libre Hardware Monitor inattendue.'
        }
        Expand-Archive -LiteralPath $archive -DestinationPath $provider -Force
    }
}

$shell = New-Object -ComObject WScript.Shell
$places = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))
foreach ($place in $places) {
    $primary = Join-Path $place 'Pixel Monitor.lnk'
    $links = @(Get-ChildItem -LiteralPath $place -Filter 'Pixel Monitor*.lnk' | ForEach-Object FullName)
    foreach ($link in @($primary) + @($links | Where-Object { $_ -ne $primary })) {
        $shortcut = $shell.CreateShortcut($link)
        $shortcut.TargetPath = $launcher
        $shortcut.Arguments = ''
        $shortcut.WorkingDirectory = $repo
        $shortcut.IconLocation = "$icon,0"
        $shortcut.Description = 'Pixel Monitor - performances du PC'
        $shortcut.Save()
    }
}
