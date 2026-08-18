Describe 'AppGetter website link scanning' {
    BeforeAll {
        $script:modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'AppGetter.psd1'
        Import-Module $script:modulePath -Force

        $script:html = @'
<html><body>
  <a href="/downloads/contoso-setup-x64.exe">64-bit installer</a>
  <a href="/downloads/contoso-setup-x86.exe">32-bit installer</a>
  <a href="/downloads/contoso-admin.msi">MSI for deployment</a>
  <a href="/support.html">Support</a>
</body></html>
'@

        # Serve the page from a loopback listener so the scan exercises real HTTP.
        $script:listener = $null
        $script:serverWorker = $null
        $script:baseUrl = $null

        foreach ($port in 18730..18760) {
            $candidate = [System.Net.HttpListener]::new()
            $candidate.Prefixes.Add("http://127.0.0.1:$port/")
            try {
                $candidate.Start()
                $script:listener = $candidate
                $script:baseUrl = "http://127.0.0.1:$port/"
                break
            } catch {
                $candidate.Close()
            }
        }

        if ($script:listener) {
            $powershell = [powershell]::Create()
            $null = $powershell.AddScript({
                    param($Listener, $Body)
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
                    while ($Listener.IsListening) {
                        try {
                            $context = $Listener.GetContext()
                        } catch {
                            break
                        }
                        $context.Response.ContentType = 'text/html'
                        $context.Response.ContentLength64 = $bytes.Length
                        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                        $context.Response.OutputStream.Close()
                    }
                }).AddArgument($script:listener).AddArgument($script:html)
            $script:serverWorker = @{
                PowerShell  = $powershell
                AsyncResult = $powershell.BeginInvoke()
            }
        }
    }

    AfterAll {
        if ($script:listener) {
            try { $script:listener.Stop() } catch { Write-Verbose 'Listener already stopped.' }
            try { $script:listener.Close() } catch { Write-Verbose 'Listener already closed.' }
        }
        if ($script:serverWorker) {
            try { $script:serverWorker.PowerShell.Stop() } catch { Write-Verbose 'Worker already stopped.' }
            $script:serverWorker.PowerShell.Dispose()
        }
    }

    It 'finds every download link on the page' {
        if (-not $script:listener) { Set-ItResult -Skipped -Because 'no loopback HTTP listener is available' }
        $links = @(Get-AppGetterDownloadLinkList -Url $script:baseUrl -AppName 'Contoso')
        $links.Count | Should -BeGreaterOrEqual 3
        $links | Should -Contain "$($script:baseUrl)downloads/contoso-setup-x64.exe"
        $links | Should -Contain "$($script:baseUrl)downloads/contoso-admin.msi"
    }

    It 'returns links as individual strings, not one nested collection' {
        if (-not $script:listener) { Set-ItResult -Skipped -Because 'no loopback HTTP listener is available' }
        # The GUI shows one radio button per link; a nested array would collapse them into one entry.
        $links = @(Get-AppGetterDownloadLinkList -Url $script:baseUrl -AppName 'Contoso')
        foreach ($link in $links) {
            $link | Should -BeOfType [string]
        }
    }

    It 'survives the background job round-trip used by the Find Links button' {
        if (-not $script:listener) { Set-ItResult -Skipped -Because 'no loopback HTTP listener is available' }
        $job = Start-Job -ArgumentList $script:modulePath, $script:baseUrl, 'Contoso' -ScriptBlock {
            param($ModulePath, $Url, $Name)
            Import-Module $ModulePath -Force
            Get-AppGetterDownloadLinkList -Url $Url -AppName $Name
        }

        try {
            $null = Wait-Job -Job $job -Timeout 60
            $links = @(Receive-Job -Job $job)
        } finally {
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }

        $links.Count | Should -BeGreaterOrEqual 3
        $links[0] | Should -BeOfType [string]
    }

    It 'labels each link with the installer file name shown in the picker' {
        if (-not $script:listener) { Set-ItResult -Skipped -Because 'no loopback HTTP listener is available' }
        $links = @(Get-AppGetterDownloadLinkList -Url $script:baseUrl -AppName 'Contoso')
        $fileNames = @($links | ForEach-Object { Get-AppGetterInstallerFileNameFromUrl -Url $_ })
        $fileNames | Should -Contain 'contoso-setup-x64.exe'
        $fileNames | Should -Contain 'contoso-admin.msi'
    }

    It 'returns an empty list for an unreachable site instead of throwing' {
        $links = @(Get-AppGetterDownloadLinkList -Url 'http://127.0.0.1:1/nothing-here' -AppName 'Contoso' -WarningAction SilentlyContinue 6> $null)
        $links.Count | Should -Be 0
    }
}
