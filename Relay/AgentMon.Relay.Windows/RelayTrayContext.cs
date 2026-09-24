namespace AgentMon.Relay.Windows;

internal sealed class RelayTrayContext : ApplicationContext
{
    private readonly IRelayController controller;
    private readonly NotifyIcon trayIcon;
    private readonly RelayForm form;
    private readonly EventWaitHandle shutdownSignal;
    private readonly System.Windows.Forms.Timer shutdownTimer;
    private readonly RelayIconSet relayIcons;
    private RelayIconState currentIconState;
    private bool quitting;

    internal RelayTrayContext(
        IRelayController controller,
        bool startInBackground,
        bool queryWindowsIntegration = true)
    {
        this.controller = controller;
        relayIcons = RelayIconSet.Load();
        form = new RelayForm(controller, QuitAsync, queryWindowsIntegration);
        form.RelayStateChanged += UpdateStatusPresentation;
        shutdownSignal = new EventWaitHandle(false, EventResetMode.AutoReset, Program.ShutdownEventName);
        shutdownTimer = new System.Windows.Forms.Timer { Interval = 200 };
        shutdownTimer.Tick += async (_, _) =>
        {
            if (shutdownSignal.WaitOne(0))
                await QuitAsync();
        };
        shutdownTimer.Start();

        var menu = new ContextMenuStrip();
        menu.Items.Add("&Open AgentMon Relay", null, (_, _) => ShowForm());
        menu.Items.Add("-");
        menu.Items.Add("&Quit", null, async (_, _) => await QuitAsync());

        trayIcon = new NotifyIcon
        {
            ContextMenuStrip = menu,
            Icon = relayIcons[RelayIconState.Stopped],
            Text = "AgentMon Relay",
            Visible = true,
        };
        trayIcon.DoubleClick += (_, _) => ShowForm();
        UpdateStatusPresentation(controller.GetView().State);

        _ = StartRelayAsync();
        if (!startInBackground)
        {
            ShowForm();
        }
    }

    internal Icon CurrentTrayIcon => trayIcon.Icon ?? relayIcons[RelayIconState.Stopped];

    internal RelayIconState CurrentIconState => currentIconState;

    internal RelayForm ManagementForm => form;

    internal Task RequestQuitAsync() => QuitAsync();

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            shutdownTimer.Stop();
            shutdownTimer.Dispose();
            shutdownSignal.Dispose();
            trayIcon.Visible = false;
            trayIcon.Icon = null;
            form.Icon = null;
            trayIcon.Dispose();
            form.Dispose();
            relayIcons.Dispose();
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

    private void UpdateStatusPresentation(string state)
    {
        currentIconState = state switch
        {
            "Running" => RelayIconState.Running,
            "Waiting for private network" => RelayIconState.Waiting,
            "Error" => RelayIconState.Error,
            _ => RelayIconState.Stopped,
        };
        var icon = relayIcons[currentIconState];
        trayIcon.Icon = icon;
        trayIcon.Text = $"AgentMon Relay - {state}";
        form.Icon = icon;
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
