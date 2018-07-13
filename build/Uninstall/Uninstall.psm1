$ErrorActionPreference = "Stop"

[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")


function Get-SitecoreDatabase(
    [parameter(Mandatory=$true)]$SqlServer, 
    [parameter(Mandatory=$true)]$SqlAdminUser, 
    [parameter(Mandatory=$true)]$SqlAdminPassword
) {
    $databaseServer = New-Object Microsoft.SqlServer.Management.Smo.Server($SqlServer)
    $databaseServer.ConnectionContext.LoginSecure = $false
    $databaseServer.ConnectionContext.Login = $SqlAdminUser
    $databaseServer.ConnectionContext.Password = $SqlAdminPassword
    $databases = $databaseServer.Databases
    return $databaseServer
}


function Remove-SitecoreDatabase(
    [parameter(Mandatory=$true)] $Name,
    [parameter(Mandatory=$true)] $Server
) {
    if ($Server.Databases[$Name]) {
        $Server.KillDatabase($Name)
        Write-Host "Database ($Name) is dropped" -ForegroundColor Green
    }
    else {
        Write-Host "Could not find database ($Name)" -ForegroundColor Yellow
    }
}

function Remove-SitecoreCertificate($certificateName) {

    $cert = Get-ChildItem -Path "cert:\LocalMachine\My" | Where-Object { $_.subject -like "CN=$certificateName" }
    if ($cert -and $cert.Thumbprint) {
        $certPath = "cert:\LocalMachine\My\" + $cert.Thumbprint
        Remove-Item $certPath
        Write-Host "Removing certificate $certificateName ($certPath)" -ForegroundColor Green
    }
    else {
        Write-Host "Could not find certificate $certificateName under cert:\LocalMachine\My" -ForegroundColor Yellow
    }
}

function Remove-SitecoreWindowsService($name) {
    if (Get-Service $name -ErrorAction SilentlyContinue) {
        Uninstall-Service $name
        Write-Host "Windows service $name is uninstalled" -ForegroundColor Green
    }
    else {
        Write-Host "Could not find windows service $name" -ForegroundColor Yellow
    }
}


function Remove-SitecoreIisSite($name) {
    # Delete site
    if (Get-IisWebsite $name) {
        Uninstall-IisWebsite $name
        Write-Host "IIS site $name is uninstalled" -ForegroundColor Green
    }
    else {
        Write-Host "Could not find IIS site $name" -ForegroundColor Yellow
    }

    # Delete app pool
    if (Get-IisAppPool $name) {
        Uninstall-IisAppPool $name
        Write-Host "IIS App Pool $name is uninstalled" -ForegroundColor Green
    }
    else {
        Write-Host "Could not find IIS App Pool $name" -ForegroundColor Yellow
    }
}

function Remove-SitecoreFiles($path) {
    # Delete site
    if (Test-Path($path)) {
        Remove-Item $path -Recurse -Force
        Write-Host "Removing files $path" -ForegroundColor Green
    }
    else {
        Write-Host "Could not find files $path" -ForegroundColor Yellow
    }
}

function Remove-SitecoreSolrCore {
    param(
        [string] $SolrUrl,
        [string] $SolutionPrefix
    )

    $indexes =  "${SolutionPrefix}_core_index",
                "${SolutionPrefix}_master_index",
                "${SolutionPrefix}_web_index",
                "${SolutionPrefix}_marketingdefinitions_master",
                "${SolutionPrefix}_marketingdefinitions_web",
                "${SolutionPrefix}_marketing_asset_index_master",
                "${SolutionPrefix}_marketing_asset_index_web",
                "${SolutionPrefix}_testing_index",
                "${SolutionPrefix}_suggested_test_index",
                "${SolutionPrefix}_fxm_master_index",
                "${SolutionPrefix}_fxm_web_index",
                "${SolutionPrefix}_xdb",
                "${SolutionPrefix}_xdb_rebuild"

    $Action = "UNLOAD"
    Write-Host "Removing Sitecore Solr Cores..................."
    foreach($core in $indexes){
        $uriParameters = "core=$core"
        Write-Host "Removing $core"
        $uri = "$SolrUrl/admin/cores?action=$Action&$uriParameters&deleteInstanceDir=true"
        $SolrRequest = [System.Net.WebRequest]::Create($uri)
        $SolrResponse = $SolrRequest.GetResponse()
        try {
            If ([int]$SolrResponse.StatusCode -ne 200) {
                throw "[Remove] Could not contact Solr on '$SolrUrl'. . Response status was '$SolrResponse.StatusCode'"
            }
        }
        finally {
            $SolrResponse.Close()
        }
    }
    Write-Host "Removed successfully Sitecore Solr Cores."

}
