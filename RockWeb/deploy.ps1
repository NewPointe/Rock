# --------------------------------------------------
# ./deploy.ps1
# This script is run by AppVeyor's deploy agent after the deploy
# --------------------------------------------------

$RootLocation = $env:APPLICATION_PATH;
$TempLocation = Join-Path $env:Temp $env:APPVEYOR_JOB_ID;


function Restore-RockFile([string] $RockWebFile) {
    $RockLocation = Join-Path $RootLocation $RockWebFile;
    $BackupLocation = Join-Path $TempLocation $RockWebFile;
    if (Test-Path $BackupLocation) {
        Write-Information "Restoring '$RockWebFile'";
        if(Test-Path $RockLocation) {
            Remove-Item $RockLocation -Recurse
        }
        Move-Item $BackupLocation $RockLocation;
    }
    else {
        Write-Warning "Could not restore '$RockWebFile': Location does not exist.";
    }
}

function Join-Paths {
    $path, $parts= $args;
    foreach ($part in $parts) {
        $path = Join-Path $path $part;
    }
    return $path;
}

function Expand-RockPlugin([string] $PluginPath, [string] $DestinationPath) {
    
    $PackageHash = (Get-FileHash $PluginPath).Hash;
    $TempZip = Join-Paths $TempLocation "$PackageHash.zip";
    Copy-Item $PluginPath $TempZip;
    Expand-Archive $TempZip $DestinationPath -Force;
    Remove-Item $TempZip -Force;
}

function Restore-RockPlugin([string] $PluginPackagePath) {

    $PackageHash = (Get-FileHash $PluginPackagePath).Hash;
    $PackageTempLocation = Join-Path $TempLocation $PackageHash;

    New-Item $PackageTempLocation -ItemType Directory | Out-Null;
    Expand-RockPlugin $PluginPackagePath $PackageTempLocation;

    $ContentPath = Join-Path $PackageTempLocation "content";
    if(Test-Path $ContentPath) {
        Get-ChildItem $ContentPath | Copy-Item -Destination $RootLocation -Recurse -Container -Force
    }
    
    Remove-Item $PackageTempLocation -Recurse -Force;
}


Write-Information "===== NP Rock Deployment script v0.1 =====";
Write-Information "Mode: Post-deploy";
Write-Information "Application: $env:APPVEYOR_PROJECT_NAME";
Write-Information "Build Number: $env:APPVEYOR_BUILD_VERSION";
Write-Information "Deploy Location: $RootLocation";
Write-Information "==========================================";

Write-Information "Restoring server-specific files";

Restore-RockFile "web.config";
Restore-RockFile "web.ConnectionStrings.config";
Restore-RockFile "App_Data\Logs";
Restore-RockFile "App_Data\packages";
Restore-RockFile "App_Data\RockShop";
Restore-RockFile "App_Data\InstalledStorePackages.json";

Write-Information "Rewriting Templated Files";

$TemplateFilenamePattern = "*.template.*" # something.template.txt
$TemplateVariableRegex = "\[\[(\w+)]]";   # [[Variable_Name]]

# For each template file
$TemplateFiles = Get-ChildItem $RootLocation -Recurse -Include $TemplateFilenamePattern;
foreach($TemplateFile in $TemplateFiles) {

    Write-Information "Rewriting $TemplateFile";

    # Get the raw contents
    $TemplateContents = Get-Content $TemplateFile -Raw;

    # Get a list of all the variables
    $TemplateVariables = ($TemplateContents | Select-String -AllMatches $TemplateVariableRegex).Matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object | Get-Unique;

    # For each needed variable
    foreach($TemplateVariable in $TemplateVariables) {

        $EnvVar = "DEPLOY_$TemplateVariable".ToUpper();

        # Check that it's in the environment
        if(Test-Path "env:$EnvVar") {
            
            # Update it's value
            $TemplateContents = $TemplateContents.Replace("[[$TemplateVariable]]", $(Get-Item "env:$EnvVar").TemplateVariable);
        }
        else {
            Write-Warning "Could not update '[[$TemplateVariable]]' in '$TemplateFile'. Environment variable '$EnvVar' is not set.";
        }

    }

    # Save the new file
    $TemplateTempLocation = $TemplateFile -replace ".template", "";
    Set-Content $TemplateTempLocation $TemplateContents;
}

Write-Information "Reinstalling Plugin Files";

$InstalledPluginsPath = Join-Paths $RootLocation "App_Data" "RockShop";
if(Test-Path $InstalledPluginsPath) {

    $InstalledPlugins = Get-ChildItem $InstalledPluginsPath;
    foreach ($Plugin in $InstalledPlugins) {

        $PluginVersions = Get-ChildItem $Plugin.FullName;
        if($PluginVersions.Count -gt 0) {

            $LatestVersion = $PluginVersions  | Sort-Object "Name" | Select-Object -Last 1;
            Write-Information "Restoring ${Plugin.Name}";
            Restore-RockPlugin $LatestVersion.FullName;

        }

    }
    
}

Remove-Item $TempLocation -Recurse -Force;

Write-Information "Taking application out of maintenence mode";

Move-Item -Path (Join-Path $RootLocation "app_offline.htm") -Destination (Join-Path $RootLocation "app_offline-template.htm") -ErrorAction SilentlyContinue;

Write-Information "Deployment script finished successfully";