using System.Reflection;
using System.Drawing;
using System.Windows.Forms;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace AgentMon.Relay.Windows.Tests;

[TestClass]
public sealed class TrayUiTests
{
    [TestMethod]
    public Task NormalAndBackgroundLaunch_BothStartController()
        => RunStaAsync(async () =>
        {
            var normalController = new FakeRelayController();
            using (var normal = new RelayTrayContext(normalController, startInBackground: false, queryWindowsIntegration: false))
            {
                Assert.AreEqual(1, normalController.StartCount);
                await normal.RequestQuitAsync();
            }

            var backgroundController = new FakeRelayController();
            using (var background = new RelayTrayContext(backgroundController, startInBackground: true, queryWindowsIntegration: false))
            {
                Assert.AreEqual(1, backgroundController.StartCount);
                await background.RequestQuitAsync();
            }
        });

    [TestMethod]
    public Task ErrorState_ShowsErrorAndOffersStop()
        => RunStaAsync(() =>
        {
            var controller = new FakeRelayController
            {
                View = CreateView("Error", error: "Safe stale-indexing status."),
            };
            using var form = new RelayForm(controller, () => Task.CompletedTask, queryWindowsIntegration: false);

            Assert.AreEqual("Error", form.StateText);
            Assert.AreEqual("Safe stale-indexing status.", form.ErrorText);
            Assert.AreEqual("&Stop relay", form.StartStopText);
            form.Show();
            form.StartStopButton.PerformClick();
            Assert.AreEqual(1, controller.StopCount);
            return Task.CompletedTask;
        });

    [TestMethod]
    public Task RunningState_StillShowsNonNullError()
        => RunStaAsync(() =>
        {
            var controller = new FakeRelayController
            {
                View = CreateView("Running", error: "Indexing failed; serving the last successful snapshot."),
            };
            using var form = new RelayForm(controller, () => Task.CompletedTask, queryWindowsIntegration: false);

            Assert.AreEqual("Running", form.StateText);
            Assert.AreEqual("Indexing failed; serving the last successful snapshot.", form.ErrorText);
            return Task.CompletedTask;
        });

    [TestMethod]
    public Task DirtyDisplayName_IsPreservedUntilReverted()
        => RunStaAsync(() =>
        {
            var controller = new FakeRelayController { View = CreateView("Running", displayName: "Original") };
            using var form = new RelayForm(controller, () => Task.CompletedTask, queryWindowsIntegration: false);
            form.Show();

            form.DisplayNameEditor.Text = "Unsaved edit";
            controller.View = CreateView("Running", displayName: "Refreshed elsewhere");
            form.RefreshView();
            Assert.AreEqual("Unsaved edit", form.DisplayNameEditor.Text);

            form.RevertNameButton.PerformClick();
            Assert.AreEqual("Refreshed elsewhere", form.DisplayNameEditor.Text);

            form.DisplayNameEditor.Text = "Saved name";
            form.SaveNameButton.PerformClick();
            Assert.AreEqual("Saved name", controller.View.DisplayName);
            controller.View = CreateView("Running", displayName: "Updated after save");
            form.RefreshView();
            Assert.AreEqual("Updated after save", form.DisplayNameEditor.Text);
            return Task.CompletedTask;
        });

    [TestMethod]
    public Task StateChanges_UpdateTrayAndWindowIcons()
        => RunStaAsync(async () =>
        {
            var controller = new FakeRelayController { View = CreateView("Stopped") };
            using var context = new RelayTrayContext(controller, startInBackground: true, queryWindowsIntegration: false);

            Assert.AreEqual(SystemIcons.Application.Handle, context.CurrentTrayIcon.Handle);
            controller.View = CreateView("Running");
            context.ManagementForm.RefreshView();
            Assert.AreEqual(SystemIcons.Information.Handle, context.CurrentTrayIcon.Handle);
            Assert.AreEqual(SystemIcons.Information.Handle, context.ManagementForm.Icon?.Handle);
            controller.View = CreateView("Error", error: "Safe error.");
            context.ManagementForm.RefreshView();
            Assert.AreEqual(SystemIcons.Error.Handle, context.CurrentTrayIcon.Handle);
            Assert.AreEqual(SystemIcons.Error.Handle, context.ManagementForm.Icon?.Handle);

            await context.RequestQuitAsync();
        });

    [TestMethod]
    public Task ApplicationExitClosing_RequestsCleanShutdown()
        => RunStaAsync(() =>
        {
            var shutdownRequests = 0;
            using var form = new RelayForm(
                new FakeRelayController(),
                () =>
                {
                    shutdownRequests++;
                    return Task.CompletedTask;
                },
                queryWindowsIntegration: false);
            var closing = typeof(RelayForm).GetMethod(
                "OnFormClosing",
                BindingFlags.Instance | BindingFlags.NonPublic)
                ?? throw new AssertFailedException("RelayForm.OnFormClosing was not found.");

            closing.Invoke(form, [new FormClosingEventArgs(CloseReason.ApplicationExitCall, cancel: false)]);

            Assert.AreEqual(1, shutdownRequests);
            return Task.CompletedTask;
        });

    [TestMethod]
    public Task FormLayout_RendersWithoutClippedControlsAtOneHundredAndOneHundredFiftyPercent()
        => RunStaAsync(() =>
        {
            using var form = new RelayForm(
                new FakeRelayController { View = CreateView("Running") },
                () => Task.CompletedTask,
                queryWindowsIntegration: false);
            form.Show();
            Application.DoEvents();

            AssertLayoutFits(form);
            CaptureLayout(form, "tray-ui-100.png");
            form.Scale(new SizeF(1.5f, 1.5f));
            form.PerformLayout();
            AssertLayoutFits(form);
            CaptureLayout(form, "tray-ui-150.png");
            return Task.CompletedTask;
        });

    private static void AssertLayoutFits(Control root)
    {
        root.PerformLayout();
        foreach (Control child in root.Controls)
        {
            Assert.IsTrue(child.Width >= child.MinimumSize.Width, $"{child.Name} width is clipped.");
            Assert.IsTrue(child.Height >= child.MinimumSize.Height, $"{child.Name} height is clipped.");
            if (child is Button or CheckBox)
            {
                Assert.IsTrue(
                    child.Width >= child.PreferredSize.Width,
                    $"The '{child.Text}' control text is clipped.");
            }

            AssertLayoutFits(child);
        }
    }

    private static void CaptureLayout(Form form, string fileName)
    {
        using var capture = new Bitmap(form.ClientSize.Width, form.ClientSize.Height);
        form.DrawToBitmap(capture, form.ClientRectangle);
        Assert.AreEqual(form.ClientSize, capture.Size);
        var captureDirectory = Environment.GetEnvironmentVariable("AGENTMON_UI_CAPTURE_DIR");
        if (!string.IsNullOrWhiteSpace(captureDirectory))
        {
            Directory.CreateDirectory(captureDirectory);
            capture.Save(Path.Combine(captureDirectory, fileName));
        }
    }

    private static RelayView CreateView(
        string state,
        string displayName = "Test PC",
        string? error = null)
    {
        return new RelayView(
            state,
            displayName,
            ["https://192.168.1.10:47831"],
            "aa:bb:cc",
            2,
            DateTimeOffset.UtcNow,
            error,
            "Advertising");
    }

    private static Task RunStaAsync(Func<Task> action)
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(
            () =>
            {
                try
                {
                    action().GetAwaiter().GetResult();
                    completion.SetResult();
                }
                catch (Exception error)
                {
                    completion.SetException(error);
                }
            });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return completion.Task;
    }

    private sealed class FakeRelayController : IRelayController
    {
        internal RelayView View { get; set; } = CreateView("Stopped");
        internal int StartCount { get; private set; }
        internal int StopCount { get; private set; }
        internal int DisposeCount { get; private set; }

        public RelayView GetView() => View;

        public Task StartAsync()
        {
            StartCount++;
            return Task.CompletedTask;
        }

        public Task StopAsync()
        {
            StopCount++;
            return Task.CompletedTask;
        }

        public Task SetDisplayNameAsync(string name)
        {
            View = View with { DisplayName = name };
            return Task.CompletedTask;
        }

        public Task RegenerateTokenAsync() => Task.CompletedTask;

        public Task RegenerateCertificateAsync() => Task.CompletedTask;

        public string RevealToken() => "test-token";

        public ValueTask DisposeAsync()
        {
            DisposeCount++;
            return ValueTask.CompletedTask;
        }
    }
}
