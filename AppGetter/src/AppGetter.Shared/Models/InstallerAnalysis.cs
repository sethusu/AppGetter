namespace AppGetter.Shared.Models;

public sealed class InstallerFrameworkInfo
{
    public string Framework { get; set; } = "EXE_Generic";
    public string Extension { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public string Confidence { get; set; } = "Low";
    public string DetectionMethod { get; set; } = "Fallback";
    public string? MatchedPattern { get; set; }
}

public sealed class SilentSwitchCandidate
{
    public string Switch { get; set; } = string.Empty;
    public string Confidence { get; set; } = "Heuristic";
    public string Source { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
}

public sealed class HelpProbeResult
{
    public string Argument { get; set; } = string.Empty;
    public bool Success { get; set; }
    public string Output { get; set; } = string.Empty;
    public List<string> Switches { get; set; } = [];
}

public sealed class SwitchTestResult
{
    public string Switch { get; set; } = string.Empty;
    public string Status { get; set; } = "NotTested";
    public int? ExitCode { get; set; }
    public long? DurationMs { get; set; }
    public string Message { get; set; } = string.Empty;
    public bool Recommended { get; set; }
}

public sealed class WebResearchResult
{
    public string SourceUrl { get; set; } = string.Empty;
    public List<string> InstallSwitches { get; set; } = [];
    public List<string> BestPractices { get; set; } = [];
}

public sealed class InstallerAnalysisResult
{
    public string InstallerPath { get; set; } = string.Empty;
    public InstallerFrameworkInfo Framework { get; set; } = new();
    public List<SilentSwitchCandidate> Candidates { get; set; } = [];
    public WebResearchResult? WebResearch { get; set; }
    public List<HelpProbeResult> HelpProbes { get; set; } = [];
    public List<SwitchTestResult> TestResults { get; set; } = [];
    public SilentSwitchCandidate? RecommendedSwitch { get; set; }
    public string InstallCommand { get; set; } = string.Empty;
    public string Status { get; set; } = "NeedsDiscovery";
}

public class AnalyzeInstallerRequest
{
    public string InstallerPath { get; set; } = string.Empty;
    public string? SupportUrl { get; set; }
    public string? AppName { get; set; }
    public bool ProbeHelp { get; set; } = true;
    public bool TestInstall { get; set; }
    public bool DryRun { get; set; } = true;
}

public sealed class DiscoverSwitchesRequest : AnalyzeInstallerRequest
{
    public bool ForceDiscovery { get; set; }
}

public sealed class DownloadRequest
{
    public string Url { get; set; } = string.Empty;
    public string? FileName { get; set; }
    public string? TargetDirectory { get; set; }
}

public sealed class DownloadResult
{
    public bool Success { get; set; }
    public string Path { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public double SizeMB { get; set; }
    public string Message { get; set; } = string.Empty;
}
