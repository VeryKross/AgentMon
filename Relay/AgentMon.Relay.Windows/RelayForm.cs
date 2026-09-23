using System.ComponentModel;

namespace AgentMon.Relay.Windows;

internal sealed class RelayForm : Form
{
    private enum UiOperation
    {
        CertificateRotation,
        ClipboardCopy,
        DisplayNameUpdate,
        FirewallElevation,
        OpenLogs,
        RelayStateChange,
        StartupSetting,
        StartupStatus,
        TokenReveal,
        TokenRotation,
    }

    private static readonly TimeSpan TokenVisibilityDuration = TimeSpan.FromSeconds(30);

    private readonly IRelayController controller;
    private readonly Func<Task> quitAsync;
    private readonly Label stateValue = CreateValueLabel();
    private readonly Label errorValue = CreateValueLabel();
    private readonly TextBox displayNameTextBox = new();
    private readonly ListBox urlsListBox = new();
    private readonly TextBox fingerprintTextBox = CreateReadOnlyTextBox();
    private readonly TextBox tokenTextBox = CreateReadOnlyTextBox();
    private readonly Label sessionsValue = CreateValueLabel();
    private readonly Label lastIndexedValue = CreateValueLabel();
    private readonly Label discoveryValue = CreateValueLabel();
    private readonly Label firewallValue = CreateValueLabel();
    private readonly Button startStopButton = new();
    private readonly Button saveNameButton = new();
    private readonly Button copyUrlButton = new();
    private readonly Button copyFingerprintButton = new();
    private readonly Button revealTokenButton = new();
    private readonly Button rotateTokenButton = new();
    private readonly Button rotateCertificateButton = new();
    private readonly Button configureFirewallButton = new();
    private readonly CheckBox startupCheckBox = new();
    private readonly System.Windows.Forms.Timer refreshTimer = new() { Interval = 1000 };
    private readonly System.Windows.Forms.Timer tokenTimer = new();
    private bool busy;
    private bool closingForQuit;
    private bool firewallCanConfigure = true;
    private bool startupAvailable = true;

    internal RelayForm(IRelayController controller, Func<Task> quitAsync)
    {
        this.controller = controller;
        this.quitAsync = quitAsync;

        Text = "AgentMon Relay";
        AccessibleName = "AgentMon Relay management";
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(720, 650);
        MinimumSize = new Size(620, 580);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.Sizable;
        MaximizeBox = false;
        Padding = new Padding(16);

        BuildLayout();
        WireEvents();
        RefreshView();
        RefreshWindowsIntegration();
    }

    internal void RefreshView()
    {
        if (IsDisposed)
        {
            return;
        }

        var view = controller.GetView();
        stateValue.Text = view.State;
        stateValue.ForeColor = GetStateColor(view.State);
        errorValue.Text = string.IsNullOrWhiteSpace(view.Error) ? "None" : view.Error;
        errorValue.ForeColor = string.IsNullOrWhiteSpace(view.Error) ? SystemColors.GrayText : Color.Firebrick;
        discoveryValue.Text = view.DiscoveryStatus;
        sessionsValue.Text = view.SessionCount.ToString(System.Globalization.CultureInfo.CurrentCulture);
        lastIndexedValue.Text = view.LastIndexedAt is null
            ? "Not yet indexed"
            : view.LastIndexedAt.Value.ToLocalTime().ToString("g", System.Globalization.CultureInfo.CurrentCulture);
        fingerprintTextBox.Text = view.Fingerprint;

        if (!displayNameTextBox.Focused)
        {
            displayNameTextBox.Text = view.DisplayName;
        }

        var selectedUrl = urlsListBox.SelectedItem as string;
        urlsListBox.BeginUpdate();
        urlsListBox.Items.Clear();
        urlsListBox.Items.AddRange(view.Urls.Cast<object>().ToArray());
        if (selectedUrl is not null && urlsListBox.Items.Contains(selectedUrl))
        {
            urlsListBox.SelectedItem = selectedUrl;
        }
        else if (urlsListBox.Items.Count > 0)
        {
            urlsListBox.SelectedIndex = 0;
        }

        urlsListBox.EndUpdate();
        copyUrlButton.Enabled = urlsListBox.SelectedItem is not null && !busy;
        startStopButton.Text = IsRunningState(view.State) ? "&Stop relay" : "&Start relay";
    }

    internal void PrepareForShutdown()
    {
        closingForQuit = true;
        refreshTimer.Stop();
        HideToken();
        Hide();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!closingForQuit && e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            HideToken();
            Hide();
            return;
        }

        base.OnFormClosing(e);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            refreshTimer.Dispose();
            tokenTimer.Dispose();
        }

        base.Dispose(disposing);
    }

    private void BuildLayout()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            AutoScroll = true,
            ColumnCount = 1,
            RowCount = 4,
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        var heading = new Label
        {
            AutoSize = true,
            Font = new Font(Font, FontStyle.Bold),
            Text = "Share AgentMon status with paired Macs",
            AccessibleName = "Relay summary",
            Margin = new Padding(0, 0, 0, 12),
        };
        root.Controls.Add(heading);

        var statusGroup = CreateGroup("Relay status");
        var statusGrid = CreateGrid();
        AddRow(statusGrid, "State", stateValue);
        AddRow(statusGrid, "Problem", errorValue);
        AddRow(statusGrid, "Sessions", sessionsValue);
        AddRow(statusGrid, "Last indexed", lastIndexedValue);
        AddRow(statusGrid, "Discovery", discoveryValue);
        startStopButton.Text = "&Start relay";
        startStopButton.AccessibleName = "Start or stop relay";
        AddFullWidthRow(statusGrid, startStopButton);
        statusGroup.Controls.Add(statusGrid);
        root.Controls.Add(statusGroup);

        var identityGroup = CreateGroup("Identity and pairing");
        var identityGrid = CreateGrid();
        displayNameTextBox.AccessibleName = "Computer display name";
        saveNameButton.Text = "&Save name";
        saveNameButton.AccessibleName = "Save computer display name";
        AddRowWithButton(identityGrid, "Computer name", displayNameTextBox, saveNameButton);

        urlsListBox.Height = 54;
        urlsListBox.IntegralHeight = false;
        urlsListBox.AccessibleName = "Listening URLs";
        copyUrlButton.Text = "Copy &URL";
        copyUrlButton.AccessibleName = "Copy selected listening URL";
        AddRowWithButton(identityGrid, "Listening URLs", urlsListBox, copyUrlButton);

        fingerprintTextBox.AccessibleName = "Certificate fingerprint";
        copyFingerprintButton.Text = "Copy &fingerprint";
        copyFingerprintButton.AccessibleName = "Copy certificate fingerprint";
        AddRowWithButton(identityGrid, "Fingerprint", fingerprintTextBox, copyFingerprintButton);

        tokenTextBox.AccessibleName = "Pairing token";
        tokenTextBox.UseSystemPasswordChar = true;
        revealTokenButton.Text = "&Reveal and copy token...";
        revealTokenButton.AccessibleName = "Reveal and copy pairing token";
        AddRowWithButton(identityGrid, "Pairing token", tokenTextBox, revealTokenButton);

        var rotationPanel = new FlowLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
        };
        rotateTokenButton.Text = "Rotate &token...";
        rotateTokenButton.AccessibleName = "Rotate pairing token";
        rotateCertificateButton.Text = "Rotate &certificate...";
        rotateCertificateButton.AccessibleName = "Rotate relay certificate";
        rotationPanel.Controls.Add(rotateTokenButton);
        rotationPanel.Controls.Add(rotateCertificateButton);
        AddFullWidthRow(identityGrid, rotationPanel);
        identityGroup.Controls.Add(identityGrid);
        root.Controls.Add(identityGroup);

        var windowsGroup = CreateGroup("Windows integration");
        var windowsGrid = CreateGrid();
        firewallValue.AccessibleName = "Private network firewall status";
        configureFirewallButton.Text = "Configure private &firewall...";
        configureFirewallButton.AccessibleName = "Configure private network firewall rule";
        AddRowWithButton(windowsGrid, "Firewall", firewallValue, configureFirewallButton);

        startupCheckBox.Text = "Start AgentMon Relay when I sign in";
        startupCheckBox.AccessibleName = "Start AgentMon Relay when signing in";
        AddFullWidthRow(windowsGrid, startupCheckBox);

        var footerPanel = new FlowLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            WrapContents = false,
        };
        var quitButton = new Button
        {
            AutoSize = true,
            Text = "&Quit",
            AccessibleName = "Quit AgentMon Relay",
        };
        var logsButton = new Button
        {
            AutoSize = true,
            Text = "Open &logs",
            AccessibleName = "Open relay log folder",
        };
        quitButton.Click += async (_, _) => await quitAsync();
        logsButton.Click += (_, _) => RunUiAction(UiOperation.OpenLogs, WindowsIntegration.OpenLogDirectory);
        footerPanel.Controls.Add(quitButton);
        footerPanel.Controls.Add(logsButton);
        AddFullWidthRow(windowsGrid, footerPanel);
        windowsGroup.Controls.Add(windowsGrid);
        root.Controls.Add(windowsGroup);

        Controls.Add(root);
        AcceptButton = saveNameButton;
    }

    private void WireEvents()
    {
        startStopButton.Click += async (_, _) => await RunControllerActionAsync(
            UiOperation.RelayStateChange,
            async () =>
            {
                if (IsRunningState(controller.GetView().State))
                {
                    await controller.StopAsync();
                }
                else
                {
                    await controller.StartAsync();
                }
            });

        saveNameButton.Click += async (_, _) =>
        {
            var name = displayNameTextBox.Text.Trim();
            if (name.Length == 0)
            {
                ShowInformation("Enter a computer name first.");
                displayNameTextBox.Focus();
                return;
            }

            await RunControllerActionAsync(UiOperation.DisplayNameUpdate, () => controller.SetDisplayNameAsync(name));
        };

        copyUrlButton.Click += (_, _) =>
        {
            if (urlsListBox.SelectedItem is string url)
            {
                CopyToClipboard(url, "listening URL");
            }
        };
        copyFingerprintButton.Click += (_, _) => CopyToClipboard(fingerprintTextBox.Text, "certificate fingerprint");
        revealTokenButton.Click += (_, _) => RevealAndCopyToken();
        rotateTokenButton.Click += async (_, _) => await RotateTokenAsync();
        rotateCertificateButton.Click += async (_, _) => await RotateCertificateAsync();
        configureFirewallButton.Click += async (_, _) => await ConfigureFirewallAsync();
        startupCheckBox.CheckedChanged += (_, _) => ChangeStartupSetting();
        refreshTimer.Tick += (_, _) => RefreshView();
        tokenTimer.Tick += (_, _) => HideToken();
        refreshTimer.Start();
    }

    private async Task RotateTokenAsync()
    {
        if (!ConfirmPairingChange(
                "Rotate pairing token?",
                "All paired Macs will stop connecting until their saved token is updated."))
        {
            return;
        }

        HideToken();
        await RunControllerActionAsync(UiOperation.TokenRotation, controller.RegenerateTokenAsync);
    }

    private async Task RotateCertificateAsync()
    {
        if (!ConfirmPairingChange(
                "Rotate relay certificate?",
                "All paired Macs will reject the relay until they are paired again with the new certificate fingerprint."))
        {
            return;
        }

        HideToken();
        await RunControllerActionAsync(UiOperation.CertificateRotation, controller.RegenerateCertificateAsync);
    }

    private void RevealAndCopyToken()
    {
        var result = MessageBox.Show(
            "The pairing token grants access to this relay. It will be shown for 30 seconds and copied to the clipboard only because you requested it.\n\nOther apps, clipboard history, and clipboard sync may be able to read it. Continue?",
            "Reveal pairing token",
            MessageBoxButtons.OKCancel,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);
        if (result != DialogResult.OK)
        {
            return;
        }

        try
        {
            var token = controller.RevealToken();
            Clipboard.SetText(token);
            tokenTextBox.UseSystemPasswordChar = false;
            tokenTextBox.Text = token;
            tokenTimer.Stop();
            tokenTimer.Interval = (int)TokenVisibilityDuration.TotalMilliseconds;
            tokenTimer.Start();
        }
        catch (Exception error)
        {
            LogFailure(UiOperation.TokenReveal, error);
            ShowFailure("The token could not be revealed or copied", error);
        }
    }

    private async Task ConfigureFirewallAsync()
    {
        var result = MessageBox.Show(
            "Windows will ask for administrator approval to create one inbound TCP rule for port 47831.\n\nThe rule is limited to this exact app, Private networks, and the local subnet. No Public-network rule will be created. Continue?",
            "Configure private-network firewall",
            MessageBoxButtons.OKCancel,
            MessageBoxIcon.Information,
            MessageBoxDefaultButton.Button2);
        if (result != DialogResult.OK)
        {
            return;
        }

        SetBusy(true);
        try
        {
            var configured = await WindowsIntegration.ConfigurePrivateFirewallRuleElevatedAsync();
            RefreshWindowsIntegration();
            if (!configured)
            {
                ShowInformation("Windows did not configure the firewall rule.");
            }
        }
        catch (Win32Exception error) when (error.NativeErrorCode == 1223)
        {
            ShowInformation("Firewall setup was canceled.");
        }
        catch (Exception error)
        {
            LogFailure(UiOperation.FirewallElevation, error);
            ShowFailure("The firewall rule could not be configured", error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void ChangeStartupSetting()
    {
        if (startupCheckBox.Tag is true)
        {
            return;
        }

        RunUiAction(
            UiOperation.StartupSetting,
            () => WindowsIntegration.SetStartupEnabled(startupCheckBox.Checked));
        RefreshWindowsIntegration();
    }

    private async Task RunControllerActionAsync(UiOperation operation, Func<Task> action)
    {
        if (busy)
        {
            return;
        }

        SetBusy(true);
        try
        {
            await action();
            RefreshView();
        }
        catch (Exception error)
        {
            LogFailure(operation, error);
            ShowFailure("AgentMon Relay could not complete that action", error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void RunUiAction(UiOperation operation, Action action)
    {
        try
        {
            action();
        }
        catch (Exception error)
        {
            LogFailure(operation, error);
            ShowFailure("AgentMon Relay could not complete that action", error);
        }
    }

    private void RefreshWindowsIntegration()
    {
        startupCheckBox.Tag = true;
        try
        {
            startupCheckBox.Checked = WindowsIntegration.IsStartupEnabled();
            startupAvailable = true;
            startupCheckBox.Enabled = !busy;
        }
        catch (Exception error)
        {
            LogFailure(UiOperation.StartupStatus, error);
            startupCheckBox.Checked = false;
            startupAvailable = false;
            startupCheckBox.Enabled = false;
        }
        finally
        {
            startupCheckBox.Tag = false;
        }

        var firewallStatus = WindowsIntegration.GetPrivateFirewallStatus();
        firewallValue.Text = firewallStatus switch
        {
            WindowsIntegration.FirewallStatus.Configured => "Configured for Private networks and local subnet",
            WindowsIntegration.FirewallStatus.NotConfigured => "Not configured",
            WindowsIntegration.FirewallStatus.UnsafeRulePresent => "Public-profile rule detected; not modified",
            _ => "Status unavailable",
        };
        firewallValue.ForeColor = firewallStatus == WindowsIntegration.FirewallStatus.Configured
            ? Color.DarkGreen
            : firewallStatus == WindowsIntegration.FirewallStatus.UnsafeRulePresent
                ? Color.Firebrick
                : SystemColors.ControlText;
        firewallCanConfigure = firewallStatus != WindowsIntegration.FirewallStatus.UnsafeRulePresent;
        configureFirewallButton.Enabled = !busy && firewallCanConfigure;
    }

    private void SetBusy(bool value)
    {
        busy = value;
        UseWaitCursor = value;
        startStopButton.Enabled = !value;
        saveNameButton.Enabled = !value;
        copyUrlButton.Enabled = !value && urlsListBox.SelectedItem is not null;
        copyFingerprintButton.Enabled = !value;
        revealTokenButton.Enabled = !value;
        rotateTokenButton.Enabled = !value;
        rotateCertificateButton.Enabled = !value;
        configureFirewallButton.Enabled = !value && firewallCanConfigure;
        startupCheckBox.Enabled = !value && startupAvailable;
    }

    private void CopyToClipboard(string value, string description)
    {
        if (string.IsNullOrEmpty(value))
        {
            return;
        }

        try
        {
            Clipboard.SetText(value);
        }
        catch (Exception error)
        {
            LogFailure(UiOperation.ClipboardCopy, error);
            ShowFailure($"The {description} could not be copied", error);
        }
    }

    private void HideToken()
    {
        tokenTimer.Stop();
        tokenTextBox.Clear();
        tokenTextBox.UseSystemPasswordChar = true;
    }

    private static bool ConfirmPairingChange(string title, string warning)
    {
        return MessageBox.Show(
            $"{warning}\n\nThis cannot be undone. Continue?",
            title,
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2) == DialogResult.Yes;
    }

    private static void LogFailure(UiOperation operation, Exception error)
    {
        switch (operation)
        {
            case UiOperation.CertificateRotation:
                RelayApplication.LogFailure("certificate rotation", error);
                break;
            case UiOperation.ClipboardCopy:
                RelayApplication.LogFailure("clipboard copy", error);
                break;
            case UiOperation.DisplayNameUpdate:
                RelayApplication.LogFailure("display name update", error);
                break;
            case UiOperation.FirewallElevation:
                RelayApplication.LogFailure("firewall elevation", error);
                break;
            case UiOperation.OpenLogs:
                RelayApplication.LogFailure("open logs", error);
                break;
            case UiOperation.RelayStateChange:
                RelayApplication.LogFailure("relay state change", error);
                break;
            case UiOperation.StartupSetting:
                RelayApplication.LogFailure("startup setting", error);
                break;
            case UiOperation.StartupStatus:
                RelayApplication.LogFailure("startup status", error);
                break;
            case UiOperation.TokenReveal:
                RelayApplication.LogFailure("token reveal", error);
                break;
            case UiOperation.TokenRotation:
                RelayApplication.LogFailure("token rotation", error);
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(operation), operation, null);
        }
    }

    private static void ShowFailure(string text, Exception error)
    {
        MessageBox.Show(
            $"{text} ({error.GetType().Name}).",
            "AgentMon Relay",
            MessageBoxButtons.OK,
            MessageBoxIcon.Error);
    }

    private static void ShowInformation(string text)
    {
        MessageBox.Show(
            text,
            "AgentMon Relay",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);
    }

    private static bool IsRunningState(string state)
    {
        return state.Equals("Running", StringComparison.OrdinalIgnoreCase) ||
               state.Equals("Waiting for private network", StringComparison.OrdinalIgnoreCase);
    }

    private static Color GetStateColor(string state)
    {
        if (state.Equals("Running", StringComparison.OrdinalIgnoreCase))
        {
            return Color.DarkGreen;
        }

        if (state.Equals("Error", StringComparison.OrdinalIgnoreCase))
        {
            return Color.Firebrick;
        }

        if (state.Equals("Waiting for private network", StringComparison.OrdinalIgnoreCase))
        {
            return Color.DarkOrange;
        }

        return SystemColors.ControlText;
    }

    private static GroupBox CreateGroup(string text)
    {
        return new GroupBox
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            Text = text,
            Padding = new Padding(12),
            Margin = new Padding(0, 0, 0, 12),
        };
    }

    private static TableLayoutPanel CreateGrid()
    {
        var grid = new TableLayoutPanel
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            ColumnCount = 3,
            Padding = new Padding(0),
        };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        return grid;
    }

    private static Label CreateValueLabel()
    {
        return new Label
        {
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            MaximumSize = new Size(480, 0),
        };
    }

    private static TextBox CreateReadOnlyTextBox()
    {
        return new TextBox
        {
            ReadOnly = true,
            Dock = DockStyle.Fill,
        };
    }

    private static void AddRow(TableLayoutPanel grid, string label, Control control)
    {
        var row = grid.RowCount++;
        grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        grid.Controls.Add(CreateFieldLabel(label), 0, row);
        grid.Controls.Add(control, 1, row);
        grid.SetColumnSpan(control, 2);
    }

    private static void AddRowWithButton(
        TableLayoutPanel grid,
        string label,
        Control control,
        Button button)
    {
        var row = grid.RowCount++;
        grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        control.Dock = DockStyle.Fill;
        button.AutoSize = true;
        button.Anchor = AnchorStyles.Top | AnchorStyles.Right;
        grid.Controls.Add(CreateFieldLabel(label), 0, row);
        grid.Controls.Add(control, 1, row);
        grid.Controls.Add(button, 2, row);
    }

    private static void AddFullWidthRow(TableLayoutPanel grid, Control control)
    {
        var row = grid.RowCount++;
        grid.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        control.Margin = new Padding(0, 8, 0, 0);
        grid.Controls.Add(control, 0, row);
        grid.SetColumnSpan(control, 3);
    }

    private static Label CreateFieldLabel(string text)
    {
        return new Label
        {
            AutoSize = true,
            Anchor = AnchorStyles.Top | AnchorStyles.Left,
            Text = $"{text}:",
            Margin = new Padding(0, 6, 8, 6),
        };
    }
}
