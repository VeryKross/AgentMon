using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace AgentMon.Relay.Windows.Tests;

[TestClass]
public sealed class HttpsTests
{
    [TestMethod]
    public async Task Status_PinnedTlsAndAuthentication_ReturnsExactSnapshotWithinTwoSeconds()
    {
        await using var relay = await RunningRelay.CreateAsync();
        var stopwatch = Stopwatch.StartNew();
        using var response = await relay.Client.GetAsync("/v1/status");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        Assert.IsTrue(stopwatch.Elapsed < TimeSpan.FromSeconds(2));
        Assert.AreEqual("application/json", response.Content.Headers.ContentType!.MediaType);
        Assert.IsTrue(response.Headers.CacheControl!.NoStore);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.AreEqual(1, json.RootElement.GetProperty("protocolVersion").GetInt32());
        Assert.AreEqual(TestDirectory.Now, json.RootElement.GetProperty("generatedAt").GetDateTimeOffset());

        relay.Client.DefaultRequestHeaders.Authorization = null;
        using var missing = await relay.Client.GetAsync("/v1/status");
        Assert.AreEqual(HttpStatusCode.Unauthorized, missing.StatusCode);
        Assert.IsTrue(missing.Headers.CacheControl!.NoStore);
        relay.Client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", "invalid");
        using var invalid = await relay.Client.GetAsync("/v1/status");
        Assert.AreEqual(HttpStatusCode.Unauthorized, invalid.StatusCode);
    }

    [TestMethod]
    public async Task Status_UnknownRouteWrongMethodAndUnsupportedVersion_ReturnsProtocolCodes()
    {
        await using var relay = await RunningRelay.CreateAsync();
        using var unknown = await relay.Client.GetAsync("/v1/unknown");
        Assert.AreEqual(HttpStatusCode.NotFound, unknown.StatusCode);
        using var method = await relay.Client.PostAsync("/v1/status", null);
        Assert.AreEqual(HttpStatusCode.MethodNotAllowed, method.StatusCode);
        CollectionAssert.Contains(method.Content.Headers.Allow.ToArray(), "GET");
        using var version = await relay.Client.GetAsync("/v2/status");
        Assert.AreEqual(HttpStatusCode.UpgradeRequired, version.StatusCode);
        using var unknownVersionRoute = await relay.Client.GetAsync("/v2/unknown");
        Assert.AreEqual(HttpStatusCode.NotFound, unknownVersionRoute.StatusCode);
    }

    [TestMethod]
    public async Task Status_BurstyPolling_IsRateLimitedWithoutQueueing()
    {
        await using var relay = await RunningRelay.CreateAsync();
        var throttled = false;
        for (var index = 0; index < 60; index++)
        {
            using var response = await relay.Client.GetAsync("/v1/status");
            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                Assert.IsNotNull(response.Headers.RetryAfter);
                throttled = true;
                break;
            }
        }
        Assert.IsTrue(throttled);
    }

    [TestMethod]
    public async Task Status_IndexFailure_NeverReplacesOldGeneratedAtWithRequestTime()
    {
        await using var relay = await RunningRelay.CreateAsync();
        using var first = await relay.Client.GetAsync("/v1/status");
        var before = await first.Content.ReadAsStringAsync();
        using var second = await relay.Client.GetAsync("/v1/status");
        Assert.AreEqual(before, await second.Content.ReadAsStringAsync());
        Assert.IsFalse(before.Contains(relay.Token, StringComparison.Ordinal));
    }

    [TestMethod]
    public async Task Status_ExceptionIsSanitized_AndInitialFailureReturns500()
    {
        await using var relay = await RunningRelay.CreateAsync();
        relay.Snapshot = null;
        using var noSnapshot = await relay.Client.GetAsync("/v1/status");
        Assert.AreEqual(HttpStatusCode.InternalServerError, noSnapshot.StatusCode);
        relay.FailSnapshot = true;
        using var error = await relay.Client.GetAsync("/v1/status?SECRET_RAW_QUERY");
        Assert.AreEqual(HttpStatusCode.InternalServerError, error.StatusCode);
        Assert.IsTrue(error.Headers.CacheControl!.NoStore);
        Assert.AreEqual("", await error.Content.ReadAsStringAsync());
        var logs = File.ReadAllText(relay.Directory.FilePath("logs\\relay.log"));
        Assert.IsFalse(logs.Contains("SECRET_", StringComparison.Ordinal));
        Assert.IsFalse(logs.Contains(relay.Token, StringComparison.Ordinal));
    }

    [TestMethod]
    public async Task Status_ProfileBecomesPublic_ExistingConnectionFailsClosed()
    {
        await using var relay = await RunningRelay.CreateAsync();
        using var initial = await relay.Client.GetAsync("/v1/status");
        Assert.AreEqual(HttpStatusCode.OK, initial.StatusCode);
        relay.PrivateNetwork = false;
        await Assert.ThrowsAsync<HttpRequestException>(async () => await relay.Client.GetAsync("/v1/status"));
    }

    [TestMethod]
    public async Task Status_TokenRotation_RejectsOldPairingImmediately()
    {
        await using var relay = await RunningRelay.CreateAsync();
        relay.Token = ProtectedSettingsStore.NewToken();
        using var old = await relay.Client.GetAsync("/v1/status");
        Assert.AreEqual(HttpStatusCode.Unauthorized, old.StatusCode);
        relay.Client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", relay.Token);
        using var updated = await relay.Client.GetAsync("/v1/status");
        Assert.AreEqual(HttpStatusCode.OK, updated.StatusCode);
    }

    [TestMethod]
    public async Task Status_ChangedCertificatePin_FailsUntilRepaired()
    {
        await using var relay = await RunningRelay.CreateAsync();
        using var other = ProtectedSettingsStore.OpenCertificate(new RelaySettings(
            Guid.NewGuid().ToString(), "Test", relay.Token, ProtectedSettingsStore.NewCertificate()));
        using var wrongPinClient = relay.CreateClient(other);
        await Assert.ThrowsAsync<HttpRequestException>(async () => await wrongPinClient.GetAsync("/v1/status"));
        using var correctPinClient = relay.CreateClient(relay.Certificate);
        using var response = await correctPinClient.GetAsync("/v1/status");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
    }

    [TestMethod]
    public async Task Dispose_StopsHttpsAndReleasesPort()
    {
        await using var relay = await RunningRelay.CreateAsync();
        using var initial = await relay.Client.GetAsync("/v1/status");
        Assert.AreEqual(HttpStatusCode.OK, initial.StatusCode);
        var port = relay.Client.BaseAddress!.Port;
        await relay.StopAsync();
        await Assert.ThrowsAsync<HttpRequestException>(async () => await relay.Client.GetAsync("/v1/status"));
        using var listener = new System.Net.Sockets.TcpListener(IPAddress.Loopback, port);
        listener.Start();
        listener.Stop();
    }

    private sealed class RunningRelay : IAsyncDisposable
    {
        internal TestDirectory Directory { get; } = new();
        internal string Token { get; set; } = ProtectedSettingsStore.NewToken();
        internal bool PrivateNetwork { get; set; } = true;
        internal bool FailSnapshot { get; set; }
        internal RelaySnapshot? Snapshot { get; set; } = new(
            1, "test", TestDirectory.Now, TestDirectory.Host, []);
        internal X509Certificate2 Certificate { get; }
        internal HttpClient Client { get; private set; } = null!;
        private RelayServer? server;
        private Uri address = null!;

        private RunningRelay()
        {
            Certificate = ProtectedSettingsStore.OpenCertificate(new RelaySettings(
                Guid.NewGuid().ToString(), "Test", Token, ProtectedSettingsStore.NewCertificate()));
        }

        internal static async Task<RunningRelay> CreateAsync()
        {
            var fixture = new RunningRelay();
            try
            {
                fixture.server = new RelayServer([IPAddress.Loopback], 0, fixture.Certificate, () => fixture.Token,
                    () => fixture.FailSnapshot ? throw new InvalidOperationException("SECRET_EVENT SECRET_PATH") : fixture.Snapshot,
                    (local, remote) => fixture.PrivateNetwork && local is not null && remote is not null &&
                        IPAddress.IsLoopback(local) && IPAddress.IsLoopback(remote), fixture.Directory.Log);
                await fixture.server.StartAsync();
                fixture.address = new Uri(fixture.server.Urls.Single());
                fixture.Client = fixture.CreateClient(fixture.Certificate);
                return fixture;
            }
            catch
            {
                await fixture.DisposeAsync();
                throw;
            }
        }

        internal HttpClient CreateClient(X509Certificate2 pin)
        {
            var fingerprint = pin.GetCertHash(HashAlgorithmName.SHA256);
            var handler = new HttpClientHandler
            {
                UseProxy = false,
                ServerCertificateCustomValidationCallback = (_, certificate, _, _) =>
                    certificate is not null &&
                    CryptographicOperations.FixedTimeEquals(fingerprint, certificate.GetCertHash(HashAlgorithmName.SHA256))
            };
            var client = new HttpClient(handler) { BaseAddress = address, Timeout = TimeSpan.FromSeconds(5) };
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", Token);
            return client;
        }

        internal async Task StopAsync()
        {
            if (server is not null)
            {
                await server.DisposeAsync();
                server = null;
            }
        }

        public async ValueTask DisposeAsync()
        {
            Client?.Dispose();
            await StopAsync();
            Certificate.Dispose();
            Directory.Dispose();
        }
    }
}
