﻿<#
.SYNOPSIS
    Local-Job-Gen
.DESCRIPTION
    Generates a set of jobs (as xml) based on the input groovy script
.PARAMETER CIFile
    netci.groovy file
.PARAMETER CIOutputDir
    Directory to put combined netci file as well as the output xml
.PARAMETER Project
    Project name.  Used to replace GithubProject.  If ommitted, "dotnet/test-project" is used
.PARAMETER Branch
    Branch name.  Used to replace GithubBranchName.  If ommitted, "master" is used
.PARAMETER DotnetCIUtilities
    Utilities.groovy file from the dotnet-ci repo.  If omitted, will be downloaded from dotnet-ci repo
.PARAMETER DotnetCIInternalUtilities
    InternalUtilities.groovy file fromm the dotnet-ci-internal repo.  Not needed if file does not reference InternalUtilities.  Parameter can be raw github link or local file.
.PARAMETER JobDslStandaloneJar
    Job DSL Standalone jar file.  If ommitted, currently in-use release is downloaded from dotnet-ci.  Can also be a local file.
.PARAMETER RemovePreviousGeneratedFiles
    Remove XML files from the output directory
.PARAMETER ForceJarDownload
    Even if jar exists, download.
.EXAMPLE
    .\Local-Job-Gen.ps1 -CIFile "https://raw.githubusercontent.com/dotnet/coreclr/master/netci.groovy" -CIOutputDir "D:\scratch\coreclr-master"
#>

param (
    [Parameter(Mandatory=$True)]
    [string]$CIFile = $(Read-Host -prompt "CI script file"),
    [Parameter(Mandatory=$True)]
    [string]$CIOutputDir = $(Read-Host -prompt "Directory for CI outputs"),
    [string]$Project = "dotnet/test-project",
	[string]$Branch = "master",
    [string]$DotnetCIUtilities = "https://raw.githubusercontent.com/dotnet/dotnet-ci/master/jobs/generation/Utilities.groovy",
    [string]$DotnetCIJobReport = "https://raw.githubusercontent.com/dotnet/dotnet-ci/master/jobs/generation/JobReport.groovy",
    [string]$DotnetCIInternalUtilities = $null,
    [string]$JobDslStandaloneJar = "https://github.com/dotnet/dotnet-ci/releases/download/1.40/job-dsl-core-1.40-SNAPSHOT-standalone.jar",
    [switch]$ForceJarDownload = $false,
    [switch]$RemovePreviousGeneratedFiles = $false
)

if (Test-Path $CIOutputDir)
{
    if (-not (Test-Path $CIOutputDir -PathType Container))
    {
        throw "CIOutput must be a directory or path that does not exist"
    }
}
else
{
    New-Item $CIOutputDir -ItemType Directory | Out-Null
}

if ($CIFile.StartsWith("http"))
{
    $outFile = [System.IO.Path]::Combine($CIOutputDir, "netci.groovy")
    Invoke-WebRequest $CIFile -OutFile $outFile
    $CIFile = $outFile
}

$CIFile = Resolve-Path $CIFile
$CIOutputDir = Resolve-Path $CIOutputDir
$combinedCIFileName = [System.IO.Path]::Combine($CIOutputDir, "combinednetci.groovy")

Write-Output "Processing $CIFile to $CIOutputDir.  Pre-processed groovy in $combinedCIFileName"
Write-Output "Please wait, this may take a few moments depending on the number of jobs created"

if ($RemovePreviousGeneratedFiles)
{
    Write-Verbose "Removing xml files from $CIOutputDir"

    Remove-Item -Path ([System.IO.Path]::Combine($CIOutputDir, "*")) -Include "*.xml"
}

Copy-Item $CIFile $combinedCIFileName -Force

# Grab the job DSL jar if it's at http

if ($JobDslStandaloneJar.StartsWith("http"))
{
    Write-Verbose "Downloading job dsl jar from $JobDslStandaloneJar"

    $outputJar = [System.IO.Path]::Combine($CIOutputDir, "job-dsl.jar")

    if ((Test-Path $outputJar) -and (-not $ForceJarDownload))
    {
        Write-Verbose "job-dsl jar already exists, skipping download (pass -ForceJarDownload to override)"
    }
    else
    {
        Invoke-WebRequest $JobDslStandaloneJar -OutFile $outputJar
    }

    $JobDslStandaloneJar = $outputJar
}

# Replace the following lines in the file:

# import jobs.generation.Utilities; -> With the groovy text from the DotnetCIUtilities as well as the data from the job report

$jobReportContent = $null
if ($DotnetCIJobReport.StartsWith("http"))
{
    Write-Verbose "Downloading Utilities.groovy from $DotnetCIUtilities"
    # Grab online
    $jobReport = Invoke-WebRequest $DotnetCIJobReport
    $jobReportContent = $jobReport.Content
}
else
{
    $jobReportContent = Get-Content $DotnetCIJobReport
    $jobReportContent = $jobReportContent -join [System.Environment]::Newline
}

$groovyText = Get-Content $combinedCIFileName

$dotnetCIContent = $null
if ($DotnetCIUtilities.StartsWith("http"))
{
    Write-Verbose "Downloading Utilities.groovy from $DotnetCIUtilities"
    # Grab online
    $dotnetCI = Invoke-WebRequest $DotnetCIUtilities
    $dotnetCIContent = $dotnetCI.Content
}
else
{
    $dotnetCIContent = Get-Content $DotnetCIUtilities
    $dotnetCIContent = $dotnetCIContent -join [System.Environment]::Newline
}

Write-Verbose "Preprocessing Utilities"

$groovyText = $groovyText -replace "import jobs.generation.Utilities;", $($dotnetCIContent + [System.Environment]::Newline)
$groovyText = $groovyText -replace "import jobs.generation.JobReport;", $($jobReportContent + [System.Environment]::Newline)

# import jobs.generation.InternalUtilities; -> With the groovy text from the DotnetCIInternalUtilities

if ($groovyText -match "import jobs.generation.InternalUtilities;")
{
    Write-Verbose "Preprocessing Internal Utilities"

    $dotnetInternalCIContent = $null
    if ($DotnetCIInternalUtilities -eq $null)
    {
        throw "Please provide a file/URL for the internal utilities"
    }

    if ($DotnetCIInternalUtilities.StartsWith("http"))
    {
        Write-Verbose "Downloading InternalUtilities.groovy from $DotnetCIInternalUtilities"
        $dotnetInternalCI = Invoke-WebRequest $DotnetCIInternalUtilities
        $dotnetInternalCIContent = $dotnetInternalCI.Content
    }
    else
    {
        $dotnetInternalCIContent = Get-Content $DotnetCIInternalUtilities
        $dotnetInternalCIContent = $dotnetInternalCIContent -join [System.Environment]::Newline
    }

    $groovyText = $groovyText -replace "import jobs.generation.InternalUtilities;", $dotnetInternalCIContent
}

$Project = '''' + $Project + ''''
$Branch = '''' + $Branch + ''''

$groovyText = $groovyText -replace "GithubProject", $Project
$groovyText = $groovyText -replace "GithubBranchName", $Branch

# Need to remove the package section, which is only valid at the top of the file.
$groovyText = $groovyText -replace "package jobs.generation;", ""

# WORKAROUNDS

# Replace the use of githubPullRequest with pullRequest since githubPullRequest currently sits in
# an extension.  There are other ways to potentially fix thisd.
$groovyText = $groovyText -replace "githubPullRequest", "pullRequest"
# Replace whitelist target branches with an empty line
$groovyText = $groovyText -replace ".*whiteListTargetBranches.*", ""
# Replace the Helix step with the batchFile
$groovyText = $groovyText -replace "helix\(", "batchFile("
# ViewStatus isn't available as a permission in the local jar, so change to Discover
$groovyText = $groovyText -replace "hudson.model.Item.ViewStatus", "hudson.model.Item.Discover"

Write-Verbose "Writing combined script"

# Write out to a file

Set-Content -Path $combinedCIFileName -Value $groovyText

Write-Verbose "Launching generator"

# Invoke the groovy parser
# Pass only the file, not the full path to the combined CI file
$combinedCIFileName = Split-Path $combinedCIFileName -leaf -resolve

try {
    $currentLocation = Get-Location
    Set-Location -Path $CIOutputDir
    & java.exe "-jar" $JobDslStandaloneJar $combinedCIFileName 2>&1 | %{ $_ | Where { -not $_.ToString().Contains('JarClassLoader') -and -not  $_.ToString().Contains('Generated item:') } }
}
finally {
    Set-Location -Path $currentLocation
}
