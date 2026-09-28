namespace HateVPN.Core;

public sealed record ConnectionEntry(string Key, string Name, string Description,
    string? SubscriptionUrl, string ProfileId, bool IsSelected);

public static class ConnectionCatalog
{
    public static IReadOnlyList<ConnectionEntry> Entries(ProfileData data)
    {
        var entries = new List<ConnectionEntry>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var profile in data.Profiles)
        {
            if (profile.SubscriptionUrl is not { } url)
            {
                entries.Add(new("profile:" + profile.Id, profile.Name, profile.IsInvitation ? "Приглашение · личный доступ" : profile.Endpoint,
                    null, profile.Id, profile.Id == data.SelectedId));
                continue;
            }
            if (!seen.Add(url)) continue;
            var members = data.Profiles.Where(p => p.SubscriptionUrl == url).ToList();
            var selected = members.FirstOrDefault(p => p.Id == data.SelectedId) ?? members[0];
            var host = Uri.TryCreate(url, UriKind.Absolute, out var uri) ? uri.Host : "серверы";
            entries.Add(new("subscription:" + url, "Подписка · " + host,
                $"{members.Count} {ServerWord(members.Count)} · {selected.Name}", url,
                selected.Id, members.Any(p => p.Id == data.SelectedId)));
        }
        return entries;
    }

    public static ProfileData MergeSubscription(ProfileData data, string url,
        IReadOnlyList<XrayNode> nodes, bool selectSubscription)
    {
        if (nodes.Count == 0) throw new ArgumentException("Subscription has no nodes.", nameof(nodes));
        var previous = data.Profiles.Where(p => p.SubscriptionUrl == url).ToList();
        var used = new HashSet<string>(StringComparer.Ordinal);
        var refreshed = new List<Profile>(nodes.Count);
        foreach (var node in nodes)
        {
            var match = previous.FirstOrDefault(p => !used.Contains(p.Id) && p.Config == node.Link)
                ?? previous.FirstOrDefault(p => !used.Contains(p.Id) && p.Name == node.Name && p.Endpoint == node.Endpoint);
            if (match is not null) used.Add(match.Id);
            refreshed.Add(new(match?.Id ?? Guid.NewGuid().ToString("D"), node.Name,
                node.Link, node.Endpoint, true, url));
        }
        var profiles = new List<Profile>(data.Profiles.Count - previous.Count + refreshed.Count);
        var inserted = false;
        foreach (var profile in data.Profiles)
        {
            if (profile.SubscriptionUrl != url) { profiles.Add(profile); continue; }
            if (!inserted) { profiles.AddRange(refreshed); inserted = true; }
        }
        if (!inserted) profiles.AddRange(refreshed);
        var selectedId = data.SelectedId;
        if (selectSubscription || previous.Any(p => p.Id == selectedId))
            selectedId = refreshed.FirstOrDefault(p => p.Id == selectedId)?.Id ?? refreshed[0].Id;
        return new ProfileData { Profiles = profiles, SelectedId = selectedId };
    }

    public static string ServerWord(int count) => count % 10 == 1 && count % 100 != 11 ? "сервер" :
        count % 10 is >= 2 and <= 4 && count % 100 is not (>= 12 and <= 14) ? "сервера" : "серверов";
}
