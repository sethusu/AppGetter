using AppGetter.Api.Services;
using AppGetter.Shared.Models;
using Microsoft.AspNetCore.Mvc;

namespace AppGetter.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public sealed class InstallersController : ControllerBase
{
    private readonly InstallerAnalysisService _analysisService;
    private readonly ConfigService _configService;
    private readonly IWebHostEnvironment _environment;

    public InstallersController(
        InstallerAnalysisService analysisService,
        ConfigService configService,
        IWebHostEnvironment environment)
    {
        _analysisService = analysisService;
        _configService = configService;
        _environment = environment;
    }

    [HttpPost("analyze")]
    public async Task<ActionResult<InstallerAnalysisResult>> Analyze(
        [FromBody] AnalyzeInstallerRequest request,
        CancellationToken cancellationToken)
    {
        var result = await _analysisService.AnalyzeAsync(request, cancellationToken);
        return Ok(result);
    }

    [HttpPost("discover")]
    public async Task<ActionResult<InstallerAnalysisResult>> Discover(
        [FromBody] DiscoverSwitchesRequest request,
        CancellationToken cancellationToken)
    {
        request.ProbeHelp = true;
        if (request.ForceDiscovery)
        {
            request.TestInstall = true;
            request.DryRun = false;
        }

        var result = await _analysisService.AnalyzeAsync(request, cancellationToken);
        return Ok(result);
    }

    [HttpPost("upload")]
    [RequestSizeLimit(1024L * 1024L * 1024L)]
    public async Task<ActionResult<InstallerAnalysisResult>> Upload(
        IFormFile file,
        [FromForm] string? supportUrl,
        [FromForm] string? appName,
        [FromForm] bool probeHelp = true,
        [FromForm] bool testInstall = false,
        [FromForm] bool dryRun = true,
        CancellationToken cancellationToken = default)
    {
        if (file is null || file.Length == 0)
        {
            return BadRequest("Installer file is required.");
        }

        var config = _configService.GetConfig();
        Directory.CreateDirectory(config.DownloadPath);

        var safeName = Path.GetFileName(file.FileName);
        var installerPath = Path.Combine(config.DownloadPath, safeName);

        await using (var stream = System.IO.File.Create(installerPath))
        {
            await file.CopyToAsync(stream, cancellationToken);
        }

        var request = new AnalyzeInstallerRequest
        {
            InstallerPath = installerPath,
            SupportUrl = supportUrl,
            AppName = appName,
            ProbeHelp = probeHelp,
            TestInstall = testInstall,
            DryRun = dryRun
        };

        var result = await _analysisService.AnalyzeAsync(request, cancellationToken);
        return Ok(result);
    }

    [HttpPost("download")]
    public async Task<ActionResult<DownloadResult>> Download(
        [FromBody] DownloadRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Url))
        {
            return BadRequest("Download URL is required.");
        }

        var result = await _analysisService.DownloadInstallerAsync(request, _configService, cancellationToken);
        if (!result.Success)
        {
            return BadRequest(result);
        }

        return Ok(result);
    }

    [HttpGet("framework")]
    public ActionResult<InstallerFrameworkInfo> DetectFramework([FromQuery] string path)
    {
        if (string.IsNullOrWhiteSpace(path) || !System.IO.File.Exists(path))
        {
            return NotFound("Installer file not found.");
        }

        return Ok(_analysisService.DetectFramework(path));
    }
}
