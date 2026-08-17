param(
  [Parameter(Mandatory=$true)]
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

$certFile       = Join-Path $OutputDir 'localhost-cert.pem'
$keyFile        = Join-Path $OutputDir 'localhost-key.pem'
$thumbprintFile = Join-Path $OutputDir 'localhost-thumbprint.txt'

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

  [IO.File]::WriteAllText(
    $Path,
    $text,
    [Text.Encoding]::ASCII
  )
}

function Remove-MailNotesCertificateByThumbprint {
  param(
    [string]$Thumbprint
  )

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

function Test-MailNotesTlsPair {
  param(
    [string]$CertificateFile,
    [string]$PrivateKeyFile,
    [string]$Thumbprint
  )

  if (-not (Test-Path $CertificateFile)) {
    return $false
  }

  if (-not (Test-Path $PrivateKeyFile)) {
    return $false
  }

  if (-not $Thumbprint) {
    return $false
  }

  if (-not (Test-Path "Cert:\LocalMachine\Root\$Thumbprint")) {
    return $false
  }

  try {
    $certPem = [IO.File]::ReadAllText($CertificateFile, [Text.Encoding]::ASCII)
    $keyPem  = [IO.File]::ReadAllText($PrivateKeyFile, [Text.Encoding]::ASCII)

    if (-not $certPem.StartsWith('-----BEGIN CERTIFICATE-----')) {
      return $false
    }

    if (-not $keyPem.StartsWith('-----BEGIN PRIVATE KEY-----')) {
      return $false
    }

    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem(
      $certPem,
      $keyPem
    )

    try {
      if (-not $cert.HasPrivateKey) {
        return $false
      }

      if (-not [string]::Equals(
        $cert.Thumbprint,
        $Thumbprint,
        [System.StringComparison]::OrdinalIgnoreCase
      )) {
        return $false
      }

      return $true
    }
    finally {
      $cert.Dispose()
    }
  }
  catch {
    return $false
  }
}

$existingThumbprint = ''

if (Test-Path $thumbprintFile) {
  $existingThumbprint = (Get-Content $thumbprintFile -Raw).Trim()
}

if (
  (Test-MailNotesTlsPair `
    -CertificateFile $certFile `
    -PrivateKeyFile $keyFile `
    -Thumbprint $existingThumbprint)
) {
  Write-Host 'MailNotes TLS certificate already exists, matches the private key and is trusted.'
  exit 0
}

Write-Host 'Existing MailNotes TLS material is incomplete or invalid. Recreating certificate and key.'

Remove-MailNotesCertificateByThumbprint -Thumbprint $existingThumbprint

Remove-Item $certFile       -Force -ErrorAction SilentlyContinue
Remove-Item $keyFile        -Force -ErrorAction SilentlyContinue
Remove-Item $thumbprintFile -Force -ErrorAction SilentlyContinue

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

& icacls.exe $keyFile `
  /inheritance:r `
  /grant:r `
  '*S-1-5-18:(R)' `
  '*S-1-5-32-544:(R)' `
  '*S-1-5-32-545:(R)' | Out-Null

Write-Host "MailNotes TLS certificate created: $certFile"
Write-Host "Thumbprint: $($cert.Thumbprint)"
