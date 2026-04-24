@{
    Latest = @{
        Version       = '1.0'
        Tag           = 'v1.0'
        ReleaseCommit = 'pending-main-tag'
        ReleaseUrl    = 'https://github.com/MrLiebi/ETLFramework/releases/tag/v1.0'
        Notes         = 'Final release 1.0 with bundled .NET Framework 4.8.1 offline installer.'
    }

    BundledInstallers = @{
        DotNetFramework481 = @{
            Path   = 'Templates/Installers/DotNet/NDP481-x86-x64-AllOS-ENU.exe'
            Sha256 = 'c0ca2e0c9cd18a24a0a77369a13fae2c2c4e8bc83355dd24e5ddc00f9d791fe3'
        }
    }
}
