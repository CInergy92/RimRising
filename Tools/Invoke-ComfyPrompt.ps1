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
    # 'zimage'   - Alibaba Z-Image-Turbo: 6B DiT with a Qwen3-4B text encoder, so
    #              prompt adherence is far better than SDXL Turbo's. Distilled
    #              though, so it runs at cfg 1 and the NEGATIVE PROMPT IS IGNORED -
    #              the official template wires ConditioningZeroOut into the negative
    #              slot to say so explicitly.
    # 'zcontrol' - Z-Image-Turbo + the Fun Union ControlNet patch. This is the one
    #              that matters for sprite work: -InitImage is reduced to Canny
    #              edges and used to CONSTRAIN geometry, so denoise stays at 1.0
    #              and the model repaints freely while our silhouette survives.
    #              img2img cannot do that - low denoise barely restyles and high
    #              denoise loses the shape.
    [ValidateSet('sdxl','pixeldit','zimage','zcontrol')] [string] $Pipeline = 'sdxl',
    # 0 = ignore the control image entirely, 1 = follow it closely.
    [double] $ControlStrength = 1.0,
    # Skip Canny and feed the init image to the ControlNet as-is (for depth or
    # pose maps that are already preprocessed).
    [switch] $NoCanny,
    [double] $CannyLow  = 0.1,
    [double] $CannyHigh = 0.32,
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

# ComfyUI can only read images from its own input folder, so push it there first.
# PS7's -Form does the multipart encoding.
function Send-InitImage {
    param([string] $Server, [string] $Path)
    $up = Invoke-RestMethod -Uri "$Server/upload/image" -Method Post -TimeoutSec 60 -Form @{
        image     = Get-Item -LiteralPath $Path
        overwrite = 'true'
    }
    if ($up.subfolder) { "$($up.subfolder)/$($up.name)" } else { $up.name }
}

$clientId = [guid]::NewGuid().ToString()

# ComfyUI API format. Node ids are arbitrary strings; the wiring is the
# [ "<id>", <slot> ] references.
if ($Pipeline -eq 'zcontrol') {
    if (-not $InitImage) { throw "-Pipeline zcontrol needs -InitImage: the control image is what supplies the geometry." }
    if (-not $PSBoundParameters.ContainsKey('Steps'))     { $Steps = 8 }
    if (-not $PSBoundParameters.ContainsKey('Cfg'))       { $Cfg = 1.0 }
    if (-not $PSBoundParameters.ContainsKey('Sampler'))   { $Sampler = 'res_multistep' }
    if (-not $PSBoundParameters.ContainsKey('Scheduler')) { $Scheduler = 'simple' }

    $patches = (Invoke-RestMethod -Uri "$Server/object_info/ModelPatchLoader" -TimeoutSec 30).ModelPatchLoader.input.required.name[0]
    $patch = $patches | Where-Object { $_ -match 'Controlnet-Union' } | Select-Object -First 1
    if (-not $patch) {
        throw "No ControlNet patch in models/model_patches. Open the 'Z-Image-Turbo Fun Union ControlNet' template in ComfyUI and let it download Z-Image-Turbo-Fun-Controlnet-Union.safetensors."
    }

    $uploaded = Send-InitImage -Server $Server -Path $InitImage
    Write-Host ("  control    : {0} via {1}, strength {2}" -f $uploaded, $(if ($NoCanny) { 'raw' } else { 'canny' }), $ControlStrength) -ForegroundColor DarkGray

    $prompt = @{
        '46' = @{ class_type = 'UNETLoader'; inputs = @{ unet_name = 'z_image_turbo_bf16.safetensors'; weight_dtype = 'default' } }
        '39' = @{ class_type = 'CLIPLoader'; inputs = @{ clip_name = 'qwen_3_4b.safetensors'; type = 'lumina2'; device = 'default' } }
        '40' = @{ class_type = 'VAELoader';  inputs = @{ vae_name = 'ae.safetensors' } }
        '64' = @{ class_type = 'ModelPatchLoader'; inputs = @{ name = $patch } }
        '58' = @{ class_type = 'LoadImage'; inputs = @{ image = $uploaded } }
        '62' = @{ class_type = 'ImageScaleToMaxDimension'; inputs = @{
                    image = @('58', 0); upscale_method = 'lanczos'; largest_size = $Width } }
        # ControlNet patches the raw UNet; the AuraFlow shift goes AFTER it.
        '60' = @{ class_type = 'QwenImageDiffsynthControlnet'; inputs = @{
                    model = @('46', 0); model_patch = @('64', 0); vae = @('40', 0)
                    image = @('57', 0); strength = $ControlStrength } }
        '47' = @{ class_type = 'ModelSamplingAuraFlow'; inputs = @{ model = @('60', 0); shift = 3.0 } }
        '45' = @{ class_type = 'CLIPTextEncode'; inputs = @{ text = $Positive; clip = @('39', 0) } }
        '42' = @{ class_type = 'ConditioningZeroOut'; inputs = @{ conditioning = @('45', 0) } }
        # Latent is sized from the control image so the two grids line up exactly.
        '69' = @{ class_type = 'GetImageSize'; inputs = @{ image = @('57', 0) } }
        '41' = @{ class_type = 'EmptySD3LatentImage'; inputs = @{
                    width = @('69', 0); height = @('69', 1); batch_size = $Batch } }
        '44' = @{ class_type = 'KSampler'; inputs = @{
                    seed = $Seed; steps = $Steps; cfg = $Cfg
                    sampler_name = $Sampler; scheduler = $Scheduler; denoise = 1.0
                    model = @('47', 0); positive = @('45', 0); negative = @('42', 0); latent_image = @('41', 0) } }
        '43' = @{ class_type = 'VAEDecode'; inputs = @{ samples = @('44', 0); vae = @('40', 0) } }
        '9'  = @{ class_type = 'SaveImage'; inputs = @{ filename_prefix = $Name; images = @('43', 0) } }
    }
    if ($NoCanny) {
        $prompt['57'] = @{ class_type = 'ImageScaleToMaxDimension'; inputs = @{
                            image = @('58', 0); upscale_method = 'lanczos'; largest_size = $Width } }
        $prompt.Remove('62')
    } else {
        $prompt['57'] = @{ class_type = 'Canny'; inputs = @{
                            image = @('62', 0); low_threshold = $CannyLow; high_threshold = $CannyHigh } }
    }
}
elseif ($Pipeline -eq 'zimage') {
    # Graph copied from ComfyUI's image_z_image_turbo template. Note CLIP type
    # 'lumina2' (not a 'z_image' type - there isn't one), EmptySD3LatentImage, and
    # the ModelSamplingAuraFlow shift-3 patch between the UNet and the sampler.
    if (-not $PSBoundParameters.ContainsKey('Steps'))     { $Steps = 8 }
    if (-not $PSBoundParameters.ContainsKey('Cfg'))       { $Cfg = 1.0 }
    if (-not $PSBoundParameters.ContainsKey('Sampler'))   { $Sampler = 'res_multistep' }
    if (-not $PSBoundParameters.ContainsKey('Scheduler')) { $Scheduler = 'simple' }
    if ($Negative -and $Cfg -le 1.0) {
        Write-Host '  note       : cfg is 1, so the negative prompt is ignored. Describe what you WANT instead.' -ForegroundColor Yellow
    }

    $prompt = @{
        '28' = @{ class_type = 'UNETLoader'; inputs = @{ unet_name = 'z_image_turbo_bf16.safetensors'; weight_dtype = 'default' } }
        '30' = @{ class_type = 'CLIPLoader'; inputs = @{ clip_name = 'qwen_3_4b.safetensors'; type = 'lumina2'; device = 'default' } }
        '29' = @{ class_type = 'VAELoader';  inputs = @{ vae_name = 'ae.safetensors' } }
        '11' = @{ class_type = 'ModelSamplingAuraFlow'; inputs = @{ model = @('28', 0); shift = 3.0 } }
        '27' = @{ class_type = 'CLIPTextEncode'; inputs = @{ text = $Positive; clip = @('30', 0) } }
        '33' = @{ class_type = 'ConditioningZeroOut'; inputs = @{ conditioning = @('27', 0) } }
        '13' = @{ class_type = 'EmptySD3LatentImage'; inputs = @{ width = $Width; height = $Height; batch_size = $Batch } }
        '3'  = @{ class_type = 'KSampler'; inputs = @{
                    seed = $Seed; steps = $Steps; cfg = $Cfg
                    sampler_name = $Sampler; scheduler = $Scheduler; denoise = 1.0
                    model = @('11', 0); positive = @('27', 0); negative = @('33', 0); latent_image = @('13', 0) } }
        '8'  = @{ class_type = 'VAEDecode';  inputs = @{ samples = @('3', 0); vae = @('29', 0) } }
        '9'  = @{ class_type = 'SaveImage';  inputs = @{ filename_prefix = $Name; images = @('8', 0) } }
    }

    if ($InitImage) {
        $uploaded = Send-InitImage -Server $Server -Path $InitImage
        Write-Host ("  init image : {0} (denoise {1})" -f $uploaded, $Denoise) -ForegroundColor DarkGray
        $prompt['20'] = @{ class_type = 'LoadImage';  inputs = @{ image = $uploaded } }
        $prompt['21'] = @{ class_type = 'ImageScale'; inputs = @{
                            image = @('20', 0); width = $Width; height = $Height
                            upscale_method = 'lanczos'; crop = 'disabled' } }
        $prompt['22'] = @{ class_type = 'VAEEncode'; inputs = @{ pixels = @('21', 0); vae = @('29', 0) } }
        # VAEEncode yields batch 1, so ask for variants explicitly.
        $prompt['23'] = @{ class_type = 'RepeatLatentBatch'; inputs = @{ samples = @('22', 0); amount = $Batch } }
        $prompt['3'].inputs.latent_image = @('23', 0)
        $prompt['3'].inputs.denoise = $Denoise
        $prompt.Remove('13')
    }
}
elseif ($Pipeline -eq 'pixeldit') {
    # Node graph copied from ComfyUI's own image_pixeldit_t2i template rather than
    # guessed: the CLIP loader needs type 'pixeldit', the latent comes from
    # EmptyChromaRadianceLatentImage (NOT EmptyLatentImage), and the sampler
    # defaults are er_sde / simple at 30 steps, cfg 4.
    if (-not $PSBoundParameters.ContainsKey('Steps'))     { $Steps = 30 }
    if (-not $PSBoundParameters.ContainsKey('Cfg'))       { $Cfg = 4.0 }
    if (-not $PSBoundParameters.ContainsKey('Sampler'))   { $Sampler = 'er_sde' }
    if (-not $PSBoundParameters.ContainsKey('Scheduler')) { $Scheduler = 'simple' }

    if ($InitImage) {
        $uploaded = Send-InitImage -Server $Server -Path $InitImage
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
        $prompt['35'] = @{ class_type = 'RepeatLatentBatch'; inputs = @{ samples = @('34', 0); amount = $Batch } }
        $prompt['42'].inputs.latent_image = @('35', 0)
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
