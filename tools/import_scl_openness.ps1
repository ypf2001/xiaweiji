param(
    [string]$ProjectPath = (Join-Path $PSScriptRoot '..\xiaweiji.ap21'),
    [string]$SclPath = (Join-Path $PSScriptRoot '..\src\xiaweiji.scl'),
    [string]$OpennessDllPath = '',
    [switch]$WithUserInterface
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
}

function Find-OpennessDll {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath)) {
            throw "Openness DLL not found: $ExplicitPath"
        }
        return (Resolve-FullPath $ExplicitPath)
    }

    $candidates = @(
        'C:\Program Files\Siemens\Automation\Portal V21\PublicAPI\V21\Siemens.Engineering.dll',
        'C:\Program Files\Siemens\Automation\Portal V21\Bin\PublicAPI\V21\Siemens.Engineering.dll',
        'C:\Program Files\Siemens\Automation\Portal V20\PublicAPI\V20\Siemens.Engineering.dll',
        'C:\Program Files\Siemens\Automation\Portal V19\PublicAPI\V19\Siemens.Engineering.dll'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $searchRoot = 'C:\Program Files\Siemens\Automation'
    if (Test-Path -LiteralPath $searchRoot) {
        $found = Get-ChildItem -LiteralPath $searchRoot -Recurse -Filter Siemens.Engineering.dll -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'PublicAPI' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    throw 'Siemens.Engineering.dll was not found. Install TIA Portal Openness, or pass -OpennessDllPath.'
}

function Get-PlcSoftware {
    param([Siemens.Engineering.TiaPortal]$TiaPortal)

    foreach ($device in $TiaPortal.Projects[0].Devices) {
        foreach ($deviceItem in $device.DeviceItems) {
            $softwareContainer = $deviceItem.GetService([Siemens.Engineering.HW.Features.SoftwareContainer])
            if ($softwareContainer -and ($softwareContainer.Software -is [Siemens.Engineering.SW.PlcSoftware])) {
                return $softwareContainer.Software
            }
        }
    }

    throw 'No PLC software object was found in the project.'
}

$projectFullPath = Resolve-FullPath $ProjectPath
$sclFullPath = Resolve-FullPath $SclPath
$dllFullPath = Find-OpennessDll $OpennessDllPath

Add-Type -Path $dllFullPath

$mode = [Siemens.Engineering.TiaPortalMode]::WithoutUserInterface
if ($WithUserInterface) {
    $mode = [Siemens.Engineering.TiaPortalMode]::WithUserInterface
}

$tiaPortal = [Siemens.Engineering.TiaPortal]::new($mode)

try {
    $project = $tiaPortal.Projects.Open([System.IO.FileInfo]::new($projectFullPath))
    $plcSoftware = Get-PlcSoftware $tiaPortal

    $sourceFile = [System.IO.FileInfo]::new($sclFullPath)
    $externalSource = $plcSoftware.ExternalSourceGroup.ExternalSources.CreateFromFile($sourceFile)

    try {
        $externalSource.GenerateBlocksFromSource([Siemens.Engineering.SW.ExternalSources.GenerateOptions]::Override)
    }
    finally {
        $externalSource.Delete()
    }

    $project.Save()
    Write-Host "Imported SCL into project: $projectFullPath"
}
finally {
    if ($project) {
        $project.Close()
    }
    $tiaPortal.Dispose()
}
