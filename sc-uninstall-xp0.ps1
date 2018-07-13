#####################################################
# 
#  Uninstall Sitecore
# 
#####################################################

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$scversion,
    [Parameter(Mandatory=$true)]
    [string]$instanceName,
    [string]$sqlServer = "localhost",
    [string]$sqlAdminUser = "sa",
    [Parameter(Mandatory=$true)]
    [string]$sqlAdminPassword,
    [string]$scwebroot
)

$ErrorActionPreference = "Stop"

if (Get-Module("Utilities")) {
    Remove-Module "Utilities"
}
Import-Module "$PSScriptRoot/scripts/Utilities.psm1"

$InstallerVersion = Get-Sitecore-SIF -SitecoreVersion $scversion
$SitecoreVersion = Get-Sitecore-Packages -SitecoreVersion $scversion

$webroot = $scwebroot

# SQL Parameters
$SqlServer = $sqlServer
$SqlAdminUser = $sqlAdminUser
$SqlAdminPassword = $sqlAdminPassword

# Solution parameters
$SolutionPrefix = $instanceName
$SitePostFix = "dev.local"
$SitecoreSiteName = "$SolutionPrefix.$SitePostFix"
$SitecoreSiteRoot = Join-Path $webroot -ChildPath $SitecoreSiteName


$XConnectSiteName = "${SolutionPrefix}_xconnect.$SitePostFix"
$XConnectSiteRoot = Join-Path $webroot -ChildPath $XConnectSiteName
$XConnectCert = "$SolutionPrefix.$SitePostFix.xConnect.Client"


# Solr Parameters
$SolrUrl = "https://localhost:8983/solr"


Write-Host "*******************************************************" -ForegroundColor Green
Write-Host " UN Installing Sitecore $SitecoreVersion" -ForegroundColor Green
Write-Host " Sitecore: $SitecoreSiteName" -ForegroundColor Green
Write-Host " xConnect: $XConnectSiteName" -ForegroundColor Green
Write-Host "*******************************************************" -ForegroundColor Green

Import-Module "$PSScriptRoot\build\uninstall\uninstall.psm1" -Force
#Import-Module SitecoreInstallFramework -RequiredVersion $InstallerVersion

#Install SIF
$module = Get-Module -FullyQualifiedName @{ModuleName="SitecoreInstallFramework";ModuleVersion=$InstallerVersion}
if (-not $module) {
    write-host "Installing the Sitecore Install Framework, version $InstallerVersion" -ForegroundColor Green
    Install-Module SitecoreInstallFramework -RequiredVersion $InstallerVersion -Scope CurrentUser
    Import-Module SitecoreInstallFramework -RequiredVersion $InstallerVersion
}

$carbon = Get-Module Carbon
if (-not $carbon) {
    $carbon = Get-InstalledModule Carbon
    if (-not $carbon) {
        write-host "Installing Carbon..." -ForegroundColor Green
        Install-Module -Name 'Carbon' -AllowClobber -Scope CurrentUser -Repository PSGallery
    }
    Import-Module Carbon
}


$database = Get-SitecoreDatabase -SqlServer $SqlServer -SqlAdminUser $SqlAdminUser -SqlAdminPassword $SqlAdminPassword

# Unregister xconnect services
Remove-SitecoreWindowsService "$XConnectSiteName-MarketingAutomationService"
Remove-SitecoreWindowsService "$XConnectSiteName-IndexWorker"

# Delete xconnect site
Remove-SitecoreIisSite $XConnectSiteName

# Drop xconnect databases
Remove-SitecoreDatabase -Name "${SolutionPrefix}_Xdb.Collection.Shard0" -Server $database
Remove-SitecoreDatabase -Name "${SolutionPrefix}_Xdb.Collection.Shard1" -Server $database
Remove-SitecoreDatabase -Name "${SolutionPrefix}_Xdb.Collection.ShardMapManager" -Server $database
Remove-SitecoreDatabase -Name "${SolutionPrefix}_MarketingAutomation" -Server $database
Remove-SitecoreDatabase -Name "${SolutionPrefix}_Processing.Pools" -Server $database
Remove-SitecoreDatabase -Name "${SolutionPrefix}_Processing.Tasks" -Server $database
Remove-SitecoreDatabase -Name "${SolutionPrefix}_ReferenceData" -Server $database
Remove-SitecoreDatabase -Name "${SolutionPrefix}_Reporting" -Server $database
Remove-SitecoreDatabase -Name "${SolutionPrefix}_EXM.Master" -Server $database
Remove-SitecoreDatabase -Name "${SolutionPrefix}_Messaging" -Server $database

# Delete xconnect files
Remove-SitecoreFiles $XConnectSiteRoot

# Delete xconnect server certificate
Remove-SitecoreCertificate $XConnectSiteName
# Delete xconnect client certificate
Remove-SitecoreCertificate $XConnectCert

# Delete sitecore site
Remove-SitecoreIisSite $SitecoreSiteName

# Drop sitecore databases
Remove-SitecoreDatabase -Name "${SolutionPrefix}_Core" -Server $database
Remove-SitecoreDatabase -Name "${SolutionPrefix}_ExperienceForms" -Server $database
Remove-SitecoreDatabase -Name "${SolutionPrefix}_Master" -Server $database
Remove-SitecoreDatabase -Name "${SolutionPrefix}_Web" -Server $database

# Delete sitecore files
Remove-SitecoreFiles $SitecoreSiteRoot

# Delete sitecore certificate
Remove-SitecoreCertificate $SitecoreSiteName

# Remove Solr indexes
Remove-SitecoreSolrCore -SolrUrl $SolrUrl -SolutionPrefix $SolutionPrefix