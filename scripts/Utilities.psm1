function Get-Sitecore-SIF(
    [parameter(Mandatory=$true)][string]$SitecoreVersion
) {
    if ($SitecoreVersion -eq "") {
        throw "The version of Sitecore is required."
    }

    switch ($SitecoreVersion) {
        "9.0.0" { return "1.0.2"}
        "9.0.2" { return "1.2.1" }
        Default { return "1.1.0" }
    }
}

function Get-Sitecore-Packages(
    [parameter(Mandatory=$true)][string]$SitecoreVersion
) {
    if ($SitecoreVersion -eq "") {
        throw "The version of Sitecore is required."
    }

    switch ($SitecoreVersion) {
        "9.0.0" { return "9.0.0 rev. 171002"}
        "9.0.1" { return "9.0.1 rev. 171219"}
        "9.0.2" { return "9.0.2 rev. 180604" }
        Default { throw "The version of Sitecore is not correct." }
    }
}

function Check-FilePath (
    [parameter(Mandatory=$true)][string]$FilePath
) {
    if (!(Test-Path $FilePath)) {
        throw "$FilePath does not exist."
    }
    return true;
}

function Verify-Solr (
    [parameter(Mandatory=$true)][string]$SolrUrl
) {
    Write-Host "Verifying Solr connection $SolrUrl" -ForegroundColor Green
    if (-not $SolrUrl.ToLower().StartsWith("https")) {
        throw "Solr URL ($SolrUrl) must be secured with https"
    }
    
    $SolrRequest = [System.Net.WebRequest]::Create($SolrUrl)
	$SolrResponse = $SolrRequest.GetResponse()
	try {
		If ([int]$SolrResponse.StatusCode -ne 200) {
			throw "Could not contact Solr on '$SolrUrl'. Response status was '$SolrResponse.StatusCode'"
		}
	}
	finally {
		$SolrResponse.Close()
    }
}

function Remove-Logs(){
    get-childitem .\ -include *.log -recurse | foreach ($_) {Remove-Item $_.fullname}
}