using AppGetter.App.Services;
using AppGetter.App.Views;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using WinRT.Interop;

namespace AppGetter.App;

public sealed partial class MainWindow : Window
{
    private readonly AppGetterApiClient _apiClient = new();
    private MicaController? _micaController;
    private SystemBackdropConfiguration? _backdropConfig;

    public MainWindow()
    {
        InitializeComponent();
        Title = "AppGetter";
        SetWindowProperties();
        TrySetMicaBackdrop();
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        var healthy = await _apiClient.IsHealthyAsync();
        BackendStatusBar.IsOpen = !healthy;
        BackendStatusBar.Message = healthy
            ? "Connected to AppGetter backend."
            : "Backend API is not running. Start AppGetter.Api on http://localhost:5050.";

        if (healthy)
        {
            BackendStatusBar.Severity = InfoBarSeverity.Success;
        }
        else
        {
            BackendStatusBar.Severity = InfoBarSeverity.Warning;
        }
    }

    private void SetWindowProperties()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
        var appWindow = AppWindow.GetFromWindowId(windowId);
        appWindow.Resize(new Windows.Graphics.SizeInt32(1280, 860));
        appWindow.Title = "AppGetter";
    }

    private void TrySetMicaBackdrop()
    {
        if (MicaController.IsSupported())
        {
            _micaController = new MicaController { Kind = MicaKind.BaseAlt };
            _backdropConfig = new SystemBackdropConfiguration();
            Activated += (_, _) => _micaController.AddSystemBackdropTarget(this);
            Closed += (_, _) => _micaController.Dispose();
            _micaController.SetSystemBackdropConfiguration(_backdropConfig);
        }
        else
        {
            SystemBackdrop = new MicaBackdrop();
        }
    }

    private void NavigationView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is not NavigationViewItem item || item.Tag is not string tag)
        {
            return;
        }

        Frame rootFrame = ContentFrame;
        rootFrame.Navigate(tag switch
        {
            "home" => typeof(HomePage),
            "installer" => typeof(InstallerPage),
            "settings" => typeof(SettingsPage),
            _ => typeof(HomePage)
        });
    }

    public AppGetterApiClient ApiClient => _apiClient;
}
