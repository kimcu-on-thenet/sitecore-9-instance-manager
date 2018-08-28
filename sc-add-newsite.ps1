
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$scversion,
    [Parameter(Mandatory=$true)]
    [string]$instanceName,
    [Parameter(Mandatory=$true)]
    [string]$hostname,
    [Parameter(Mandatory=$true)]
    [string]$scwebroot
)

$ErrorActionPreference = 'Stop'

if (Get-Module("Utilities")) {
    Remove-Module "Utilities"
}
Import-Module "$PSScriptRoot/scripts/Utilities.psm1"

#Sitecore Install Framework dependencies
Import-Module WebAdministration


$InstallerVersion = Get-Sitecore-SIF -SitecoreVersion $scversion

# Assets and prerequisites
$AssetsPSRepository = "https://sitecore.myget.org/F/sc-powershell/api/v2/"
$AssetsPSRepositoryName = "SitecoreGallery"


$SitePostFix = "dev.local"
$SitecoreSiteName = "$instanceName.$SitePostFix"

$jsonConfigFile = "$PSScriptRoot/build/Bindings/Bindings-Config.json"

function Install-Prerequisites {
     #Register Assets PowerShell Repository
     if ((Get-PSRepository | Where-Object {$_.Name -eq $AssetsPSRepositoryName}).count -eq 0) {
        Register-PSRepository -Name $AssetsPSRepositoryName -SourceLocation $AssetsPSRepository -InstallationPolicy Trusted
    }

    #Install SIF
    $module = Get-Module -FullyQualifiedName @{ModuleName="SitecoreInstallFramework";ModuleVersion=$InstallerVersion}
    if (-not $module) {
        write-host "Installing the Sitecore Install Framework, version $InstallerVersion" -ForegroundColor Green
        Install-Module SitecoreInstallFramework -RequiredVersion $InstallerVersion -Scope CurrentUser
        Import-Module SitecoreInstallFramework -RequiredVersion $InstallerVersion
    }
}

function Validate-Site {
    $site = Get-Item IIS:\sites\$SitecoreSiteName -ErrorAction SilentlyContinue
    if(!$site){
        throw "Could not find site: $SitecoreSiteName"
    }
}

function Add-Bindings {
    try {
        # Add Http Binding + hosts file
        Install-SitecoreConfiguration $jsonConfigFile `
                                        -SiteName $SitecoreSiteName `
                                        -HostName $hostname

        # Add Https Binding
        Add-HttpsBinding
    }
    catch {
        Write-Host "Add Binding Failed" -ForegroundColor Red
        Throw
    }
}

function Add-HttpsBinding {
    $RootCertLocation = 'Cert:\LocalMachine\Root'
    $RootDnsName = 'DO_NOT_TRUST_SitecoreFundamentalsRoot'
    $RootCertName = $hostname
    $ClientCertLocation = 'Cert:\LocalMachine\My'
    $OutputDirectory = Join-Path $scwebroot -ChildPath $SitecoreSiteName | Join-Path -ChildPath "App_Data"
    $Port = 443
 
    $getRootCertParams = @{
        CertStoreLocation = $RootCertLocation
        DnsName = $RootDnsName
    }

    $rootCertificate = GetCertificateByDnsName @getRootCertParams
    

    if ($null -eq $rootCertificate) {
        Write-Host "$functionPrefix Create Root certificate in Cert:\CurrentUser\My store"
        $newRootCertParams = @{
            Path = $OutputDirectory
            DnsName = $RootDnsName
            Name = $RootCertName
            StoreLocation = 'CurrentUser'
        }
        $rootCertResponse = New-RootCertificate @newRootCertParams
        Write-Host $rootCertResponse

        Write-Host "$functionPrefix Add Root certificate to Trusted Root Certification Authorities store"
        $importCertParams = @{
            CertStoreLocation = $RootCertLocation
            FilePath = $($rootCertResponse.FileInfo)
        }
        $rootCertificate = Import-Certificate @importCertParams
        Write-Host $rootCertificate
    }
    
    Write-Host $OutputDirectory
    $params = @{
        Signer = $rootCertificate
        Path = $OutputDirectory
        CertStoreLocation = $ClientCertLocation
        DnsName = $hostname
        FriendlyName = $hostname
    }
    New-SignedCertificate @params | Out-Null

    $params = @{
        IisSite = $SitecoreSiteName
        HostName = $hostname
        Port = ($Port -as [int])
        CertStoreLocation = $ClientCertLocation
    }
    AddSSLBinding @params
}

function AddSSLBinding {
    param(
        [Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
        [string] $IisSite,
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string] $HostName,
		[Parameter(Mandatory=$true)]
		[ValidateScript({ $_.StartsWith("cert:\", "CurrentCultureIgnoreCase")})]
		[string] $CertStoreLocation,
		[int] $Port = 443
	)

    If (! ( Get-WebBinding -Name $HostName -Protocol https ) )
	{
		$certificate = GetCertificateByDnsName -CertStoreLocation $CertStoreLocation -DnsName $HostName

		if ($null -eq $certificate)
		{
			throw "Failed to find certificate for DnsName '$HostName' in $CertStoreLocation"
		}

		$certHash = $($certificate.thumbprint)

		Write-Verbose "$functionPrefix add SSL certificate binding to $HostName`:${Port} using $certHash"
		AddSslCertMapping -HostNamePort "${HostName}:${Port}" -CertHash $certHash

		Write-Verbose "$functionPrefix creating SNI enabled HTTPS protocol web binding for $HostName port ${Port}"
		New-WebBinding -Name $IisSite -Port ${Port} -Protocol https -HostHeader $HostName -SslFlags 1

		Write-Verbose "$functionPrefix successfully added SSL Binding for $HostName`:${Port}"
	}
	Else
	{
		Write-Verbose "$functionPrefix HTTPS WebBinding already exists, skipping"
	}
}

function AddSslCertMapping {

	param(
		[Parameter(Mandatory = $true)]
		[string] $HostNamePort,
		[Parameter(Mandatory = $true)]
		[string] $CertHash
	)

	# TODO replace with cert capabilities

	# http.sys mapping of ip/hostheader to cert
	$guid = [guid]::NewGuid().ToString("B")
	netsh http add sslcert hostnameport="$HostNamePort" certhash=$CertHash certstorename=MY appid="$guid" | Out-Null
}

function GetCertificateByDnsName{

    param
	(
		[Parameter(Mandatory = $true)]
		[ValidateScript({ $_.StartsWith("cert:\", "CurrentCultureIgnoreCase")})]
		[string] $CertStoreLocation,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string] $DnsName
	)

    $certificates = Get-ChildItem -Path $CertStoreLocation -Recurse | Where-Object {
		$DnsName -eq $_.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
	}

	if (( $certificates | Measure-Object ).Count -gt 1) {

		NewInvalidOperationException -Message "Multiple certificates returned from $CertStoreLocation for Name $DnsName ($($certificates.length) found)"
	}

	if ($null -eq $certificates) {

		Write-Verbose -Message "Failed to find certificate with Name $DnsName"
	}
	else {

		Write-Verbose -Message "Success, found certificate for Name $DnsName (thumbprint: $($certificates.thumbprint))"
	}

	return $certificates
}

Write-Host "*******************************************************" -ForegroundColor Green
Write-Host " Add new host name $hostname" -ForegroundColor Green
Write-Host " To: $SitecoreSiteName" -ForegroundColor Green
Write-Host "*******************************************************" -ForegroundColor Green

Validate-Site
Install-Prerequisites
Add-Bindings
Remove-Logs

#.\sc-add-newsite.ps1 -scversion "9.0.2" -instanceName "habitathome" -scwebroot "D:\Inetpub\wwwroot" -hostname "habitatkim.dev.local"