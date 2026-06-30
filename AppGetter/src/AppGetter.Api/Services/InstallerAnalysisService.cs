using System.Diagnostics;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using AppGetter.Shared.Models;

namespace AppGetter.Api.Services;

public sealed class InstallerAnalysisService
{
    private static readonly Dictionary<string, List<SilentSwitchCandidate>> KnownSwitches = new()
    {
        ["MSI"] =
        [
            new() { Switch = "/quiet", Confidence = "Known", Source = "MSI Standard", Description = "No UI, basic logging" },
            new() { Switch = "/qn", Confidence = "Known", Source = "MSI Standard", Description = "No UI, no UI sequence" },
            new() { Switch = "/norestart", Confidence = "Known", Source = "MSI Standard", Description = "Suppress restart" }
        ],
        ["NSIS"] =
        [
            new() { Switch = "/S", Confidence = "Known", Source = "NSIS Standard", Description = "Silent install" }
        ],
        ["InnoSetup"] =
        [
            new() { Switch = "/VERYSILENT", Confidence = "Known", Source = "Inno Setup", Description = "No wizard or progress window" },
            new() { Switch = "/SILENT", Confidence = "Known", Source = "Inno Setup", Description = "Progress window only" },
            new() { Switch = "/SUPPRESSMSGBOXES", Confidence = "Known", Source = "Inno Setup", Description = "Suppress message boxes" },
            new() { Switch = "/NORESTART", Confidence = "Known", Source = "Inno Setup", Description = "Suppress restart" }
        ],
        ["InstallShield"] =
        [
            new() { Switch = "/s", Confidence = "Known", Source = "InstallShield", Description = "Silent install" },
            new() { Switch = "/v\"/qn\"", Confidence = "Known", Source = "InstallShield MSI wrapper", Description = "Silent MSI inside setup.exe" }
        ],
        ["WiXBurn"] =
        [
            new() { Switch = "/quiet", Confidence = "Known", Source = "WiX Burn", Description = "Silent install" },
            new() { Switch = "/passive", Confidence = "Known", Source = "WiX Burn", Description = "Unattended with progress" }
        ],
        ["EXE_Generic"] =
        [
            new() { Switch = "/S", Confidence = "Heuristic", Source = "Common EXE", Description = "Common silent flag" },
            new() { Switch = "/silent", Confidence = "Heuristic", Source = "Common EXE", Description = "Common silent flag" },
            new() { Switch = "/quiet", Confidence = "Heuristic", Source = "Common EXE", Description = "Common silent flag" }
        ]
    };

    private static readonly (string Name, string[] Patterns)[] FrameworkSignatures =
    [
        ("NSIS", ["Nullsoft Install System", "NSIS Error", "NullsoftInst"]),
        ("InnoSetup", ["Inno Setup Setup Data", "Inno Setup Messages", "jrsoftware.org"]),
        ("InstallShield", ["InstallShield", "ISSetup", "Setup Launcher for InstallShield"]),
        ("WiXBurn", ["WiX Toolset", "burn engine", "WixBundle"]),
        ("Squirrel", ["Squirrel", "Update.exe"])
    ];

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<InstallerAnalysisService> _logger;

    public InstallerAnalysisService(IHttpClientFactory httpClientFactory, ILogger<InstallerAnalysisService> logger)
    {
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    public InstallerFrameworkInfo DetectFramework(string installerPath)
    {
        var extension = Path.GetExtension(installerPath).ToLowerInvariant();
        var fileName = Path.GetFileName(installerPath);

        if (extension == ".msi")
        {
            return new InstallerFrameworkInfo
            {
                Framework = "MSI",
                Extension = extension,
                FileName = fileName,
                Confidence = "Known",
                DetectionMethod = "Extension"
            };
        }

        if (extension is ".msix" or ".appx")
        {
            return new InstallerFrameworkInfo
            {
                Framework = "MSIX",
                Extension = extension,
                FileName = fileName,
                Confidence = "Known",
                DetectionMethod = "Extension"
            };
        }

        var bytes = File.ReadAllBytes(installerPath);
        var text = Encoding.ASCII.GetString(bytes);

        foreach (var (name, patterns) in FrameworkSignatures)
        {
            foreach (var pattern in patterns)
            {
                if (text.Contains(pattern, StringComparison.Ordinal))
                {
                    return new InstallerFrameworkInfo
                    {
                        Framework = name,
                        Extension = extension,
                        FileName = fileName,
                        Confidence = "High",
                        DetectionMethod = "BinarySignature",
                        MatchedPattern = pattern
                    };
                }
            }
        }

        return new InstallerFrameworkInfo
        {
            Framework = "EXE_Generic",
            Extension = extension,
            FileName = fileName,
            Confidence = "Low",
            DetectionMethod = "Fallback"
        };
    }

    public async Task<WebResearchResult?> ResearchFromWebAsync(string url, CancellationToken cancellationToken)
    {
        try
        {
            var client = _httpClientFactory.CreateClient();
            var html = await client.GetStringAsync(url, cancellationToken);
            var text = Regex.Replace(html, "<[^>]+>", " ");
            text = Regex.Replace(text, @"\s+", " ");

            var result = new WebResearchResult { SourceUrl = url };
            var patterns = new[]
            {
                "/VERYSILENT", "/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-",
                "/S", "/quiet", "/qn", "/qb", "/passive", "--silent",
                "silent install", "quiet install", "unattended install", "msiexec"
            };

            foreach (var pattern in patterns)
            {
                var matches = Regex.Matches(text, $".{{0,80}}{Regex.Escape(pattern)}.{{0,80}}", RegexOptions.IgnoreCase);
                foreach (Match match in matches)
                {
                    var snippet = match.Value.Trim();
                    if (!result.InstallSwitches.Contains(snippet))
                    {
                        result.InstallSwitches.Add(snippet);
                    }
                }
            }

            if (Regex.IsMatch(text, "(deployment|enterprise|administrator|silent|unattended)", RegexOptions.IgnoreCase))
            {
                result.BestPractices.Add("Page contains deployment or enterprise installation information.");
            }

            return result;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Web research failed for {Url}", url);
            return null;
        }
    }

    public List<HelpProbeResult> ProbeInstallerHelp(string installerPath, int timeoutSeconds = 15)
    {
        var results = new List<HelpProbeResult>();
        if (!OperatingSystem.IsWindows())
        {
            results.Add(new HelpProbeResult
            {
                Argument = "N/A",
                Success = false,
                Output = "Help probing requires Windows."
            });
            return results;
        }

        foreach (var arg in new[] { "/?", "/help", "--help", "-h", "/h" })
        {
            var probe = new HelpProbeResult { Argument = arg };
            try
            {
                using var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = installerPath,
                        Arguments = arg,
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true
                    }
                };

                process.Start();
                if (!process.WaitForExit(timeoutSeconds * 1000))
                {
                    process.Kill(entireProcessTree: true);
                    probe.Output = "Timed out waiting for help output.";
                    results.Add(probe);
                    continue;
                }

                var output = (process.StandardOutput.ReadToEnd() + Environment.NewLine + process.StandardError.ReadToEnd()).Trim();
                probe.Output = output;
                probe.Success = output.Length > 0;

                foreach (Match match in Regex.Matches(output, @"(?i)(/[\w-]+|--[\w-]+|/quiet|/qn|/qb|/passive)"))
                {
                    if (!probe.Switches.Contains(match.Value))
                    {
                        probe.Switches.Add(match.Value);
                    }
                }
            }
            catch (Exception ex)
            {
                probe.Output = ex.Message;
            }

            results.Add(probe);
        }

        return results;
    }

    public List<SwitchTestResult> TestSilentSwitches(string installerPath, IEnumerable<string> candidates, bool dryRun, int timeoutSeconds = 30)
    {
        var results = new List<SwitchTestResult>();
        var extension = Path.GetExtension(installerPath).ToLowerInvariant();

        foreach (var candidate in candidates.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var test = new SwitchTestResult { Switch = candidate };

            if (dryRun)
            {
                test.Status = "DryRun";
                test.Message = $"Would test: \"{Path.GetFileName(installerPath)}\" {candidate}";
                results.Add(test);
                continue;
            }

            if (!OperatingSystem.IsWindows())
            {
                test.Status = "Skipped";
                test.Message = "Live installer testing requires Windows.";
                results.Add(test);
                continue;
            }

            if (extension == ".msi")
            {
                test.Status = "Skipped";
                test.Message = "MSI installers should be tested with msiexec in a controlled VM.";
                results.Add(test);
                continue;
            }

            try
            {
                var sw = Stopwatch.StartNew();
                using var process = Process.Start(new ProcessStartInfo
                {
                    FileName = installerPath,
                    Arguments = candidate,
                    UseShellExecute = false,
                    CreateNoWindow = true
                });

                if (process is null)
                {
                    test.Status = "Error";
                    test.Message = "Could not start installer process.";
                    results.Add(test);
                    continue;
                }

                if (!process.WaitForExit(timeoutSeconds * 1000))
                {
                    process.Kill(entireProcessTree: true);
                    test.Status = "Timeout";
                    test.Message = "Installer did not exit within timeout; may be waiting for UI input.";
                }
                else
                {
                    test.ExitCode = process.ExitCode;
                    test.Status = process.ExitCode == 0 ? "Success" : "Failed";
                    test.Message = $"Exit code: {process.ExitCode}";
                    test.Recommended = process.ExitCode == 0;
                }

                sw.Stop();
                test.DurationMs = sw.ElapsedMilliseconds;
            }
            catch (Exception ex)
            {
                test.Status = "Error";
                test.Message = ex.Message;
            }

            results.Add(test);
        }

        return results;
    }

    public async Task<InstallerAnalysisResult> AnalyzeAsync(AnalyzeInstallerRequest request, CancellationToken cancellationToken)
    {
        if (!File.Exists(request.InstallerPath))
        {
            throw new FileNotFoundException("Installer not found.", request.InstallerPath);
        }

        var framework = DetectFramework(request.InstallerPath);
        var candidates = GetKnownCandidates(framework.Framework);

        WebResearchResult? webResearch = null;
        if (!string.IsNullOrWhiteSpace(request.SupportUrl))
        {
            webResearch = await ResearchFromWebAsync(request.SupportUrl, cancellationToken);
            if (webResearch is not null)
            {
                AddWebCandidates(candidates, webResearch);
            }
        }

        var helpProbes = request.ProbeHelp && framework.Extension == ".exe"
            ? ProbeInstallerHelp(request.InstallerPath)
            : [];

        foreach (var probe in helpProbes)
        {
            foreach (var sw in probe.Switches)
            {
                if (!candidates.Any(c => c.Switch.Equals(sw, StringComparison.OrdinalIgnoreCase)))
                {
                    candidates.Add(new SilentSwitchCandidate
                    {
                        Switch = sw,
                        Confidence = "Medium",
                        Source = $"HelpProbe({probe.Argument})",
                        Description = "Found in installer help output"
                    });
                }
            }
        }

        var testResults = request.TestInstall
            ? TestSilentSwitches(request.InstallerPath, candidates.Select(c => c.Switch), request.DryRun)
            : [];

        foreach (var test in testResults.Where(t => t.Recommended))
        {
            var match = candidates.FirstOrDefault(c => c.Switch.Equals(test.Switch, StringComparison.OrdinalIgnoreCase));
            if (match is not null)
            {
                match.Confidence = "Verified";
            }
        }

        var recommended = candidates
            .OrderBy(c => ConfidenceRank(c.Confidence))
            .ThenBy(c => c.Switch)
            .FirstOrDefault();

        var installCommand = BuildInstallCommand(framework, recommended?.Switch);

        return new InstallerAnalysisResult
        {
            InstallerPath = request.InstallerPath,
            Framework = framework,
            Candidates = candidates,
            WebResearch = webResearch,
            HelpProbes = helpProbes,
            TestResults = testResults,
            RecommendedSwitch = recommended,
            InstallCommand = installCommand,
            Status = recommended?.Confidence is "Known" or "Verified" or "High" ? "Known" : "NeedsDiscovery"
        };
    }

    public async Task<DownloadResult> DownloadInstallerAsync(DownloadRequest request, ConfigService configService, CancellationToken cancellationToken)
    {
        var config = configService.GetConfig();
        var targetDir = string.IsNullOrWhiteSpace(request.TargetDirectory)
            ? config.DownloadPath
            : request.TargetDirectory;

        Directory.CreateDirectory(targetDir);

        var fileName = request.FileName;
        if (string.IsNullOrWhiteSpace(fileName))
        {
            fileName = Path.GetFileName(new Uri(request.Url).LocalPath);
            if (fileName.Contains('?'))
            {
                fileName = fileName.Split('?')[0];
            }
        }

        if (string.IsNullOrWhiteSpace(fileName))
        {
            fileName = $"installer-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}.exe";
        }

        var outputPath = Path.Combine(targetDir, fileName);

        try
        {
            var client = _httpClientFactory.CreateClient();
            await using var stream = await client.GetStreamAsync(request.Url, cancellationToken);
            await using var file = File.Create(outputPath);
            await stream.CopyToAsync(file, cancellationToken);

            var sizeMb = Math.Round(new FileInfo(outputPath).Length / (1024.0 * 1024.0), 2);

            if (!config.RecentDownloadUrls.Contains(request.Url))
            {
                config.RecentDownloadUrls.Insert(0, request.Url);
                config.RecentDownloadUrls = config.RecentDownloadUrls.Take(20).ToList();
                config.LastUpdated = DateTimeOffset.UtcNow;
                var json = System.Text.Json.JsonSerializer.Serialize(config, new System.Text.Json.JsonSerializerOptions
                {
                    WriteIndented = true,
                    PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
                });
                var configDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "AppGetter");
                File.WriteAllText(Path.Combine(configDir, "config.json"), json);
            }

            return new DownloadResult
            {
                Success = true,
                Path = outputPath,
                FileName = fileName,
                SizeMB = sizeMb,
                Message = "Download completed."
            };
        }
        catch (Exception ex)
        {
            return new DownloadResult
            {
                Success = false,
                Path = outputPath,
                FileName = fileName,
                Message = ex.Message
            };
        }
    }

    private static List<SilentSwitchCandidate> GetKnownCandidates(string framework)
    {
        if (KnownSwitches.TryGetValue(framework, out var list))
        {
            return list.Select(c => new SilentSwitchCandidate
            {
                Switch = c.Switch,
                Confidence = c.Confidence,
                Source = c.Source,
                Description = c.Description
            }).ToList();
        }

        return KnownSwitches["EXE_Generic"].Select(c => new SilentSwitchCandidate
        {
            Switch = c.Switch,
            Confidence = c.Confidence,
            Source = c.Source,
            Description = c.Description
        }).ToList();
    }

    private static void AddWebCandidates(List<SilentSwitchCandidate> candidates, WebResearchResult webResearch)
    {
        foreach (var snippet in webResearch.InstallSwitches)
        {
            foreach (Match match in Regex.Matches(snippet, @"(?i)(/VERYSILENT|/SILENT|/SUPPRESSMSGBOXES|/NORESTART|/SP-|/S\b|/quiet|/qn|/qb|/passive|--silent)"))
            {
                var sw = match.Value;
                if (!candidates.Any(c => c.Switch.Equals(sw, StringComparison.OrdinalIgnoreCase)))
                {
                    candidates.Add(new SilentSwitchCandidate
                    {
                        Switch = sw,
                        Confidence = "Medium",
                        Source = "WebDocumentation",
                        Description = snippet.Length > 120 ? snippet[..120] : snippet
                    });
                }
            }
        }
    }

    private static int ConfidenceRank(string confidence) => confidence switch
    {
        "Verified" => 0,
        "Known" => 1,
        "High" => 2,
        "Medium" => 3,
        _ => 4
    };

    private static string BuildInstallCommand(InstallerFrameworkInfo framework, string? selectedSwitch)
    {
        return framework.Extension switch
        {
            ".msi" => $"msiexec /i \"{framework.FileName}\" /quiet /norestart",
            ".msix" or ".appx" => $"Add-AppxPackage -Path \"{framework.FileName}\"",
            _ => $"\"{framework.FileName}\" {selectedSwitch ?? "/S"}"
        };
    }
}
