# Release 1.0 checklist

Use this checklist **after PR #3 is merged to `main`**.

## 1) Update local `main`

```powershell
git checkout main
git pull origin main
```

## 2) Create and push release tag

```powershell
git tag -a v1.0 -m "PS ETL Framework 1.0"
git push origin v1.0
```

## 3) Publish GitHub release

Open: `https://github.com/MrLiebi/ETLFramework/releases/new`

- **Choose a tag:** `v1.0`
- **Release title:** `1.0`
- **Target branch:** `main`

### Suggested release notes (copy/paste)

Final `1.0` release of the PowerShell ETL Framework.

#### Added
- Bundled offline installer for .NET Framework 4.8.1 at `Templates/Installers/DotNet/NDP481-x86-x64-AllOS-ENU.exe`.
- Automatic bundled-installer fallback in wizard prerequisite handling when no explicit offline installer path is provided.
- Runtime smoke tests and release manifest smoke coverage for release traceability.

#### Changed
- Framework release line finalized at `1.0` across entry scripts, templates, runtime modules, wizard banner, and documentation.
- Previous changelog versions moved to `0.x` to clearly mark all pre-final releases.
- Wizard prerequisite defaults now target .NET Framework `4.8.1`.

#### Security / Integrity
- Bundled .NET installer SHA-256 is tracked in `ReleaseManifest.psd1`.

#### Notes
- The bundled installer file exceeds GitHub's 50 MB recommendation but is within repository hard limits.

## 4) Optional post-release verification

```powershell
git fetch origin --tags
git tag --list "v1.0"
```
