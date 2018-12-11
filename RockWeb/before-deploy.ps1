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
        Write-Host "Backing up '$RockWebFile'";
        $BackupParentLocation = Split-Path $BackupLocation;
        New-Item $BackupParentLocation -ItemType Directory -Force | Out-Null
        Move-Item $RockLocation $BackupLocation;
    }
    else {
        Write-Warning "Could not backup '$RockWebFile': Location does not exist.";
    }
}

if(Test-Path "env:DEPLOY_DEBUG") {
    Write-Host "================= DEBUG ==================";
    Write-Host "Working Directories: $(Get-Location)";
    Write-Host "Environment:";
    Get-ChildItem "env:";
}

Write-Host "===== NP Rock Deployment script v0.1 =====";
Write-Host "Mode: Pre-deploy";
Write-Host "Application: $env:APPVEYOR_PROJECT_NAME";
Write-Host "Build Number: $env:APPVEYOR_BUILD_VERSION";
Write-Host "Deploy Location: $RootLocation";
Write-Host "==========================================";
Write-Host "Putting application in maintenence mode";

Move-Item -Path (Join-Path $RootLocation "app_offline-template.htm") -Destination (Join-Path $RootLocation "app_offline.htm") -ErrorAction SilentlyContinue;

Write-Host "Saving server-specific files";

Backup-RockFile "web.config";
Backup-RockFile "web.ConnectionStrings.config";
Backup-RockFile "App_Data\Files";
Backup-RockFile "App_Data\Logs";
Backup-RockFile "App_Data\packages";
Backup-RockFile "App_Data\RockShop";
Backup-RockFile "App_Data\InstalledStorePackages.json";
Backup-RockFile "Content";
Backup-RockFile "wp-content";

Write-Host "Deployment script finished successfully";