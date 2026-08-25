<#
.SYNOPSIS
    Queues a text-to-image job on a LOCAL ComfyUI and retrieves the results.

.DESCRIPTION
    Talks to ComfyUI's HTTP API on 127.0.0.1:8188 so art can be generated and
    reviewed without touching the node editor:

        POST /prompt          queue a job, returns a prompt_id
        GET  /history/<id>    poll until the job appears, then read its outputs
        GET  /view?...        download each produced image

    The payload is ComfyUI's API format - a flat map of node id to
    { class_type, inputs } - which is NOT the same as the UI workflow JSON that
    gets dragged onto the canvas. Inputs that come from another node are written
    as [ "<node id>", <output slot> ].

    MODEL DEFAULTS MATTER MORE THAN THE PROMPT HERE. SDXL Turbo is a DISTILLED
    model: it is built for 1-4 steps at cfg 1.0, and running it at the usual 30
    steps / cfg 6 produces a burnt, oversaturated mess. Because cfg is 1.0,
    classifier-free guidance is off and the NEGATIVE PROMPT IS IGNORED - so
    unwanted content has to be excluded by describing what you do want instead.

    Defaults below are set for Turbo. Pass -Steps/-Cfg explicitly for a normal
    checkpoint.

.PARAMETER Positive
    What to draw.

.PARAMETER OutDir
    Where to save results. Defaults to the scratch folder, deliberately NOT
    Textures/ - generated images get reviewed before anything ships.

.EXAMPLE
    .\Tools\Invoke-ComfyPrompt.ps1 -Positive "a red rock landscape" -Batch 4
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Positive,
    [string] $Negative = 'text, watermark, signature, blurry, jpeg artifacts',
    [string] $Server   = 'http://127.0.0.1:8188',
    [string] $Checkpoint,
    [int]    $Width  = 512,
    [int]    $Height = 512,
    [int]    $Batch  = 4,
    [int]    $Steps  = 4,
    [double] $Cfg    = 1.0,
    [string] $Sampler   = 'euler_ancestral',
    [string] $Scheduler = 'normal',
    [int]    $Seed = 0,
    [string] $Name = 'RimRising',
    [string] $OutDir,
    [int]    $TimeoutSec = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $OutDir) {
    $OutDir = Join-Path ([System.IO.Path]::GetTempPath()) 'RimRisingArt'
}
if (-not (Test-Path $OutDir)) { $null = New-Item -ItemType Directory -Path $OutDir -Force }

if ($Seed -eq 0) { $Seed = Get-Random -Minimum 1 -Maximum 2147483646 }

# Pick the first installed checkpoint unless told otherwise, so the script works
# on a fresh install without the caller knowing what is there.
if (-not $Checkpoint) {
    $info = Invoke-RestMethod -Uri "$Server/object_info/CheckpointLoaderSimple" -TimeoutSec 30
    $Checkpoint = $info.CheckpointLoaderSimple.input.required.ckpt_name[0][0]
    Write-Host ("  checkpoint : {0}" -f $Checkpoint) -ForegroundColor DarkGray
}

$clientId = [guid]::NewGuid().ToString()

# ComfyUI API format. Node ids are arbitrary strings; the wiring is the
# [ "<id>", <slot> ] references.
$prompt = @{
    '4' = @{ class_type = 'CheckpointLoaderSimple'; inputs = @{ ckpt_name = $Checkpoint } }
    '5' = @{ class_type = 'EmptyLatentImage';       inputs = @{ width = $Width; height = $Height; batch_size = $Batch } }
    '6' = @{ class_type = 'CLIPTextEncode';         inputs = @{ text = $Positive; clip = @('4', 1) } }
    '7' = @{ class_type = 'CLIPTextEncode';         inputs = @{ text = $Negative; clip = @('4', 1) } }
    '3' = @{ class_type = 'KSampler'; inputs = @{
                seed = $Seed; steps = $Steps; cfg = $Cfg
                sampler_name = $Sampler; scheduler = $Scheduler; denoise = 1.0
                model = @('4', 0); positive = @('6', 0); negative = @('7', 0); latent_image = @('5', 0) } }
    '8' = @{ class_type = 'VAEDecode';  inputs = @{ samples = @('3', 0); vae = @('4', 2) } }
    '9' = @{ class_type = 'SaveImage';  inputs = @{ filename_prefix = $Name; images = @('8', 0) } }
}

$body = @{ prompt = $prompt; client_id = $clientId } | ConvertTo-Json -Depth 12 -Compress

Write-Host ("  queueing   : {0}x{1} x{2}, {3} steps, cfg {4}, seed {5}" -f $Width, $Height, $Batch, $Steps, $Cfg, $Seed) -ForegroundColor DarkGray
$queued = Invoke-RestMethod -Uri "$Server/prompt" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 60
$promptId = $queued.prompt_id
Write-Host ("  prompt_id  : {0}" -f $promptId) -ForegroundColor DarkGray

# Poll history. The entry only appears once the job finishes, so absence means
# "still running" rather than "failed".
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$entry = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 1500
    try {
        $hist = Invoke-RestMethod -Uri "$Server/history/$promptId" -TimeoutSec 30
    } catch { continue }
    if ($hist.PSObject.Properties[$promptId]) { $entry = $hist.$promptId; break }
}

if (-not $entry) { throw "Timed out after $TimeoutSec s waiting for $promptId. Is the model still loading? First run loads several GB." }

$saved = @()
foreach ($nodeId in $entry.outputs.PSObject.Properties.Name) {
    $node = $entry.outputs.$nodeId
    if (-not $node.PSObject.Properties['images']) { continue }
    foreach ($img in $node.images) {
        $q = "filename=$([uri]::EscapeDataString($img.filename))&subfolder=$([uri]::EscapeDataString($img.subfolder))&type=$($img.type)"
        $dest = Join-Path $OutDir $img.filename
        Invoke-WebRequest -Uri "$Server/view?$q" -OutFile $dest -TimeoutSec 120 | Out-Null
        $saved += $dest
        Write-Host ("  saved      : {0}" -f $dest) -ForegroundColor Green
    }
}

if ($saved.Count -eq 0) { throw 'Job finished but produced no images. Check the ComfyUI console for a node error.' }
$saved
