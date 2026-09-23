namespace AgentMon.Relay.Windows;

internal sealed class RelayTrayContext : ApplicationContext
{
    private readonly IRelayController controller;
    private readonly NotifyIcon trayIcon;
    private readonly RelayForm form;
    private bool quitting;

    internal RelayTrayContext(IRelayController controller, bool startInBackground)
    {
        this.controller = controller;
        form = new RelayForm(controller, QuitAsync);

        var menu = new ContextMenuStrip();
        menu.Items.Add("&Open AgentMon Relay", null, (_, _) => ShowForm());
        menu.Items.Add("-");
        menu.Items.Add("&Quit", null, async (_, _) => await QuitAsync());

        trayIcon = new NotifyIcon
        {
            ContextMenuStrip = menu,
            Icon = SystemIcons.Application,
            Text = "AgentMon Relay",
            Visible = true,
        };
        trayIcon.DoubleClick += (_, _) => ShowForm();

        if (startInBackground)
        {
            _ = StartRelayAsync();
        }
        else
        {
            ShowForm();
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            trayIcon.Visible = false;
            trayIcon.Dispose();
            form.Dispose();
        }

        base.Dispose(disposing);
    }

    private void ShowForm()
    {
        if (form.Visible)
        {
            form.Activate();
            return;
        }

        form.Show();
        form.Activate();
    }

    private async Task StartRelayAsync()
    {
        try
        {
            await controller.StartAsync();
            form.RefreshView();
        }
        catch (Exception error)
        {
            RelayApplication.LogFailure("background relay start", error);
            trayIcon.ShowBalloonTip(
                5000,
                "AgentMon Relay",
                $"The relay could not start ({error.GetType().Name}). Open the app for details.",
                ToolTipIcon.Error);
        }
    }

    private async Task QuitAsync()
    {
        if (quitting)
        {
            return;
        }

        quitting = true;
        form.PrepareForShutdown();
        trayIcon.Visible = false;

        try
        {
            await controller.StopAsync();
        }
        catch (Exception error)
        {
            RelayApplication.LogFailure("relay stop", error);
        }

        try
        {
            await controller.DisposeAsync();
        }
        catch (Exception error)
        {
            RelayApplication.LogFailure("relay disposal", error);
        }

        ExitThread();
    }
}
