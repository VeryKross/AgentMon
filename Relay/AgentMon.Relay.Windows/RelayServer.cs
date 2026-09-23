using System.Net;
using System.Net.Http.Headers;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Connections;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace AgentMon.Relay.Windows;

internal sealed class RelayServer : IAsyncDisposable
{
    private readonly WebApplication application;
    private readonly FixedWindowRateLimiter limiter = new(new FixedWindowRateLimiterOptions
    {
        PermitLimit = 20, Window = TimeSpan.FromSeconds(1), QueueLimit = 0,
        AutoReplenishment = true
    });

    internal RelayServer(
        IReadOnlyList<IPAddress> addresses, int port, X509Certificate2 certificate,
        Func<string> token, Func<RelaySnapshot?> snapshot, Func<IPAddress?, IPAddress?, bool> allowed,
        SafeLog log)
    {
        if (addresses.Count == 0)
            throw new ArgumentException("At least one explicit interface is required.", nameof(addresses));
        var builder = WebApplication.CreateSlimBuilder(new WebApplicationOptions { Args = [] });
        // Disable framework request/exception logging: it can include raw URLs, headers and paths.
        builder.Logging.ClearProviders();
        builder.Configuration.Sources.Clear();
        builder.WebHost.ConfigureKestrel(options =>
        {
            options.AddServerHeader = false;
            options.Limits.MaxConcurrentConnections = 32;
            options.Limits.MaxRequestBodySize = 0;
            options.Limits.MaxRequestHeadersTotalSize = 8192;
            options.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(5);
            options.Limits.KeepAliveTimeout = TimeSpan.FromSeconds(15);
            foreach (var address in addresses)
                options.Listen(address, port, listen =>
                {
                    listen.Protocols = HttpProtocols.Http1;
                    listen.Use(next => async connection =>
                    {
                        try
                        {
                            var local = (connection.LocalEndPoint as IPEndPoint)?.Address;
                            var remote = (connection.RemoteEndPoint as IPEndPoint)?.Address;
                            if (!allowed(local, remote))
                            {
                                connection.Abort();
                                return;
                            }
                            await next(connection);
                        }
                        catch (Exception ex)
                        {
                            log.Write(LogEvent.RequestFailed, ex);
                            connection.Abort();
                        }
                    });
                    listen.UseHttps(https =>
                    {
                        https.ServerCertificate = certificate;
                        https.SslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13;
                        https.HandshakeTimeout = TimeSpan.FromSeconds(5);
                    });
                });
        });
        application = builder.Build();
        application.Run(async context =>
        {
            context.Response.Headers.CacheControl = "no-store";
            try
            {
                if (!allowed(context.Connection.LocalIpAddress, context.Connection.RemoteIpAddress))
                {
                    context.Abort();
                    return;
                }
                using var lease = limiter.AttemptAcquire();
                if (!lease.IsAcquired)
                {
                    context.Response.Headers.RetryAfter = "1";
                    context.Response.StatusCode = StatusCodes.Status429TooManyRequests;
                    return;
                }
                var path = context.Request.Path.Value ?? "";
                if (!path.StartsWith("/v", StringComparison.Ordinal))
                {
                    context.Response.StatusCode = StatusCodes.Status404NotFound;
                    return;
                }
                if (!IsAuthorized(context.Request.Headers.Authorization.ToString(), token()))
                {
                    context.Response.Headers.WWWAuthenticate = "Bearer";
                    context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                    return;
                }
                if (path != "/v1/status")
                {
                    var segments = path.Split('/');
                    context.Response.StatusCode = segments.Length == 3 && segments[2] == "status" &&
                        segments[1].Length > 1 && int.TryParse(segments[1].AsSpan(1), out var version) && version != 1
                        ? StatusCodes.Status426UpgradeRequired : StatusCodes.Status404NotFound;
                    return;
                }
                if (!HttpMethods.IsGet(context.Request.Method))
                {
                    context.Response.Headers.Allow = "GET";
                    context.Response.StatusCode = StatusCodes.Status405MethodNotAllowed;
                    return;
                }
                var current = snapshot();
                if (current is null)
                {
                    context.Response.StatusCode = StatusCodes.Status500InternalServerError;
                    return;
                }
                if (current.ProtocolVersion != RelaySnapshot.Version)
                {
                    context.Response.StatusCode = StatusCodes.Status426UpgradeRequired;
                    return;
                }
                await context.Response.WriteAsJsonAsync(current, RelaySnapshot.JsonOptions, context.RequestAborted);
            }
            catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
            {
                // The caller disconnected; there is no response left to send.
            }
            catch (Exception ex)
            {
                // This is the external failure boundary. Never send exception messages or event contents.
                log.Write(LogEvent.RequestFailed, ex);
                if (!context.Response.HasStarted)
                    context.Response.StatusCode = StatusCodes.Status500InternalServerError;
                else
                    context.Abort();
            }
        });
    }

    internal IReadOnlyList<string> Urls => application.Urls.ToArray();
    internal Task StartAsync(CancellationToken cancellationToken = default) => application.StartAsync(cancellationToken);

    internal static bool IsAuthorized(string header, string expected)
    {
        if (header.Length > 512 || !AuthenticationHeaderValue.TryParse(header, out var value) ||
            !string.Equals(value.Scheme, "Bearer", StringComparison.OrdinalIgnoreCase) || value.Parameter is null)
            return false;
        var suppliedHash = SHA256.HashData(Encoding.UTF8.GetBytes(value.Parameter));
        var expectedHash = SHA256.HashData(Encoding.UTF8.GetBytes(expected));
        return CryptographicOperations.FixedTimeEquals(suppliedHash, expectedHash);
    }

    public async ValueTask DisposeAsync()
    {
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            await application.StopAsync(timeout.Token).ConfigureAwait(false);
        }
        finally
        {
            await application.DisposeAsync().ConfigureAwait(false);
            limiter.Dispose();
        }
    }
}
