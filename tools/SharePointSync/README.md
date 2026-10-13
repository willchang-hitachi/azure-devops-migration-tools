# SharePoint Sync

`Sync-SharePoint.ps1` compares a local folder with a SharePoint document library, reports the differences, and downloads files that are new or updated on SharePoint. It never deletes or uploads anything.

The defaults point at:

- **Site:** `https://hsdyn.sharepoint.com/sites/AEON-HitachiLMSprj`
- **Library:** `Shared Documents`
- **Local folder:** `C:\Users\73008309\OneDrive - Hitachi Group\Documents\ACSM\Sharepoint\Documents\`

## One-time setup

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
```

The script works with Windows PowerShell 5.1 or PowerShell 7+.

If the script is blocked because it was downloaded, run `Unblock-File .\Sync-SharePoint.ps1`, or run it with `powershell -ExecutionPolicy Bypass -File .\Sync-SharePoint.ps1`.

## Usage

```powershell
# 1. See what is different (downloads nothing)
.\Sync-SharePoint.ps1 -DryRun

# 2. Download new and updated files
.\Sync-SharePoint.ps1

# Only one folder of the library, into a different local folder
.\Sync-SharePoint.ps1 -RemoteFolder "Design/Phase 1" -LocalPath "D:\AEON\Phase 1"

# Sign in with a code instead of a browser pop-up
.\Sync-SharePoint.ps1 -UseDeviceCode
```

On the first run, a Microsoft sign-in window opens. Sign in with your Hitachi account.

## How files are classified

Files are compared by path and by last-modified time (UTC, with a 2-second tolerance).

| Status       | Meaning                                    | Action                                      |
|--------------|--------------------------------------------|---------------------------------------------|
| `New`        | Only on SharePoint                         | Downloaded                                  |
| `Changed`    | The SharePoint copy is newer               | Downloaded (overwrites the local copy)      |
| `LocalNewer` | The local copy is newer (edited locally?)  | Skipped, unless `-OverwriteLocalChanges`    |
| `LocalOnly`  | Only in the local folder                   | Reported, never deleted                     |
| `Same`       | Same modified time                         | Nothing to do                               |

After a download, the script sets the local file's modified time to the SharePoint time, so the next run reports the file as `Same`.

Size is not used to decide anything. SharePoint adds metadata to Office files when they are downloaded, so the local size of a `.docx` or `.xlsx` can legitimately differ from the size SharePoint reports.

Every run writes `sync-report.csv` into the local folder. It lists every file with its status and the result of the download.

## Troubleshooting

- **"Need admin approval" at sign-in:** your tenant does not let users consent to apps themselves. Ask an Entra ID admin to grant `Sites.Read.All` and `Files.Read.All` to the *Microsoft Graph Command Line Tools* enterprise app.
- **Quick access check:** in [Graph Explorer](https://developer.microsoft.com/graph/graph-explorer), run `GET https://graph.microsoft.com/v1.0/sites/hsdyn.sharepoint.com:/sites/AEON-HitachiLMSprj`. If it returns the site, the script can reach it.
- **Library not found:** the error message lists the libraries the site has. Pass the right one with `-Library`.

## Notes on using a OneDrive folder as the target

- Files the script downloads into a OneDrive folder are also uploaded to your personal OneDrive, which uses its quota.
- Cloud-only (Files On-Demand) files are not downloaded during the comparison. The script reads only their metadata.
- **No-code alternative:** open the library in the browser and click **Sync** (or **Add shortcut to My files**). The OneDrive client then keeps the library mirrored on your PC automatically. Use this script when you want a one-way, on-demand pull with a report of what changed.
