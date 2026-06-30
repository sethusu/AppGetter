using AppGetter.Api.Services;
using AppGetter.Shared.Models;
using Microsoft.AspNetCore.Mvc;

namespace AppGetter.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public sealed class ConfigController : ControllerBase
{
    private readonly ConfigService _configService;

    public ConfigController(ConfigService configService)
    {
        _configService = configService;
    }

    [HttpGet]
    public ActionResult<AppGetterConfig> Get() => Ok(_configService.GetConfig());

    [HttpPut]
    public ActionResult<AppGetterConfig> Update([FromBody] UpdateConfigRequest request) =>
        Ok(_configService.UpdateConfig(request));

    [HttpPost("reset")]
    public ActionResult<AppGetterConfig> Reset() => Ok(_configService.ResetConfig());

    [HttpPost("validate-path")]
    public ActionResult<PathValidationResult> ValidatePath([FromBody] PathValidationRequest request) =>
        Ok(_configService.ValidatePath(request.Path, request.CreateIfMissing));
}

public sealed class PathValidationRequest
{
    public string Path { get; set; } = string.Empty;
    public bool CreateIfMissing { get; set; }
}
