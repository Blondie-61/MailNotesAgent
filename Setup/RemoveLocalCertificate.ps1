param(
  [Parameter(Mandatory=$true)]
  [string]$OutputDir
)

$ErrorActionPreference = 'SilentlyContinue'

$thumbprintFile = Join-Path $OutputDir 'localhost-thumbprint.txt'
$thumbprint = ''

if (Test-Path $thumbprintFile) {
  $thumbprint = (Get-Content $thumbprintFile -Raw).Trim()
}

if ($thumbprint) {
  foreach ($store in @('Root', 'My')) {
    $path = "Cert:\LocalMachine\$store\$thumbprint"
    if (Test-Path $path) {
      Remove-Item $path -Force
    }
  }
}
else {
  # Rückfall für frühe Testinstallationen ohne gespeicherten Thumbprint:
  # nur Zertifikate mit unserem eindeutigen FriendlyName entfernen.
  Get-ChildItem 'Cert:\LocalMachine\Root' |
    Where-Object { $_.FriendlyName -eq 'MailNotes Local HTTPS' } |
    Remove-Item -Force

  Get-ChildItem 'Cert:\LocalMachine\My' |
    Where-Object { $_.FriendlyName -eq 'MailNotes Local HTTPS' } |
    Remove-Item -Force
}

if (Test-Path $OutputDir) {
  Remove-Item $OutputDir -Recurse -Force
}
