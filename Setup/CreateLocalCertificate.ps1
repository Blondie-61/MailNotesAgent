param(
  [Parameter(Mandatory=$true)]
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

$certFile       = Join-Path $OutputDir 'localhost-cert.pem'
$keyFile        = Join-Path $OutputDir 'localhost-key.pem'
$thumbprintFile = Join-Path $OutputDir 'localhost-thumbprint.txt'

$tempCertFile       = Join-Path $OutputDir 'localhost-cert.pem.new'
$tempKeyFile        = Join-Path $OutputDir 'localhost-key.pem.new'
$tempThumbprintFile = Join-Path $OutputDir 'localhost-thumbprint.txt.new'

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Write-PemFile {
  param(
    [string]$Path,
    [string]$Label,
    [byte[]]$Bytes
  )

  $base64 = [Convert]::ToBase64String($Bytes)
  $lines = [regex]::Matches($base64, '.{1,64}') | ForEach-Object { $_.Value }

  $text =
    "-----BEGIN $Label-----`r`n" +
    ($lines -join "`r`n") +
    "`r`n-----END $Label-----`r`n"

  [IO.File]::WriteAllText($Path, $text, [Text.Encoding]::ASCII)
}

function Remove-MailNotesCertificateByThumbprint {
  param([string]$Thumbprint)

  if (-not $Thumbprint) {
    return
  }

  foreach ($store in @('Root', 'My')) {
    $path = "Cert:\LocalMachine\$store\$Thumbprint"
    if (Test-Path $path) {
      Remove-Item $path -Force
    }
  }
}

function Test-MailNotesTlsMaterial {
  param(
    [string]$CertificateFile,
    [string]$PrivateKeyFile,
    [string]$ThumbprintFile
  )

  # Cert, Key und Thumbprint sind eine Einheit. Fehlt ein Bestandteil,
  # wird das komplette Material neu erzeugt.
  if (-not (Test-Path $CertificateFile)) { return $false }
  if (-not (Test-Path $PrivateKeyFile))  { return $false }
  if (-not (Test-Path $ThumbprintFile))  { return $false }

  try {
    $certPem = [IO.File]::ReadAllText($CertificateFile, [Text.Encoding]::ASCII)
    $keyPem  = [IO.File]::ReadAllText($PrivateKeyFile, [Text.Encoding]::ASCII)
    $thumbprint = ([IO.File]::ReadAllText($ThumbprintFile, [Text.Encoding]::ASCII)).Trim()

    if (-not $certPem.StartsWith('-----BEGIN CERTIFICATE-----')) { return $false }
    if (-not $keyPem.StartsWith('-----BEGIN PRIVATE KEY-----'))  { return $false }
    if (-not $thumbprint) { return $false }

    # Windows PowerShell 5.1/.NET Framework hat CreateFromPem() nicht.
    # Der gespeicherte Thumbprint und beide Zertifikatsspeicher reichen hier
    # als Konsistenzsignal, weil Cert/Key ausschließlich gemeinsam erzeugt
    # und gemeinsam ersetzt werden.
    if (-not (Test-Path "Cert:\LocalMachine\Root\$thumbprint")) { return $false }
    if (-not (Test-Path "Cert:\LocalMachine\My\$thumbprint"))   { return $false }

    return $true
  }
  catch {
    return $false
  }
}

function Remove-MailNotesTlsFiles {
  param(
    [string]$CertificateFile,
    [string]$PrivateKeyFile,
    [string]$ThumbprintFile
  )

  # Alte Setups haben Administratoren am Key nur Leserechte gegeben.
  # Dadurch konnte ein Upgrade den alten Key nicht ersetzen. Vor einem
  # Austausch bekommt die Administratorengruppe deshalb temporär Vollzugriff.
  if (Test-Path $PrivateKeyFile) {
    & icacls.exe $PrivateKeyFile /grant:r '*S-1-5-32-544:(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw 'Die Zugriffsrechte des vorhandenen TLS-Schlüssels konnten nicht für das Upgrade angepasst werden.'
    }
  }

  foreach ($file in @($CertificateFile, $PrivateKeyFile, $ThumbprintFile)) {
    if (Test-Path $file) {
      Remove-Item $file -Force
    }
  }
}

function Remove-TemporaryTlsFiles {
  foreach ($file in @($tempCertFile, $tempKeyFile, $tempThumbprintFile)) {
    if (Test-Path $file) {
      Remove-Item $file -Force -ErrorAction SilentlyContinue
    }
  }
}

$existingThumbprint = ''
if (Test-Path $thumbprintFile) {
  $existingThumbprint = ([IO.File]::ReadAllText($thumbprintFile, [Text.Encoding]::ASCII)).Trim()
}

if (Test-MailNotesTlsMaterial `
  -CertificateFile $certFile `
  -PrivateKeyFile $keyFile `
  -ThumbprintFile $thumbprintFile) {
  Write-Host 'MailNotes TLS material already exists and is trusted.'
  exit 0
}

Write-Host 'Existing MailNotes TLS material is incomplete or invalid. Recreating certificate and key.'
Remove-TemporaryTlsFiles

$cert = $null
$newThumbprint = ''

try {
  # Zuerst ein vollständiges neues Paar erzeugen. Die bestehenden Dateien
  # werden erst angefasst, wenn Cert, Key und Thumbprint erfolgreich vorliegen.
  $cert = New-SelfSignedCertificate `
    -DnsName 'localhost' `
    -CertStoreLocation 'Cert:\LocalMachine\My' `
    -FriendlyName 'MailNotes Local HTTPS' `
    -Provider 'Microsoft Software Key Storage Provider' `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -KeyExportPolicy Exportable `
    -NotAfter (Get-Date).AddYears(5)

  $newThumbprint = $cert.Thumbprint

  $rootStore = New-Object `
    System.Security.Cryptography.X509Certificates.X509Store(
      'Root',
      'LocalMachine'
    )

  $rootStore.Open(
    [System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite
  )

  try {
    $rootStore.Add($cert)
  }
  finally {
    $rootStore.Close()
  }

  Write-PemFile `
    -Path $tempCertFile `
    -Label 'CERTIFICATE' `
    -Bytes $cert.RawData

  $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)

  try {
    if (-not ($rsa -is [System.Security.Cryptography.RSACng])) {
      throw 'Der private Schlüssel wurde nicht als CNG-RSA-Schlüssel erzeugt.'
    }

    $keyBytes = $rsa.Key.Export(
      [System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob
    )

    Write-PemFile `
      -Path $tempKeyFile `
      -Label 'PRIVATE KEY' `
      -Bytes $keyBytes
  }
  finally {
    if ($rsa) {
      $rsa.Dispose()
    }
  }

  [IO.File]::WriteAllText(
    $tempThumbprintFile,
    $newThumbprint,
    [Text.Encoding]::ASCII
  )

  # Erst jetzt das alte Material als Einheit entfernen und das neue Paar
  # gemeinsam aktivieren.
  Remove-MailNotesTlsFiles `
    -CertificateFile $certFile `
    -PrivateKeyFile $keyFile `
    -ThumbprintFile $thumbprintFile

  Move-Item $tempCertFile       $certFile       -Force
  Move-Item $tempKeyFile        $keyFile        -Force
  Move-Item $tempThumbprintFile $thumbprintFile -Force

  # Agent läuft als Benutzer und muss lesen können. Administratoren erhalten
  # Vollzugriff, damit das nächste Setup den Key zuverlässig ersetzen kann.
  & icacls.exe $keyFile `
    /inheritance:r `
    /grant:r `
    '*S-1-5-18:(R)' `
    '*S-1-5-32-544:(F)' `
    '*S-1-5-32-545:(R)' | Out-Null

  if ($LASTEXITCODE -ne 0) {
    throw 'Die Zugriffsrechte des neuen TLS-Schlüssels konnten nicht gesetzt werden.'
  }

  # Das alte Zertifikat erst nach erfolgreicher Aktivierung des neuen Paares entfernen.
  if ($existingThumbprint -and ($existingThumbprint -ne $newThumbprint)) {
    Remove-MailNotesCertificateByThumbprint -Thumbprint $existingThumbprint
  }

  Write-Host "MailNotes TLS certificate created: $certFile"
  Write-Host "Thumbprint: $newThumbprint"
}
catch {
  Remove-TemporaryTlsFiles

  # Ein eventuell neu erzeugtes Zertifikat aus beiden Stores wieder entfernen,
  # wenn die Aktivierung nicht vollständig abgeschlossen wurde.
  if ($newThumbprint) {
    Remove-MailNotesCertificateByThumbprint -Thumbprint $newThumbprint
  }

  throw
}
finally {
  if ($cert) {
    $cert.Dispose()
  }
}
