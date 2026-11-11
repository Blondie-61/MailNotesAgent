param([Parameter(Mandatory = $true)][string]$Directory)
$ErrorActionPreference = 'Stop'
try {
    $root = (Resolve-Path -LiteralPath $Directory).Path
    $manifest = Get-Content -LiteralPath (Join-Path $root 'addin-build.json') -Raw | ConvertFrom-Json
    if ($manifest.version -ne 1 -or $manifest.files.Count -eq 0) { throw 'Invalid build manifest' }
    $names = @{}
    foreach ($entry in $manifest.files) {
        $name = [string]$entry.path
        if ($name -notmatch '^[a-zA-Z0-9_./-]+$' -or $name -match '(^|/)(\.|\.\.|)($|/)' -or $names.ContainsKey($name)) {
            throw 'Invalid build path'
        }
        $names[$name] = $true
        $file = Join-Path $root $name
        $stream = [IO.File]::OpenRead($file)
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
        } finally {
            $sha.Dispose()
            $stream.Dispose()
        }
        if ($hash -ne $entry.sha256) { throw "Hash mismatch: $name" }
    }
    foreach ($required in @('taskpane.html', 'taskpane.js', 'commands.html', 'commands.js', 'polyfill.js', 'manifest.xml')) {
        if (!$names.ContainsKey($required)) { throw "Missing file: $required" }
    }
    if (@(Get-ChildItem -LiteralPath $root -File -Recurse).Count -ne $names.Count + 1) { throw 'Unexpected build files' }
    exit 0
} catch {
    Write-Error $_
    exit 1
}
