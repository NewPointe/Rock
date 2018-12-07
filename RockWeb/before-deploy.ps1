# --------------------------------------------------
# ./before-deploy.ps1
# This script is run by AppVeyor's deploy agent before the deploy
# --------------------------------------------------

$RootLocation = $env:APPLICATION_PATH;
$TempLocation = Join-Path $env:Temp $env:APPVEYOR_JOB_ID;
New-Item $TempLocation -ItemType Directory

function Backup-RockFile([string] $RockWebFile) {
    $RockLocation = Join-Path $RootLocation $RockWebFile;
    $BackupLocation = Join-Path $TempLocation $RockWebFile;
    if (Test-Path $RockLocation) {
        Write-Information "Backing up '$RockWebFile'";
        $BackupParentLocation = Split-Path $BackupLocation;
        New-Item $BackupParentLocation -ItemType Directory -Force | Out-Null
        Move-Item $RockLocation $BackupLocation;
    }
    else {
        Write-Warning "Could not backup '$RockWebFile': Location does not exist.";
    }
}


Write-Information "===== NP Rock Deployment script v0.1 =====";
Write-Information "Mode: Pre-deploy";
Write-Information "Application: $env:APPVEYOR_PROJECT_NAME";
Write-Information "Build Number: $env:APPVEYOR_BUILD_VERSION";
Write-Information "Deploy Location: $RootLocation";
Write-Information "==========================================";
Write-Information "Putting application in maintenence mode";

Move-Item -Path (Join-Path $RootLocation "app_offline-template.htm") -Destination (Join-Path $RootLocation "app_offline.htm") -ErrorAction SilentlyContinue;

Write-Information "Saving server-specific files";

Backup-RockFile "web.config";
Backup-RockFile "web.ConnectionStrings.config";
Backup-RockFile "App_Data\Logs";
Backup-RockFile "App_Data\packages";
Backup-RockFile "App_Data\RockShop";
Backup-RockFile "App_Data\InstalledStorePackages.json";

Write-Information "Deployment script finished successfully";