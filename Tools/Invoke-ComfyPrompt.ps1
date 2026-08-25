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
    # 'sdxl'     - CheckpointLoaderSimple, for SDXL/SD checkpoints
    # 'pixeldit' - NVIDIA PixelDiT: separate UNet + Gemma text encoder + pixel_space
    #              VAE, and crucially it runs at cfg > 1 with a WORKING negative
    #              prompt, unlike the distilled turbo models.
    [ValidateSet('sdxl','pixeldit')] [string] $Pipeline = 'sdxl',
    # img2img: start from an existing sprite instead of noise, so OUR geometry is
    # preserved and the model only supplies texture and shading. There are no
    # ControlNet models installed for PixelDiT (and none are likely to exist - it
    # is a new architecture), so this is the only structural control available.
    [string] $InitImage,
    [double] $Denoise = 1.0,
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
if (-not $Checkpoint -and $Pipeline -eq 'sdxl') {
    $info = Invoke-RestMethod -Uri "$Server/object_info/CheckpointLoaderSimple" -TimeoutSec 30
    $Checkpoint = $info.CheckpointLoaderSimple.input.required.ckpt_name[0][0]
    Write-Host ("  checkpoint : {0}" -f $Checkpoint) -ForegroundColor DarkGray
}

$clientId = [guid]::NewGuid().ToString()

# ComfyUI API format. Node ids are arbitrary strings; the wiring is the
# [ "<id>", <slot> ] references.
if ($Pipeline -eq 'pixeldit') {
    # Node graph copied from ComfyUI's own image_pixeldit_t2i template rather than
    # guessed: the CLIP loader needs type 'pixeldit', the latent comes from
    # EmptyChromaRadianceLatentImage (NOT EmptyLatentImage), and the sampler
    # defaults are er_sde / simple at 30 steps, cfg 4.
    if (-not $PSBoundParameters.ContainsKey('Steps'))     { $Steps = 30 }
    if (-not $PSBoundParameters.ContainsKey('Cfg'))       { $Cfg = 4.0 }
    if (-not $PSBoundParameters.ContainsKey('Sampler'))   { $Sampler = 'er_sde' }
    if (-not $PSBoundParameters.ContainsKey('Scheduler')) { $Scheduler = 'simple' }

    if ($InitImage) {
        # ComfyUI can only read images from its own input folder, so push it there
        # first. PS7's -Form does the multipart encoding.
        $up = Invoke-RestMethod -Uri "$Server/upload/image" -Method Post -TimeoutSec 60 -Form @{
            image = Get-Item -LiteralPath $InitImage
            overwrite = 'true'
        }
        $uploaded = if ($up.subfolder) { "$($up.subfolder)/$($up.name)" } else { $up.name }
        Write-Host ("  init image : {0} (denoise {1})" -f $uploaded, $Denoise) -ForegroundColor DarkGray
        $latentSrc = @('34', 0)
    } else {
        $latentSrc = @('31', 0)
    }

    $prompt = @{
        '2'  = @{ class_type = 'UNETLoader'; inputs = @{ unet_name = 'pixeldit_1300m_1024px_bf16.safetensors'; weight_dtype = 'default' } }
        '9'  = @{ class_type = 'CLIPLoader'; inputs = @{ clip_name = 'gemma_2_2b_it_elm_bf16.safetensors'; type = 'pixeldit'; device = 'default' } }
        '16' = @{ class_type = 'VAELoader';  inputs = @{ vae_name = 'pixel_space' } }
        '31' = @{ class_type = 'EmptyChromaRadianceLatentImage'; inputs = @{ width = $Width; height = $Height; batch_size = $Batch } }
        '6'  = @{ class_type = 'CLIPTextEncode'; inputs = @{ text = $Positive; clip = @('9', 0) } }
        '30' = @{ class_type = 'CLIPTextEncode'; inputs = @{ text = $Negative; clip = @('9', 0) } }
        '42' = @{ class_type = 'KSampler'; inputs = @{
                    seed = $Seed; steps = $Steps; cfg = $Cfg
                    sampler_name = $Sampler; scheduler = $Scheduler; denoise = 1.0
                    model = @('2', 0); positive = @('6', 0); negative = @('30', 0); latent_image = $latentSrc } }
        '15' = @{ class_type = 'VAEDecode'; inputs = @{ samples = @('42', 0); vae = @('16', 0) } }
        '43' = @{ class_type = 'SaveImage'; inputs = @{ filename_prefix = $Name; images = @('15', 0) } }
    }
    if ($InitImage) {
        $prompt['32'] = @{ class_type = 'LoadImage';  inputs = @{ image = $uploaded } }
        $prompt['33'] = @{ class_type = 'ImageScale'; inputs = @{
                            image = @('32', 0); width = $Width; height = $Height
                            upscale_method = 'lanczos'; crop = 'disabled' } }
        $prompt['34'] = @{ class_type = 'VAEEncode'; inputs = @{ pixels = @('33', 0); vae = @('16', 0) } }
        $prompt['42'].inputs.denoise = $Denoise
        $prompt.Remove('31')
    }
}
else {
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
