param(
    [string]$ProjectPath = (Join-Path $PSScriptRoot '..\xiaweiji.ap21'),
    [string]$SclPath = (Join-Path $PSScriptRoot '..\src\xiaweiji.scl'),
    [string]$OpennessDllPath = '',
    [string]$TiaVersion = 'V21',
    [string]$PythonOpennessRoot = 'D:\Digital Twin\plc_openness_v21',
    [switch]$WithUserInterface,
    [switch]$Compile,
    [switch]$ListOpennessDlls,
    [switch]$UsePowerShellOpenness
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
}

function Get-TiaVersionNumber([string]$Path) {
    $matches = [regex]::Matches($Path, 'V(\d+)')
    if ($matches.Count -eq 0) {
        return 0
    }
    return [int]$matches[$matches.Count - 1].Groups[1].Value
}

function Add-DllCandidate {
    param(
        [System.Collections.Generic.List[string]]$Candidates,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $fullPath = Resolve-FullPath $Path
    if (-not $Candidates.Contains($fullPath)) {
        [void]$Candidates.Add($fullPath)
    }
}

function Get-OpennessDllCandidates {
    param([string]$PreferredTiaVersion)

    $candidatePaths = [System.Collections.Generic.List[string]]::new()

    Add-DllCandidate $candidatePaths $env:TIA_OPENNESS_DLL
    Add-DllCandidate $candidatePaths $env:SIEMENS_ENGINEERING_DLL

    $installRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($root in @(
        $env:ProgramFiles,
        [Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),
        'C:\Program Files',
        'C:\Program Files (x86)',
        'D:\Program Files',
        'D:\Program Files (x86)'
    )) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $automationRoot = Join-Path $root 'Siemens\Automation'
            if ((Test-Path -LiteralPath $automationRoot) -and (-not $installRoots.Contains($automationRoot))) {
                [void]$installRoots.Add($automationRoot)
            }
        }
    }

    foreach ($automationRoot in $installRoots) {
        $preferredPortal = Join-Path $automationRoot "Portal $PreferredTiaVersion"
        Add-DllCandidate $candidatePaths (Join-Path $preferredPortal "PublicAPI\$PreferredTiaVersion\Siemens.Engineering.dll")
        Add-DllCandidate $candidatePaths (Join-Path $preferredPortal "PublicAPI\$PreferredTiaVersion\net48\Siemens.Engineering.dll")
        Add-DllCandidate $candidatePaths (Join-Path $preferredPortal "PublicAPI\$PreferredTiaVersion\net48\Siemens.Engineering.Base.dll")
        Add-DllCandidate $candidatePaths (Join-Path $preferredPortal "Bin\PublicAPI\$PreferredTiaVersion\Siemens.Engineering.dll")
        Add-DllCandidate $candidatePaths (Join-Path $preferredPortal "Bin\PublicAPI\$PreferredTiaVersion\net48\Siemens.Engineering.dll")
        Add-DllCandidate $candidatePaths (Join-Path $preferredPortal "Bin\PublicAPI\$PreferredTiaVersion\net48\Siemens.Engineering.Base.dll")

        $portalDirs = Get-ChildItem -LiteralPath $automationRoot -Directory -Filter 'Portal V*' -ErrorAction SilentlyContinue
        foreach ($portalDir in $portalDirs) {
            foreach ($relativePath in @(
                "PublicAPI\$PreferredTiaVersion\Siemens.Engineering.dll",
                "PublicAPI\$PreferredTiaVersion\net48\Siemens.Engineering.dll",
                "PublicAPI\$PreferredTiaVersion\net48\Siemens.Engineering.Base.dll",
                "Bin\PublicAPI\$PreferredTiaVersion\Siemens.Engineering.dll",
                "Bin\PublicAPI\$PreferredTiaVersion\net48\Siemens.Engineering.dll",
                "Bin\PublicAPI\$PreferredTiaVersion\net48\Siemens.Engineering.Base.dll",
                'PublicAPI',
                'Bin\PublicAPI'
            )) {
                $probePath = Join-Path $portalDir.FullName $relativePath
                if ($probePath.EndsWith('PublicAPI')) {
                    Get-ChildItem -LiteralPath $probePath -Recurse -Filter 'Siemens.Engineering.dll' -ErrorAction SilentlyContinue |
                        ForEach-Object { Add-DllCandidate $candidatePaths $_.FullName }
                    Get-ChildItem -LiteralPath $probePath -Recurse -Filter 'Siemens.Engineering.Base.dll' -ErrorAction SilentlyContinue |
                        ForEach-Object { Add-DllCandidate $candidatePaths $_.FullName }
                }
                else {
                    Add-DllCandidate $candidatePaths $probePath
                }
            }
        }
    }

    return $candidatePaths |
        Sort-Object `
            @{ Expression = { if ($_ -match "\\$PreferredTiaVersion\\") { 0 } else { 1 } } }, `
            @{ Expression = { -1 * (Get-TiaVersionNumber $_) } }, `
            @{ Expression = { $_ } }
}

function Show-OpennessDllCandidates {
    param([string]$PreferredTiaVersion)

    $candidates = @(Get-OpennessDllCandidates $PreferredTiaVersion)
    if ($candidates.Count -eq 0) {
        Write-Warning "No TIA Openness assembly candidates found for preferred TIA version $PreferredTiaVersion."
        return
    }

    Write-Host "Found TIA Openness assembly candidates:"
    foreach ($candidate in $candidates) {
        $mark = if ($candidate -match "\\$PreferredTiaVersion\\") { '*' } else { ' ' }
        Write-Host " $mark $candidate"
    }
}

function Find-OpennessDll {
    param(
        [string]$ExplicitPath,
        [string]$PreferredTiaVersion
    )

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath)) {
            throw "Openness DLL/API path not found: $ExplicitPath"
        }
        return (Resolve-FullPath $ExplicitPath)
    }

    $candidates = @(Get-OpennessDllCandidates $PreferredTiaVersion)
    if ($candidates.Count -gt 0) {
        return $candidates[0]
    }

    throw @"
TIA Openness assemblies were not found.
Checked common TIA Portal Openness locations under Program Files, Program Files (x86), and D:\Program Files.
Next checks:
  1. Confirm TIA Portal and TIA Openness are installed.
  2. Run this script with -ListOpennessDlls.
  3. If the DLL/API folder exists in a custom location, pass -OpennessDllPath "C:\...\PublicAPI\V21\net48".
  4. Confirm the selected DLL version matches the project target, currently $PreferredTiaVersion.
"@
}

function Load-OpennessAssemblies {
    param([string]$AssemblyOrApiPath)

    $resolvedPath = Resolve-FullPath $AssemblyOrApiPath
    $item = Get-Item -LiteralPath $resolvedPath

    if ($item.PSIsContainer) {
        $apiDir = $item.FullName
        $legacyDll = Join-Path $apiDir 'Siemens.Engineering.dll'
    }
    else {
        if ($item.Name -eq 'Siemens.Engineering.dll') {
            Add-Type -Path $item.FullName
            return
        }
        $apiDir = Split-Path -Parent $item.FullName
        $legacyDll = Join-Path $apiDir 'Siemens.Engineering.dll'
    }

    if (Test-Path -LiteralPath $legacyDll) {
        Add-Type -Path $legacyDll
        return
    }

    $baseDll = Join-Path $apiDir 'Siemens.Engineering.Base.dll'
    $step7Dll = Join-Path $apiDir 'Siemens.Engineering.Step7.dll'
    foreach ($requiredDll in @($baseDll, $step7Dll)) {
        if (-not (Test-Path -LiteralPath $requiredDll)) {
            throw "Required TIA Openness assembly not found: $requiredDll"
        }
    }

    $publicApiDir = Split-Path -Parent (Split-Path -Parent $apiDir)
    $portalRoot = Split-Path -Parent $publicApiDir
    $contractDll = Join-Path $portalRoot 'Bin\PublicAPI\Siemens.Engineering.Contract.dll'
    $binDir = Join-Path $portalRoot 'Bin'
    $binPublicApiDir = Join-Path $portalRoot 'Bin\PublicAPI'

    $script:OpennessAssemblySearchDirs = @(
        $apiDir,
        $binPublicApiDir,
        $binDir
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique

    if (-not $script:OpennessAssemblyResolverRegistered) {
        [System.AppDomain]::CurrentDomain.add_AssemblyResolve({
            param($sender, $eventArgs)

            $requestedName = [System.Reflection.AssemblyName]::new($eventArgs.Name).Name
            foreach ($loadedAssembly in [System.AppDomain]::CurrentDomain.GetAssemblies()) {
                if ($loadedAssembly.GetName().Name -eq $requestedName) {
                    return $loadedAssembly
                }
            }

            if ($null -eq $script:OpennessResolvingAssemblies) {
                $script:OpennessResolvingAssemblies = @{}
            }
            if ($script:OpennessResolvingAssemblies.ContainsKey($requestedName)) {
                return $null
            }

            $script:OpennessResolvingAssemblies[$requestedName] = $true
            $assemblyName = $requestedName + '.dll'
            foreach ($dir in $script:OpennessAssemblySearchDirs) {
                $candidate = Join-Path $dir $assemblyName
                if (Test-Path -LiteralPath $candidate) {
                    try {
                        return [System.Reflection.Assembly]::LoadFrom($candidate)
                    }
                    finally {
                        [void]$script:OpennessResolvingAssemblies.Remove($requestedName)
                    }
                }
            }
            [void]$script:OpennessResolvingAssemblies.Remove($requestedName)
            return $null
        })
        $script:OpennessAssemblyResolverRegistered = $true
    }

    function Load-AssemblyFromPath([string]$Path) {
        try {
            [void][System.Reflection.Assembly]::LoadFrom($Path)
        }
        catch [System.Reflection.ReflectionTypeLoadException] {
            Write-Error "Failed to load assembly: $Path"
            foreach ($loaderException in $_.Exception.LoaderExceptions) {
                Write-Error $loaderException.Message
            }
            throw
        }
    }

    if (Test-Path -LiteralPath $contractDll) {
        Load-AssemblyFromPath $contractDll
    }

    Load-AssemblyFromPath $baseDll
    Load-AssemblyFromPath $step7Dll
}

function Test-SplitNet48Openness {
    param([string]$AssemblyOrApiPath)

    $resolvedPath = Resolve-FullPath $AssemblyOrApiPath
    $item = Get-Item -LiteralPath $resolvedPath
    if ($item.PSIsContainer) {
        $apiDir = $item.FullName
    }
    elseif ($item.Name -eq 'Siemens.Engineering.Base.dll' -or $item.Name -eq 'Siemens.Engineering.Step7.dll') {
        $apiDir = Split-Path -Parent $item.FullName
    }
    else {
        return $false
    }

    return (
        (Test-Path -LiteralPath (Join-Path $apiDir 'Siemens.Engineering.Base.dll')) -and
        (Test-Path -LiteralPath (Join-Path $apiDir 'Siemens.Engineering.Step7.dll'))
    )
}

function Invoke-PythonOpennessImport {
    param(
        [string]$PythonRoot,
        [string]$Project,
        [string]$Source,
        [switch]$DoCompile
    )

    $importScript = Join-Path $PythonRoot 'examples\import_scl_to_project.py'
    if (-not (Test-Path -LiteralPath $importScript)) {
        throw "Python Openness import script not found: $importScript"
    }

    $arguments = @(
        $importScript,
        '--project', $Project,
        '--source', $Source,
        '--source-name', ([System.IO.Path]::GetFileNameWithoutExtension($Source)),
        '--no-ui'
    )
    if ($DoCompile) {
        $arguments += '--compile'
    }

    Write-Host "Using Python Openness bridge: $importScript"
    & python @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Python Openness import failed with exit code $LASTEXITCODE."
    }
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

function Write-CompileResult {
    param($CompileResult)

    if ($null -eq $CompileResult) {
        Write-Host 'Compile passed. TIA Openness did not return detailed diagnostics.'
        return 0
    }

    $errorCount = 0
    $warningCount = 0
    if ($CompileResult.PSObject.Properties.Name -contains 'ErrorCount') {
        $errorCount = [int]$CompileResult.ErrorCount
    }
    if ($CompileResult.PSObject.Properties.Name -contains 'WarningCount') {
        $warningCount = [int]$CompileResult.WarningCount
    }
    if ($CompileResult.PSObject.Properties.Name -contains 'State') {
        Write-Host "Compile state: $($CompileResult.State)"
    }
    Write-Host "Compile errors: $errorCount"
    Write-Host "Compile warnings: $warningCount"

    if ($CompileResult.PSObject.Properties.Name -contains 'Messages') {
        foreach ($message in $CompileResult.Messages) {
            Write-Host "[$($message.State)] $($message.Description)"
        }
    }

    return $errorCount
}

function Invoke-PlcCompile {
    param([Siemens.Engineering.SW.PlcSoftware]$PlcSoftware)

    $compiler = $PlcSoftware.GetService([Siemens.Engineering.Compiler.ICompilable])
    if ($null -eq $compiler) {
        throw 'PLC software does not expose Siemens.Engineering.Compiler.ICompilable.'
    }
    $compileResult = $compiler.Compile()
    return (Write-CompileResult $compileResult)
}

if ($ListOpennessDlls) {
    Show-OpennessDllCandidates $TiaVersion
    return
}

$projectFullPath = Resolve-FullPath $ProjectPath
$sclFullPath = Resolve-FullPath $SclPath
$opennessAssemblyPath = Find-OpennessDll $OpennessDllPath $TiaVersion

Write-Host "Using TIA Openness assembly/API path: $opennessAssemblyPath"

if ((-not $UsePowerShellOpenness) -and (Test-SplitNet48Openness $opennessAssemblyPath)) {
    Invoke-PythonOpennessImport -PythonRoot $PythonOpennessRoot -Project $projectFullPath -Source $sclFullPath -DoCompile:$Compile
    return
}

Load-OpennessAssemblies $opennessAssemblyPath

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

    if ($Compile) {
        Write-Host 'Compiling PLC software...'
        $compileErrors = Invoke-PlcCompile $plcSoftware
        if ($compileErrors -gt 0) {
            throw "PLC compile failed with $compileErrors error(s)."
        }
        Write-Host 'Compile passed.'
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
