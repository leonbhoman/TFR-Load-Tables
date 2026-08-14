# deploy.ps1
# Usage: .\deploy.ps1 "1.0.5" "Testing unified branch automation"

param (
    [string]$NewVersion = $(Read-Host -Prompt "Enter the new version number (e.g., 1.0.5)"),
    [string]$ChangeLog  = $(Read-Host -Prompt "Enter a brief change description")
)

Write-Host "Formatting footsteps for single-branch deployment to version $NewVersion..." -ForegroundColor Cyan

# =========================================================================
# STEP 1: Update configuration files in the root folder
# =========================================================================
# Update version.json
$JsonPath = "version.json"
$JsonContent = Get-Content $JsonPath | ConvertFrom-Json
$JsonContent.version = $NewVersion
$JsonContent | ConvertTo-Json | Set-Content $JsonPath
Write-Host "✓ Local version.json updated to $NewVersion." -ForegroundColor Green

# Update pubspec.yaml
$PubspecPath = "pubspec.yaml"
$PubspecContent = Get-Content $PubspecPath
$PubspecContent = $PubspecContent -replace "version: .*", "version: ${NewVersion}+1"
$PubspecContent | Set-Content $PubspecPath
Write-Host "✓ pubspec.yaml updated to ${NewVersion}+1." -ForegroundColor Green


# =========================================================================
# STEP 2: Compile native Android package and Web assets
# =========================================================================
Write-Host "Compiling Android APK..." -ForegroundColor Yellow
flutter build apk

Write-Host "Compiling Web assets..." -ForegroundColor Yellow
flutter build web --base-href "/load_tables/"


# =========================================================================
# STEP 3: Sync the version beacon straight to the web folder
# =========================================================================
Copy-Item "version.json" "build\web\version.json"
Write-Host "✓ Sync step complete: version.json copied to web build folder." -ForegroundColor Green


# =========================================================================
# STEP 4: Synchronize EVERYTHING to your gh-pages branch from the Root
# =========================================================================
Write-Host "Committing and forcing push of source and web assets..." -ForegroundColor Yellow
git add .
git commit -m "Release v$NewVersion - $ChangeLog"
git push origin gh-pages --force

# =========================================================================
# FINAL EXECUTION COMPLETE
# =========================================================================
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "HALT! Execution complete. Everything is synchronized live." -ForegroundColor Green
Write-Host "Remaining manual task: Go to GitHub and upload the APK from:" -ForegroundColor Yellow
Write-Host "build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Cyan