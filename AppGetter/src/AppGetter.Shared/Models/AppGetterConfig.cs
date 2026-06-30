namespace AppGetter.Shared.Models;

public sealed class AppGetterConfig
{
    public string DownloadPath { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        "Downloads",
        "AppGetter");

    public string OutputPath { get; set; } = @"D:\Intoon In Progress";
    public string ContentPrepToolPath { get; set; } = string.Empty;
    public string ApiBaseUrl { get; set; } = "http://localhost:5050";
    public List<string> RecentDownloadUrls { get; set; } = [];
    public List<RecentPackage> RecentPackages { get; set; } = [];
    public DateTimeOffset LastUpdated { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class RecentPackage
{
    public string AppName { get; set; } = string.Empty;
    public string PackageId { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public string OutputDirectory { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class PathValidationResult
{
    public string Path { get; set; } = string.Empty;
    public bool Exists { get; set; }
    public bool Writable { get; set; }
    public double? FreeSpaceGB { get; set; }
    public string Message { get; set; } = string.Empty;
}

public sealed class UpdateConfigRequest
{
    public string? DownloadPath { get; set; }
    public string? OutputPath { get; set; }
    public string? ContentPrepToolPath { get; set; }
    public string? ApiBaseUrl { get; set; }
}
