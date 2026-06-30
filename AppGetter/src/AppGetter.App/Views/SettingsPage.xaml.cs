using AppGetter.Shared.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage.Pickers;

namespace AppGetter.App.Views;

public sealed partial class SettingsPage : Page
{
    public SettingsPage()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e) => await LoadConfigAsync();

    private static Services.AppGetterApiClient Api => App.MainWindow?.ApiClient ?? new Services.AppGetterApiClient();

    private async Task LoadConfigAsync()
    {
        try
        {
            var config = await Api.GetConfigAsync();
            DownloadPathBox.Text = config.DownloadPath;
            OutputPathBox.Text = config.OutputPath;
            ApiUrlBox.Text = config.ApiBaseUrl;
        }
        catch (Exception ex)
        {
            ShowInfo($"Could not load settings: {ex.Message}", InfoBarSeverity.Error);
        }
    }

    private async void BrowseDownload_Click(object sender, RoutedEventArgs e) =>
        DownloadPathBox.Text = await PickFolderAsync() ?? DownloadPathBox.Text;

    private async void BrowseOutput_Click(object sender, RoutedEventArgs e) =>
        OutputPathBox.Text = await PickFolderAsync() ?? OutputPathBox.Text;

    private async Task<string?> PickFolderAsync()
    {
        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.Downloads
        };
        picker.FileTypeFilter.Add("*");

        if (App.MainWindow is not null)
        {
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(App.MainWindow);
            WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
        }

        var folder = await picker.PickSingleFolderAsync();
        return folder?.Path;
    }

    private async void ValidateDownload_Click(object sender, RoutedEventArgs e) =>
        await ValidatePathAsync(DownloadPathBox.Text, DownloadValidationText, createIfMissing: true);

    private async void ValidateOutput_Click(object sender, RoutedEventArgs e) =>
        await ValidatePathAsync(OutputPathBox.Text, OutputValidationText, createIfMissing: true);

    private async Task ValidatePathAsync(string path, TextBlock target, bool createIfMissing)
    {
        try
        {
            var result = await Api.ValidatePathAsync(path, createIfMissing);
            target.Text = result.Writable
                ? $"{result.Message} Free space: {result.FreeSpaceGB:0.##} GB"
                : result.Message;
        }
        catch (Exception ex)
        {
            target.Text = ex.Message;
        }
    }

    private async void Save_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Api.SetBaseUrl(ApiUrlBox.Text);
            var config = await Api.UpdateConfigAsync(new UpdateConfigRequest
            {
                DownloadPath = DownloadPathBox.Text,
                OutputPath = OutputPathBox.Text,
                ApiBaseUrl = ApiUrlBox.Text
            });

            ShowInfo($"Settings saved at {config.LastUpdated:u}", InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowInfo($"Save failed: {ex.Message}", InfoBarSeverity.Error);
        }
    }

    private async void Reset_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            await Api.UpdateConfigAsync(new UpdateConfigRequest
            {
                DownloadPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "AppGetter"),
                OutputPath = @"D:\Intoon In Progress",
                ApiBaseUrl = "http://localhost:5050"
            });
            await LoadConfigAsync();
            ShowInfo("Settings reset to defaults.", InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowInfo($"Reset failed: {ex.Message}", InfoBarSeverity.Error);
        }
    }

    private void ShowInfo(string message, InfoBarSeverity severity)
    {
        SettingsInfoBar.Message = message;
        SettingsInfoBar.Severity = severity;
        SettingsInfoBar.IsOpen = true;
    }
}
