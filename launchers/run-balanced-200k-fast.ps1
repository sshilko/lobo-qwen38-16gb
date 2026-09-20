param(
    [string] $ModelPath = (Join-Path $PSScriptRoot '..\models\Qwen3.8-27B-GSQ-RCO-IQ3_S-MTP-Q4XS-Q3S.gguf'),
    [string] $ServerPath = '',
    [int] $Port = 18080,
    # fixed
    [int] $Threads = 8,
    [string] $SlotSavePath = ''
)

$ErrorActionPreference = 'Stop'
$ModelPath = [IO.Path]::GetFullPath($ModelPath)
if (-not $ServerPath) {
    $packaged = Join-Path $PSScriptRoot '..\runtime\llama-server.exe'
    $ServerPath = if (Test-Path -LiteralPath $packaged) { $packaged } else { Join-Path $PSScriptRoot '..\dist\lobo-sm120-win64\runtime\llama-server.exe' }
}
$ServerPath = [IO.Path]::GetFullPath($ServerPath)
if (-not (Test-Path -LiteralPath $ServerPath -PathType Leaf)) { throw "Server not found: $ServerPath" }
if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) { throw "MTP model pack not found: $ModelPath" }

# specifies the tile/block size (e.g., typically a fixed token block such as 32, 64, or 128 tokens) 
# over which local variance normalization and quantization operations are chunked and executed
#$env:GGML_KVARN_Q_TILE = '2'

$env:GGML_KVARN_Q_TILE = '2'
$env:GGML_KVARN_TEST_FORCE_PORTABLE_FATTN = $null
$env:GGML_KVARN_DEBUG_ROUTES = $null
$env:LLAMA_MTP_N_CTX = '256'
$env:LLAMA_MTP_SKIP_PREFILL = '1'

# '-b', '1024', '-ub', '1024'
# If VRAM allows, matching -ub to -b maximizes prompt evaluation speed

# KVarN quantization and Multi-Token Prediction (MTP) draft speculation llama fork
# use kvarn4 everywhere, kvarn2 is too degrading for long context and draft speculation, 
# ideally keys should be fp16 actually, but kvarn4 is the best quality for long context and draft speculation
# only values are fine to be quantized (but again, leads to hallucinations and degradation in long context)

$serverArgs = @(

    # fixed
    '-m', $ModelPath, '-c', '150000', '-b', '512', '-ub', '512',
    # fixed
    '-ctk', 'kvarn5', '-ctv', 'kvarn4', '--kv-tail-tokens', '256',

    '-t', "$Threads", '-ngl', 'all', '-fit', 'off', '-fa', 'on',
    '--load-mode', 'none', '--no-warmup', '--host', '127.0.0.1', '--port', "$Port",
    '-np', '1', '--no-ui', '--cache-prompt', '--cache-ram', '0',
    '--ctx-checkpoints', '1', '--no-cache-idle-slots', '--no-host',
    '--spec-type', 'draft-mtp', '--spec-draft-n-max', '3',
    '--temp 0.7', '--top-p 0.95', '--top-k 20', '--reasoning-preserve',

    '--parallel', '1', '--no-context-shift', 
    '--alias Qwen3.8-27B-GSQ-RCO-IQ3_S-MTP-Q4XS-Q3S',
    '--spec-draft-p-min', '0.75'

    # fixed
    '--spec-draft-type-k', 'kvarn5', '--spec-draft-type-v', 'kvarn4',

    '--log-colors', 'off'
)

if ($SlotSavePath) {
    $SlotSavePath = [IO.Path]::GetFullPath($SlotSavePath)
    New-Item -ItemType Directory -Force -Path $SlotSavePath | Out-Null
    $serverArgs += @('--slot-save-path', $SlotSavePath)
}

# The bounded 256-token draft cache is a hard part of this profile.
& $ServerPath @serverArgs
exit $LASTEXITCODE
