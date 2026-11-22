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
