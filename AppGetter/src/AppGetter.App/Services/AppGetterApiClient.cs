using System.Net.Http.Json;
using System.Text.Json;
using AppGetter.Shared.Models;

namespace AppGetter.App.Services;

public sealed class AppGetterApiClient
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _httpClient;

    public AppGetterApiClient(string baseUrl = "http://localhost:5050")
    {
        _httpClient = new HttpClient { BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/") };
    }

    public void SetBaseUrl(string baseUrl)
    {
        _httpClient.BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/");
    }

    public async Task<bool> IsHealthyAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var response = await _httpClient.GetAsync("api/health", cancellationToken);
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    public async Task<AppGetterConfig> GetConfigAsync(CancellationToken cancellationToken = default)
    {
        return await _httpClient.GetFromJsonAsync<AppGetterConfig>("api/config", JsonOptions, cancellationToken)
            ?? new AppGetterConfig();
    }

    public async Task<AppGetterConfig> UpdateConfigAsync(UpdateConfigRequest request, CancellationToken cancellationToken = default)
    {
        var response = await _httpClient.PutAsJsonAsync("api/config", request, JsonOptions, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<AppGetterConfig>(JsonOptions, cancellationToken)
            ?? new AppGetterConfig();
    }

    public async Task<PathValidationResult> ValidatePathAsync(string path, bool createIfMissing, CancellationToken cancellationToken = default)
    {
        var response = await _httpClient.PostAsJsonAsync("api/config/validate-path",
            new { path, createIfMissing }, JsonOptions, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<PathValidationResult>(JsonOptions, cancellationToken)
            ?? new PathValidationResult { Path = path };
    }

    public async Task<InstallerAnalysisResult> AnalyzeInstallerAsync(AnalyzeInstallerRequest request, CancellationToken cancellationToken = default)
    {
        var response = await _httpClient.PostAsJsonAsync("api/installers/analyze", request, JsonOptions, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<InstallerAnalysisResult>(JsonOptions, cancellationToken)
            ?? new InstallerAnalysisResult();
    }

    public async Task<InstallerAnalysisResult> DiscoverSwitchesAsync(DiscoverSwitchesRequest request, CancellationToken cancellationToken = default)
    {
        var response = await _httpClient.PostAsJsonAsync("api/installers/discover", request, JsonOptions, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<InstallerAnalysisResult>(JsonOptions, cancellationToken)
            ?? new InstallerAnalysisResult();
    }

    public async Task<DownloadResult> DownloadInstallerAsync(DownloadRequest request, CancellationToken cancellationToken = default)
    {
        var response = await _httpClient.PostAsJsonAsync("api/installers/download", request, JsonOptions, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadFromJsonAsync<DownloadResult>(JsonOptions, cancellationToken);
            return error ?? new DownloadResult { Success = false, Message = response.ReasonPhrase ?? "Download failed." };
        }

        return await response.Content.ReadFromJsonAsync<DownloadResult>(JsonOptions, cancellationToken)
            ?? new DownloadResult { Success = false, Message = "Empty response." };
    }

    public async Task<InstallerAnalysisResult> UploadInstallerAsync(
        string filePath,
        string? supportUrl,
        string? appName,
        bool probeHelp,
        bool testInstall,
        bool dryRun,
        CancellationToken cancellationToken = default)
    {
        await using var stream = File.OpenRead(filePath);
        using var content = new MultipartFormDataContent();
        content.Add(new StreamContent(stream), "file", Path.GetFileName(filePath));

        if (!string.IsNullOrWhiteSpace(supportUrl))
        {
            content.Add(new StringContent(supportUrl), "supportUrl");
        }

        if (!string.IsNullOrWhiteSpace(appName))
        {
            content.Add(new StringContent(appName), "appName");
        }

        content.Add(new StringContent(probeHelp.ToString()), "probeHelp");
        content.Add(new StringContent(testInstall.ToString()), "testInstall");
        content.Add(new StringContent(dryRun.ToString()), "dryRun");

        var response = await _httpClient.PostAsync("api/installers/upload", content, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<InstallerAnalysisResult>(JsonOptions, cancellationToken)
            ?? new InstallerAnalysisResult();
    }
}
