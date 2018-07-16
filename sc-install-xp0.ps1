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
    [Parameter(Mandatory=$true)]
    [string]$solrRoot,
    [string]$scwebroot
)

$ErrorActionPreference = 'Stop'
#. $PSScriptRoot\settings.ps1

if (Get-Module("Utilities")) {
    Remove-Module "Utilities"
}
Import-Module "$PSScriptRoot/scripts/Utilities.psm1"

$InstallerVersion = Get-Sitecore-SIF -SitecoreVersion $scversion
$SitecoreVersion = Get-Sitecore-Packages -SitecoreVersion $scversion

# Solution parameters
$SolutionPrefix = $instanceName
$SitePostFix = "dev.local"
$webroot = $scwebroot

# SQL Parameters
$SqlServer = $sqlServer
$SqlAdminUser = $sqlAdminUser
$SqlAdminPassword = $sqlAdminPassword

# Assets and prerequisites
$AssetsRoot = "$PSScriptRoot\build\assets"
$AssetsPSRepository = "https://sitecore.myget.org/F/sc-powershell/api/v2/"
$AssetsPSRepositoryName = "SitecoreGallery"

$LicenseFile = "$AssetsRoot\license.xml"

# Certificates
$CertPath = Join-Path "$AssetsRoot" "Certificates"

$ConfigurationPath = "$AssetsRoot\$scversion"

# XConnect Parameters
$XConnectConfiguration = "$ConfigurationPath\xconnect-xp0.json"
$XConnectCertificateConfiguration = "$ConfigurationPath\xconnect-createcert.json"
$XConnectSolrConfiguration = "$ConfigurationPath\xconnect-solr.json"
$XConnectPackage = "$AssetsRoot\Sitecore $SitecoreVersion (OnPrem)_xp0xconnect.scwdp.zip"
$XConnectSiteName = "${SolutionPrefix}_xconnect.$SitePostFix"
$XConnectCert = "$SolutionPrefix.$SitePostFix.xConnect.Client"
$XConnectSiteRoot = Join-Path $webroot -ChildPath $XConnectSiteName
$XConnectSqlCollectionUser = "collectionuser"
$XConnectSqlCollectionPassword = "Test12345"

# Sitecore Parameters
$SitecoreSolrConfiguration = "$ConfigurationPath\sitecore-solr.json"
$SitecoreConfiguration = "$ConfigurationPath\sitecore-xp0.json"
$SitecoreSSLConfiguration = "$PSScriptRoot\build\certificates\sitecore-ssl.json"
$SitecorePackage = "$AssetsRoot\Sitecore $SitecoreVersion (OnPrem)_single.scwdp.zip"
$SitecoreSiteName = "$SolutionPrefix.$SitePostFix"
$SitecoreSiteRoot = Join-Path $webroot -ChildPath $SitecoreSiteName

# Solr Parameters
$SolrUrl = "https://localhost:8983/solr"
$SolrRoot = $solrRoot


function Install-Prerequisites {
    #Verify SQL version
    $SqlRequiredVersion = "13.0.4001"
    [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | out-null
    $srv = New-Object "Microsoft.SqlServer.Management.Smo.Server" $SqlServer
    $minVersion = New-Object System.Version($RequiredSqlVersion)
    if ($srv.Version.CompareTo($minVersion) -lt 0) {
        throw "Invalid SQL version. Expected SQL 2016 SP1 (13.0.4001.0) or over."
    }

    # Verify Web Deploy
    $webDeployPath = ([IO.Path]::Combine($env:ProgramFiles, 'iis', 'Microsoft Web Deploy V3', 'msdeploy.exe'))
    if (!(Test-Path $webDeployPath)) {
        throw "Could not find WebDeploy in $webDeployPath"
    }   

    # Verify DAC Fx
    # Verify Microsoft.SqlServer.TransactSql.ScriptDom.dll
    try {
        $assembly = [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.TransactSql.ScriptDom")
        if (-not $assembly) {
            throw "error"
        }
    } catch {
        throw "Could load the Microsoft.SqlServer.TransactSql.ScriptDom assembly. Please make sure it is installed and registered in the GAC"
    }
    
    #Add ApplicationPoolIdentity to performance log users to avoid Sitecore log errors (https://kb.sitecore.net/articles/404548)
     if (!(Get-LocalGroupMember "Performance Log Users" "IIS APPPOOL\DefaultAppPool")) {
         Add-LocalGroupMember "Performance Log Users" "IIS APPPOOL\DefaultAppPool"    
     }
     if (!(Get-LocalGroupMember "Performance Monitor Users" "IIS APPPOOL\DefaultAppPool")) {
         Add-LocalGroupMember "Performance Monitor Users" "IIS APPPOOL\DefaultAppPool"
     }
    
    #Enable Contained Databases
    Write-Host "Enable contained databases" -ForegroundColor Green
    try
    {
        Invoke-Sqlcmd -ServerInstance $SqlServer `
                      -Username $SqlAdminUser `
                      -Password $SqlAdminPassword `
                      -InputFile "$PSScriptRoot\build\database\containedauthentication.sql"
    }
    catch
    {
        write-host "Set Enable contained databases failed" -ForegroundColor Red
        throw
    }

    # Verify Solr
    Verify-Solr -SolrUrl $SolrUrl
    

	#Verify .NET framework
	$requiredDotNetFrameworkVersionValue = 394802
	$requiredDotNetFrameworkVersion = "4.6.2"
	$versionExists = Get-ChildItem "hklm:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\" | Get-ItemPropertyValue -Name Release | % { $_ -ge $requiredDotNetFrameworkVersionValue }
	if (-not $versionExists) {
		throw "Please install .NET Framework $requiredDotNetFrameworkVersion or later"
	}
}

function Install-Assets {
    #Register Assets PowerShell Repository
    if ((Get-PSRepository | Where-Object {$_.Name -eq $AssetsPSRepositoryName}).count -eq 0) {
        Register-PSRepository -Name $AssetsPSRepositoryName -SourceLocation $AssetsPSRepository -InstallationPolicy Trusted
    }

    #Sitecore Install Framework dependencies
    Import-Module WebAdministration

    #Install SIF
    $module = Get-Module -FullyQualifiedName @{ModuleName="SitecoreInstallFramework";ModuleVersion=$InstallerVersion}
    if (-not $module) {
        write-host "Installing the Sitecore Install Framework, version $InstallerVersion" -ForegroundColor Green
        Install-Module SitecoreInstallFramework -RequiredVersion $InstallerVersion -Scope CurrentUser
        Import-Module SitecoreInstallFramework -RequiredVersion $InstallerVersion
    }

    #Verify that manual assets are present
    if (!(Test-Path $AssetsRoot)) {
        throw "$AssetsRoot not found"
    }

    #Verify license file
    if (!(Test-Path $LicenseFile)) {
        throw "License file $LicenseFile not found"
    }
    
    #Verify Sitecore package
    if (!(Test-Path $SitecorePackage)) {
        throw "Sitecore package $SitecorePackage not found"
    }
    
    #Verify xConnect package
    if (!(Test-Path $XConnectPackage)) {
        throw "XConnect package $XConnectPackage not found"
    }
}

function Install-XConnect {
    #Install xConnect Solr
    try
    {
        Install-SitecoreConfiguration $XConnectSolrConfiguration `
                                      -SolrUrl $SolrUrl `
                                      -SolrRoot $SolrRoot `
                                      -SolrService $SolrService `
                                      -CorePrefix $SolutionPrefix
    }
    catch
    {
        write-host "XConnect SOLR Failed" -ForegroundColor Red
        throw
    }

    #Generate xConnect client certificate
    try
    {
        Install-SitecoreConfiguration $XConnectCertificateConfiguration `
                                      -CertificateName $XConnectCert `
                                      -CertPath $CertPath
    }
    catch
    {
        write-host "XConnect Certificate Creation Failed" -ForegroundColor Red
        throw
    }

    #Install xConnect
    try
    {
        Write-Host $webroot
        Install-SitecoreConfiguration $XConnectConfiguration `
                                      -Package $XConnectPackage `
                                      -LicenseFile $LicenseFile `
                                      -SiteName $XConnectSiteName `
                                      -XConnectCert $XConnectCert `
                                      -SqlDbPrefix $SolutionPrefix `
                                      -SolrCorePrefix $SolutionPrefix `
                                      -SqlAdminUser $SqlAdminUser `
                                      -SqlAdminPassword $SqlAdminPassword `
                                      -SqlServer $SqlServer `
                                      -SqlCollectionUser $XConnectSqlCollectionUser `
                                      -SqlCollectionPassword $XConnectSqlCollectionPassword `
                                      -SolrUrl $SolrUrl `
                                      -wwwRootPath $webroot

                                      
    }
    catch
    {
        write-host "XConnect Setup Failed" -ForegroundColor Red
        throw
    }
                             

    #Set rights on the xDB connection database
    Write-Host "Setting Collection User rights" -ForegroundColor Green
    try
    {
        $sqlVariables = "DatabasePrefix = $SolutionPrefix", "UserName = $XConnectSqlCollectionUser", "Password = $XConnectSqlCollectionPassword"
        Invoke-Sqlcmd -ServerInstance $SqlServer `
                      -Username $SqlAdminUser `
                      -Password $SqlAdminPassword `
                      -InputFile "$PSScriptRoot\build\database\collectionusergrant.sql" `
                      -Variable $sqlVariables
    }
    catch
    {
        write-host "Set Collection User rights failed" -ForegroundColor Red
        throw
    }
}

function Install-Sitecore {

    try
    {
        #Install Sitecore Solr
        Install-SitecoreConfiguration $SitecoreSolrConfiguration `
                                      -SolrUrl $SolrUrl `
                                      -SolrRoot $SolrRoot `
                                      -SolrService $SolrService `
                                      -CorePrefix $SolutionPrefix
    }
    catch
    {
        write-host "Sitecore SOLR Failed" -ForegroundColor Red
        throw
    }

    try
    {
        #Install Sitecore
        Install-SitecoreConfiguration $SitecoreConfiguration `
                                      -Package $SitecorePackage `
                                      -LicenseFile $LicenseFile `
                                      -SiteName $SitecoreSiteName `
                                      -XConnectCert $XConnectCert `
                                      -SqlDbPrefix $SolutionPrefix `
                                      -SolrCorePrefix $SolutionPrefix `
                                      -SqlAdminUser $SqlAdminUser `
                                      -SqlAdminPassword $SqlAdminPassword `
                                      -SqlServer $SqlServer `
                                      -SolrUrl $SolrUrl `
                                      -XConnectCollectionService "https://$XConnectSiteName" `
                                      -XConnectReferenceDataService "https://$XConnectSiteName" `
                                      -MarketingAutomationOperationsService "https://$XConnectSiteName" `
                                      -MarketingAutomationReportingService "https://$XConnectSiteName" `
                                      -wwwRootPath $webroot
    }
    catch
    {
        write-host "Sitecore Setup Failed" -ForegroundColor Red
        throw
    }

    try
    {
        #Set web certificate on Sitecore site
        Install-SitecoreConfiguration $SitecoreSSLConfiguration `
                                      -SiteName $SitecoreSiteName `
                                      -wwwRootPath $webroot
    }
    catch
    {
        write-host "Sitecore SSL Binding Failed" -ForegroundColor Red
        throw
    }
}


Write-Host "*******************************************************" -ForegroundColor Green
Write-Host " Installing Sitecore $SitecorePackagesVersion" -ForegroundColor Green
Write-Host " Sitecore: $SitecoreSiteName" -ForegroundColor Green
Write-Host " xConnect: $XConnectSiteName" -ForegroundColor Green
Write-Host "*******************************************************" -ForegroundColor Green
    Install-Prerequisites
    Install-Assets
    Install-XConnect
    Install-Sitecore
    Remove-Logs