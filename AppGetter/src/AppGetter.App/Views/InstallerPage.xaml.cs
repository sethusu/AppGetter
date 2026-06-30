using AppGetter.Shared.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage.Pickers;

namespace AppGetter.App.Views;

public sealed partial class InstallerPage : Page
{
    private string? _installerPath;

    public InstallerPage()
    {
        InitializeComponent();
    }

    private static Services.AppGetterApiClient Api => App.MainWindow?.ApiClient ?? new Services.AppGetterApiClient();

    private async void Download_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(DownloadUrlBox.Text))
        {
            ShowInfo("Enter a download URL first.", InfoBarSeverity.Warning);
            return;
        }

        await RunBusyAsync(async () =>
        {
            var result = await Api.DownloadInstallerAsync(new DownloadRequest
            {
                Url = DownloadUrlBox.Text.Trim()
            });

            if (!result.Success)
            {
                ShowInfo(result.Message, InfoBarSeverity.Error);
                return;
            }

            _installerPath = result.Path;
            InstallerPathText.Text = $"Downloaded: {result.Path} ({result.SizeMB:0.##} MB)";
            ShowInfo("Installer downloaded successfully.", InfoBarSeverity.Success);
        });
    }

    private async void Upload_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".exe");
        picker.FileTypeFilter.Add(".msi");
        picker.FileTypeFilter.Add(".msix");
        picker.FileTypeFilter.Add(".appx");

        if (App.MainWindow is not null)
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(App.MainWindow);
            WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
        }

        var file = await picker.PickSingleFileAsync();
        if (file is null)
        {
            return;
        }

        _installerPath = file.Path;
        InstallerPathText.Text = $"Selected: {_installerPath}";
    }

    private async void Analyze_Click(object sender, RoutedEventArgs e) =>
        await AnalyzeInternalAsync(forceDiscovery: false);

    private async void Discover_Click(object sender, RoutedEventArgs e) =>
        await AnalyzeInternalAsync(forceDiscovery: true);

    private async Task AnalyzeInternalAsync(bool forceDiscovery)
    {
        if (string.IsNullOrWhiteSpace(_installerPath))
        {
            ShowInfo("Download or upload an installer first.", InfoBarSeverity.Warning);
            return;
        }

        await RunBusyAsync(async () =>
        {
            InstallerAnalysisResult result;

            if (forceDiscovery && File.Exists(_installerPath) && _installerPath.StartsWith(@"\\") == false)
            {
                result = await Api.DiscoverSwitchesAsync(new DiscoverSwitchesRequest
                {
                    InstallerPath = _installerPath,
                    SupportUrl = string.IsNullOrWhiteSpace(SupportUrlBox.Text) ? null : SupportUrlBox.Text.Trim(),
                    AppName = string.IsNullOrWhiteSpace(AppNameBox.Text) ? null : AppNameBox.Text.Trim(),
                    ProbeHelp = ProbeHelpSwitch.IsOn,
                    TestInstall = LiveTestSwitch.IsOn || forceDiscovery,
                    DryRun = DryRunSwitch.IsOn && !LiveTestSwitch.IsOn,
                    ForceDiscovery = forceDiscovery
                });
            }
            else if (File.Exists(_installerPath))
            {
                result = await Api.AnalyzeInstallerAsync(new AnalyzeInstallerRequest
                {
                    InstallerPath = _installerPath,
                    SupportUrl = string.IsNullOrWhiteSpace(SupportUrlBox.Text) ? null : SupportUrlBox.Text.Trim(),
                    AppName = string.IsNullOrWhiteSpace(AppNameBox.Text) ? null : AppNameBox.Text.Trim(),
                    ProbeHelp = ProbeHelpSwitch.IsOn,
                    TestInstall = LiveTestSwitch.IsOn,
                    DryRun = DryRunSwitch.IsOn && !LiveTestSwitch.IsOn
                });
            }
            else
            {
                result = await Api.UploadInstallerAsync(
                    _installerPath,
                    string.IsNullOrWhiteSpace(SupportUrlBox.Text) ? null : SupportUrlBox.Text.Trim(),
                    string.IsNullOrWhiteSpace(AppNameBox.Text) ? null : AppNameBox.Text.Trim(),
                    ProbeHelpSwitch.IsOn,
                    LiveTestSwitch.IsOn,
                    DryRunSwitch.IsOn && !LiveTestSwitch.IsOn);
            }

            BindResults(result);
            ShowInfo(
                result.Status == "Known"
                    ? "Silent install switches are known or verified."
                    : "Switches need discovery — review candidates or run live tests in a VM.",
                result.Status == "Known" ? InfoBarSeverity.Success : InfoBarSeverity.Warning);
        });
    }

    private void BindResults(InstallerAnalysisResult result)
    {
        FrameworkText.Text =
            $"Framework: {result.Framework.Framework} ({result.Framework.Confidence}) — {result.Framework.DetectionMethod}";
        StatusText.Text = $"Status: {result.Status}";
        InstallCommandBox.Text = result.InstallCommand;
        CandidatesList.ItemsSource = result.Candidates;
        _installerPath = result.InstallerPath;
        InstallerPathText.Text = $"Installer: {result.InstallerPath}";
    }

    private async Task RunBusyAsync(Func<Task> action)
    {
        BusyRing.Visibility = Visibility.Visible;
        BusyRing.IsActive = true;
        try
        {
            await action();
        }
        catch (Exception ex)
        {
            ShowInfo(ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            BusyRing.IsActive = false;
            BusyRing.Visibility = Visibility.Collapsed;
        }
    }

    private void ShowInfo(string message, InfoBarSeverity severity)
    {
        InstallerInfoBar.Message = message;
        InstallerInfoBar.Severity = severity;
        InstallerInfoBar.IsOpen = true;
    }
}
