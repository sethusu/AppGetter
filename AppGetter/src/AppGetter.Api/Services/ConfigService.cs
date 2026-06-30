using System.Text.Json;
using AppGetter.Shared.Models;

namespace AppGetter.Api.Services;

public sealed class ConfigService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly string _configPath;

    public ConfigService()
    {
        var configDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AppGetter");
        Directory.CreateDirectory(configDir);
        _configPath = Path.Combine(configDir, "config.json");
    }

    public AppGetterConfig GetConfig()
    {
        if (!File.Exists(_configPath))
        {
            var defaults = new AppGetterConfig();
            SaveConfig(defaults);
            return defaults;
        }

        var json = File.ReadAllText(_configPath);
        return JsonSerializer.Deserialize<AppGetterConfig>(json, JsonOptions) ?? new AppGetterConfig();
    }

    public AppGetterConfig UpdateConfig(UpdateConfigRequest request)
    {
        var config = GetConfig();

        if (!string.IsNullOrWhiteSpace(request.DownloadPath))
        {
            config.DownloadPath = request.DownloadPath;
        }

        if (!string.IsNullOrWhiteSpace(request.OutputPath))
        {
            config.OutputPath = request.OutputPath;
        }

        if (request.ContentPrepToolPath is not null)
        {
            config.ContentPrepToolPath = request.ContentPrepToolPath;
        }

        if (!string.IsNullOrWhiteSpace(request.ApiBaseUrl))
        {
            config.ApiBaseUrl = request.ApiBaseUrl;
        }

        config.LastUpdated = DateTimeOffset.UtcNow;
        SaveConfig(config);
        return config;
    }

    public AppGetterConfig ResetConfig()
    {
        if (File.Exists(_configPath))
        {
            File.Delete(_configPath);
        }

        return GetConfig();
    }

    public PathValidationResult ValidatePath(string path, bool createIfMissing = false)
    {
        var result = new PathValidationResult { Path = path };

        if (string.IsNullOrWhiteSpace(path))
        {
            result.Message = "Path is empty.";
            return result;
        }

        if (!Directory.Exists(path))
        {
            if (createIfMissing)
            {
                try
                {
                    Directory.CreateDirectory(path);
                }
                catch (Exception ex)
                {
                    result.Message = $"Could not create path: {ex.Message}";
                    return result;
                }
            }
            else
            {
                result.Message = "Path does not exist.";
                return result;
            }
        }

        result.Exists = true;

        try
        {
            var testFile = Path.Combine(path, ".appgetter-write-test");
            File.WriteAllText(testFile, "test");
            File.Delete(testFile);
            result.Writable = true;
        }
        catch (Exception ex)
        {
            result.Message = $"Path is not writable: {ex.Message}";
            return result;
        }

        try
        {
            var root = Path.GetPathRoot(Path.GetFullPath(path));
            if (!string.IsNullOrEmpty(root))
            {
                var drive = new DriveInfo(root);
                if (drive.IsReady)
                {
                    result.FreeSpaceGB = Math.Round(drive.AvailableFreeSpace / (1024.0 * 1024 * 1024), 2);
                }
            }
        }
        catch
        {
            // Non-fatal
        }

        result.Message = "Path is valid and writable.";
        return result;
    }

    private void SaveConfig(AppGetterConfig config)
    {
        var json = JsonSerializer.Serialize(config, JsonOptions);
        File.WriteAllText(_configPath, json);
    }
}
