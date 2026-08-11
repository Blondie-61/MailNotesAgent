param(
  [Parameter(Mandatory=$true)]
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

$certFile       = Join-Path $OutputDir 'localhost-cert.pem'
$keyFile        = Join-Path $OutputDir 'localhost-key.pem'
$thumbprintFile = Join-Path $OutputDir 'localhost-thumbprint.txt'

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# Vorhandene, vollständige MailNotes-TLS-Installation weiterverwenden.
if ((Test-Path $certFile) -and
    (Test-Path $keyFile) -and
    (Test-Path $thumbprintFile)) {

  $existingThumbprint = (Get-Content $thumbprintFile -Raw).Trim()

  if ($existingThumbprint -and
      (Test-Path "Cert:\LocalMachine\Root\$existingThumbprint")) {
    Write-Host 'MailNotes TLS certificate already exists and is trusted.'
    exit 0
  }
}

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

  [IO.File]::WriteAllText(
    $Path,
    $text,
    [Text.Encoding]::ASCII
  )
}

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
  -Path $certFile `
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
    -Path $keyFile `
    -Label 'PRIVATE KEY' `
    -Bytes $keyBytes
}
finally {
  if ($rsa) {
    $rsa.Dispose()
  }
}

[IO.File]::WriteAllText(
  $thumbprintFile,
  $cert.Thumbprint,
  [Text.Encoding]::ASCII
)

# Der Agent läuft im Benutzerkontext. Normale Benutzer benötigen Leserechte
# auf den exportierten privaten Schlüssel.
& icacls.exe $keyFile `
  /inheritance:r `
  /grant:r `
  '*S-1-5-18:(R)' `
  '*S-1-5-32-544:(R)' `
  '*S-1-5-32-545:(R)' | Out-Null

Write-Host "MailNotes TLS certificate created: $certFile"
Write-Host "Thumbprint: $($cert.Thumbprint)"
