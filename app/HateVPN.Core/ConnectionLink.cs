namespace HateVPN.Core;

public enum ConnectionLinkKind { Subscription, Invitation, OneTimeInvitation }

public static class ConnectionLink
{
    public static ConnectionLinkKind Detect(string? text)
    {
        var value = text?.Trim() ?? "";
        if (value.StartsWith("hatevpn://invite/", StringComparison.OrdinalIgnoreCase))
            return ConnectionLinkKind.Invitation;
        if (value.StartsWith("hatevpn://claim/", StringComparison.OrdinalIgnoreCase))
            return ConnectionLinkKind.OneTimeInvitation;
        if (Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
            uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(uri.Host))
            return ConnectionLinkKind.Subscription;
        throw new FormatException("Вставьте HTTPS-ссылку подписки или ссылку приглашения HateVPN.");
    }
}
