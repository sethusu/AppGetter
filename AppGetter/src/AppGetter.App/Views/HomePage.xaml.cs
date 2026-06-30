using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace AppGetter.App.Views;

public sealed partial class HomePage : Page
{
    public HomePage()
    {
        InitializeComponent();
    }

    private void OpenInstaller_Click(object sender, RoutedEventArgs e)
    {
        if (Parent is Frame frame)
        {
            frame.Navigate(typeof(InstallerPage));
        }
    }
}
