# v16.1.2: v16.1.1 + an explicit confirmation before a port-443-only final
#        fallback list overrides -PortMode Non443.
# v16.1.1: the proven v16 server-testing engine + existing Windows SSTP VPN
#        profile verification/maintenance with hardened removal rules.
#      - New -VerifyExisting switch: test every existing Windows SSTP VPN
#        profile (per-user and AllUser phonebooks) with TCP, a real SSTP dial,
#        public-IP route verification, tunnel latency, and a download test.
#      - New -PruneFirst switch: run the same verification at the start of a
#        normal run, then continue testing new servers.
#      - New -ReportOnly switch: dry-run; show what would be removed but never
#        delete anything.
#      - New -ListExisting switch: only list existing Windows VPN profiles and
#        exit without dialing or changing anything.
#      - New -ExistingRemovalMode Balanced|Conservative: Balanced also marks
#        confirmed TCP/dial failures for removal; Conservative only marks
#        profiles that connect but do not route through the VPN.
#      - IMPORTANT: this build keeps the v16 speed-test engine (Cloudflare URL,
#        partial-download samples accepted). A sample with real bytes over
#        HTTP 2xx counts even when the transfer is cut short; slow but working
#        free SSTP servers are not rejected for an incomplete transfer.
#      - Profiles are removed only after a summary table and an explicit YES.
#        Local RAS errors, credential rejections, split tunneling, duplicate
#        names, and uncertain states are always kept.
# v16: v15 FINAL + VPN Gate as an additional (supplementary) server source.
#      - New -ExtraSourceUrl parameter (default: the VPN Gate mirror page
#        http://v-dot-pn-ams2.opengw.net:34637/en/).
#      - The VPN Gate page is parsed from its MS-SSTP column, so only servers
#        that actually publish an "SSTP Hostname" (with its real port) are used.
#      - Both sources are merged and de-duplicated by host:port. When the same
#        endpoint appears twice, the entry with the lower published PING wins.
#      - Every snapshot and result row now carries a Source column.
#      - Extra-source failures are warnings, not fatal; the primary list still
#        works. Use -NoExtraSource to disable the supplementary source, or
#        -ExtraSourceOnly to use only the supplementary source(s).
#      - Last-resort fallback: when the clipboard, the primary source, and the
#        supplementary source(s) all yield nothing, a plain-text SSTP host list
#        is read from -FinalFallbackUrl (Delta-Kronecker Vpn-Gate by default).
#        Use -FinalFallbackOnly to test that source alone. The default list
#        currently publishes only port-443 endpoints; when -PortMode Non443
#        would discard all of them, the script asks before overriding the
#        filter to All for that last-resort run.
# v15 FINAL: faster, measurement-based server selection.
#      - Shortlist: sort all candidates by the PING column already published by
#        the source list (ascending, unknown last), then apply -MaxServers.
#        No extra preflight pass over all candidates is performed.
#      - Final ranking: measure real VPN tunnel latency (ICMP with TCP fallback)
#        and real download speed on the shortlisted servers only.
#      - Default -RankMode Balanced = 70% normalized download +
#        30% normalized measured latency. Use Speed or Latency to change this.
#      - Default -SpeedSamples 1 keeps the run short; 2-5 is optional.
#      - Parses the source UPTIME column and uses it as a tie-breaker.
#      - Results CSV stays sorted by DownloadMbps descending and includes the
#        measured latency and selection-score columns.
#      - At the end, adds the top -AddBestVpnCount (default 3) ranked servers
#        to Windows as SSTP VPN profiles. Existing profiles/addresses are
#        skipped, and username/password are stored in the RAS phone-book entry.
# Typical run:
#   .\Test-FreeSstpServers_v16_1.ps1 -UseClipboard -PortMode Non443 -MaxServers 10
# v14.3: Parses the PING column already published by the source list and sorts
#        all candidate servers by it (ascending, unknown last) before
#        PriorityServer and MaxServers, so a limited test run uses the fastest.
# v14.2 FINAL: v14.1 + selectable port filtering (All / 443 / Non443).
#      - Preserves SSTP endpoint parsing for FQDN, IPv4, bracketed IPv6, and non-443 ports.
#      - Requires PowerShell 7+ (the timed process runner uses ProcessStartInfo.ArgumentList).
#      - Compares public IPs within the same address family (IPv4 with IPv4, IPv6 with IPv6).
#      - Removes an unsupported VpnClient credential cmdlet and avoids false credential-success claims.
#      - Makes -ContinueAfterLocalRas633 control whether later VPN dials continue after cleanup.
#      - Verifies the saved profile and RememberCredential flag before reporting it added.
#      - Adds -PortMode All|443|Non443; filtering is applied before PriorityServer and MaxServers.
# For full help run: Get-Help .\Test-FreeSstpServers_v16_1.ps1 -Full
#                or: .\Test-FreeSstpServers_v16_1.ps1 -Help

<#
.SYNOPSIS
    Tests free SSTP VPN servers, saves the best working ones as Windows VPN
    profiles, and verifies/cleans up existing Windows SSTP VPN profiles.

.DESCRIPTION
    Test-FreeSstpServers_v16_1.ps1 keeps the proven v16 server-testing engine
    and adds existing-profile verification with safer removal rules and the
    v16 speed-test behaviour.

    Existing-profile maintenance:
      -VerifyExisting   Test every existing Windows SSTP profile and, after a
                        summary and an explicit YES, remove rejected profiles.
      -PruneFirst       Run the same verification before a normal server run.
      -ReportOnly       Dry-run for the verification phase; never deletes.
      -ListExisting     List existing Windows VPN profiles and exit; no dial.

    New-server testing (the proven v16 logic): builds a shortlist from the PING
    column that the source list already publishes, tests only that shortlist,
    and ranks servers using measurements taken during this run.

    Workflow:
      0. Optional: with -ListExisting, show existing profiles and exit. With
         -VerifyExisting or -PruneFirst, verify/clean existing SSTP profiles
         first (standalone mode exits; -PruneFirst continues).
      1. Obtain the server list from the primary source (web page, clipboard,
         saved HTML, or a local CSV snapshot from a previous run) and, by default,
         also from the supplementary VPN Gate source (-ExtraSourceUrl). Merge both
         lists and remove duplicate host:port endpoints. If every earlier source
         is empty, try the final fallback plain host list (-FinalFallbackUrl); a
         port-443-only fallback with -PortMode Non443 asks before the filter is
         overridden to All.
      2. Filter by -PortMode, sort by source PING ascending (unknown last; longer
         published uptime wins a tie), then optionally move -PriorityServer first
         and keep only the first -MaxServers entries.
      3. For each shortlisted server: TCP probe, temporary SSTP profile, VPN dial,
         route/public-IP verification, tunnel latency measurement (ICMP first with
         TCP fallback), and one or more HTTPS download samples.
      4. Rank confirmed servers with -RankMode (default Balanced = 70% normalized
         download speed + 30% normalized measured latency).
      5. Save a full results CSV sorted by DownloadMbps descending.
      6. Add the top -AddBestVpnCount confirmed servers to Windows as SSTP VPN
         profiles named "<country> - <host>" (non-443 ports keep a -p<port>
         suffix), skip entries whose name or host:port already exists, and store
         -Username/-Password (default vpn/vpn) in the per-user RAS phone book.

    Requirements:
      - Windows 10/11
      - PowerShell 7 or later (pwsh.exe)
      - Elevated session (Run as Administrator)
      - Built-in rasdial.exe and curl.exe
      - VpnClient PowerShell module (inbox Windows component)

.PARAMETER Url
    URL of the primary server-list page.
    Default: https://ipspeed.info/free-sstp.php

.PARAMETER ExtraSourceUrl
    One or more supplementary server-list URLs. The default is the VPN Gate
    mirror http://v-dot-pn-ams2.opengw.net:34637/en/ . VPN Gate rows are read from
    the MS-SSTP column ("SSTP Hostname"), so the advertised hostname and port are
    used exactly as published. VPN Gate requires its .opengw.net DDNS hostname
    (never the bare IP) and uses the same public vpn/vpn credentials, which are
    this script's defaults. Sources are merged with the primary list and
    de-duplicated by host:port. A failing extra source only produces a warning.
    Use -NoExtraSource to disable supplementary sources.

.PARAMETER NoExtraSource
    Do not fetch or merge -ExtraSourceUrl or -FinalFallbackUrl. Useful for a
    primary-only run or when the machine has no access to the supplementary site.

.PARAMETER ExtraSourceOnly
    Use only the URLs supplied in -ExtraSourceUrl (default: the VPN Gate mirror)
    and ignore the primary -Url page, clipboard, saved HTML, and CSV snapshot.
    This is the simplest way to test the supplementary source alone:
      .\Test-FreeSstpServers_v16_1.ps1 -ExtraSourceOnly -PortMode Non443 -MaxServers 30
    Cannot be combined with -NoExtraSource.

.PARAMETER FinalFallbackUrl
    Last-resort plain-text host list, consulted only when the clipboard, the
    primary -Url, and every -ExtraSourceUrl produced no servers.
    Default: https://raw.githubusercontent.com/Delta-Kronecker/Vpn-Gate/refs/heads/main/sstp_hosts.txt
    The file format is one "host[:port]" entry per line, with optional '#'
    comments and "=== Country (CC) - N servers ===" section headers. If the raw
    URL is unreachable, the readable-text mirror is tried. Disabled by
    -NoExtraSource and ignored in -ExtraSourceOnly mode.
    Use -FinalFallbackOnly to test this source alone.
    The default list currently publishes only port-443 endpoints. If
    -PortMode Non443 would discard all of them, the script asks before
    overriding the filter to All for that last-resort run.

.PARAMETER FinalFallbackOnly
    Use only -FinalFallbackUrl: skip the clipboard, the primary -Url, every
    -ExtraSourceUrl, saved HTML, and CSV snapshots. Intended for validating the
    plain-text host list by itself:
      .\Test-FreeSstpServers_v16_1.ps1 -FinalFallbackOnly -PortMode All -MaxServers 30
    Cannot be combined with -ExtraSourceOnly, -NoExtraSource, -ServerListCsv,
    or -HtmlFile. The port filter still applies, so use -PortMode All to test
    every entry regardless of port. If -PortMode Non443 would discard the
    entire port-443-only list, the script asks before overriding it to All.

.PARAMETER ConnectTimeoutSec
    Maximum seconds to wait for one SSTP VPN dial. Range 10-300. Default 150.

.PARAMETER SpeedTimeoutSec
    Maximum seconds allowed for each download sample. Range 1-120. Default 12.

.PARAMETER SpeedSamples
    Number of download samples per server. Range 1-5. Default 1.
    The median sample is used. More samples improve stability but increase runtime.

.PARAMETER SpeedDownloadBytes
    Number of bytes requested per download sample.
    Range 1,000,000-100,000,000. Default 10,000,000 bytes.

.PARAMETER SpeedTestUrl
    Download URL template. When it contains {0}, that token is replaced with
    -SpeedDownloadBytes. Default: https://speed.cloudflare.com/__down?bytes={0}

.PARAMETER LatencyTestHost
    Host probed through the VPN tunnel for the measured latency. Default 1.1.1.1.

.PARAMETER LatencyTestPort
    TCP port used for the latency TCP fallback. Range 1-65535. Default 443.

.PARAMETER LatencyTimeoutMs
    Timeout for one latency probe, in milliseconds. Range 250-10000. Default 2000.

.PARAMETER LatencySamples
    Number of latency probes per server. Range 1-5. Default 1.
    The median sample is used.

.PARAMETER RankMode
    Final ranking formula:
      Balanced - 70% normalized download speed + 30% normalized latency (default)
      Speed    - download speed only
      Latency  - measured latency only

.PARAMETER MaxServers
    Test only the first N servers after the PING sort. Range 0-10000.
    Default 0, which means all servers. Use 10 for a short run.

.PARAMETER PortMode
    Port filter, applied before sorting and -MaxServers:
      All    - every server (default)
      443    - only servers on port 443
      Non443 - only servers on ports other than 443
    When the final fallback source is the only source and every entry uses
    port 443, the script asks before overriding Non443 to All for that run.

.PARAMETER TcpTimeoutMs
    TCP pre-check timeout in milliseconds. Range 250-10000. Default 1800.

.PARAMETER RasRecoveryDelaySec
    Seconds to wait during RAS cleanup between attempts. Range 1-30. Default 4.

.PARAMETER Ras633Retries
    Number of automatic retries after a local RAS 633 error. Range 0-3. Default 1.

.PARAMETER Username
    VPN username stored in newly created profiles. Default vpn.

.PARAMETER Password
    VPN password stored in newly created profiles. Default vpn.

.PARAMETER OutputCsv
    Path for the results CSV. Default: sstp_test_results_<timestamp>.csv next to
    this script. The file is sorted by DownloadMbps descending; rows without a
    download value are placed last.

.PARAMETER HtmlFile
    Path to a saved HTML copy of the source page, for situations where automatic
    retrieval is blocked (for example, a Cloudflare challenge).

.PARAMETER ServerListCsv
    Path to a server-list CSV snapshot written by a previous run. When supplied,
    the page is not downloaded and the clipboard is not read.

.PARAMETER PriorityServer
    host[:port] of a server to move to the first position after the PING sort.
    Useful for calibration with a known-good server. If the address is not found,
    a warning is shown and the PING-sorted order is kept.

.PARAMETER AddBestVpnCount
    Number of top confirmed servers to add to Windows VPN at the end.
    Range 0-20. Default 3; 0 disables profile creation. Only servers whose tunnel
    and internet download were verified are added. New profiles are named
    "<country> - <host>" (plus -p<port> for non-443 endpoints). Existing profiles
    with the same name or the same host:port are skipped. New profiles keep
    -Username/-Password.

.PARAMETER UseClipboard
    Read the server list from text copied from the browser instead of downloading
    the page. On the page, wait for the table, then press Ctrl+A and Ctrl+C.
    If the clipboard is empty, unreadable, or holds no recognizable server rows,
    the primary -Url is fetched next. The supplementary -ExtraSourceUrl source(s)
    are always merged afterwards, and if everything is still empty the
    -FinalFallbackUrl host list is tried last.

.PARAMETER ListOnly
    Retrieve, filter, sort, and save the server-list snapshot, then exit without
    connecting to any VPN or changing Windows profiles. The saved CSV can be reused
    later with -ServerListCsv. PowerShell 7 and an Administrator session are still
    required.

.PARAMETER TrySstpAfterTcpTimeout
    When the TCP pre-check times out (rather than being actively refused), still
    attempt the real SSTP connection. By default, a TCP timeout skips the server.

.PARAMETER ContinueAfterLocalRas633
    Continue dialing later servers after a repeated local RAS 633 error. By
    default, the run stops after the failed profile is cleaned up.

.PARAMETER VerifyExisting
    Standalone existing-profile verification. Every Windows SSTP VPN profile
    from the per-user and AllUser phonebooks is tested with TCP, a real SSTP
    dial, public-IP route verification, tunnel latency, and an internet download
    test. Accepted profiles are kept untouched. Rejected profiles are removed
    only after a summary table and an explicit YES confirmation. After the
    verification, the script exits without fetching a server list.
    Combine with -ReportOnly for a dry run.

.PARAMETER PruneFirst
    Run the same existing-profile verification at the very start of a normal
    server-test run, then continue fetching/testing new servers. Removal still
    requires the summary table and an explicit YES.

.PARAMETER ReportOnly
    Dry-run for -VerifyExisting or -PruneFirst. Rejected profiles are shown but
    never removed. Requires -VerifyExisting or -PruneFirst.

.PARAMETER ListExisting
    List existing Windows VPN profiles (name, scope, server address, tunnel type,
    connection status, split tunneling, duplicate-name flag) and exit without
    dialing or changing anything. Useful for a quick inventory.

.PARAMETER ExistingRemovalMode
    Balanced (default): profiles with a confirmed TCP failure after several
    attempts, or a confirmed remote dial failure after retries, are marked for
    removal. Conservative: only profiles that connect but do not route through
    the VPN are marked for removal; TCP/dial failures are kept and reported.
    In both modes, local RAS errors, credential rejections, split tunneling,
    duplicate names, and uncertain states are always kept.

.PARAMETER ExistingTcpAttempts
    Number of TCP probes per existing profile before a TCP failure is considered
    confirmed. Range 1-5. Default 3.

.PARAMETER ExistingTcpRetryDelaySec
    Seconds between TCP probes for an existing profile. Range 0-10. Default 1.

.PARAMETER TransientDialRetryDelaySec
    Seconds to wait before retrying an existing-profile dial after RAS
    619/628/629/631 (the remote terminated the connection). Range 0-60.
    Default 15.

.PARAMETER Help
    Show this help text and exit.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -ListExisting

    Show every existing Windows VPN profile without dialing or changing anything.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -VerifyExisting -ReportOnly

    Test every existing Windows SSTP profile and show what would be removed,
    but never delete anything. This is the recommended first run.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -VerifyExisting

    Test existing SSTP profiles; after the summary, type YES to remove the
    rejected ones. Press Enter to keep all of them.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -PruneFirst -UseClipboard -PortMode Non443 -MaxServers 10

    Clean up dead existing profiles first (with confirmation), then run the
    normal v16 server test and add the best new profiles.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -UseClipboard -PortMode Non443 -MaxServers 10

    Typical run: parse a copied list, merge the VPN Gate supplementary source,
    keep non-443 servers, test the 10 lowest-PING candidates, and add the top 3
    verified servers to Windows VPN.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -UseClipboard -NoExtraSource -PortMode Non443 -MaxServers 10

    Same run, but use only the clipboard/primary list and skip the VPN Gate source.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -ExtraSourceUrl 'http://v-dot-pn-ams2.opengw.net:34637/en/' -ListOnly

    Fetch the primary list plus the specified supplementary VPN Gate mirror, merge
    and de-duplicate the servers, save the snapshot, and exit without VPN tests.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -ExtraSourceOnly -PortMode Non443 -MaxServers 30 -AddBestVpnCount 3

    Use only the supplementary VPN Gate source: do not fetch ipspeed.info, do not
    read the clipboard, and do not load an HTML file or CSV snapshot. Test the 30
    lowest-PING non-443 servers and add the top 3 verified profiles.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -FinalFallbackOnly -PortMode All -MaxServers 30 -AddBestVpnCount 3

    Use only the -FinalFallbackUrl plain-text list (Delta-Kronecker sstp_hosts.txt
    by default): skip the clipboard, ipspeed.info, and every supplementary source.
    -PortMode All tests every entry regardless of port. To fetch and inspect the
    list without any VPN connection test, add -ListOnly.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -ServerListCsv .\sstp_server_list_20261029_051549.csv -MaxServers 5 -AddBestVpnCount 0

    Re-test 5 servers from an existing snapshot and do not create VPN profiles.
    A CSV snapshot is used as-is; no web source is fetched.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -ServerListCsv .\sstp_server_list_20261031_060042.csv -PortMode Non443 -MaxServers 30 -AddBestVpnCount 3

    Reuse a list saved by -ListOnly: the saved servers are filtered by port,
    sorted by their published PING, and tested normally without downloading the
    source page again.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -UseClipboard -ListOnly

    Only fetch, parse, merge, sort, and save the server list; no VPN connections or
    Windows profile changes.

.EXAMPLE
    .\Test-FreeSstpServers_v16_1.ps1 -UseClipboard -PortMode Non443 -MaxServers 10 -RankMode Speed -SpeedSamples 3 -AddBestVpnCount 5

    Longer run: three download samples per server, rank by speed only, and add up
    to five verified profiles.

.NOTES
    Version  : v16.1.2
    Requires : Windows 10/11, PowerShell 7+, Administrator
    The results CSV stays sorted by DownloadMbps descending even when -RankMode is
    Balanced or Latency; the console table and Windows-profile selection use
    SelectionScore.
    Source column: identifies where the row came from (for example ipspeed.info,
    VPN Gate, clipboard, or local HTML). Duplicate host:port endpoints are merged.
    For detailed help: Get-Help .\Test-FreeSstpServers_v16_1.ps1 -Full
#>
[CmdletBinding()]
param(
    [string]$Url = 'https://ipspeed.info/free-sstp.php',
    [string[]]$ExtraSourceUrl = @('http://v-dot-pn-ams2.opengw.net:34637/en/'),
    [switch]$NoExtraSource,
    [switch]$ExtraSourceOnly,
    [switch]$FinalFallbackOnly,
    [string]$FinalFallbackUrl = 'https://raw.githubusercontent.com/Delta-Kronecker/Vpn-Gate/refs/heads/main/sstp_hosts.txt',
    [ValidateRange(10, 300)] [int]$ConnectTimeoutSec = 150,
    [ValidateRange(1, 120)] [int]$SpeedTimeoutSec = 12,
    [ValidateRange(1, 5)] [int]$SpeedSamples = 1,
    [ValidateRange(1000000, 100000000)] [int]$SpeedDownloadBytes = 10000000,
    [string]$SpeedTestUrl = 'https://speed.cloudflare.com/__down?bytes={0}',
    [string]$LatencyTestHost = '1.1.1.1',
    [ValidateRange(1, 65535)] [int]$LatencyTestPort = 443,
    [ValidateRange(250, 10000)] [int]$LatencyTimeoutMs = 2000,
    [ValidateRange(1, 5)] [int]$LatencySamples = 1,
    [ValidateSet('Speed', 'Balanced', 'Latency')] [string]$RankMode = 'Balanced',
    [ValidateRange(0, 10000)] [int]$MaxServers = 0,
    [Alias('PortFilter')] [ValidateSet('All', '443', 'Non443')] [string]$PortMode = 'All',
    [ValidateRange(250, 10000)] [int]$TcpTimeoutMs = 1800,
    [ValidateRange(1, 30)] [int]$RasRecoveryDelaySec = 4,
    [ValidateRange(0, 3)] [int]$Ras633Retries = 1,
    [string]$Username = 'vpn',
    [string]$Password = 'vpn',
    [string]$OutputCsv = '',
    [string]$HtmlFile = '',
    [string]$ServerListCsv = '',
    [string]$PriorityServer = '',
    [ValidateRange(0, 20)] [int]$AddBestVpnCount = 3,
    [switch]$UseClipboard,
    [switch]$ListOnly,
    [switch]$TrySstpAfterTcpTimeout,
    [switch]$ContinueAfterLocalRas633,
    [switch]$VerifyExisting,
    [switch]$PruneFirst,
    [switch]$ReportOnly,
    [switch]$ListExisting,
    [ValidateSet('Balanced', 'Conservative')] [string]$ExistingRemovalMode = 'Balanced',
    [ValidateRange(1, 5)] [int]$ExistingTcpAttempts = 3,
    [ValidateRange(0, 10)] [int]$ExistingTcpRetryDelaySec = 1,
    [ValidateRange(0, 60)] [int]$TransientDialRetryDelaySec = 15,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# -Help prints the comment-based help and exits before the Administrator check,
# so users can read all options without changing any VPN configuration.
if ($Help) {
    Get-Help -Name $PSCommandPath -Full | Out-Host
    return
}

if ($ExtraSourceOnly -and $NoExtraSource) {
    throw '-ExtraSourceOnly cannot be combined with -NoExtraSource.'
}
if ($ExtraSourceOnly -and -not [string]::IsNullOrWhiteSpace($ServerListCsv)) {
    throw '-ExtraSourceOnly cannot be combined with -ServerListCsv. Use -ServerListCsv alone to reuse a saved snapshot.'
}
if ($FinalFallbackOnly) {
    if ($ExtraSourceOnly -or $NoExtraSource) {
        throw '-FinalFallbackOnly cannot be combined with -ExtraSourceOnly or -NoExtraSource.'
    }
    if (-not [string]::IsNullOrWhiteSpace($ServerListCsv) -or
        -not [string]::IsNullOrWhiteSpace($HtmlFile)) {
        throw '-FinalFallbackOnly cannot be combined with -ServerListCsv or -HtmlFile.'
    }
    if ([string]::IsNullOrWhiteSpace($FinalFallbackUrl)) {
        throw '-FinalFallbackOnly requires a non-empty -FinalFallbackUrl value.'
    }
}
if ($VerifyExisting -and $PruneFirst) {
    throw '-VerifyExisting and -PruneFirst cannot be combined. Use -VerifyExisting for a standalone cleanup run or -PruneFirst before a normal run.'
}
if ($ReportOnly -and -not ($VerifyExisting -or $PruneFirst)) {
    throw '-ReportOnly only affects existing-profile verification; combine it with -VerifyExisting or -PruneFirst.'
}
if (($VerifyExisting -or $PruneFirst) -and ($ExtraSourceOnly -or $FinalFallbackOnly -or $ListOnly -or $ListExisting)) {
    throw '-VerifyExisting and -PruneFirst cannot be combined with -ExtraSourceOnly, -FinalFallbackOnly, -ListOnly, or -ListExisting.'
}
if ($ListExisting -and ($VerifyExisting -or $PruneFirst -or $ListOnly -or $ExtraSourceOnly -or $FinalFallbackOnly)) {
    throw '-ListExisting is a standalone inventory command; do not combine it with other modes.'
}
if ($ListExisting -and $ReportOnly) {
    throw '-ListExisting does not delete anything; -ReportOnly is not needed.'
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ClipboardText {
    # First use PowerShell's built-in clipboard cmdlet. This path worked on
    # PowerShell 7.6.6 in previous runs and avoids a System.Windows.Forms
    # dependency on machines where the Windows Desktop runtime is absent.
    $directError = ''
    try {
        $text = [string](Get-Clipboard -Raw -ErrorAction Stop)
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return $text
        }
        $directError = 'Get-Clipboard returned empty text.'
    }
    catch {
        $directError = $_.Exception.GetBaseException().Message
    }

    # Fallback for PowerShell hosts where the built-in cmdlet cannot retrieve
    # plain text. Access WinForms clipboard only on a dedicated STA thread.
    if (-not ('SstpClipboardHelper' -as [type])) {
        $csCode = @'
using System;
using System.Threading;
using System.Windows.Forms;

public static class SstpClipboardHelper
{
    public static string GetText(int timeoutMs)
    {
        string result = null;
        Exception error = null;
        Thread t = new Thread(delegate()
        {
            try { result = Clipboard.GetText(); }
            catch (Exception ex) { error = ex; }
        });
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
        if (!t.Join(timeoutMs))
        {
            throw new TimeoutException("Clipboard read timed out after " + timeoutMs + " ms.");
        }
        if (error != null) { throw error; }
        return result ?? string.Empty;
    }
}
'@
        try {
            Add-Type -TypeDefinition $csCode -ReferencedAssemblies 'System.Windows.Forms' -ErrorAction Stop
        }
        catch {
            throw ("Could not read clipboard with Get-Clipboard (" + $directError + ") or load the STA fallback: " +
                $_.Exception.GetBaseException().Message +
                ". Use the HTML file option (-HtmlFile or 'H' in the menu) instead.")
        }
    }

    try {
        $text = [string][SstpClipboardHelper]::GetText(5000)
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return $text
        }
        throw 'The STA clipboard fallback returned empty text.'
    }
    catch {
        throw ("Could not read the clipboard with Get-Clipboard (" + $directError + ") or the STA fallback (" +
            $_.Exception.GetBaseException().Message +
            "). Use the HTML file option (-HtmlFile or 'H' in the menu) instead.")
    }
}

function Test-SstpHostName {
    param([string]$HostName)
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }
    $h = $HostName.Trim().TrimEnd('.')
    if ($h.StartsWith('[') -and $h.EndsWith(']')) {
        $h = $h.Substring(1, $h.Length - 2)
    }
    if ($h.Length -lt 1 -or $h.Length -gt 253) { return $false }

    # IPv4 literal
    if ($h -match '^(?:\d{1,3}\.){3}\d{1,3}$') {
        foreach ($octet in $h.Split('.')) {
            if ([int]$octet -lt 0 -or [int]$octet -gt 255) { return $false }
        }
        return $true
    }

    # IPv6 literal
    $ip = $null
    if ([System.Net.IPAddress]::TryParse($h, [ref]$ip) -and
        $ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        return $true
    }

    # FQDN
    return ($h -match '^(?i)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$')
}

function Format-SstpServerAddress {
    param([string]$HostName, [int]$Port)
    $isIPv6 = ($HostName -match ':')
    if ($isIPv6) {
        if ($Port -eq 443) { return "[$HostName]" }
        return "[$HostName]:$Port"
    }
    if ($Port -eq 443) { return $HostName }
    return "$HostName`:$Port"
}

function Parse-SstpServerAddress {
    param([string]$Text)
    # Returns a canonical parsed form, or $null when the text is not a
    # recognizable SSTP server endpoint. Accepted forms:
    #   example.com          -> fqdn, port 443, no explicit port
    #   example.com:1909     -> fqdn, port 1909, explicit port
    #   1.2.3.4              -> IPv4, port 443
    #   1.2.3.4:1909         -> IPv4, port 1909
    #   [2001:db8::1]        -> IPv6, port 443
    #   [2001:db8::1]:1909   -> IPv6, port 1909
    #   2001:db8::1          -> IPv6, port 443 (bracketless IPv6 is allowed
    #                           only when no port is appended, because host:port
    #                           is ambiguous for IPv6)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $t = $Text.Trim()

    # [ipv6] or [ipv6]:port
    if ($t -match '^\[(?<h>[0-9a-fA-F:.]+)\](?::(?<p>\d{1,5}))?$') {
        $h = $Matches['h']
        $p = if ($Matches['p']) { [int]$Matches['p'] } else { 443 }
        $hasPort = [bool]$Matches['p']
        if (-not (Test-SstpHostName $h)) { return $null }
        $isIPv6 = $h -match ':'
        if (-not $isIPv6) { return $null }
        if ($p -lt 1 -or $p -gt 65535) { return $null }
        return [pscustomobject]@{
            Host     = $h
            Port     = $p
            HasPort  = $hasPort
            IsIPv6   = $true
            Server   = (Format-SstpServerAddress -HostName $h -Port $p)
        }
    }

    # host:port (a single colon, so not IPv6)
    if ($t -match '^(?<h>[^:\s]+):(?<p>\d{1,5})$') {
        $h = $Matches['h'].Trim().TrimEnd('.')
        $p = [int]$Matches['p']
        if (-not (Test-SstpHostName $h)) { return $null }
        if ($p -lt 1 -or $p -gt 65535) { return $null }
        return [pscustomobject]@{
            Host     = $h
            Port     = $p
            HasPort  = $true
            IsIPv6   = $false
            Server   = (Format-SstpServerAddress -HostName $h -Port $p)
        }
    }

    # bare host: fqdn, ipv4, or bracketless ipv6 (no explicit port)
    $h = $t.TrimEnd('.')
    if ($h.StartsWith('[') -and $h.EndsWith(']')) {
        $h = $h.Substring(1, $h.Length - 2)
    }
    if (-not (Test-SstpHostName $h)) { return $null }
    $isV6 = $h -match ':'
    return [pscustomobject]@{
        Host     = $h
        Port     = 443
        HasPort  = $false
        IsIPv6   = $isV6
        Server   = (Format-SstpServerAddress -HostName $h -Port 443)
    }
}

function Convert-HtmlCellToText {
    param([string]$Html)
    $value = [regex]::Replace($Html, '(?is)<br\s*/?>', ' ')
    $value = [regex]::Replace($value, '(?is)<[^>]+>', ' ')
    $value = [System.Net.WebUtility]::HtmlDecode($value)
    return ([regex]::Replace($value, '\s+', ' ')).Trim()
}

function Convert-PingTextToMs {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    # The source table publishes values such as "36 ms". A dash means the
    # source did not provide a PING value, so it is treated as unknown.
    $match = [regex]::Match($Text, '(?i)(?<!\d)(?<ms>\d{1,5}(?:\.\d{1,2})?)\s*ms(?![\p{L}\d])')
    if (-not $match.Success) { return $null }

    $value = 0.0
    if ([double]::TryParse(
            $match.Groups['ms'].Value,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$value)) {
        return $value
    }
    return $null
}

function Convert-UptimeTextToMinutes {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $t = ($Text -replace '\s+', ' ').Trim().ToLowerInvariant()
    $uptimeMatches = [regex]::Matches(
        $t,
        '(?<n>\d+(?:\.\d+)?)\s*(?<unit>months?|days?|hours?|hrs?|minutes?|mins?|d|h|m)\b')
    if ($uptimeMatches.Count -eq 0) { return $null }

    $total = 0.0
    foreach ($match in $uptimeMatches) {
        $amount = 0.0
        if (-not [double]::TryParse(
                $match.Groups['n'].Value,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$amount)) {
            continue
        }

        $unit = $match.Groups['unit'].Value
        if ($unit -match '^(?:month|months)$') { $total += $amount * 43200 }
        elseif ($unit -match '^(?:day|days|d)$') { $total += $amount * 1440 }
        elseif ($unit -match '^(?:hour|hours|hr|hrs|h)$') { $total += $amount * 60 }
        elseif ($unit -match '^(?:minute|minutes|min|mins|m)$') { $total += $amount }
    }

    return [math]::Round($total, 2)
}

function Get-UptimeTextFromLine {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $pattern = '(?i)\d+(?:\.\d+)?\s*(?:months?|days?|hours?|hrs?|minutes?|mins?|d|h|m)\b(?:' +
        '\s+\d+(?:\.\d+)?\s*(?:months?|days?|hours?|hrs?|minutes?|mins?|d|h|m)\b)*'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return '' }
    return (($match.Value -replace '\s+', ' ').Trim())
}

function Get-MedianValue {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }

    $ordered = @($Values | Sort-Object)
    $middle = [int][math]::Floor($ordered.Count / 2)
    if ($ordered.Count % 2 -eq 1) {
        return [math]::Round([double]$ordered[$middle], 2)
    }
    return [math]::Round((([double]$ordered[$middle - 1] + [double]$ordered[$middle]) / 2), 2)
}

function Convert-ServerListContent {
    param(
        [string]$Content,
        [string]$SourceName = 'ipspeed.info'
    )

    if ([string]::IsNullOrWhiteSpace($Content)) { return @() }

    # Matches a bracketed IPv6 (with optional :port) OR a domain name (with
    # optional :port). Unbracketed IPv6 is intentionally not matched here so
    # that a bare "a:b" in cell text is not misread as an IPv6 address.
    $serverPattern = '(?i)(?<server>\[[0-9a-fA-F:.]+\](?::\d{1,5})?|(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}|(?:\d{1,3}\.){3}\d{1,3})(?::\d{1,5})?)'

    $servers = [System.Collections.Generic.List[object]]::new()

    $rows = [regex]::Matches($Content, '(?is)<tr\b[^>]*>(.*?)</tr>')
    foreach ($row in $rows) {
        $cells = [regex]::Matches($row.Groups[1].Value, '(?is)<td\b[^>]*>(.*?)</td>')
        if ($cells.Count -lt 3) { continue }

        $country = Convert-HtmlCellToText $cells[1].Groups[1].Value
        $hostCell = Convert-HtmlCellToText $cells[2].Groups[1].Value
        $match = [regex]::Match($hostCell, $serverPattern)
        if (-not $match.Success) { continue }

        $serverText = $match.Groups['server'].Value.Trim().TrimEnd('.')
        $parsed = Parse-SstpServerAddress -Text $serverText
        if (-not $parsed) { continue }

        # The source table has columns like: # | LOCATION | HOSTNAME | UPTIME | PING.
        # Scan the cells after HOSTNAME so an extra/missing column does not
        # prevent UPTIME or PING from being found.
        $uptimeText = ''
        $pingMs = $null
        for ($c = 3; $c -lt $cells.Count; $c++) {
            $cellText = Convert-HtmlCellToText $cells[$c].Groups[1].Value
            if ([string]::IsNullOrWhiteSpace($uptimeText)) {
                $candidateUptime = Get-UptimeTextFromLine $cellText
                if (-not [string]::IsNullOrWhiteSpace($candidateUptime)) {
                    $uptimeText = $candidateUptime
                }
            }
            if ($null -eq $pingMs) {
                $candidatePing = Convert-PingTextToMs $cellText
                if ($null -ne $candidatePing) { $pingMs = $candidatePing }
            }
        }
        $uptimeMinutes = Convert-UptimeTextToMinutes $uptimeText

        $servers.Add([pscustomobject]@{
            Country       = $country
            Source        = $SourceName
            Server        = $parsed.Server
            Host          = $parsed.Host
            Port          = $parsed.Port
            PingMs        = $pingMs
            UptimeText    = $uptimeText
            UptimeMinutes = $uptimeMinutes
        })
    }

    if ($servers.Count -eq 0) {
        foreach ($line in ($Content -split "`r?`n")) {
            if ($line -notmatch '^\s*\|?\s*\d{1,3}(?:\.|\s*\||\s+)') { continue }
            $match = [regex]::Match($line, $serverPattern)
            if (-not $match.Success) { continue }

            $beforeHost = $line.Substring(0, $match.Index)
            $country = [regex]::Replace($beforeHost, '(?is)<[^>]+>', ' ')
            $country = [regex]::Replace($country, '^\s*\|?\s*\d{1,3}\.?\s*', '')
            $country = $country.Trim().Trim('|').Trim()
            if ([string]::IsNullOrWhiteSpace($country) -or $country -match '^(?i:LOCATION|COUNTRY|---+)$') { continue }

            $serverText = $match.Groups['server'].Value.Trim().TrimEnd('.')
            $parsed = Parse-SstpServerAddress -Text $serverText
            if (-not $parsed) { continue }

            # In browser-copied plain text, the remainder of the row is
            # "<uptime> <ping>" (for example "2 days    36 ms"). A dash means
            # that the source has no PING value for this server.
            $afterHost = $line.Substring($match.Index + $match.Length)
            $pingMs = Convert-PingTextToMs $afterHost
            $uptimeText = Get-UptimeTextFromLine $afterHost
            $uptimeMinutes = Convert-UptimeTextToMinutes $uptimeText

            $servers.Add([pscustomobject]@{
                Country       = $country
                Source        = $SourceName
                Server        = $parsed.Server
                Host          = $parsed.Host
                Port          = $parsed.Port
                PingMs        = $pingMs
                UptimeText    = $uptimeText
                UptimeMinutes = $uptimeMinutes
            })
        }
    }

    $seen = @{}
    return @($servers | Where-Object {
        $key = ([string]$_.Server).ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $true } else { $false }
    })
}

function Convert-VpnGateServerListContent {
    param(
        [string]$Content,
        [string]$SourceName = 'VPN Gate'
    )

    if ([string]::IsNullOrWhiteSpace($Content)) { return @() }

    $servers = [System.Collections.Generic.List[object]]::new()
    $seen = @{}

    # VPN Gate publishes the real SSTP endpoint in its MS-SSTP column as
    # "SSTP Hostname : host[:port]". Only rows that contain this text are
    # SSTP-capable, so rows without it (for example UDP-only servers) are
    # deliberately skipped instead of being tested on a guessed port.
    $rows = [regex]::Matches($Content, '(?is)<tr\b[^>]*>(.*?)</tr>')
    foreach ($row in $rows) {
        $rowHtml = $row.Groups[1].Value
        if ($rowHtml -notmatch '(?i)SSTP\s+Hostname') { continue }

        $cells = [regex]::Matches($rowHtml, '(?is)<td\b[^>]*>(.*?)</td>')
        if ($cells.Count -lt 3) { continue }

        $country = Convert-HtmlCellToText $cells[0].Groups[1].Value
        $country = ($country -replace '\s+', ' ').Trim()

        $sstpText = ''
        for ($c = 0; $c -lt $cells.Count; $c++) {
            $cellText = Convert-HtmlCellToText $cells[$c].Groups[1].Value
            if ($cellText -match '(?i)SSTP\s+Hostname') {
                $sstpText = $cellText
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace($sstpText)) { continue }

        $endpointMatch = [regex]::Match(
            $sstpText,
            '(?i)SSTP\s+Hostname\s*:?\s*(?<server>[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?(?::\d{1,5})?)')
        if (-not $endpointMatch.Success) { continue }

        $parsed = Parse-SstpServerAddress -Text $endpointMatch.Groups['server'].Value.Trim().TrimEnd('.')
        if (-not $parsed) { continue }

        # Scan the whole row for the published PING and UPTIME values. VPN Gate
        # formats them as "Ping: 9 ms" and "6 days" inside separate cells.
        $pingMs = $null
        $uptimeText = ''
        for ($c = 1; $c -lt $cells.Count; $c++) {
            $cellText = Convert-HtmlCellToText $cells[$c].Groups[1].Value
            if ($null -eq $pingMs) {
                $candidatePing = Convert-PingTextToMs $cellText
                if ($null -ne $candidatePing) { $pingMs = $candidatePing }
            }
            if ([string]::IsNullOrWhiteSpace($uptimeText)) {
                $candidateUptime = Get-UptimeTextFromLine $cellText
                if (-not [string]::IsNullOrWhiteSpace($candidateUptime)) {
                    $uptimeText = $candidateUptime
                }
            }
        }
        $uptimeMinutes = Convert-UptimeTextToMinutes $uptimeText

        $key = ([string]$parsed.Server).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $servers.Add([pscustomobject]@{
            Country       = $country
            Source        = $SourceName
            Server        = $parsed.Server
            Host          = $parsed.Host
            Port          = $parsed.Port
            PingMs        = $pingMs
            UptimeText    = $uptimeText
            UptimeMinutes = $uptimeMinutes
        })
    }

    # Plain-text fallback for a browser-copied VPN Gate page. Each
    # SSTP-capable server contributes one "SSTP Hostname : host[:port]" line.
    # Country, PING, and uptime are not reliably preserved in copied text, but
    # the endpoints themselves are still testable.
    if ($servers.Count -eq 0) {
        foreach ($line in ($Content -split "`r?`n")) {
            $endpointMatch = [regex]::Match(
                $line,
                '(?i)SSTP\s+Hostname\s*:?\s*(?<server>[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?(?::\d{1,5})?)')
            if (-not $endpointMatch.Success) { continue }

            $parsed = Parse-SstpServerAddress -Text $endpointMatch.Groups['server'].Value.Trim().TrimEnd('.')
            if (-not $parsed) { continue }

            $key = ([string]$parsed.Server).ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true

            # When a copied row keeps its values on one line, recover the
            # published PING/UPTIME too; otherwise they stay unknown and the
            # endpoint is sorted after rows with a known PING.
            $pingMs = Convert-PingTextToMs $line
            $uptimeText = Get-UptimeTextFromLine $line
            $uptimeMinutes = Convert-UptimeTextToMinutes $uptimeText

            # Best-effort country recovery: in a copied VPN Gate row the
            # country precedes the DDNS hostname or the IPv4 address.
            $country = ''
            $countryMatch = [regex]::Match(
                $line,
                '^\s*(?<country>[A-Za-z][A-Za-z .()''-]{1,50}?)\s+(?=(?:[A-Za-z0-9-]+\.)+opengw\.net|\d{1,3}\.)')
            if ($countryMatch.Success) {
                $country = $countryMatch.Groups['country'].Value.Trim()
            }

            $servers.Add([pscustomobject]@{
                Country       = $country
                Source        = $SourceName
                Server        = $parsed.Server
                Host          = $parsed.Host
                Port          = $parsed.Port
                PingMs        = $pingMs
                UptimeText    = $uptimeText
                UptimeMinutes = $uptimeMinutes
            })
        }
    }

    return @($servers)
}

function Convert-AnyServerListContent {
    param(
        [string]$Content,
        [string]$DefaultSource = 'ipspeed.info'
    )

    if ([string]::IsNullOrWhiteSpace($Content)) { return @() }

    $vpnGate = @(Convert-VpnGateServerListContent -Content $Content)
    $standard = @(Convert-ServerListContent -Content $Content -SourceName $DefaultSource)

    # A VPN Gate page can also look like a generic table, so prefer the
    # dedicated SSTP-column parser when it found at least as many endpoints.
    if ($vpnGate.Count -gt 0 -and $vpnGate.Count -ge $standard.Count) { return $vpnGate }
    if ($standard.Count -gt 0) { return $standard }
    return $vpnGate
}

function Convert-PlainSstpHostListContent {
    param(
        [string]$Content,
        [string]$SourceName = 'plain host list'
    )

    # Parses a newline-separated host list such as the Delta-Kronecker
    # sstp_hosts.txt file: comment lines start with '#', optional country
    # section headers look like "=== Japan (JP) - 195 servers ===", and every
    # other non-empty line is a bare "host" or "host:port" entry.
    if ([string]::IsNullOrWhiteSpace($Content)) { return @() }

    $servers = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    $country = ''

    foreach ($rawLine in ($Content -split "`r?`n")) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('#')) { continue }

        $section = [regex]::Match($line, '^=+\s*(?<country>.+?)\s*=+$')
        if ($section.Success) {
            $country = $section.Groups['country'].Value
            $country = [regex]::Replace($country, '\s*\([A-Za-z]{2}\)\s*-\s*\d+\s+servers?\s*$', '')
            $country = ($country -replace '\s+', ' ').Trim()
            continue
        }

        # Remove trailing comments and tolerate sstp:// prefixes and trailing
        # punctuation, but skip anything that still looks like prose.
        $candidate = ($line -replace '\s+#.*$', '').Trim().Trim(',', ';')
        $candidate = [regex]::Replace($candidate, '^(?i)sstp://', '')
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($candidate -match '\s') { continue }

        $parsed = Parse-SstpServerAddress -Text $candidate
        if (-not $parsed) { continue }

        $key = ([string]$parsed.Server).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $servers.Add([pscustomobject]@{
            Country       = $country
            Source        = $SourceName
            Server        = $parsed.Server
            Host          = $parsed.Host
            Port          = $parsed.Port
            PingMs        = $null
            UptimeText    = ''
            UptimeMinutes = $null
        })
    }

    return @($servers)
}

function Merge-SstpServerLists {
    param([object[]]$Lists)

    # Merge by canonical host:port. When both sources publish the same
    # endpoint, keep the entry with the lower source PING; fill any missing
    # country/uptime fields from the other entry.
    $merged = [ordered]@{}
    foreach ($srv in @($Lists)) {
        if ($null -eq $srv) { continue }
        $key = ([string]$srv.Server).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($key)) { continue }

        if (-not $merged.Contains($key)) {
            $merged[$key] = $srv
            continue
        }

        $existing = $merged[$key]
        $useNew = $false
        if ($null -eq $existing.PingMs -and $null -ne $srv.PingMs) {
            $useNew = $true
        } elseif ($null -ne $existing.PingMs -and $null -ne $srv.PingMs -and
            [double]$srv.PingMs -lt [double]$existing.PingMs) {
            $useNew = $true
        }

        if ($useNew) {
            if ([string]::IsNullOrWhiteSpace([string]$srv.Country)) {
                $srv.Country = [string]$existing.Country
            }
            if ([string]::IsNullOrWhiteSpace([string]$srv.UptimeText)) {
                $srv.UptimeText = [string]$existing.UptimeText
                if ($null -eq $srv.UptimeMinutes) { $srv.UptimeMinutes = $existing.UptimeMinutes }
            }
            $merged[$key] = $srv
        } else {
            if ([string]::IsNullOrWhiteSpace([string]$existing.Country) -and
                -not [string]::IsNullOrWhiteSpace([string]$srv.Country)) {
                $existing.Country = [string]$srv.Country
            }
            if ([string]::IsNullOrWhiteSpace([string]$existing.UptimeText) -and
                -not [string]::IsNullOrWhiteSpace([string]$srv.UptimeText)) {
                $existing.UptimeText = [string]$srv.UptimeText
                $existing.UptimeMinutes = $srv.UptimeMinutes
            }
        }
    }

    return @($merged.Values)
}

function Get-SstpServers {
    param(
        [string]$PageUrl,
        [string]$LocalHtmlFile
    )

    if (-not [string]::IsNullOrWhiteSpace($LocalHtmlFile)) {
        if (-not (Test-Path -LiteralPath $LocalHtmlFile -PathType Leaf)) {
            throw "HTML file not found: $LocalHtmlFile"
        }
        Write-Host "Reading server list from local HTML file: $LocalHtmlFile" -ForegroundColor Cyan
        $localContent = Get-Content -LiteralPath $LocalHtmlFile -Raw -Encoding UTF8
        $localServers = @(Convert-AnyServerListContent -Content $localContent -DefaultSource 'local HTML')
        if ($localServers.Count -eq 0) {
            throw 'No server rows were found in the saved HTML file. In Edge, use Save page as > Webpage, HTML only, after the server table has fully appeared.'
        }
        return $localServers
    }

    $hostPart = $PageUrl -replace '^https?://', ''
    $sources = @(
        [pscustomobject]@{ Url = $PageUrl; Name = 'original site' },
        [pscustomobject]@{ Url = "https://r.jina.ai/http://$hostPart"; Name = 'readable-text fallback (HTTP)' },
        [pscustomobject]@{ Url = "https://r.jina.ai/https://$hostPart"; Name = 'readable-text fallback (HTTPS)' }
    )

    foreach ($source in $sources) {
        Write-Host "Trying server list source: $($source.Name) ..." -ForegroundColor Cyan
        try {
            $response = Invoke-WebRequest -Uri $source.Url -TimeoutSec 30 `
                -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128.0 Safari/537.36' } `
                -SkipHttpErrorCheck -ErrorAction Stop
            $content = [string]$response.Content
            $defaultSource = ''
            try { $defaultSource = ([uri]$PageUrl).Host } catch { $defaultSource = $hostPart }
            $found = @(Convert-AnyServerListContent -Content $content -DefaultSource $defaultSource)
            if ($found.Count -gt 0) {
                $formats = (@($found | ForEach-Object { [string]$_.Source } | Sort-Object -Unique) -join ', ')
                Write-Host ("Retrieved {0} server(s) from {1} [{2}]." -f $found.Count, $source.Name, $formats) -ForegroundColor Green
                return $found
            }
            if ($content -match '(?is)Just a moment|Enable JavaScript and cookies to continue|cf_chl_|challenge-platform') {
                Write-Warning "$($source.Name) returned a Cloudflare browser challenge, not the server list."
            } elseif ([int]$response.StatusCode -ge 400) {
                Write-Warning "$($source.Name) returned HTTP $($response.StatusCode)."
            } else {
                Write-Warning "$($source.Name) did not contain recognizable server rows."
            }
        }
        catch {
            $shortError = $_.Exception.GetBaseException().Message
            if ($shortError.Length -gt 180) { $shortError = $shortError.Substring(0, 180) }
            Write-Warning "$($source.Name) could not be read: $shortError"
        }
    }

    throw @"
Automatic retrieval did not produce recognizable server rows. The website may handle normal browser requests differently from PowerShell HTTP requests.
Recommended fallback: open $PageUrl in Microsoft Edge, wait until the real server table is visible, click the page, press Ctrl+A then Ctrl+C, return to this PowerShell window, and choose C to parse the copied browser text.
Alternative: press Ctrl+S and save as 'Webpage, HTML only' in Downloads (for example ipspeed-sstp.html), then choose H and provide that path.
The browser-copied or saved page is used only to obtain the server list; server tests still run locally on this PC.
"@
}

function Get-SstpServersFromUrls {
    param([string[]]$Urls)

    $collected = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($url in @($Urls)) {
        $cleanUrl = ([string]$url).Trim()
        if ([string]::IsNullOrWhiteSpace($cleanUrl)) { continue }
        try {
            $found = @(Get-SstpServers -PageUrl $cleanUrl -LocalHtmlFile '')
            foreach ($srv in $found) { $collected.Add($srv) }
        } catch {
            $message = $_.Exception.GetBaseException().Message
            $short = ($message -replace '\s+', ' ').Trim()
            if ($short.Length -gt 220) { $short = $short.Substring(0, 220) + '...' }
            $errors.Add(("{0}: {1}" -f $cleanUrl, $short))
            Write-Warning ("Server-list source could not be read: {0} - {1}" -f $cleanUrl, $short)
        }
    }

    return [pscustomobject]@{
        Servers = @($collected)
        Errors  = @($errors)
    }
}

function Merge-ExtraServerSources {
    param(
        [AllowEmptyCollection()][System.Collections.Generic.List[object]]$Target,
        [string[]]$Urls
    )

    if ($null -eq $Target) { $Target = [System.Collections.Generic.List[object]]::new() }
    $errors = @()
    if ($null -eq $Urls -or $Urls.Count -eq 0) { return $errors }

    $result = Get-SstpServersFromUrls -Urls $Urls
    foreach ($srv in @($result.Servers)) { $Target.Add($srv) }
    return @($result.Errors)
}


function Get-SstpServersFromPlainHostListUrls {
    param([string[]]$Urls)

    $collected = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($url in @($Urls)) {
        $cleanUrl = ([string]$url).Trim()
        if ([string]::IsNullOrWhiteSpace($cleanUrl)) { continue }

        # Try the raw URL first, then the readable-text mirror, so a blocked
        # raw.githubusercontent.com does not automatically kill the fallback.
        $attempts = @(
            [pscustomobject]@{ Url = $cleanUrl; Name = 'direct' },
            [pscustomobject]@{ Url = ("https://r.jina.ai/{0}" -f $cleanUrl); Name = 'readable-text mirror' }
        )

        foreach ($attempt in $attempts) {
            Write-Host ("Trying final fallback source ({0}): {1} ..." -f $attempt.Name, $attempt.Url) -ForegroundColor Cyan
            try {
                $response = Invoke-WebRequest -Uri $attempt.Url -TimeoutSec 30 -SkipHttpErrorCheck `
                    -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128.0 Safari/537.36' } `
                    -ErrorAction Stop
                $found = @(Convert-PlainSstpHostListContent -Content ([string]$response.Content) -SourceName 'final fallback list')
                if ($found.Count -eq 0) {
                    throw ("No recognizable host rows were found (HTTP {0})." -f [int]$response.StatusCode)
                }
                foreach ($srv in $found) { $collected.Add($srv) }
                Write-Host ("Retrieved {0} host(s) from the final fallback source." -f $found.Count) -ForegroundColor Green
                break
            } catch {
                $short = ($_.Exception.GetBaseException().Message -replace '\s+', ' ').Trim()
                if ($short.Length -gt 180) { $short = $short.Substring(0, 180) + '...' }
                $errors.Add(("{0}: {1}" -f $attempt.Url, $short))
                Write-Warning ("Final fallback source could not be read: {0} - {1}" -f $attempt.Url, $short)
            }
        }
    }

    return [pscustomobject]@{
        Servers = @($collected)
        Errors  = @($errors)
    }
}


function Get-SstpServersFromCsv {
    param([Parameter(Mandatory)][string]$CsvPath)

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        throw "Server-list CSV file not found: $CsvPath"
    }
    $rows = @(Import-Csv -LiteralPath $CsvPath -Encoding UTF8)
    if ($rows.Count -eq 0) { throw "Server-list CSV is empty: $CsvPath" }

    $servers = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $serverText = [string]$row.Server
        $hostText   = [string]$row.Host
        $portText   = [string]$row.Port
        $country    = [string]$row.Country
        $source     = ''
        if ($row.PSObject.Properties.Name -contains 'Source') {
            $source = ([string]$row.Source).Trim()
        }
        if ([string]::IsNullOrWhiteSpace($source)) { $source = 'CSV snapshot' }

        # New snapshots keep the source PING value in a PingMs column. Older
        # snapshots simply have no value, so they are sorted after known PINGs.
        $pingMs = $null
        if (($row.PSObject.Properties.Name -contains 'PingMs') -and
            -not [string]::IsNullOrWhiteSpace([string]$row.PingMs)) {
            $parsedPing = 0.0
            if ([double]::TryParse(
                    ([string]$row.PingMs).Trim(),
                    [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref]$parsedPing) -and $parsedPing -ge 0) {
                $pingMs = $parsedPing
            } else {
                $pingMs = Convert-PingTextToMs ([string]$row.PingMs)
            }
        }

        $hostName = ''
        $port = 443
        $hasExplicitPort = $false

        # New snapshots keep UPTIME in UptimeText/UptimeMinutes columns. Older
        # snapshots may have neither, in which case uptime stays unknown.
        $uptimeText = ''
        if ($row.PSObject.Properties.Name -contains 'UptimeText') {
            $uptimeText = ([string]$row.UptimeText).Trim()
        } elseif ($row.PSObject.Properties.Name -contains 'Uptime') {
            $uptimeText = ([string]$row.Uptime).Trim()
        }
        $uptimeMinutes = $null
        if (($row.PSObject.Properties.Name -contains 'UptimeMinutes') -and
            -not [string]::IsNullOrWhiteSpace([string]$row.UptimeMinutes)) {
            $parsedUptime = 0.0
            if ([double]::TryParse(
                    ([string]$row.UptimeMinutes).Trim(),
                    [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref]$parsedUptime) -and $parsedUptime -ge 0) {
                $uptimeMinutes = $parsedUptime
            }
        }
        if ($null -eq $uptimeMinutes -and -not [string]::IsNullOrWhiteSpace($uptimeText)) {
            $uptimeMinutes = Convert-UptimeTextToMinutes $uptimeText
        }

        # Prefer the Server column, which is authoritative when it carries an
        # explicit port (host:port or [ipv6]:port).
        if (-not [string]::IsNullOrWhiteSpace($serverText)) {
            $parsed = Parse-SstpServerAddress -Text $serverText
            if ($parsed) {
                $hostName = $parsed.Host
                $port = $parsed.Port
                $hasExplicitPort = $parsed.HasPort
            }
        }

        # Fall back to the Host column if Server was empty or unparseable.
        if ([string]::IsNullOrWhiteSpace($hostName) -and -not [string]::IsNullOrWhiteSpace($hostText)) {
            $hostName = $hostText.Trim().TrimEnd('.')
            if ($hostName.StartsWith('[') -and $hostName.EndsWith(']')) {
                $hostName = $hostName.Substring(1, $hostName.Length - 2)
            }
        }

        # Apply the Port column when present. If both the address and the Port
        # column carry a port and they disagree, trust the address.
        if (-not [string]::IsNullOrWhiteSpace($portText)) {
            $parsedPort = 0
            if (-not [int]::TryParse($portText, [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
                Write-Warning ("Skipping CSV row with invalid Port '{0}'." -f $portText)
                continue
            }
            if ($hasExplicitPort -and $parsedPort -ne $port) {
                Write-Warning ("CSV row Server='{0}' (port {1}) disagrees with Port column '{2}'. Using address port {1}." -f $serverText, $port, $parsedPort)
            } elseif (-not $hasExplicitPort) {
                $port = $parsedPort
            }
        }

        if (-not (Test-SstpHostName $hostName)) { continue }
        if ($port -lt 1 -or $port -gt 65535) { continue }

        $canonical = Format-SstpServerAddress -HostName $hostName -Port $port
        $servers.Add([pscustomobject]@{
            Country       = $country.Trim()
            Source        = $source
            Server        = $canonical
            Host          = $hostName
            Port          = $port
            PingMs        = $pingMs
            UptimeText    = $uptimeText
            UptimeMinutes = $uptimeMinutes
        })
    }

    $seen = @{}
    $unique = @($servers | Where-Object {
        $key = ([string]$_.Server).ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $true } else { $false }
    })
    if ($unique.Count -eq 0) {
        throw 'No valid server entries were found in the CSV. Required columns: Country, Server, Host, Port.'
    }
    return $unique
}

function Resolve-SstpServerTarget {
    param([Parameter(Mandatory)][object]$Server)

    $serverText = ([string]$Server.Server).Trim()
    $hostFromField = ([string]$Server.Host).Trim().TrimEnd('.')
    if ($hostFromField.StartsWith('[') -and $hostFromField.EndsWith(']')) {
        $hostFromField = $hostFromField.Substring(1, $hostFromField.Length - 2)
    }
    $portFromField = 443
    if ($Server.PSObject.Properties.Name -contains 'Port') {
        $portText = [string]$Server.Port
        if (-not [string]::IsNullOrWhiteSpace($portText)) {
            $parsedPort = 0
            if (-not [int]::TryParse($portText, [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
                throw "Invalid Port field '$portText' for server '$serverText'."
            }
            $portFromField = $parsedPort
        }
    }

    # The server address is authoritative when it carries an explicit port;
    # otherwise the Host/Port fields are used. This preserves the canonical
    # behavior of earlier versions and adds IPv6 bracket handling.
    $parsed = Parse-SstpServerAddress -Text $serverText
    if ($parsed) {
        if ($parsed.HasPort -and $parsed.Port -ne $portFromField -and
            ($Server.PSObject.Properties.Name -contains 'Port') -and
            -not [string]::IsNullOrWhiteSpace([string]$Server.Port)) {
            Write-Warning ("Port mismatch for '{0}': address says {1}, Port field says {2}. Using address port {1}." -f $serverText, $parsed.Port, $portFromField)
        }
        $hostName = $parsed.Host
        $port = if ($parsed.HasPort) { $parsed.Port } else { $portFromField }
    } else {
        if ([string]::IsNullOrWhiteSpace($hostFromField)) {
            throw "Invalid or unsupported SSTP server entry '$serverText'."
        }
        $hostName = $hostFromField
        $port = $portFromField
    }

    if (-not (Test-SstpHostName $hostName)) {
        throw "Invalid or unsupported SSTP hostname in server entry '$serverText'."
    }

    # Canonical Windows SSTP address:
    #   IPv4/FQDN, port 443   -> host
    #   IPv4/FQDN, other port -> host:port
    #   IPv6, any port        -> [ipv6] or [ipv6]:port
    $serverAddress = Format-SstpServerAddress -HostName $hostName -Port $port

    return [pscustomobject]@{
        Host          = $hostName
        Port          = $port
        ServerAddress = $serverAddress
    }
}

function Test-TcpPort {
    param(
        [string]$HostName,
        [int]$PortNumber,
        [int]$TimeoutMs
    )
    $client = [System.Net.Sockets.TcpClient]::new()
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # TcpClient.ConnectAsync accepts a raw hostname, IPv4, or IPv6 literal
        # (never a bracketed form). Brackets are stripped upstream by
        # Parse-SstpServerAddress, so $HostName here is always bracket-free.
        $task = $client.ConnectAsync($HostName, $PortNumber)
        if (-not $task.Wait($TimeoutMs)) {
            try { $client.Close() } catch { }
            try { [void]$task.Wait(200) } catch { }
            return [pscustomobject]@{ Reachable = $false; Milliseconds = $null; Error = 'TCP timeout' }
        }
        $task.GetAwaiter().GetResult()
        $watch.Stop()
        return [pscustomobject]@{ Reachable = $client.Connected; Milliseconds = [math]::Round($watch.Elapsed.TotalMilliseconds, 1); Error = '' }
    }
    catch {
        $watch.Stop()
        return [pscustomobject]@{ Reachable = $false; Milliseconds = [math]::Round($watch.Elapsed.TotalMilliseconds, 1); Error = $_.Exception.GetBaseException().Message }
    }
    finally {
        $client.Dispose()
    }
}

function Measure-TunnelLatency {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMs,
        [int]$Samples
    )

    $icmpValues = @()
    $tcpValues = @()
    $errors = @()
    $icmpTimeout = [math]::Min($TimeoutMs, 1500)

    # Try ICMP first; fall back to TCP connect time when the tunnel or target
    # blocks echo requests. The target is a fixed endpoint so all servers are
    # compared against the same destination.
    for ($i = 0; $i -lt $Samples; $i++) {
        $ping = $null
        try {
            $ping = [System.Net.NetworkInformation.Ping]::new()
            $reply = $ping.Send($HostName, $icmpTimeout)
            if ($reply -and $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                $icmpValues += [double]$reply.RoundtripTime
            }
        }
        catch {
            $errors += $_.Exception.GetBaseException().Message
        }
        finally {
            if ($ping) { $ping.Dispose() }
        }
    }

    if ($icmpValues.Count -eq 0) {
        for ($i = 0; $i -lt $Samples; $i++) {
            $tcp = Test-TcpPort -HostName $HostName -PortNumber $Port -TimeoutMs $TimeoutMs
            if ($tcp.Reachable) {
                $tcpValues += [double]$tcp.Milliseconds
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$tcp.Error)) {
                $errors += [string]$tcp.Error
            }
        }
    }

    $values = if ($icmpValues.Count -gt 0) { @($icmpValues) } else { @($tcpValues) }
    $method = if ($icmpValues.Count -gt 0) { 'ICMP' } elseif ($tcpValues.Count -gt 0) { 'TCP' } else { 'none' }
    $median = Get-MedianValue -Values $values
    $minimum = $null
    $maximum = $null
    if ($values.Count -gt 0) {
        $minimum = [math]::Round([double](($values | Measure-Object -Minimum).Minimum), 2)
        $maximum = [math]::Round([double](($values | Measure-Object -Maximum).Maximum), 2)
    }

    $errorText = (@($errors | Select-Object -Unique) -join ' | ')
    if ($errorText.Length -gt 350) { $errorText = $errorText.Substring(0, 350) }

    return [pscustomobject]@{
        LatencyMs         = $median
        Method            = $method
        SuccessfulSamples = $values.Count
        Samples           = ($values -join '|')
        Min               = $minimum
        Max               = $maximum
        Error             = $errorText
    }
}

function Invoke-NativeTimed {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [int]$TimeoutSec
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        [void]$startInfo.ArgumentList.Add([string]$argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSec * 1000)) {
            try { $process.Kill($true) } catch { }
            try { $process.WaitForExit() } catch { }
            $clock.Stop()
            return [pscustomobject]@{
                ExitCode = -1; TimedOut = $true; StdOut = ''; StdErr = 'Process timed out.'
                Seconds = [math]::Round($clock.Elapsed.TotalSeconds, 2)
            }
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $clock.Stop()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode; TimedOut = $false; StdOut = $stdout; StdErr = $stderr
            Seconds = [math]::Round($clock.Elapsed.TotalSeconds, 2)
        }
    }
    catch {
        $clock.Stop()
        return [pscustomobject]@{
            ExitCode = -1; TimedOut = $false; StdOut = ''; StdErr = $_.Exception.GetBaseException().Message
            Seconds = [math]::Round($clock.Elapsed.TotalSeconds, 2)
        }
    }
    finally {
        $process.Dispose()
    }
}

function Measure-DownloadSpeed {
    param(
        [Parameter(Mandatory)][string]$CurlPath,
        [ValidateSet('IPv4', 'IPv6')][string]$AddressFamily = 'IPv4',
        [Parameter(Mandatory)][string]$SpeedTestUrl,
        [int]$DownloadBytes = 10000000,
        [int]$Samples = 2,
        [int]$TimeoutSec = 12
    )

    $familyArgument = if ($AddressFamily -eq 'IPv6') { '--ipv6' } else { '--ipv4' }
    $url = if ($SpeedTestUrl -match '\{0\}') {
        $SpeedTestUrl -replace '\{0\}', [string]$DownloadBytes
    }
    else {
        $SpeedTestUrl
    }

    $sampleResults = [System.Collections.Generic.List[object]]::new()
    for ($sampleIndex = 1; $sampleIndex -le $Samples; $sampleIndex++) {
        $download = Invoke-NativeTimed -FilePath $CurlPath -Arguments @(
            $familyArgument, '--location', '--silent', '--show-error', '--fail',
            '--max-time', [string]$TimeoutSec, '--connect-timeout', '5',
            '--output', 'NUL', '--write-out', '%{http_code}|%{size_download}|%{time_total}|%{speed_download}',
            $url
        ) -TimeoutSec ($TimeoutSec + 4)

        $speedText = [string]$download.StdOut
        $speedMatch = [regex]::Match($speedText, '(\d{3})\|([\d.]+)\|([\d.]+)\|([\d.]+)')
        if ($speedMatch.Success) {
            $httpCode = [int]$speedMatch.Groups[1].Value
            $bytes = [double]::Parse($speedMatch.Groups[2].Value, [System.Globalization.CultureInfo]::InvariantCulture)
            $seconds = [double]::Parse($speedMatch.Groups[3].Value, [System.Globalization.CultureInfo]::InvariantCulture)
            $bytesPerSecond = [double]::Parse($speedMatch.Groups[4].Value, [System.Globalization.CultureInfo]::InvariantCulture)
            if ($httpCode -ge 200 -and $httpCode -lt 300 -and $bytes -gt 0 -and $seconds -gt 0) {
                $sampleResults.Add([pscustomobject]@{
                    Sample   = $sampleIndex
                    Mbps     = [math]::Round(($bytesPerSecond * 8 / 1000000), 2)
                    MB       = [math]::Round(($bytes / 1000000), 2)
                    Seconds  = [math]::Round($seconds, 2)
                    Complete = (-not $download.TimedOut -and $download.ExitCode -eq 0 -and $bytes -ge ($DownloadBytes * 0.95))
                    HttpCode = $httpCode
                    TimedOut = [bool]$download.TimedOut
                    Error    = ''
                })
                continue
            }

            $detail = "HTTP $httpCode or no bytes."
            if ($download.TimedOut) { $detail = 'Download test timed out. ' + $detail }
            $sampleResults.Add([pscustomobject]@{
                Sample   = $sampleIndex
                Mbps     = $null
                MB       = if ($bytes -gt 0) { [math]::Round(($bytes / 1000000), 2) } else { $null }
                Seconds  = if ($seconds -gt 0) { [math]::Round($seconds, 2) } else { $null }
                Complete = $false
                HttpCode = $httpCode
                TimedOut = [bool]$download.TimedOut
                Error    = $detail
            })
            continue
        }

        $detail = (([string]$download.StdErr).Trim() -replace '\s+', ' ')
        if ($download.TimedOut) { $detail = 'Download test timed out. ' + $detail }
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = "curl exit code $($download.ExitCode); no diagnostic text was returned." }
        if ($detail.Length -gt 350) { $detail = $detail.Substring(0, 350) }
        $sampleResults.Add([pscustomobject]@{
            Sample   = $sampleIndex
            Mbps     = $null
            MB       = $null
            Seconds  = $null
            Complete = $false
            HttpCode = 0
            TimedOut = [bool]$download.TimedOut
            Error    = $detail
        })
    }

    $successful = @($sampleResults | Where-Object { $null -ne $_.Mbps })
    $mbpsValues = @($successful | ForEach-Object { [double]$_.Mbps })
    $median = Get-MedianValue -Values $mbpsValues
    $average = $null
    $minimum = $null
    $maximum = $null
    if ($mbpsValues.Count -gt 0) {
        $average = [math]::Round((($mbpsValues | Measure-Object -Average).Average), 2)
        $minimum = [math]::Round([double](($mbpsValues | Measure-Object -Minimum).Minimum), 2)
        $maximum = [math]::Round([double](($mbpsValues | Measure-Object -Maximum).Maximum), 2)
    }

    $mbValues = @($successful | ForEach-Object { [double]$_.MB })
    $secondValues = @($successful | ForEach-Object { [double]$_.Seconds })
    $totalMB = if ($mbValues.Count -gt 0) { [math]::Round((($mbValues | Measure-Object -Sum).Sum), 2) } else { $null }
    $totalSeconds = if ($secondValues.Count -gt 0) { [math]::Round((($secondValues | Measure-Object -Sum).Sum), 2) } else { $null }
    $allComplete = ($successful.Count -eq $Samples -and @($successful | Where-Object { -not $_.Complete }).Count -eq 0)

    $errorText = ''
    if ($successful.Count -eq 0) {
        $errorText = (@($sampleResults |
                ForEach-Object { [string]$_.Error } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique) -join ' | ')
        if ($errorText.Length -gt 350) { $errorText = $errorText.Substring(0, 350) }
    }

    $sampleErrors = (@($sampleResults |
            Where-Object { $null -eq $_.Mbps } |
            ForEach-Object { [string]$_.Error } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique) -join ' | ')
    if ($sampleErrors.Length -gt 350) { $sampleErrors = $sampleErrors.Substring(0, 350) }

    return [pscustomobject]@{
        Samples           = @($sampleResults)
        SuccessfulSamples = $successful.Count
        MedianMbps        = $median
        AverageMbps       = $average
        MinMbps           = $minimum
        MaxMbps           = $maximum
        TotalMB           = $totalMB
        TotalSeconds      = $totalSeconds
        AllComplete       = $allComplete
        Error             = $errorText
        SampleErrors      = $sampleErrors
    }
}

function Add-SelectionScores {
    param(
        [Parameter(Mandatory)][object[]]$Records,
        [ValidateSet('Speed', 'Balanced', 'Latency')][string]$RankMode = 'Balanced'
    )

    if ($Records.Count -eq 0) { return @() }

    foreach ($record in $Records) {
        # Prefer the latency measured through the live VPN tunnel. If the
        # tunnel blocked both ICMP and TCP probes, the pre-VPN TCP connect time
        # is the measured fallback instead of the source list's PING.
        $measuredLatency = $null
        if ($null -ne $record.VPNLatencyMs -and [double]$record.VPNLatencyMs -gt 0) {
            $measuredLatency = [double]$record.VPNLatencyMs
        } elseif ($null -ne $record.TcpConnectMs -and [double]$record.TcpConnectMs -gt 0) {
            $measuredLatency = [double]$record.TcpConnectMs
        }
        $record | Add-Member -NotePropertyName 'MeasuredLatencyMs' -NotePropertyValue $measuredLatency -Force
    }

    # Normalize on every measured server so all scores in the CSV use the
    # same 0..100 scale. Missing measurements score 0.
    $speedValues = @($Records |
        Where-Object { $null -ne $_.DownloadMbps } |
        ForEach-Object { [double]$_.DownloadMbps })
    $latencyValues = @($Records |
        Where-Object { $null -ne $_.MeasuredLatencyMs } |
        ForEach-Object { [double]$_.MeasuredLatencyMs })

    $maxSpeed = if ($speedValues.Count -gt 0) { [double](($speedValues | Measure-Object -Maximum).Maximum) } else { $null }
    $minLatency = if ($latencyValues.Count -gt 0) { [double](($latencyValues | Measure-Object -Minimum).Minimum) } else { $null }
    $maxLatency = if ($latencyValues.Count -gt 0) { [double](($latencyValues | Measure-Object -Maximum).Maximum) } else { $null }

    foreach ($record in $Records) {
        # Normalized score 0..100. Missing measurements score 0 so they always
        # rank after servers that were actually measured.
        $speedScore = 0.0
        if ($null -ne $record.DownloadMbps -and $null -ne $maxSpeed -and $maxSpeed -gt 0) {
            $speedScore = [math]::Round((100.0 * [double]$record.DownloadMbps / $maxSpeed), 2)
            if ($speedScore -gt 100) { $speedScore = 100 }
            if ($speedScore -lt 0) { $speedScore = 0 }
        }

        $latencyScore = 0.0
        $measuredLatency = $record.MeasuredLatencyMs
        if ($null -ne $measuredLatency) {
            if ($latencyValues.Count -le 1 -or $maxLatency -le $minLatency) {
                # Only one measured server (or all equal): latency cannot
                # discriminate, so give every measured server full credit.
                $latencyScore = 100.0
            } else {
                $latencyScore = [math]::Round((100.0 * ($maxLatency - [double]$measuredLatency) / ($maxLatency - $minLatency)), 2)
            }
            if ($latencyScore -gt 100) { $latencyScore = 100 }
            if ($latencyScore -lt 0) { $latencyScore = 0 }
        }

        $selectionScore = switch ($RankMode) {
            'Speed' { $speedScore }
            'Latency' { $latencyScore }
            default { [math]::Round((0.7 * $speedScore + 0.3 * $latencyScore), 2) }
        }

        $record | Add-Member -NotePropertyName 'SpeedScore' -NotePropertyValue $speedScore -Force
        $record | Add-Member -NotePropertyName 'LatencyScore' -NotePropertyValue $latencyScore -Force
        $record | Add-Member -NotePropertyName 'SelectionScore' -NotePropertyValue $selectionScore -Force
    }

    return @($Records)
}

function Get-PublicIp {
    param(
        [Parameter(Mandatory)][string]$CurlPath,
        [ValidateSet('IPv4', 'IPv6')][string]$AddressFamily = 'IPv4'
    )

    # Pin the curl request to one family so an IPv4 baseline is never compared
    # with an IPv6 result (or vice versa).
    $familyArgument = if ($AddressFamily -eq 'IPv4') { '--ipv4' } else { '--ipv6' }
    $response = Invoke-NativeTimed -FilePath $CurlPath -Arguments @(
        $familyArgument, '--silent', '--show-error', '--fail', '--location', '--max-time', '7',
        '--connect-timeout', '4', 'https://api.ipify.org'
    ) -TimeoutSec 9

    if ($response.ExitCode -eq 0 -and -not $response.TimedOut) {
        $ip = ([string]$response.StdOut).Trim()
        $parsedIp = $null
        if ([System.Net.IPAddress]::TryParse($ip, [ref]$parsedIp)) {
            if ($AddressFamily -eq 'IPv4' -and $parsedIp.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                return $ip
            }
            if ($AddressFamily -eq 'IPv6' -and $parsedIp.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                return $ip
            }
        }
    }
    return ''
}

if ($env:OS -ne 'Windows_NT') {
    throw 'This script must run on Windows 10/11 because it uses the built-in Windows SSTP VPN client.'
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'This v16 build requires PowerShell 7 or later. Open PowerShell 7 (pwsh.exe) and run it again.'
}
if (-not (Test-IsAdministrator)) {
    throw 'Please open PowerShell as Administrator, then run this script again.'
}

Import-Module VpnClient -ErrorAction Stop
$curlCommand = Get-Command 'curl.exe' -ErrorAction Stop
$curlPath = $curlCommand.Source
$rasdialPath = Join-Path $env:WINDIR 'System32\rasdial.exe'
if (-not (Test-Path $rasdialPath)) { throw "rasdial.exe was not found at $rasdialPath" }

function Get-ActiveWindowsVpnConnections {
    $items = @()
    try { $items += @(Get-VpnConnection -ErrorAction SilentlyContinue) } catch { }
    try { $items += @(Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue) } catch { }
    return @($items | Where-Object { [string]$_.ConnectionStatus -eq 'Connected' } | Sort-Object Name -Unique)
}

function Get-RasErrorCode {
    param([string]$Text, [int]$ProcessExitCode)
    $match = [regex]::Match([string]$Text, '(?i)Remote Access error\s+(\d{3})')
    if ($match.Success) { return [int]$match.Groups[1].Value }
    if ($ProcessExitCode -in @(633, 638, 691, 720, 809, 810)) { return $ProcessExitCode }
    return 0
}

function Set-VpnConnectionCredentials {
    param(
        [Parameter(Mandatory)][string]$ProfileName,
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][string]$Password,
        [string]$Domain = ''
    )

    # The inbox VpnClient module cannot set a VPN username/password directly.
    # RasSetCredentials writes them into the per-user RAS phone-book entry, so
    # the saved SSTP profile can connect with the public vpn/vpn credentials
    # without asking for them on first use.
    if (-not ('SstpVpnCredentialStore' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class SstpVpnCredentialStore
{
    private const int SUCCESS = 0;
    private const int ERROR_ACCESS_DENIED = 5;
    private const int UNLEN = 256;
    private const int PWLEN = 256;
    private const int DNLEN = 15;

    [Flags]
    private enum RASCM
    {
        UserName = 0x1,
        Password = 0x2,
        Domain = 0x4
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode, Pack = 4)]
    private struct RASCREDENTIALS
    {
        public int size;
        public RASCM options;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = UNLEN + 1)]
        public string userName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = PWLEN + 1)]
        public string password;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = DNLEN + 1)]
        public string domain;
    }

    [DllImport("rasapi32.dll", CharSet = CharSet.Unicode)]
    private static extern int RasSetCredentials(
        string lpszPhonebook,
        string lpszEntryName,
        IntPtr lpCredentials,
        [MarshalAs(UnmanagedType.Bool)] bool fClearCredentials);

    [DllImport("rasapi32.dll", CharSet = CharSet.Unicode)]
    private static extern int RasGetErrorString(
        int uErrorValue,
        [Out] StringBuilder lpszErrorString,
        int cBufSize);

    public static void SetCredentials(string entryName, string domain, string username, string password)
    {
        var credentials = new RASCREDENTIALS
        {
            userName = username ?? string.Empty,
            password = password ?? string.Empty,
            domain = domain ?? string.Empty,
            options = RASCM.Domain | RASCM.UserName | RASCM.Password
        };

        int size = Marshal.SizeOf(typeof(RASCREDENTIALS));
        credentials.size = size;
        IntPtr pCredentials = IntPtr.Zero;
        try
        {
            pCredentials = Marshal.AllocHGlobal(size);
            Marshal.StructureToPtr(credentials, pCredentials, true);
            int ret = RasSetCredentials(null, entryName, pCredentials, false);
            if (ret == SUCCESS) { return; }
            if (ret == ERROR_ACCESS_DENIED)
            {
                throw new UnauthorizedAccessException("Access denied while storing VPN credentials for '" + entryName + "'.");
            }

            string message = "RAS error " + ret;
            var buffer = new StringBuilder(512);
            if (RasGetErrorString(ret, buffer, buffer.Capacity) == SUCCESS)
            {
                message = buffer.ToString();
            }
            throw new InvalidOperationException(message + " (RAS " + ret + ")");
        }
        finally
        {
            if (pCredentials != IntPtr.Zero) { Marshal.FreeHGlobal(pCredentials); }
        }
    }
}
'@ -IgnoreWarnings
    }

    [SstpVpnCredentialStore]::SetCredentials($ProfileName, $Domain, $UserName, $Password)
}

function Remove-TestVpnProfileSafely {
    param(
        [Parameter(Mandatory)][string]$ProfileName,
        [Parameter(Mandatory)][string]$RasdialPath,
        [ValidateRange(1, 60)][int]$WaitSeconds = 20,
        [ValidateRange(0, 30)][int]$SettleSeconds = 4
    )

    try {
        $null = Invoke-NativeTimed -FilePath $RasdialPath `
            -Arguments @($ProfileName, '/disconnect') -TimeoutSec 12
    } catch { }

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $isDisconnected = $false
    do {
        $profile = $null
        try { $profile = Get-VpnConnection -Name $ProfileName -ErrorAction SilentlyContinue } catch { }
        if (-not $profile -or [string]$profile.ConnectionStatus -ne 'Connected') {
            $isDisconnected = $true
            break
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)

    if (-not $isDisconnected) {
        return [pscustomobject]@{
            Removed = $false; StillConnected = $true
            Error = "Profile '$ProfileName' still reports Connected after $WaitSeconds seconds; it was not removed."
        }
    }

    try {
        Remove-VpnConnection -Name $ProfileName -Force -ErrorAction Stop
    } catch {
        $removeError = $_.Exception.GetBaseException().Message
        $stillThere = $null
        try { $stillThere = Get-VpnConnection -Name $ProfileName -ErrorAction SilentlyContinue } catch { }
        if ($stillThere) {
            return [pscustomobject]@{
                Removed = $false; StillConnected = $false
                Error = $removeError
            }
        }
    }

    if ($SettleSeconds -gt 0) { Start-Sleep -Seconds $SettleSeconds }
    return [pscustomobject]@{ Removed = $true; StillConnected = $false; Error = '' }
}

function Show-Ras633Diagnostics {
    Write-Host "`n================ LOCAL WINDOWS RAS DIAGNOSTICS ================" -ForegroundColor Yellow
    Write-Host 'RAS 633 means Windows could not allocate/use a suitable remote-access port; it is not proof that the remote SSTP server rejected the connection.' -ForegroundColor Yellow

    Write-Host "`n[1] Remote Access / SSTP services" -ForegroundColor Cyan
    try {
        Get-CimInstance Win32_Service -Filter "Name='RasMan' OR Name='SstpSvc'" -ErrorAction Stop |
            Select-Object Name, State, StartMode, ExitCode |
            Format-Table -AutoSize | Out-Host
    } catch {
        Write-Host ("Could not query services: " + $_.Exception.GetBaseException().Message) -ForegroundColor DarkYellow
    }

    Write-Host "`n[2] Windows WAN Miniport devices" -ForegroundColor Cyan
    try {
        $miniports = @(Get-PnpDevice -Class Net -ErrorAction Stop |
            Where-Object { $_.FriendlyName -match 'WAN Miniport|SSTP' } |
            Select-Object Status, FriendlyName, Problem, InstanceId)
        if ($miniports.Count -gt 0) { $miniports | Format-Table -Wrap -AutoSize | Out-Host }
        else { Write-Host 'No WAN Miniport entries were returned by Get-PnpDevice.' -ForegroundColor DarkYellow }
    } catch {
        Write-Host ("Could not query PnP devices: " + $_.Exception.GetBaseException().Message) -ForegroundColor DarkYellow
    }

    Write-Host "`n[3] Recent RasClient events (last 15 minutes)" -ForegroundColor Cyan
    $events = @()
    try {
        $events = @(Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-RasClient/Operational'
            StartTime = (Get-Date).AddMinutes(-15)
        } -MaxEvents 8 -ErrorAction Stop | Select-Object TimeCreated, Id, Message)
    } catch { }
    if ($events.Count -eq 0) {
        # On some Windows installations the Operational channel is disabled or
        # unreadable, while the same RasClient failures are present in Application.
        try {
            $events = @(Get-WinEvent -FilterHashtable @{
                LogName = 'Application'
                ProviderName = 'RasClient'
                StartTime = (Get-Date).AddMinutes(-15)
            } -MaxEvents 8 -ErrorAction Stop | Select-Object TimeCreated, Id, Message)
        } catch { }
    }
    if ($events.Count -gt 0) {
        $events | Format-List | Out-Host
    } else {
        Write-Host 'No readable recent RasClient events were found in Operational or Application logs.' -ForegroundColor DarkGray
    }

    Write-Host "`nDo not change registry values or reinstall WAN Miniports yet; use the diagnostic output first." -ForegroundColor Yellow
}

# ===================== v16.1: EXISTING-PROFILE VERIFICATION =====================
# The functions below are intentionally separate from the proven v16 new-server
# path. They only run when -ListExisting, -VerifyExisting, or -PruneFirst is used.

function Get-ExistingSstpVpnProfiles {
    # Keep the per-user and AllUser phonebooks as separate records. rasdial
    # accepts only a profile name, not a scope, so a same-name entry in both
    # phonebooks is ambiguous and must never be tested or removed blindly.
    $profiles = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    $scopedItems = [System.Collections.Generic.List[object]]::new()

    try {
        foreach ($item in @(Get-VpnConnection -ErrorAction SilentlyContinue)) {
            if ($null -ne $item) {
                $scopedItems.Add([pscustomobject]@{ Item = $item; Scope = 'User' })
            }
        }
    } catch { }
    try {
        foreach ($item in @(Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue)) {
            if ($null -ne $item) {
                $scopedItems.Add([pscustomobject]@{ Item = $item; Scope = 'AllUser' })
            }
        }
    } catch { }

    foreach ($entry in $scopedItems) {
        $item = $entry.Item
        $name = ([string]$item.Name).Trim()
        $scope = [string]$entry.Scope
        $key = ($scope + '|' + $name).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($name) -or $seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $splitTunneling = $false
        try { $splitTunneling = [bool]$item.SplitTunneling } catch { }

        $profiles.Add([pscustomobject]@{
            Name             = $name
            Scope            = $scope
            ServerAddress    = ([string]$item.ServerAddress).Trim()
            TunnelType       = [string]$item.TunnelType
            ConnectionStatus = [string]$item.ConnectionStatus
            SplitTunneling   = $splitTunneling
            NameCollision    = $false
        })
    }

    $nameGroups = @($profiles | Group-Object { ([string]$_.Name).ToLowerInvariant() })
    foreach ($group in $nameGroups) {
        if ($group.Count -gt 1) {
            foreach ($profile in $group.Group) { $profile.NameCollision = $true }
        }
    }

    return @($profiles)
}

function Show-ExistingVpnProfiles {
    $profiles = @(Get-ExistingSstpVpnProfiles)
    Write-Host ''
    Write-Host '================ EXISTING WINDOWS VPN PROFILES ================' -ForegroundColor Cyan
    if ($profiles.Count -eq 0) {
        Write-Host 'No Windows VPN profiles were found.' -ForegroundColor Yellow
        return
    }

    $profiles |
        Select-Object Name, Scope, TunnelType, ServerAddress, ConnectionStatus, SplitTunneling, NameCollision |
        Format-Table -AutoSize | Out-Host

    $sstpCount = @($profiles | Where-Object { [string]$_.TunnelType -ieq 'Sstp' }).Count
    $collisionCount = @($profiles | Where-Object { [bool]$_.NameCollision }).Count
    Write-Host ("Found {0} profile(s): {1} SSTP, {2} non-SSTP, {3} duplicate-name record(s)." -f $profiles.Count, $sstpCount, ($profiles.Count - $sstpCount), $collisionCount) -ForegroundColor Cyan

    $csvPath = Join-Path $PSScriptRoot ("sstp_existing_profiles_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    try {
        $profiles |
            Select-Object Name, Scope, TunnelType, ServerAddress, ConnectionStatus, SplitTunneling, NameCollision |
            Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8 -ErrorAction Stop
        Write-Host ("Profile inventory CSV: {0}" -f $csvPath) -ForegroundColor DarkGray
    } catch {
        Write-Warning ("Could not save the profile inventory CSV: {0}" -f $_.Exception.GetBaseException().Message)
    }

    Write-Host ''
    Write-Host 'Nothing was dialed or changed. To test SSTP profiles without deleting anything, run:' -ForegroundColor Green
    Write-Host '  .\Test-FreeSstpServers_v16_1.ps1 -VerifyExisting -ReportOnly' -ForegroundColor Green
}

function Get-PublicIpRobust {
    # The v16 path uses ipify only. Existing-profile verification additionally
    # tries independent echo services, because a working SSTP exit may block one
    # particular provider. Every answer is validated as a real address of the
    # requested family, so an HTML block page is never accepted as an IP.
    param(
        [Parameter(Mandatory)][string]$CurlPath,
        [ValidateSet('IPv4', 'IPv6')][string]$AddressFamily = 'IPv4'
    )

    $primary = ''
    try { $primary = Get-PublicIp -CurlPath $CurlPath -AddressFamily $AddressFamily } catch { }
    if (-not [string]::IsNullOrWhiteSpace($primary)) { return $primary }

    $familyArgument = if ($AddressFamily -eq 'IPv4') { '--ipv4' } else { '--ipv6' }
    $echoServices = @(
        'https://checkip.amazonaws.com',
        'https://icanhazip.com',
        'https://ifconfig.me/ip',
        'https://ident.me',
        'https://api64.ipify.org'
    )

    foreach ($service in $echoServices) {
        $response = Invoke-NativeTimed -FilePath $CurlPath -Arguments @(
            $familyArgument, '--silent', '--show-error', '--fail', '--location',
            '--max-time', '6', '--connect-timeout', '3', $service
        ) -TimeoutSec 8

        if ($response.ExitCode -eq 0 -and -not $response.TimedOut) {
            $ip = ([string]$response.StdOut).Trim()
            if ($ip -match '(?m)^ip=(\S+)') { $ip = $Matches[1] }
            $parsedIp = $null
            if ([System.Net.IPAddress]::TryParse($ip, [ref]$parsedIp)) {
                if ($AddressFamily -eq 'IPv4' -and $parsedIp.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                    return $ip
                }
                if ($AddressFamily -eq 'IPv6' -and $parsedIp.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                    return $ip
                }
            }
        }
    }
    return ''
}

function Test-InternetConnectivity {
    # Connectivity-only probe. It never contributes to speed or ranking; it is
    # used only when the configured speed-test endpoint produced no sample.
    param(
        [Parameter(Mandatory)][string]$CurlPath,
        [ValidateSet('IPv4', 'IPv6')][string]$AddressFamily = 'IPv4',
        [string[]]$Urls = @(
            'https://www.google.com/generate_204',
            'https://www.gstatic.com/generate_204',
            'https://connectivitycheck.gstatic.com/generate_204',
            'https://www.msftconnecttest.com/connecttest.txt',
            'https://example.com/'
        )
    )

    $familyArgument = if ($AddressFamily -eq 'IPv6') { '--ipv6' } else { '--ipv4' }
    foreach ($url in @($Urls)) {
        $candidate = ([string]$url).Trim()
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $probe = Invoke-NativeTimed -FilePath $CurlPath -Arguments @(
            $familyArgument, '--location', '--silent', '--show-error',
            '--max-time', '6', '--connect-timeout', '4',
            '--output', 'NUL', '--write-out', '%{http_code}', $candidate
        ) -TimeoutSec 8

        $statusText = ([string]$probe.StdOut).Trim()
        $statusMatch = [regex]::Match($statusText, '(\d{3})')
        if (-not $probe.TimedOut -and $probe.ExitCode -eq 0 -and $statusMatch.Success) {
            $statusCode = [int]$statusMatch.Groups[1].Value
            if ($statusCode -ge 200 -and $statusCode -lt 400) {
                return [pscustomobject]@{ Reachable = $true; Url = $candidate; HttpCode = $statusCode; Error = '' }
            }
        }
    }
    return [pscustomobject]@{
        Reachable = $false
        Url = ''
        HttpCode = 0
        Error = 'None of the configured connectivity-probe URLs returned a successful HTTP response.'
    }
}

function Get-VpnProfileState {
    # Returns Connected, Disconnected, or '' when the scoped profile cannot be read.
    param(
        [Parameter(Mandatory)][string]$ProfileName,
        [ValidateSet('User', 'AllUser')][string]$Scope = 'User'
    )
    try {
        if ($Scope -eq 'AllUser') {
            $p = Get-VpnConnection -Name $ProfileName -AllUserConnection -ErrorAction SilentlyContinue
        } else {
            $p = Get-VpnConnection -Name $ProfileName -ErrorAction SilentlyContinue
        }
        if ($p) { return [string]$p.ConnectionStatus }
    } catch { }
    return ''
}

function Test-ExistingVpnProfileExists {
    param(
        [Parameter(Mandatory)][string]$ProfileName,
        [ValidateSet('User', 'AllUser')][string]$Scope = 'User'
    )
    try {
        if ($Scope -eq 'AllUser') {
            $p = Get-VpnConnection -Name $ProfileName -AllUserConnection -ErrorAction SilentlyContinue
        } else {
            $p = Get-VpnConnection -Name $ProfileName -ErrorAction SilentlyContinue
        }
        return ($null -ne $p)
    } catch { return $false }
}

function Disconnect-ExistingVpnProfile {
    param(
        [Parameter(Mandatory)][string]$ProfileName,
        [Parameter(Mandatory)][string]$RasdialPath,
        [ValidateSet('User', 'AllUser')][string]$Scope = 'User',
        [ValidateRange(1, 60)][int]$WaitSeconds = 20
    )

    try {
        $null = Invoke-NativeTimed -FilePath $RasdialPath -Arguments @($ProfileName, '/disconnect') -TimeoutSec 12
    } catch { }

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    do {
        $state = Get-VpnProfileState -ProfileName $ProfileName -Scope $Scope
        if ($state -eq 'Disconnected') { return $true }
        if ([string]::IsNullOrWhiteSpace($state)) { return $false }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    return ((Get-VpnProfileState -ProfileName $ProfileName -Scope $Scope) -eq 'Disconnected')
}

function Remove-ExistingVpnProfile {
    # Remove only the exact phonebook scope that was tested. Never fall back to
    # the other scope: two same-name profiles may point at different servers.
    param(
        [Parameter(Mandatory)][string]$ProfileName,
        [Parameter(Mandatory)][string]$RasdialPath,
        [ValidateSet('User', 'AllUser')][string]$PreferredScope = 'User',
        [ValidateRange(0, 30)][int]$SettleSeconds = 2
    )

    $profileState = Get-VpnProfileState -ProfileName $ProfileName -Scope $PreferredScope
    if ($profileState -eq 'Connected') {
        $disconnected = Disconnect-ExistingVpnProfile -ProfileName $ProfileName -RasdialPath $RasdialPath -Scope $PreferredScope -WaitSeconds 20
        if (-not $disconnected) {
            return [pscustomobject]@{ Removed = $false; Error = "Profile '$ProfileName' ($PreferredScope) could not be confirmed disconnected; it was kept." }
        }
    } elseif ($profileState -ne 'Disconnected') {
        return [pscustomobject]@{ Removed = $false; Error = "Could not read the state of profile '$ProfileName' in scope '$PreferredScope'; removal was cancelled." }
    }

    try {
        if ($PreferredScope -eq 'AllUser') {
            Remove-VpnConnection -Name $ProfileName -AllUserConnection -Force -ErrorAction Stop
        } else {
            Remove-VpnConnection -Name $ProfileName -Force -ErrorAction Stop
        }
    } catch {
        return [pscustomobject]@{ Removed = $false; Error = $_.Exception.GetBaseException().Message }
    }

    if ($SettleSeconds -gt 0) { Start-Sleep -Seconds $SettleSeconds }
    if (-not (Test-ExistingVpnProfileExists -ProfileName $ProfileName -Scope $PreferredScope)) {
        return [pscustomobject]@{ Removed = $true; Error = '' }
    }
    return [pscustomobject]@{ Removed = $false; Error = "Windows still reports profile '$ProfileName' in scope '$PreferredScope' after removal." }
}

function Test-ExistingSstpProfile {
    # Tests one existing Windows SSTP profile with the v16 measurement engine.
    # Returns [pscustomobject]@{ Record = <verification record> }.
    #
    # Verdicts:
    #   ACCEPT       = working; keep untouched.
    #   REJECT       = confirmed dead or not routing through the VPN; removal
    #                  candidate after the summary and an explicit YES.
    #   INCONCLUSIVE = local RAS trouble, credentials, split tunneling,
    #                  duplicate names, or an uncertain state; always keep.
    param(
        [Parameter(Mandatory)][pscustomobject]$ExistingProfile,
        [Parameter(Mandatory)][string]$RasdialPath,
        [Parameter(Mandatory)][string]$CurlPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$BaselineIPv4,
        [Parameter(Mandatory)][AllowEmptyString()][string]$BaselineIPv6,
        [Parameter(Mandatory)][ValidateSet('IPv4', 'IPv6')][string]$RouteTestFamily,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][int]$ConnectTimeoutSec,
        [Parameter(Mandatory)][int]$TcpTimeoutMs,
        [Parameter(Mandatory)][int]$SpeedTimeoutSec,
        [Parameter(Mandatory)][int]$SpeedSamples,
        [Parameter(Mandatory)][int]$SpeedDownloadBytes,
        [Parameter(Mandatory)][string]$SpeedTestUrl,
        [Parameter(Mandatory)][string]$LatencyTestHost,
        [Parameter(Mandatory)][int]$LatencyTestPort,
        [Parameter(Mandatory)][int]$LatencyTimeoutMs,
        [Parameter(Mandatory)][int]$LatencySamples,
        [Parameter(Mandatory)][int]$RasRecoveryDelaySec,
        [Parameter(Mandatory)][int]$Ras633Retries,
        [Parameter(Mandatory)][int]$TransientDialRetryDelaySec,
        [Parameter(Mandatory)][int]$ExistingTcpAttempts,
        [Parameter(Mandatory)][int]$ExistingTcpRetryDelaySec,
        [Parameter(Mandatory)][ValidateSet('Balanced', 'Conservative')][string]$ExistingRemovalMode,
        [switch]$TrySstpAfterTcpTimeout
    )

    $record = [ordered]@{
        ProfileName            = [string]$ExistingProfile.Name
        Scope                  = [string]$ExistingProfile.Scope
        ServerAddress          = ([string]$ExistingProfile.ServerAddress).Trim()
        Host                   = ''
        Port                   = $null
        WasConnectedAtStart    = ([string]$ExistingProfile.ConnectionStatus -eq 'Connected')
        TcpReachable           = $false
        TcpConnectMs           = $null
        TcpProbeError          = ''
        TcpAttempts            = 0
        CredentialSource       = ''
        DialAttempts           = 0
        VPNConnected           = $false
        VPNConnectSeconds      = $null
        BaselineIPv4           = $BaselineIPv4
        VPNIPv4                = ''
        IPv4Changed            = 'Unknown'
        BaselineIPv6           = $BaselineIPv6
        VPNIPv6                = ''
        IPv6Changed            = 'Unknown'
        RouteVerificationFamily = ''
        VPNPublicIP            = ''
        PublicIPChanged        = 'Unknown'
        VPNLatencyMs           = $null
        VPNLatencyMethod       = ''
        VPNLatencySamples      = 0
        VPNLatencyMin          = $null
        VPNLatencyMax          = $null
        VPNLatencyError        = ''
        DownloadMbps           = $null
        DownloadMB             = $null
        DownloadSeconds        = $null
        DownloadComplete       = $false
        DownloadSamples        = 0
        DownloadMinMbps        = $null
        DownloadMaxMbps        = $null
        DownloadError          = ''
        InternetReachable      = $false
        InternetCheckUrl       = ''
        Status                 = ''
        Verdict                = ''
        PlannedAction          = ''
        ActionTaken            = ''
        PostTestDisconnectFailed = $false
        Error                  = ''
    }
    $profileName = [string]$ExistingProfile.Name
    $testStarted = $false

    # Same-name User/AllUser collisions and split-tunneling profiles cannot be
    # judged safely by rasdial + public-IP comparison. Keep both untouched.
    if ([bool]$ExistingProfile.NameCollision) {
        $record.Status = 'DUPLICATE_NAME_ACROSS_PHONEBOOKS'
        $record.Verdict = 'INCONCLUSIVE'
        $record.PlannedAction = 'KEEP'
        $record.ActionTaken = 'KEPT'
        $record.Error = 'The same VPN profile name exists in both User and AllUser phonebooks. Windows rasdial cannot select the scope explicitly; both profiles were left untouched.'
        return [pscustomobject]@{ Record = [pscustomobject]$record }
    }
    if ([bool]$ExistingProfile.SplitTunneling) {
        $record.Status = 'SPLIT_TUNNELING_PROFILE_SKIPPED'
        $record.Verdict = 'INCONCLUSIVE'
        $record.PlannedAction = 'KEEP'
        $record.ActionTaken = 'KEPT'
        $record.Error = 'Split tunneling is enabled. Public-IP comparison cannot reliably determine whether this profile is working; it was not tested for automatic removal.'
        return [pscustomobject]@{ Record = [pscustomobject]$record }
    }

    try {
        $parsedAddress = Parse-SstpServerAddress -Text ([string]$record.ServerAddress)
        if (-not $parsedAddress) {
            $record.Status = 'PROFILE_ADDRESS_UNPARSEABLE'
            $record.Verdict = 'INCONCLUSIVE'
            $record.PlannedAction = 'KEEP'
            $record.ActionTaken = 'KEPT'
            $record.Error = 'The stored ServerAddress could not be parsed safely; the profile was kept.'
            return [pscustomobject]@{ Record = [pscustomobject]$record }
        }
        $record.Host = $parsedAddress.Host
        $record.Port = $parsedAddress.Port

        # Disconnect an already-connected profile first so the real dial is
        # exercised from a clean state. The baseline prompt normally prevents
        # this path, but a profile may connect between the prompt and its turn.
        if ($record.WasConnectedAtStart) {
            Write-Host '  currently connected; disconnecting first ...' -ForegroundColor DarkYellow
            $testStarted = $true
            $startDisconnected = Disconnect-ExistingVpnProfile -ProfileName $profileName -RasdialPath $RasdialPath -Scope ([string]$ExistingProfile.Scope) -WaitSeconds 20
            if (-not $startDisconnected) {
                $record.Status = 'DISCONNECT_FAILED_STATE_UNCERTAIN'
                $record.Verdict = 'INCONCLUSIVE'
                $record.PlannedAction = 'KEEP'
                $record.ActionTaken = 'KEPT'
                $record.Error = 'The profile is connected and could not be disconnected within 20 seconds; removing an active profile is unsafe, so it was kept and later profile checks are paused.'
                return [pscustomobject]@{ Record = [pscustomobject]$record }
            }
        }

        # Multiple TCP probes reduce false positives from a transient packet
        # loss. A confirmed TCP failure is remote evidence, not a local RAS
        # error, so Balanced mode may mark it for removal.
        $tcp = $null
        for ($attempt = 1; $attempt -le $ExistingTcpAttempts; $attempt++) {
            $tcp = Test-TcpPort -HostName $parsedAddress.Host -PortNumber $parsedAddress.Port -TimeoutMs $TcpTimeoutMs
            $record.TcpAttempts = $attempt
            $record.TcpReachable = [bool]$tcp.Reachable
            $record.TcpConnectMs = $tcp.Milliseconds
            $record.TcpProbeError = [string]$tcp.Error
            if ($tcp.Reachable) { break }
            if ($attempt -lt $ExistingTcpAttempts -and $ExistingTcpRetryDelaySec -gt 0) {
                Start-Sleep -Seconds $ExistingTcpRetryDelaySec
            }
        }

        if (-not $tcp.Reachable) {
            if ($TrySstpAfterTcpTimeout -and ([string]$tcp.Error -eq 'TCP timeout')) {
                Write-Host ("  TCP probe timed out after {0} attempt(s); attempting the real SSTP connection anyway" -f $ExistingTcpAttempts) -ForegroundColor Yellow
            } else {
                $record.Status = 'TCP_UNREACHABLE'
                $record.Error = ("TCP/{0} was unreachable after {1} attempt(s): {2}" -f $parsedAddress.Port, $ExistingTcpAttempts, $tcp.Error)
                if ($ExistingRemovalMode -eq 'Balanced') {
                    $record.Verdict = 'REJECT'
                    $record.PlannedAction = 'DELETE'
                    Write-Host ("  TCP/{0} unreachable after {1} attempts; marked for removal" -f $parsedAddress.Port, $ExistingTcpAttempts) -ForegroundColor DarkYellow
                } else {
                    $record.Verdict = 'INCONCLUSIVE'
                    $record.PlannedAction = 'KEEP'
                    $record.ActionTaken = 'KEPT'
                    Write-Host ("  TCP/{0} unreachable after {1} attempts; kept in Conservative mode" -f $parsedAddress.Port, $ExistingTcpAttempts) -ForegroundColor Yellow
                }
                return [pscustomobject]@{ Record = [pscustomobject]$record }
            }
        }

        # Real SSTP dial. Stored Windows credentials first; on RAS 691/649
        # retry with -Username/-Password. Remote terminations (619/628/629/631)
        # get a delayed retry because SoftEther/VPN Gate servers often refuse an
        # immediate reconnect or mask a credential refusal as 628.
        $testStarted = $true
        $transientRasCodes = @(619, 628, 629, 631)
        $dialAttempts = 0
        $rasDisconnectTimedOut = $false
        $usingFallbackCredentials = $false
        $credentialSource = 'Stored Windows credentials'
        $attemptLog = [System.Collections.Generic.List[string]]::new()
        $transientRetryCount = 0
        $dial = $null

        do {
            $dialAttempts++
            $dialArguments = if ($usingFallbackCredentials) { @($profileName, $Username, $Password) } else { @($profileName) }
            $dial = Invoke-NativeTimed -FilePath $RasdialPath -Arguments $dialArguments -TimeoutSec $ConnectTimeoutSec
            $priorSeconds = 0.0
            if ($null -ne $record.VPNConnectSeconds) { $priorSeconds = [double]$record.VPNConnectSeconds }
            $record.VPNConnectSeconds = [math]::Round(($priorSeconds + [double]$dial.Seconds), 2)
            $record.CredentialSource = $credentialSource
            if ($dial.TimedOut -or $dial.ExitCode -eq 0) { break }

            $dialText = (([string]$dial.StdOut + ' ' + [string]$dial.StdErr).Trim() -replace '\s+', ' ')
            $attemptDetail = $dialText
            if ($attemptDetail.Length -gt 300) { $attemptDetail = $attemptDetail.Substring(0, 300) }
            $attemptLog.Add(("attempt {0} ({1}): {2}" -f $dialAttempts, $credentialSource, $attemptDetail))
            $parsedRasCode = Get-RasErrorCode -Text $dialText -ProcessExitCode ([int]$dial.ExitCode)

            if (-not $usingFallbackCredentials -and $parsedRasCode -in @(691, 649)) {
                $credentialSource = 'Fallback vpn/vpn (RAS 691/649 on the stored credentials)'
                $usingFallbackCredentials = $true
                Write-Host '  stored credentials were refused (RAS 691/649); retrying once with the configured -Username/-Password' -ForegroundColor Yellow
                continue
            }
            if ($parsedRasCode -eq 633 -and $dialAttempts -le $Ras633Retries) {
                Write-Host ("  Local RAS 633 on attempt {0}; issuing a disconnect and retrying after {1}s" -f $dialAttempts, $RasRecoveryDelaySec) -ForegroundColor Yellow
                $disconnectAttempt = $null
                try {
                    $disconnectAttempt = Invoke-NativeTimed -FilePath $RasdialPath -Arguments @($profileName, '/disconnect') -TimeoutSec 12
                } catch { }
                if ($disconnectAttempt -and $disconnectAttempt.TimedOut) {
                    $rasDisconnectTimedOut = $true
                    break
                }
                Start-Sleep -Seconds $RasRecoveryDelaySec
                continue
            }
            if ($parsedRasCode -in $transientRasCodes -and $transientRetryCount -lt 2) {
                $transientRetryCount++
                if (-not $usingFallbackCredentials -and $transientRetryCount -ge 2) {
                    $credentialSource = ('Fallback vpn/vpn (remote terminated the stored-credential dials with RAS {0})' -f ($transientRasCodes -join '/'))
                    $usingFallbackCredentials = $true
                    Write-Host ("  remote terminated the stored-credential dial twice (RAS {0}); retrying with the configured -Username/-Password" -f $parsedRasCode) -ForegroundColor Yellow
                } else {
                    Write-Host ("  remote terminated the dial (RAS {0}); waiting {1}s and retrying the same credentials" -f $parsedRasCode, $TransientDialRetryDelaySec) -ForegroundColor Yellow
                }
                if ($TransientDialRetryDelaySec -gt 0) { Start-Sleep -Seconds $TransientDialRetryDelaySec }
                continue
            }
            break
        } while ($dialAttempts -le ($Ras633Retries + 4))

        $record.DialAttempts = $dialAttempts

        if ($rasDisconnectTimedOut) {
            $record.Status = 'RAS_RECOVERY_TIMEOUT_STATE_UNCERTAIN'
            $record.Verdict = 'INCONCLUSIVE'
            $record.PlannedAction = 'KEEP'
            $record.ActionTaken = 'KEPT'
            $record.Error = 'The rasdial /disconnect command timed out during recovery after local RAS 633. The profile was kept and later profile checks are paused because Windows RAS state may still be pending.'
            return [pscustomobject]@{ Record = [pscustomobject]$record }
        }

        if ($dial.TimedOut) {
            $record.Status = 'VPN_CONNECT_TIMEOUT_RAS_STATE_UNCERTAIN'
            $record.Verdict = 'INCONCLUSIVE'
            $record.PlannedAction = 'KEEP'
            $record.ActionTaken = 'KEPT'
            $record.Error = "rasdial was forcibly stopped after $ConnectTimeoutSec seconds before Windows returned a final result. The profile was kept and later profile checks are paused because RAS state may still be pending."
            return [pscustomobject]@{ Record = [pscustomobject]$record }
        }

        if ($dial.ExitCode -ne 0) {
            $detail = (([string]$dial.StdOut + ' ' + [string]$dial.StdErr).Trim() -replace '\s+', ' ')
            if ([string]::IsNullOrWhiteSpace($detail)) { $detail = "rasdial exit code $($dial.ExitCode); no diagnostic text was returned." }
            if ($detail.Length -gt 500) { $detail = $detail.Substring(0, 500) }
            $errorText = $detail
            if ($attemptLog.Count -gt 0) {
                $history = ($attemptLog -join ' | ')
                $errorText = $history + ' | FINAL: ' + $detail
            }
            if ($errorText.Length -gt 1200) { $errorText = $errorText.Substring(0, 1200) }
            $record.Error = $errorText
            $rasCode = Get-RasErrorCode -Text $detail -ProcessExitCode ([int]$dial.ExitCode)

            if ($rasCode -eq 633) {
                $record.Status = 'LOCAL_RAS_ERROR_633_AFTER_RETRY'
                $record.Verdict = 'INCONCLUSIVE'
                $record.PlannedAction = 'KEEP'
                $record.ActionTaken = 'KEPT'
                Write-Host ("  Local RAS 633 persisted after retry; profile health is inconclusive: {0}" -f $detail) -ForegroundColor Red
                Show-Ras633Diagnostics
            } elseif ($rasCode -in @(691, 649)) {
                $record.Status = 'CREDENTIALS_REJECTED'
                $record.Verdict = 'INCONCLUSIVE'
                $record.PlannedAction = 'KEEP'
                $record.ActionTaken = 'KEPT'
                $record.Error = (([string]$record.Error + ' The stored credentials and the configured -Username/-Password were both refused; the profile was kept so the credentials can be corrected.').Trim())
                Write-Host ("  credentials were refused; profile kept: {0}" -f $detail) -ForegroundColor Yellow
            } elseif ($rasCode -in $transientRasCodes) {
                $record.Status = 'VPN_CONNECT_REMOTE_TERMINATED'
                if ($ExistingRemovalMode -eq 'Balanced') {
                    $record.Verdict = 'REJECT'
                    $record.PlannedAction = 'DELETE'
                    Write-Host ("  the remote terminated every dial attempt (last RAS code {0}); marked for removal" -f $rasCode) -ForegroundColor DarkYellow
                } else {
                    $record.Verdict = 'INCONCLUSIVE'
                    $record.PlannedAction = 'KEEP'
                    $record.ActionTaken = 'KEPT'
                    $record.Error = (([string]$record.Error + ' Remote termination is treated as inconclusive in Conservative mode; the profile was kept.').Trim())
                    Write-Host ("  the remote terminated every dial attempt (last RAS code {0}); kept in Conservative mode" -f $rasCode) -ForegroundColor Yellow
                }
            } elseif ($rasCode -eq 638 -or $dial.ExitCode -eq -2147014836 -or $detail -match '(?i)connection attempt failed.*period of time|timed out|timeout') {
                $record.Status = 'VPN_CONNECT_TIMEOUT'
                if ($ExistingRemovalMode -eq 'Balanced') {
                    $record.Verdict = 'REJECT'
                    $record.PlannedAction = 'DELETE'
                    Write-Host ("  SSTP/network timeout; marked for removal: {0}" -f $detail) -ForegroundColor DarkYellow
                } else {
                    $record.Verdict = 'INCONCLUSIVE'
                    $record.PlannedAction = 'KEEP'
                    $record.ActionTaken = 'KEPT'
                    $record.Error = (([string]$record.Error + ' The dial timeout is treated as inconclusive in Conservative mode; the profile was kept.').Trim())
                    Write-Host ("  SSTP/network timeout; kept in Conservative mode: {0}" -f $detail) -ForegroundColor Yellow
                }
            } else {
                $record.Status = 'VPN_CONNECT_FAILED'
                $record.Verdict = 'INCONCLUSIVE'
                $record.PlannedAction = 'KEEP'
                $record.ActionTaken = 'KEPT'
                $record.Error = (([string]$record.Error + ' A failed RAS dial may reflect credentials, transient network state, or Windows RAS; the existing profile was kept.').Trim())
                Write-Host ("  VPN dial failed (process exit {0}; parsed RAS code {1}): {2}" -f $dial.ExitCode, $rasCode, $detail) -ForegroundColor DarkYellow
            }

            if ($record.Error.Length -gt 1400) { $record.Error = $record.Error.Substring(0, 1400) }
            return [pscustomobject]@{ Record = [pscustomobject]$record }
        }

        # Connected: verify the route, measure latency, and run the v16 download
        # test. A partial download sample still counts as a real measurement;
        # requiring the full requested transfer would reject slow working servers.
        $record.VPNConnected = $true
        Start-Sleep -Seconds 2

        $vpnIp4 = ''
        $vpnIp6 = ''
        if ($BaselineIPv4) { $vpnIp4 = Get-PublicIpRobust -CurlPath $CurlPath -AddressFamily IPv4 }
        if ($BaselineIPv6) { $vpnIp6 = Get-PublicIpRobust -CurlPath $CurlPath -AddressFamily IPv6 }
        $record.VPNIPv4 = $vpnIp4
        $record.VPNIPv6 = $vpnIp6

        $baselineFamilies = 0
        $comparableFamilies = 0
        $changedFamilies = 0
        if ($BaselineIPv4) {
            $baselineFamilies++
            if ($vpnIp4) {
                $comparableFamilies++
                $record.IPv4Changed = if ($BaselineIPv4 -ne $vpnIp4) { 'Yes' } else { 'No' }
                if ($BaselineIPv4 -ne $vpnIp4) { $changedFamilies++ }
            }
        }
        if ($BaselineIPv6) {
            $baselineFamilies++
            if ($vpnIp6) {
                $comparableFamilies++
                $record.IPv6Changed = if ($BaselineIPv6 -ne $vpnIp6) { 'Yes' } else { 'No' }
                if ($BaselineIPv6 -ne $vpnIp6) { $changedFamilies++ }
            }
        }

        if ($changedFamilies -gt 0) {
            $record.PublicIPChanged = 'Yes'
            $changedLabels = @()
            if ($record.IPv4Changed -eq 'Yes') { $changedLabels += 'IPv4' }
            if ($record.IPv6Changed -eq 'Yes') { $changedLabels += 'IPv6' }
            $record.RouteVerificationFamily = ($changedLabels -join '+')
            $record.VPNPublicIP = (@(
                if ($record.IPv4Changed -eq 'Yes') { "IPv4=$vpnIp4" }
                if ($record.IPv6Changed -eq 'Yes') { "IPv6=$vpnIp6" }
            ) -join '; ')
        } elseif ($baselineFamilies -gt 0 -and $comparableFamilies -eq $baselineFamilies) {
            $record.PublicIPChanged = 'No'
            $record.RouteVerificationFamily = if ($baselineFamilies -eq 2) { 'IPv4+IPv6' } elseif ($BaselineIPv4) { 'IPv4' } else { 'IPv6' }
            $record.VPNPublicIP = (@(
                if ($vpnIp4) { "IPv4=$vpnIp4" }
                if ($vpnIp6) { "IPv6=$vpnIp6" }
            ) -join '; ')
        } else {
            $record.PublicIPChanged = 'Unknown'
            $record.RouteVerificationFamily = 'Incomplete comparison'
        }

        $tunnelLatency = Measure-TunnelLatency -HostName $LatencyTestHost -Port $LatencyTestPort -TimeoutMs $LatencyTimeoutMs -Samples $LatencySamples
        $record.VPNLatencyMs = $tunnelLatency.LatencyMs
        $record.VPNLatencyMethod = $tunnelLatency.Method
        $record.VPNLatencySamples = $tunnelLatency.SuccessfulSamples
        $record.VPNLatencyMin = $tunnelLatency.Min
        $record.VPNLatencyMax = $tunnelLatency.Max
        $record.VPNLatencyError = $tunnelLatency.Error
        $latencyText = if ($null -ne $record.VPNLatencyMs) {
            ('{0} ms ({1})' -f $record.VPNLatencyMs, $record.VPNLatencyMethod)
        } else {
            'latency unavailable'
        }

        $downloadFamily = if ($record.IPv6Changed -eq 'Yes' -and $record.IPv4Changed -ne 'Yes') { 'IPv6' } else { $RouteTestFamily }
        $download = Measure-DownloadSpeed -CurlPath $CurlPath -AddressFamily $downloadFamily `
            -SpeedTestUrl $SpeedTestUrl -DownloadBytes $SpeedDownloadBytes `
            -Samples $SpeedSamples -TimeoutSec $SpeedTimeoutSec
        $record.DownloadSamples = $download.SuccessfulSamples
        $record.DownloadMinMbps = $download.MinMbps
        $record.DownloadMaxMbps = $download.MaxMbps
        $record.DownloadError = if (-not [string]::IsNullOrWhiteSpace([string]$download.Error)) {
            $download.Error
        } else {
            [string]$download.SampleErrors
        }

        if ($null -ne $download.MedianMbps) {
            $record.DownloadMbps = $download.MedianMbps
            $record.DownloadMB = if ($download.SuccessfulSamples -gt 0) {
                [math]::Round(($download.TotalMB / $download.SuccessfulSamples), 2)
            } else { $null }
            $record.DownloadSeconds = if ($download.SuccessfulSamples -gt 0) {
                [math]::Round(($download.TotalSeconds / $download.SuccessfulSamples), 2)
            } else { $null }
            $record.DownloadComplete = [bool]$download.AllComplete

            if ($record.PublicIPChanged -eq 'Yes') {
                $record.Status = 'WORKING_TUNNEL_AND_INTERNET'
                $record.Verdict = 'ACCEPT'
                $record.PlannedAction = 'KEEP'
                $record.ActionTaken = 'KEPT'
                Write-Host ("  OK  {0} Mbps; {1}; public IP changed ({2})" -f $record.DownloadMbps, $latencyText, $(if ($record.DownloadComplete) { 'complete sample' } else { 'partial sample' })) -ForegroundColor Green
            } elseif ($record.PublicIPChanged -eq 'No') {
                $record.Status = 'CONNECTED_ROUTE_UNCONFIRMED'
                $record.Verdict = 'REJECT'
                $record.PlannedAction = 'DELETE'
                $record.Error = 'The tunnel connected and a download succeeded, but every comparable public IP remained unchanged. The profile is not routing traffic through the VPN.'
                Write-Host ("  Connected; {0} Mbps, {1}, but all comparable public IPs remained unchanged; marked for removal" -f $record.DownloadMbps, $latencyText) -ForegroundColor Yellow
            } else {
                $record.Status = 'CONNECTED_IP_UNKNOWN'
                $record.Verdict = 'INCONCLUSIVE'
                $record.PlannedAction = 'KEEP'
                $record.ActionTaken = 'KEPT'
                $record.Error = 'A download succeeded, but public-IP comparison could not be completed. The profile was kept.'
                Write-Host ("  Connected; {0} Mbps, {1}, public IP comparison incomplete; keeping profile" -f $record.DownloadMbps, $latencyText) -ForegroundColor Yellow
            }
        } else {
            $internetProbe = Test-InternetConnectivity -CurlPath $CurlPath -AddressFamily $downloadFamily
            $record.InternetReachable = [bool]$internetProbe.Reachable
            $record.InternetCheckUrl = [string]$internetProbe.Url
            $detail = [string]$download.SampleErrors
            if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'No usable download sample was obtained from the configured speed-test endpoint.' }

            if ($internetProbe.Reachable) {
                if ($record.PublicIPChanged -eq 'Yes') {
                    $record.Status = 'WORKING_TUNNEL_CONNECTIVITY_ONLY'
                    $record.Verdict = 'ACCEPT'
                    $record.PlannedAction = 'KEEP'
                    $record.ActionTaken = 'KEPT'
                    $record.Error = ('Internet connectivity was verified through the tunnel ({0}, HTTP {1}); the speed endpoint itself was unavailable.' -f $internetProbe.Url, $internetProbe.HttpCode)
                    Write-Host ("  OK  internet reachable through the tunnel ({0}); speed endpoint unavailable, profile kept" -f $latencyText) -ForegroundColor Green
                } elseif ($record.PublicIPChanged -eq 'No') {
                    $record.Status = 'CONNECTED_ROUTE_UNCONFIRMED'
                    $record.Verdict = 'REJECT'
                    $record.PlannedAction = 'DELETE'
                    $record.Error = 'The tunnel connected and internet probes succeeded, but every comparable public IP remained unchanged. The profile is not routing traffic through the VPN.'
                    Write-Host '  Connected and internet reachable, but public IP unchanged; marked for removal' -ForegroundColor Yellow
                } else {
                    $record.Status = 'CONNECTED_IP_UNKNOWN'
                    $record.Verdict = 'INCONCLUSIVE'
                    $record.PlannedAction = 'KEEP'
                    $record.ActionTaken = 'KEPT'
                    $record.Error = 'Internet probes succeeded, but public-IP comparison could not be completed. The profile was kept.'
                    Write-Host '  Connected and internet reachable, but public IP unknown; keeping profile' -ForegroundColor Yellow
                }
            } else {
                $record.DownloadError = $detail
                if ($record.PublicIPChanged -eq 'No') {
                    $record.Status = 'CONNECTED_NO_INTERNET'
                    if ($ExistingRemovalMode -eq 'Balanced') {
                        $record.Verdict = 'REJECT'
                        $record.PlannedAction = 'DELETE'
                        $record.Error = 'The tunnel connected, but the public IP did not change and no internet probe succeeded. The profile is not providing a working VPN route.'
                        Write-Host '  Connected, but no internet and no route change; marked for removal' -ForegroundColor Yellow
                    } else {
                        $record.Verdict = 'INCONCLUSIVE'
                        $record.PlannedAction = 'KEEP'
                        $record.ActionTaken = 'KEPT'
                        $record.Error = 'The tunnel connected, but no internet probe succeeded and the public IP did not change. Conservative mode kept the profile.'
                        Write-Host '  Connected, but no internet and no route change; kept in Conservative mode' -ForegroundColor Yellow
                    }
                } else {
                    $record.Status = 'CONNECTED_NETWORK_TESTS_INCONCLUSIVE'
                    $record.Verdict = 'INCONCLUSIVE'
                    $record.PlannedAction = 'KEEP'
                    $record.ActionTaken = 'KEPT'
                    $record.Error = (([string]$detail + ' Google/connectivity probes also failed; this is inconclusive because the destinations may be filtered. The profile was kept.').Trim())
                    Write-Host ("  Connected ({0}), but no internet probe succeeded; keeping profile as inconclusive" -f $latencyText) -ForegroundColor Yellow
                }
            }
        }
    } catch {
        $caughtError = $_.Exception.GetBaseException().Message
        if ([string]::IsNullOrWhiteSpace([string]$record.Status)) {
            $record.Status = 'PROFILE_OR_TEST_ERROR'
            $record.Verdict = 'INCONCLUSIVE'
            $record.PlannedAction = 'KEEP'
        }
        $record.Error = (([string]$record.Error + ' ' + $caughtError).Trim())
        if ($record.Error.Length -gt 700) { $record.Error = $record.Error.Substring(0, 700) }
        $record.ActionTaken = 'KEPT'
        Write-Host '  Error while testing this profile; it will be kept as inconclusive' -ForegroundColor Red
    } finally {
        # Only disconnect if this profile was actually dialed or was connected at
        # the start. Early skips (duplicate names, split tunneling, unparseable
        # addresses) must not touch any phonebook entry.
        if ($testStarted) {
            $postDisconnected = Disconnect-ExistingVpnProfile -ProfileName $profileName -RasdialPath $RasdialPath -Scope ([string]$ExistingProfile.Scope) -WaitSeconds 20
            if (-not $postDisconnected) {
                $record.PostTestDisconnectFailed = $true
                $record.Verdict = 'INCONCLUSIVE'
                $record.PlannedAction = 'KEEP'
                $record.ActionTaken = 'KEPT'
                $record.Error = (([string]$record.Error + " Profile '$profileName' still reports Connected after its test; Windows RAS may be busy, so it cannot be removed.").Trim())
                if ($record.Error.Length -gt 900) { $record.Error = $record.Error.Substring(0, 900) }
                Write-Warning ("Profile '{0}' could not be disconnected after its test; later profile checks are paused." -f $profileName)
            }
        }
    }

    return [pscustomobject]@{ Record = [pscustomobject]$record }
}

function Invoke-ExistingProfileVerification {
    # Orchestrates the existing-profile verification phase:
    #   1. collect Windows SSTP VPN profiles (both phonebooks),
    #   2. confirm the no-VPN baseline interactively,
    #   3. test every profile with Test-ExistingSstpProfile,
    #   4. show the summary, ask for an explicit YES, remove rejected profiles,
    #   5. save the CSV report and return the counters.
    param(
        [Parameter(Mandatory)][ValidateSet('Standalone', 'PruneFirst')][string]$Mode,
        [Parameter(Mandatory)][string]$RasdialPath,
        [Parameter(Mandatory)][string]$CurlPath,
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][int]$ConnectTimeoutSec,
        [Parameter(Mandatory)][int]$TcpTimeoutMs,
        [Parameter(Mandatory)][int]$SpeedTimeoutSec,
        [Parameter(Mandatory)][int]$SpeedSamples,
        [Parameter(Mandatory)][int]$SpeedDownloadBytes,
        [Parameter(Mandatory)][string]$SpeedTestUrl,
        [Parameter(Mandatory)][string]$LatencyTestHost,
        [Parameter(Mandatory)][int]$LatencyTestPort,
        [Parameter(Mandatory)][int]$LatencyTimeoutMs,
        [Parameter(Mandatory)][int]$LatencySamples,
        [Parameter(Mandatory)][int]$RasRecoveryDelaySec,
        [Parameter(Mandatory)][int]$Ras633Retries,
        [Parameter(Mandatory)][int]$TransientDialRetryDelaySec,
        [Parameter(Mandatory)][int]$ExistingTcpAttempts,
        [Parameter(Mandatory)][int]$ExistingTcpRetryDelaySec,
        [Parameter(Mandatory)][ValidateSet('Balanced', 'Conservative')][string]$ExistingRemovalMode,
        [Parameter(Mandatory)][bool]$ContinueAfterLocalRas633,
        [Parameter(Mandatory)][bool]$TrySstpAfterTcpTimeout,
        [Parameter(Mandatory)][bool]$ReportOnly
    )

    $phaseLabel = if ($Mode -eq 'Standalone') {
        'VERIFY EXISTING WINDOWS SSTP VPN PROFILES'
    } else {
        'PRUNE FIRST: VERIFY EXISTING WINDOWS SSTP VPN PROFILES'
    }
    Write-Host ''
    Write-Host ("================ {0} ================" -f $phaseLabel) -ForegroundColor Cyan
    Write-Host 'The test checks TCP, a real SSTP dial, IPv4/IPv6 public-IP changes, tunnel latency, and a download test.' -ForegroundColor DarkGray
    Write-Host ("Removal mode: {0}. Profiles are removed only after the summary and an explicit YES." -f $ExistingRemovalMode) -ForegroundColor DarkGray

    $allProfiles = @(Get-ExistingSstpVpnProfiles)
    $sstpProfiles = @($allProfiles | Where-Object { [string]$_.TunnelType -ieq 'Sstp' })
    $nonSstpProfiles = @($allProfiles | Where-Object { [string]$_.TunnelType -ine 'Sstp' })

    $emptyResult = [pscustomobject]@{
        Checked = 0; Accepted = 0; Rejected = 0; Inconclusive = 0
        Deleted = 0; DeleteFailed = 0; CsvPath = ''
    }

    if ($allProfiles.Count -eq 0) {
        Write-Host 'No Windows VPN profiles were found; there is nothing to verify.' -ForegroundColor Yellow
        return $emptyResult
    }
    if ($sstpProfiles.Count -eq 0) {
        Write-Host 'No SSTP-tunnel Windows VPN profiles were found; there is nothing to verify.' -ForegroundColor Yellow
        foreach ($nonSstp in $nonSstpProfiles) {
            Write-Host ("  skipped (tunnel type {0}): {1}" -f $nonSstp.TunnelType, $nonSstp.Name) -ForegroundColor DarkGray
        }
        return $emptyResult
    }

    Write-Host ("Found {0} Windows VPN profile(s): {1} SSTP (will be tested), {2} non-SSTP (skipped)." -f $allProfiles.Count, $sstpProfiles.Count, $nonSstpProfiles.Count) -ForegroundColor Cyan

    Write-Host ''
    Write-Host 'IMPORTANT: turn OFF your temporary/ordinary VPN (for example Cloudflare WARP, SoftEther, or another VPN).' -ForegroundColor Yellow
    $baselineIPv4 = ''
    $baselineIPv6 = ''
    $routeTestFamily = 'IPv4'
    $baselineAvailable = $false

    while ($true) {
        $confirmation = (Read-Host 'After disconnecting all other VPNs, press Enter to verify the baseline and start profile tests (or type Q to quit)').Trim()
        if ($confirmation -match '^(?i:q)$') { throw 'Stopped by user before existing-profile verification.' }

        $activeConnections = @(Get-ActiveWindowsVpnConnections)
        if ($activeConnections.Count -gt 0) {
            $names = ($activeConnections | ForEach-Object { $_.Name }) -join ', '
            Write-Warning "Windows still reports these VPN connections as active: $names. Disconnect them and press Enter again."
            continue
        }

        Start-Sleep -Seconds 2
        $baselineIPv4 = Get-PublicIpRobust -CurlPath $CurlPath -AddressFamily IPv4
        $baselineIPv6 = Get-PublicIpRobust -CurlPath $CurlPath -AddressFamily IPv6
        if (-not $baselineIPv4 -and -not $baselineIPv6) {
            Write-Warning 'Could not read a public IPv4 or IPv6 address for the current connection. Ensure the ordinary VPN is off and that the internet is working.'
            $manual = (Read-Host 'Type YES only if you have manually confirmed all other VPNs are disconnected; otherwise press Enter to retry').Trim()
            if ($manual -ceq 'YES') {
                Write-Warning 'Manual confirmation cannot replace a measurable baseline IP. TCP/dial tests will continue, but any profile that connects will be kept as INCONCLUSIVE.'
                break
            }
            continue
        }
        $routeTestFamily = if ($baselineIPv4) { 'IPv4' } else { 'IPv6' }
        $baselineAvailable = $true
        break
    }

    $baselineIPv4Display = if ($baselineIPv4) { $baselineIPv4 } else { '(unavailable)' }
    $baselineIPv6Display = if ($baselineIPv6) { $baselineIPv6 } else { '(unavailable)' }
    Write-Host "Baseline public IPv4: $baselineIPv4Display; IPv6: $baselineIPv6Display; primary route check: $routeTestFamily" -ForegroundColor DarkGray
    if (-not $baselineAvailable) {
        Write-Host 'No measurable baseline IP: connected profiles will be kept as INCONCLUSIVE. TCP/dial failures are still tested.' -ForegroundColor Yellow
    }
    if ($ReportOnly) {
        Write-Host 'REPORT-ONLY mode: rejected profiles will be listed, but nothing will be deleted.' -ForegroundColor Yellow
    } else {
        Write-Host 'Rejected profiles are deleted only after the summary table and an explicit YES confirmation.' -ForegroundColor DarkGray
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $index = 0
    $stopFurtherChecks = $false
    $stopReason = ''

    foreach ($existingProfile in $sstpProfiles) {
        $index++
        Write-Progress -Activity 'Verifying existing Windows SSTP VPN profiles' -Status ("{0}/{1}  {2}" -f $index, $sstpProfiles.Count, $existingProfile.Name) -PercentComplete ([int](100 * $index / $sstpProfiles.Count))
        Write-Host ("[{0}/{1}] '{2}' (Scope: {3}, ServerAddress='{4}')" -f $index, $sstpProfiles.Count, $existingProfile.Name, $existingProfile.Scope, $existingProfile.ServerAddress) -NoNewline

        if ($stopFurtherChecks) {
            $results.Add([pscustomobject][ordered]@{
                ProfileName = [string]$existingProfile.Name
                Scope = [string]$existingProfile.Scope
                ServerAddress = ([string]$existingProfile.ServerAddress).Trim()
                Host = ''
                Port = $null
                WasConnectedAtStart = ([string]$existingProfile.ConnectionStatus -eq 'Connected')
                TcpReachable = $false
                TcpConnectMs = $null
                TcpProbeError = ''
                TcpAttempts = 0
                CredentialSource = ''
                DialAttempts = 0
                VPNConnected = $false
                VPNConnectSeconds = $null
                BaselineIPv4 = $baselineIPv4
                VPNIPv4 = ''
                IPv4Changed = 'Unknown'
                BaselineIPv6 = $baselineIPv6
                VPNIPv6 = ''
                IPv6Changed = 'Unknown'
                RouteVerificationFamily = ''
                VPNPublicIP = ''
                PublicIPChanged = 'Unknown'
                VPNLatencyMs = $null
                VPNLatencyMethod = ''
                VPNLatencySamples = 0
                VPNLatencyMin = $null
                VPNLatencyMax = $null
                VPNLatencyError = ''
                DownloadMbps = $null
                DownloadMB = $null
                DownloadSeconds = $null
                DownloadComplete = $false
                DownloadSamples = 0
                DownloadMinMbps = $null
                DownloadMaxMbps = $null
                DownloadError = ''
                InternetReachable = $false
                InternetCheckUrl = ''
                Status = 'SKIPPED_AFTER_RAS_STATE_UNCERTAIN'
                Verdict = 'INCONCLUSIVE'
                PlannedAction = 'KEEP'
                ActionTaken = 'KEPT'
                PostTestDisconnectFailed = $false
                Error = ("Skipped because the prior attempt left RAS state uncertain ({0})." -f $stopReason)
            })
            Write-Host ("  skipped after {0}" -f $stopReason) -ForegroundColor Yellow
            continue
        }

        $testParams = @{
            ExistingProfile = $existingProfile
            RasdialPath = $RasdialPath
            CurlPath = $CurlPath
            BaselineIPv4 = $baselineIPv4
            BaselineIPv6 = $baselineIPv6
            RouteTestFamily = $routeTestFamily
            Username = $Username
            Password = $Password
            ConnectTimeoutSec = $ConnectTimeoutSec
            TcpTimeoutMs = $TcpTimeoutMs
            SpeedTimeoutSec = $SpeedTimeoutSec
            SpeedSamples = $SpeedSamples
            SpeedDownloadBytes = $SpeedDownloadBytes
            SpeedTestUrl = $SpeedTestUrl
            LatencyTestHost = $LatencyTestHost
            LatencyTestPort = $LatencyTestPort
            LatencyTimeoutMs = $LatencyTimeoutMs
            LatencySamples = $LatencySamples
            RasRecoveryDelaySec = $RasRecoveryDelaySec
            Ras633Retries = $Ras633Retries
            TransientDialRetryDelaySec = $TransientDialRetryDelaySec
            ExistingTcpAttempts = $ExistingTcpAttempts
            ExistingTcpRetryDelaySec = $ExistingTcpRetryDelaySec
            ExistingRemovalMode = $ExistingRemovalMode
            TrySstpAfterTcpTimeout = [bool]$TrySstpAfterTcpTimeout
        }
        $outcome = Test-ExistingSstpProfile @testParams
        $result = $outcome.Record
        $results.Add($result)

        $latencyNote = if ($null -ne $result.VPNLatencyMs) {
            ("{0} ms ({1})" -f $result.VPNLatencyMs, $result.VPNLatencyMethod)
        } else {
            'latency n/a'
        }
        switch ([string]$result.Verdict) {
            'ACCEPT' {
                Write-Host ("  KEPT: passed the checks ({0} Mbps, {1}, public IP changed)" -f $result.DownloadMbps, $latencyNote) -ForegroundColor Green
            }
            'REJECT' {
                Write-Host ("  REJECTED ({0}): {1}" -f $result.Status, $result.Error) -ForegroundColor DarkYellow
            }
            default {
                Write-Host ("  KEPT - INCONCLUSIVE ({0}): {1}" -f $result.Status, $result.Error) -ForegroundColor Yellow
            }
        }

        if ($result.PostTestDisconnectFailed) {
            $stopFurtherChecks = $true
            $stopReason = "profile '$($result.ProfileName)' remains connected after its test"
        } elseif ([string]$result.Status -in @('DISCONNECT_FAILED_STATE_UNCERTAIN', 'VPN_CONNECT_TIMEOUT_RAS_STATE_UNCERTAIN', 'RAS_RECOVERY_TIMEOUT_STATE_UNCERTAIN')) {
            $stopFurtherChecks = $true
            $stopReason = [string]$result.Status
            Write-Host '  Later profile checks are paused because Windows RAS state may still be pending.' -ForegroundColor Yellow
        } elseif ([string]$result.Status -eq 'LOCAL_RAS_ERROR_633_AFTER_RETRY' -and -not $ContinueAfterLocalRas633) {
            $stopFurtherChecks = $true
            $stopReason = 'local Windows RAS error 633 after retry'
            Write-Host '  Stopping further profile checks by default after local RAS 633; use -ContinueAfterLocalRas633 to override.' -ForegroundColor Yellow
        }
    }
    Write-Progress -Activity 'Verifying existing Windows SSTP VPN profiles' -Completed

    # Add non-SSTP profiles to the report for completeness (never tested).
    foreach ($nonSstp in $nonSstpProfiles) {
        $results.Add([pscustomobject][ordered]@{
            ProfileName = [string]$nonSstp.Name
            Scope = [string]$nonSstp.Scope
            ServerAddress = ([string]$nonSstp.ServerAddress).Trim()
            Host = ''
            Port = $null
            WasConnectedAtStart = ([string]$nonSstp.ConnectionStatus -eq 'Connected')
            TcpReachable = $false
            TcpConnectMs = $null
            TcpProbeError = ''
            TcpAttempts = 0
            CredentialSource = ''
            DialAttempts = 0
            VPNConnected = $false
            VPNConnectSeconds = $null
            BaselineIPv4 = $baselineIPv4
            VPNIPv4 = ''
            IPv4Changed = 'Unknown'
            BaselineIPv6 = $baselineIPv6
            VPNIPv6 = ''
            IPv6Changed = 'Unknown'
            RouteVerificationFamily = ''
            VPNPublicIP = ''
            PublicIPChanged = 'Unknown'
            VPNLatencyMs = $null
            VPNLatencyMethod = ''
            VPNLatencySamples = 0
            VPNLatencyMin = $null
            VPNLatencyMax = $null
            VPNLatencyError = ''
            DownloadMbps = $null
            DownloadMB = $null
            DownloadSeconds = $null
            DownloadComplete = $false
            DownloadSamples = 0
            DownloadMinMbps = $null
            DownloadMaxMbps = $null
            DownloadError = ''
            InternetReachable = $false
            InternetCheckUrl = ''
            Status = 'NOT_SSTP_SKIPPED'
            Verdict = 'SKIPPED'
            PlannedAction = 'KEEP'
            ActionTaken = 'NOT_APPLICABLE'
            PostTestDisconnectFailed = $false
            Error = ("Tunnel type '{0}' is not SSTP; this script verifies SSTP profiles only." -f $nonSstp.TunnelType)
        })
    }

    $accepted = @($results | Where-Object { [string]$_.Verdict -eq 'ACCEPT' })
    $rejected = @($results | Where-Object { [string]$_.Verdict -eq 'REJECT' })
    $uncertain = @($results | Where-Object { [string]$_.Verdict -eq 'INCONCLUSIVE' })

    Write-Host ''
    Write-Host '================ EXISTING PROFILE VERIFICATION SUMMARY ================' -ForegroundColor Cyan
    Write-Host ("Checked {0} SSTP profile(s): {1} accepted (kept) | {2} rejected (marked for removal) | {3} inconclusive (kept)." -f $sstpProfiles.Count, $accepted.Count, $rejected.Count, $uncertain.Count) -ForegroundColor Cyan

    if ($accepted.Count -gt 0) {
        Write-Host ''
        Write-Host '====== KEPT: PROFILES THAT PASSED THE CHECKS ======' -ForegroundColor Green
        $accepted | Select-Object ProfileName, Scope, ServerAddress, VPNLatencyMs, VPNLatencyMethod, DownloadMbps, DownloadComplete, VPNPublicIP, CredentialSource, Status | Format-Table -AutoSize | Out-Host
    }
    if ($uncertain.Count -gt 0) {
        Write-Host ''
        Write-Host '====== KEPT: INCONCLUSIVE (LOCAL RAS TROUBLE IS NOT A REMOTE-SERVER VERDICT) ======' -ForegroundColor Yellow
        $uncertain | Select-Object ProfileName, Scope, ServerAddress, Status, Error | Format-Table -Wrap -AutoSize | Out-Host
    }
    if ($rejected.Count -gt 0) {
        Write-Host ''
        Write-Host '====== REJECTED: PROFILES MARKED FOR REMOVAL ======' -ForegroundColor Yellow
        $rejected | Select-Object ProfileName, Scope, ServerAddress, Status, Error | Format-Table -Wrap -AutoSize | Out-Host
    }

    $deletedCount = 0
    $deleteFailedCount = 0

    if ($rejected.Count -gt 0) {
        if ($ReportOnly) {
            foreach ($rec in $rejected) { $rec.ActionTaken = 'REPORT_ONLY_NOT_REMOVED' }
            Write-Host ''
            Write-Host 'REPORT-ONLY mode: no profiles were removed. Run again without -ReportOnly to apply the removals.' -ForegroundColor Yellow
        } else {
            Write-Host ''
            $confirmRemove = (Read-Host ("Type YES to permanently remove the {0} rejected profile(s) from Windows; press Enter to keep them all" -f $rejected.Count)).Trim()
            if ($confirmRemove -ceq 'YES') {
                Write-Host ("Removing {0} rejected profile(s) ..." -f $rejected.Count) -ForegroundColor Cyan
                foreach ($rec in $rejected) {
                    $removal = Remove-ExistingVpnProfile -ProfileName ([string]$rec.ProfileName) -RasdialPath $RasdialPath -PreferredScope ([string]$rec.Scope) -SettleSeconds $RasRecoveryDelaySec
                    if ($removal.Removed) {
                        $rec.ActionTaken = 'REMOVED'
                        $deletedCount++
                        Write-Host ("  removed '{0}' (ServerAddress='{1}')" -f $rec.ProfileName, $rec.ServerAddress) -ForegroundColor Green
                    } else {
                        $rec.ActionTaken = 'REMOVE_FAILED'
                        $deleteFailedCount++
                        $rec.Error = (([string]$rec.Error + ' ' + [string]$removal.Error).Trim())
                        if ($rec.Error.Length -gt 1000) { $rec.Error = $rec.Error.Substring(0, 1000) }
                        Write-Warning ("  could not remove '{0}': {1}" -f $rec.ProfileName, $removal.Error)
                    }
                }
            } else {
                foreach ($rec in $rejected) { $rec.ActionTaken = 'NOT_REMOVED_BY_USER_CHOICE' }
                Write-Host 'Removal was not confirmed; all rejected profiles were kept.' -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host ''
        Write-Host 'No existing SSTP profile was rejected; nothing to remove.' -ForegroundColor Green
    }

    $csvPath = Join-Path $PSScriptRoot ("sstp_existing_profile_check_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    try {
        $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8 -ErrorAction Stop
        Write-Host ("Full verification CSV report: {0}" -f $csvPath) -ForegroundColor Cyan
    } catch {
        $csvPath = ''
        Write-Warning ("Could not save the verification CSV report: {0}" -f $_.Exception.GetBaseException().Message)
    }

    if ($stopFurtherChecks) {
        Write-Host ("Verification was paused after: {0}. Start a fresh run to check the remaining profiles." -f $stopReason) -ForegroundColor Yellow
    }

    Write-Host ("`nFinished existing-profile verification ({0}): {1} checked | {2} kept | {3} rejected | {4} removed | {5} removal failure(s) | {6} inconclusive." -f $Mode, $sstpProfiles.Count, $accepted.Count, $rejected.Count, $deletedCount, $deleteFailedCount, $uncertain.Count) -ForegroundColor Cyan

    return [pscustomobject]@{
        Checked = $sstpProfiles.Count
        Accepted = $accepted.Count
        Rejected = $rejected.Count
        Inconclusive = $uncertain.Count
        Deleted = $deletedCount
        DeleteFailed = $deleteFailedCount
        CsvPath = $csvPath
    }
}

# ---- v16.1 phase entry point ----
if ($ListExisting) {
    Show-ExistingVpnProfiles
    return
}

if ($VerifyExisting -or $PruneFirst) {
    $verificationMode = if ($VerifyExisting) { 'Standalone' } else { 'PruneFirst' }
    $verifyParams = @{
        Mode = $verificationMode
        RasdialPath = $rasdialPath
        CurlPath = $curlPath
        Username = $Username
        Password = $Password
        ConnectTimeoutSec = $ConnectTimeoutSec
        TcpTimeoutMs = $TcpTimeoutMs
        SpeedTimeoutSec = $SpeedTimeoutSec
        SpeedSamples = $SpeedSamples
        SpeedDownloadBytes = $SpeedDownloadBytes
        SpeedTestUrl = $SpeedTestUrl
        LatencyTestHost = $LatencyTestHost
        LatencyTestPort = $LatencyTestPort
        LatencyTimeoutMs = $LatencyTimeoutMs
        LatencySamples = $LatencySamples
        RasRecoveryDelaySec = $RasRecoveryDelaySec
        Ras633Retries = $Ras633Retries
        TransientDialRetryDelaySec = $TransientDialRetryDelaySec
        ExistingTcpAttempts = $ExistingTcpAttempts
        ExistingTcpRetryDelaySec = $ExistingTcpRetryDelaySec
        ExistingRemovalMode = $ExistingRemovalMode
        ContinueAfterLocalRas633 = [bool]$ContinueAfterLocalRas633
        TrySstpAfterTcpTimeout = [bool]$TrySstpAfterTcpTimeout
        ReportOnly = [bool]$ReportOnly
    }
    $null = Invoke-ExistingProfileVerification @verifyParams

    if ($VerifyExisting) {
        Write-Host ''
        Write-Host 'VERIFY-EXISTING run finished. No server list was fetched and no new VPN profiles were added.' -ForegroundColor Green
        return
    }
    Write-Host ''
    Write-Host 'Prune-first phase finished; continuing with the normal server-test run.' -ForegroundColor Green
}

$servers = @()
$usedVpnRetry = $false
$finalFallbackUsed = $false
$lastFetchError = ''

# Build the supplementary URL list once. The primary URL is never repeated,
# except in -ExtraSourceOnly mode where it is not used at all.
$extraUrls = @()
if (-not $NoExtraSource) {
    foreach ($candidate in @($ExtraSourceUrl)) {
        $candidateUrl = ([string]$candidate).Trim()
        if ([string]::IsNullOrWhiteSpace($candidateUrl)) { continue }
        if (-not $ExtraSourceOnly -and $candidateUrl -ieq ([string]$Url).Trim()) { continue }
        if ($extraUrls -notcontains $candidateUrl) { $extraUrls += $candidateUrl }
    }
}
if ($FinalFallbackOnly) {
    Write-Host ("Final-fallback-only mode: {0}" -f $FinalFallbackUrl) -ForegroundColor Cyan
} elseif ($ExtraSourceOnly) {
    if ($extraUrls.Count -eq 0) {
        throw '-ExtraSourceOnly requires at least one non-empty -ExtraSourceUrl value.'
    }
    Write-Host ("Supplementary-only mode: {0}" -f ($extraUrls -join ', ')) -ForegroundColor Cyan
} elseif (-not [string]::IsNullOrWhiteSpace($ServerListCsv)) {
    Write-Host 'CSV snapshot mode: the saved list will be used as-is; no web source will be fetched.' -ForegroundColor Cyan
} elseif ($extraUrls.Count -gt 0) {
    Write-Host ("Supplementary source(s) enabled: {0}" -f ($extraUrls -join ', ')) -ForegroundColor Cyan
} else {
    Write-Host 'Supplementary sources are disabled; only the primary list will be used.' -ForegroundColor DarkGray
}

if ($FinalFallbackOnly) {
    $finalOnlyResult = Get-SstpServersFromPlainHostListUrls -Urls @($FinalFallbackUrl)
    if ($finalOnlyResult.Errors.Count -gt 0) { $lastFetchError = ($finalOnlyResult.Errors -join ' | ') }
    $servers = @(Merge-SstpServerLists -Lists @($finalOnlyResult.Servers))
    if ($servers.Count -eq 0) {
        $shortError = ($lastFetchError -replace '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($shortError)) { $shortError = 'No recognizable host rows were found.' }
        if ($shortError.Length -gt 260) { $shortError = $shortError.Substring(0, 260) + '...' }
        throw ("No server list could be obtained from -FinalFallbackUrl. Reason: {0}" -f $shortError)
    }
    $finalFallbackUsed = $true
    Write-Host ("Retrieved {0} unique server(s) from the final fallback source only." -f $servers.Count) -ForegroundColor Green
} elseif ($ExtraSourceOnly) {
    $allLists = [System.Collections.Generic.List[object]]::new()
    $extraResult = Get-SstpServersFromUrls -Urls $extraUrls
    foreach ($srv in @($extraResult.Servers)) { $allLists.Add($srv) }
    if ($extraResult.Errors.Count -gt 0) {
        $lastFetchError = ($extraResult.Errors -join ' | ')
    }
    $servers = @(Merge-SstpServerLists -Lists @($allLists))
    if ($servers.Count -gt 0) {
        Write-Host ("Retrieved {0} unique server(s) from the supplementary source(s) only." -f $servers.Count) -ForegroundColor Green
    }
} elseif ($UseClipboard -and [string]::IsNullOrWhiteSpace($ServerListCsv)) {
    $allLists = [System.Collections.Generic.List[object]]::new()

    # Stage 1: clipboard text, which is the normal -UseClipboard path. An
    # empty, unreadable, or unrecognizable clipboard is not fatal: the
    # remaining stages below still try the network sources.
    $clipboardServers = 0
    try {
        $clipboardContent = Get-ClipboardText
        $clipServers = @(Convert-AnyServerListContent -Content ([string]$clipboardContent) -DefaultSource 'clipboard')
        if ($clipServers.Count -eq 0) {
            throw 'Clipboard text did not contain recognizable server rows. In Edge, wait until the actual table is visible, click the page, press Ctrl+A and Ctrl+C, then rerun.'
        }
        foreach ($srv in $clipServers) { $allLists.Add($srv) }
        $clipboardServers = $clipServers.Count
        Write-Host ("Retrieved {0} server(s) from copied browser text." -f $clipServers.Count) -ForegroundColor Green
    } catch {
        $lastFetchError = $_.Exception.GetBaseException().Message
        Write-Warning $lastFetchError
    }

    # Stage 2: the clipboard produced nothing usable, so retry the primary
    # source before giving up. This matters when the user launched with
    # -UseClipboard but the clipboard was empty or held unrelated text.
    if ($clipboardServers -eq 0) {
        Write-Host ("Clipboard did not provide a server list; retrying the primary source: {0}" -f $Url) -ForegroundColor Cyan
        $primaryResult = Get-SstpServersFromUrls -Urls @($Url)
        foreach ($srv in @($primaryResult.Servers)) { $allLists.Add($srv) }
        if ($primaryResult.Errors.Count -gt 0) {
            $lastFetchError = ($primaryResult.Errors -join ' | ')
        }
        if (@($primaryResult.Servers).Count -gt 0) {
            Write-Host ("Retrieved {0} server(s) from the primary source." -f @($primaryResult.Servers).Count) -ForegroundColor Green
        } else {
            $extraLabel = 'none configured (supplementary sources disabled)'
            if ($extraUrls.Count -gt 0) { $extraLabel = ($extraUrls -join ', ') }
            Write-Warning ("The primary source did not provide a server list either; trying the supplementary source(s): {0}" -f $extraLabel)
        }
    }

    # Stage 3: always merge the supplementary source(s) unless -NoExtraSource
    # removed them, so one failing source never leaves the run with no data.
    $extraErrors = @(Merge-ExtraServerSources -Target $allLists -Urls $extraUrls)
    if ($extraErrors.Count -gt 0) { $lastFetchError = ($extraErrors -join ' | ') }

    $servers = @(Merge-SstpServerLists -Lists @($allLists))
    if ($servers.Count -gt 0) {
        Write-Host ("Merged {0} unique server(s) from the available sources." -f $servers.Count) -ForegroundColor Green
    } else {
        Write-Warning 'Clipboard, the primary source, and the supplementary source(s) produced no server list; trying the final fallback source next.'
    }
} elseif (-not [string]::IsNullOrWhiteSpace($ServerListCsv)) {
    $servers = @(Get-SstpServersFromCsv -CsvPath $ServerListCsv)
    Write-Host ("Loaded {0} server(s) from local CSV: {1}" -f $servers.Count, $ServerListCsv) -ForegroundColor Green
} elseif (-not [string]::IsNullOrWhiteSpace($HtmlFile)) {
    $allLists = [System.Collections.Generic.List[object]]::new()
    try {
        $localServers = @(Get-SstpServers -PageUrl $Url -LocalHtmlFile $HtmlFile)
        foreach ($srv in $localServers) { $allLists.Add($srv) }
        Write-Host ("Retrieved {0} server(s) from the saved HTML file." -f $localServers.Count) -ForegroundColor Green
    } catch {
        $lastFetchError = $_.Exception.Message
        Write-Warning $lastFetchError
    }
    [void](Merge-ExtraServerSources -Target $allLists -Urls $extraUrls)
    $servers = @(Merge-SstpServerLists -Lists @($allLists))
    if ($servers.Count -gt 0) {
        Write-Host ("Merged {0} unique server(s) from the available sources." -f $servers.Count) -ForegroundColor Green
    }
} else {
    $allLists = [System.Collections.Generic.List[object]]::new()
    $primaryResult = Get-SstpServersFromUrls -Urls @($Url)
    foreach ($srv in @($primaryResult.Servers)) { $allLists.Add($srv) }
    if ($primaryResult.Errors.Count -gt 0) {
        $lastFetchError = ($primaryResult.Errors -join ' | ')
    }

    [void](Merge-ExtraServerSources -Target $allLists -Urls $extraUrls)
    $servers = @(Merge-SstpServerLists -Lists @($allLists))
    if ($servers.Count -gt 0) {
        Write-Host ("Merged {0} unique server(s) from all enabled sources." -f $servers.Count) -ForegroundColor Green
    }
}

if ($ExtraSourceOnly -and $servers.Count -eq 0) {
    $shortError = ($lastFetchError -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($shortError)) { $shortError = 'The source returned no recognizable SSTP rows.' }
    if ($shortError.Length -gt 260) { $shortError = $shortError.Substring(0, 260) + '...' }
    throw ("No server list could be obtained from the supplementary source(s). Reason: {0}" -f $shortError)
}

# Last-resort fallback: consulted only when every other source produced no
# servers. This source is a plain newline-separated SSTP host list, so it uses
# the dedicated plain-list parser instead of the HTML/copied-text parsers.
$useFinalFallback = ($servers.Count -eq 0 -and -not $NoExtraSource -and
    -not $ExtraSourceOnly -and -not [string]::IsNullOrWhiteSpace($FinalFallbackUrl))
if ($useFinalFallback) {
    Write-Host 'All earlier sources produced no server list; trying the final fallback source.' -ForegroundColor Yellow
    $finalResult = Get-SstpServersFromPlainHostListUrls -Urls @($FinalFallbackUrl)
    if ($finalResult.Errors.Count -gt 0) { $lastFetchError = ($finalResult.Errors -join ' | ') }
    $servers = @(Merge-SstpServerLists -Lists @($finalResult.Servers))
    if ($servers.Count -gt 0) {
        $finalFallbackUsed = $true
        $lastFetchError = ''
        Write-Host ("Merged {0} unique server(s) from the final fallback source." -f $servers.Count) -ForegroundColor Green
    }
}

while ($servers.Count -eq 0) {
    Write-Host ''
    Write-Host 'The server list could not be retrieved automatically.' -ForegroundColor Yellow
    if ($lastFetchError) {
        $shortError = ($lastFetchError -replace '\s+', ' ').Trim()
        if ($shortError.Length -gt 260) { $shortError = $shortError.Substring(0, 260) + '...' }
        Write-Host "Reason: $shortError" -ForegroundColor DarkYellow
    }
    Write-Host 'Choose the next step:' -ForegroundColor Cyan
    Write-Host '  V = Turn on your usual VPN, then retry retrieving the list.'
    Write-Host '  C = Read text copied from the real browser (recommended).'
    Write-Host '  H = Use an HTML file saved from the page in a browser.'
    Write-Host '  Q = Quit.'
    $choice = (Read-Host 'Enter V, C, H, or Q').Trim().ToUpperInvariant()

    if ($choice -eq 'Q') { throw 'Stopped by user before server testing.' }
    elseif ($choice -eq 'C') {
        Write-Host ''
        Write-Host 'Browser-assisted method:' -ForegroundColor Cyan
        Write-Host "1. In Edge, open $Url and wait until the actual server table is visible (not 'Just a moment')." -ForegroundColor Cyan
        Write-Host '2. Click the page, press Ctrl+A, then Ctrl+C.' -ForegroundColor Cyan
        Write-Host '3. Return here. The script will parse the copied text from the clipboard.' -ForegroundColor Cyan
        [void](Read-Host 'After copying the page, press Enter to read the clipboard')
        $allLists = [System.Collections.Generic.List[object]]::new()
        try {
            $clipboardContent = Get-ClipboardText
            $clipServers = @(Convert-AnyServerListContent -Content ([string]$clipboardContent) -DefaultSource 'clipboard')
            if ($clipServers.Count -eq 0) { throw 'No recognizable server rows were found in the clipboard. Confirm that the table was visible and copied.' }
            foreach ($srv in $clipServers) { $allLists.Add($srv) }
            Write-Host ("Retrieved {0} server(s) from browser clipboard text." -f $clipServers.Count) -ForegroundColor Green
        } catch {
            $lastFetchError = $_.Exception.GetBaseException().Message
            Write-Warning $lastFetchError
        }
        [void](Merge-ExtraServerSources -Target $allLists -Urls $extraUrls)
        $servers = @(Merge-SstpServerLists -Lists @($allLists))
        if ($servers.Count -gt 0) {
            $lastFetchError = ''
            Write-Host ("Merged {0} unique server(s) from the available sources." -f $servers.Count) -ForegroundColor Green
        }
    }
    elseif ($choice -eq 'H') {
        $chosenHtml = (Read-Host 'Full path to saved HTML file (for example, C:\Users\YourName\Downloads\ipspeed-sstp.html)').Trim().Trim('"')
        $allLists = [System.Collections.Generic.List[object]]::new()
        try {
            $localServers = @(Get-SstpServers -PageUrl $Url -LocalHtmlFile $chosenHtml)
            foreach ($srv in $localServers) { $allLists.Add($srv) }
            $HtmlFile = $chosenHtml
            Write-Host ("Retrieved {0} server(s) from the saved HTML file." -f $localServers.Count) -ForegroundColor Green
        } catch {
            $lastFetchError = $_.Exception.Message
            Write-Warning 'That file did not yield a recognizable server table. Check that the actual table was visible before saving.'
        }
        [void](Merge-ExtraServerSources -Target $allLists -Urls $extraUrls)
        $servers = @(Merge-SstpServerLists -Lists @($allLists))
        if ($servers.Count -gt 0) {
            $lastFetchError = ''
            Write-Host ("Merged {0} unique server(s) from the available sources." -f $servers.Count) -ForegroundColor Green
        }
    }
    elseif ($choice -eq 'V') {
        $usedVpnRetry = $true
        Write-Host 'Turn on the VPN in its normal application. If needed, open the page in your browser and wait for it to load, then return here.' -ForegroundColor Cyan
        $retryConfirm = (Read-Host 'Press Enter when the VPN is connected; type Q then Enter to quit').Trim()
        if ($retryConfirm -match '^(?i:q)$') { throw 'Stopped by user before the server list was retrieved.' }
        $allLists = [System.Collections.Generic.List[object]]::new()
        $primaryResult = Get-SstpServersFromUrls -Urls @($Url)
        foreach ($srv in @($primaryResult.Servers)) { $allLists.Add($srv) }
        [void](Merge-ExtraServerSources -Target $allLists -Urls $extraUrls)
        $servers = @(Merge-SstpServerLists -Lists @($allLists))
        if ($servers.Count -eq 0 -and -not $NoExtraSource -and
            -not [string]::IsNullOrWhiteSpace($FinalFallbackUrl)) {
            Write-Host 'The regular sources are still empty; trying the final fallback source after the VPN retry.' -ForegroundColor Yellow
            $finalResult = Get-SstpServersFromPlainHostListUrls -Urls @($FinalFallbackUrl)
            if ($finalResult.Errors.Count -gt 0) { $lastFetchError = ($finalResult.Errors -join ' | ') }
            $servers = @(Merge-SstpServerLists -Lists @($finalResult.Servers))
            if ($servers.Count -gt 0) { $finalFallbackUsed = $true }
        }
        if ($servers.Count -gt 0) {
            $lastFetchError = ''
        } else {
            if ($primaryResult.Errors.Count -gt 0) { $lastFetchError = ($primaryResult.Errors -join ' | ') }
            Write-Warning 'The list is still blocked. Try H to provide an HTML file saved after the table appears in the browser.'
        }
    }
    else {
        Write-Host 'Please enter V, C, H, or Q.' -ForegroundColor Yellow
    }
}

# Filter the parsed server list by port BEFORE applying PriorityServer and MaxServers.
# This ensures -MaxServers 10 with -PortMode Non443 means ten non-443 candidates,
# not the first ten rows from the unfiltered list. The default remains All.
$serverCountBeforePortFilter = $servers.Count

# The final fallback list is a plain host list and currently contains only
# port-443 endpoints. If the user asked for Non443, the filter would discard
# every last-resort entry. Ask before overriding the filter instead of failing
# with the generic port-mode error.
if ($finalFallbackUsed -and $PortMode -eq 'Non443' -and $servers.Count -gt 0 -and
    @($servers | Where-Object { [int]$_.Port -ne 443 }).Count -eq 0) {
    Write-Host ''
    Write-Host ("The final fallback source ({0}) returned {1} server(s), all on port 443." -f $FinalFallbackUrl, $servers.Count) -ForegroundColor Yellow
    Write-Host 'The current -PortMode Non443 filter would discard every one of them.' -ForegroundColor Yellow
    $fallbackPortChoice = (Read-Host 'Type Y to continue with these port-443 servers, or Q to quit').Trim().ToUpperInvariant()
    if ($fallbackPortChoice -notin @('Y', 'YES')) {
        throw 'Stopped by user: the final fallback source contains only port-443 servers, and -PortMode Non443 excludes them.'
    }
    $PortMode = 'All'
    Write-Host 'Continuing with the final fallback list; effective port mode for this run: All.' -ForegroundColor Cyan
}

switch ($PortMode) {
    '443' {
        $servers = @($servers | Where-Object { [int]$_.Port -eq 443 })
    }
    'Non443' {
        $servers = @($servers | Where-Object { [int]$_.Port -ne 443 })
    }
    default {
        $servers = @($servers)
    }
}
Write-Host ("Port mode '{0}': retained {1} of {2} server(s)." -f $PortMode, $servers.Count, $serverCountBeforePortFilter) -ForegroundColor Cyan
if ($servers.Count -eq 0) {
    throw ("No servers matched -PortMode '{0}'. Use -PortMode All or refresh the server list." -f $PortMode)
}

# Sort every candidate by the PING value that the source list itself publishes.
# This happens before PriorityServer and MaxServers, so a limited run such as
# -MaxServers 10 tests the ten lowest-PING candidates. Rows whose PING cell is
# "-" or missing are kept, but placed after all rows with a known value. When
# several servers share the same PING, longer published uptime wins.
$inputOrder = 0
foreach ($srv in $servers) {
    $inputOrder++
    $srv | Add-Member -NotePropertyName 'InputOrder' -NotePropertyValue $inputOrder -Force
}
$servers = @($servers | Sort-Object -Property @(
    @{ Expression = { if ($null -ne $_.PingMs) { [double]$_.PingMs } else { [double]::MaxValue } }; Ascending = $true },
    @{ Expression = { if ($null -ne $_.UptimeMinutes) { [double]$_.UptimeMinutes } else { -1.0 } }; Descending = $true },
    @{ Expression = { [int]$_.InputOrder }; Ascending = $true }
))
$knownPingCount = @($servers | Where-Object { $null -ne $_.PingMs }).Count
Write-Host ("Sorted {0} server(s) by source PING ascending, then uptime descending ({1} with a PING value; unknown values last)." -f $servers.Count, $knownPingCount) -ForegroundColor Cyan
if ($knownPingCount -gt 0) {
    $fastest = @($servers | Where-Object { $null -ne $_.PingMs })[0]
    Write-Host ("Lowest source PING: {0} ms - {1} ({2})" -f $fastest.PingMs, $fastest.Server, $fastest.Country) -ForegroundColor DarkGray
} else {
    Write-Warning 'The source list did not contain any PING values; the original source order will be used.'
}

# Optionally move a known-good server to the front. This is useful for a calibration
# run: a server previously proven to work should be attempted before slower/failing entries.
# It is applied after the PING sort, so an explicit priority override stays first.
if (-not [string]::IsNullOrWhiteSpace($PriorityServer)) {
    $priorityText = $PriorityServer.Trim()
    $priorityParsed = Parse-SstpServerAddress -Text $priorityText
    if (-not $priorityParsed) {
        Write-Warning ("Priority server '{0}' could not be parsed; PING-sorted order will be used." -f $priorityText)
    } else {
        $priorityHost = $priorityParsed.Host
        $priorityPort = $priorityParsed.Port
        $priorityIndex = -1
        for ($i = 0; $i -lt $servers.Count; $i++) {
            $srvHost = ([string]$servers[$i].Host).Trim().TrimEnd('.')
            if ($srvHost.StartsWith('[') -and $srvHost.EndsWith(']')) {
                $srvHost = $srvHost.Substring(1, $srvHost.Length - 2)
            }
            if ($srvHost -ieq $priorityHost -and [int]$servers[$i].Port -eq $priorityPort) {
                $priorityIndex = $i
                break
            }
        }
        if ($priorityIndex -ge 0) {
            if ($priorityIndex -gt 0) {
                $priorityItem = $servers[$priorityIndex]
                $servers = @($priorityItem) + @($servers | Where-Object {
                    $h = ([string]$_.Host).Trim().TrimEnd('.')
                    if ($h.StartsWith('[') -and $h.EndsWith(']')) { $h = $h.Substring(1, $h.Length - 2) }
                    -not ($h -ieq $priorityHost -and [int]$_.Port -eq $priorityPort)
                })
            }
            Write-Host ("Priority server moved to first position: {0} (port {1})" -f $priorityHost, $priorityPort) -ForegroundColor Green
        } else {
            Write-Warning ("Priority server '{0}' was not found in the input list; PING-sorted order will be used." -f $priorityText)
        }
    }
}

$snapshotPath = Join-Path $PSScriptRoot ("sstp_server_list_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$servers | Select-Object Country, Source, Server, Host, Port, PingMs, UptimeText, UptimeMinutes | Export-Csv -Path $snapshotPath -NoTypeInformation -Encoding utf8
Write-Host ("Successfully obtained {0} unique server(s)." -f $servers.Count) -ForegroundColor Green
Write-Host "Local server-list snapshot: $snapshotPath" -ForegroundColor DarkGray
if ($ListOnly) {
    Write-Host 'LIST-ONLY CHECK PASSED: server-list acquisition and parsing completed. No VPN connections or VPN profiles were changed.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'To test this saved list later without downloading it again, run:' -ForegroundColor Cyan
    $reuseScriptName = Split-Path -Leaf $PSCommandPath
    Write-Host ("  .\{0} -ServerListCsv '{1}' -PortMode {2} -MaxServers {3} -AddBestVpnCount {4}" -f $reuseScriptName, $snapshotPath, $PortMode, $MaxServers, $AddBestVpnCount) -ForegroundColor Cyan
    return
}
$listFetchIp4 = Get-PublicIp -CurlPath $curlPath -AddressFamily IPv4
if ($MaxServers -gt 0 -and $servers.Count -gt $MaxServers) {
    $servers = @($servers | Select-Object -First $MaxServers)
    Write-Host ("This run will test the {0} lowest-PING server(s)." -f $MaxServers) -ForegroundColor Cyan
}

Write-Host ''
Write-Host 'IMPORTANT: The server list has already been saved locally.' -ForegroundColor Yellow
Write-Host 'Now turn OFF your temporary/ordinary VPN (for example Cloudflare WARP, SoftEther, or another VPN).' -ForegroundColor Yellow
Write-Host 'Do not close this PowerShell window. The downloaded list is already in memory and will not be lost.' -ForegroundColor Cyan

$baselineIPv4 = ''
$baselineIPv6 = ''
$routeTestFamily = 'IPv4'
while ($true) {
    $confirmation = (Read-Host 'After disconnecting all other VPNs, press Enter to verify and start tests (or type Q to quit)').Trim()
    if ($confirmation -match '^(?i:q)$') { throw "Stopped by user. The downloaded server list is saved at: $snapshotPath" }

    $activeConnections = @(Get-ActiveWindowsVpnConnections)
    if ($activeConnections.Count -gt 0) {
        $names = ($activeConnections | ForEach-Object { $_.Name }) -join ', '
        Write-Warning "Windows still reports these VPN connections as active: $names. Disconnect them and press Enter again."
        continue
    }

    Start-Sleep -Seconds 2
    $baselineIPv4 = Get-PublicIp -CurlPath $curlPath -AddressFamily IPv4
    $baselineIPv6 = Get-PublicIp -CurlPath $curlPath -AddressFamily IPv6
    if (-not $baselineIPv4 -and -not $baselineIPv6) {
        Write-Warning 'Could not read a public IPv4 or IPv6 address for the current connection. Ensure the ordinary VPN is off and that the internet is working.'
        $manual = (Read-Host 'Type YES only if you have manually confirmed all other VPNs are disconnected; otherwise press Enter to retry').Trim()
        if ($manual -ceq 'YES') { break }
        continue
    }

    # Prefer IPv4 for route verification when available; fall back to IPv6-only
    # verification on networks that do not provide public IPv4 connectivity.
    $routeTestFamily = if ($baselineIPv4) { 'IPv4' } else { 'IPv6' }

    if ($usedVpnRetry -and $listFetchIp4 -and $baselineIPv4 -and ($baselineIPv4 -eq $listFetchIp4)) {
        Write-Warning "The public IPv4 address ($baselineIPv4) is unchanged from when the list was fetched. The VPN may still be active, or it may use split tunneling."
        $manual = (Read-Host 'Disconnect/check the VPN again. Type YES to continue anyway only if you are sure; otherwise press Enter to retry').Trim()
        if ($manual -ceq 'YES') { break }
        continue
    }
    break
}

$baselineIPv4Display = if ($baselineIPv4) { $baselineIPv4 } else { '(unavailable)' }
$baselineIPv6Display = if ($baselineIPv6) { $baselineIPv6 } else { '(unavailable)' }
Write-Host "Baseline public IPv4: $baselineIPv4Display; IPv6: $baselineIPv6Display; primary route check: $routeTestFamily" -ForegroundColor DarkGray
Write-Host ("Found {0} server(s) for this test run (port mode: {1}), ordered by source PING ascending. Only this shortlist is tested, one server at a time." -f $servers.Count, $PortMode) -ForegroundColor Cyan
Write-Host ("VPN timeout: {0}s | speed: {1} sample(s) of up to {2} MB | latency target: {3}:{4} | ranking: {5}" -f `
    $ConnectTimeoutSec, $SpeedSamples, [math]::Round(($SpeedDownloadBytes / 1000000), 1), $LatencyTestHost, $LatencyTestPort, $RankMode) -ForegroundColor DarkGray
if ($AddBestVpnCount -gt 0) {
    Write-Host ("At the end, the top {0} confirmed server(s) will be added to Windows VPN; existing duplicates are skipped and username/password are stored." -f $AddBestVpnCount) -ForegroundColor DarkGray
}
if ($ContinueAfterLocalRas633) {
    Write-Host 'Continue-after-633 is enabled: the script continues to later VPN dials only if the failed profile disconnects and is removed cleanly.' -ForegroundColor DarkGray
} else {
    Write-Host 'After a repeated local RAS 633, later VPN dials stop by default. Use -ContinueAfterLocalRas633 to override only when desired.' -ForegroundColor DarkGray
}
Write-Host 'Port handling: port 443 uses the hostname; every other port uses hostname:port. IPv6 endpoints are bracketed as [ipv6] or [ipv6]:port.' -ForegroundColor DarkGray
Write-Host 'RAS 633 is retried once and is not treated as a remote-server failure if it persists.' -ForegroundColor DarkGray
Write-Host 'Only a forcibly killed rasdial process or a profile that remains connected always pauses subsequent VPN attempts.' -ForegroundColor DarkGray

$runId = Get-Date -Format 'MMddHHmmss'
$results = [System.Collections.Generic.List[object]]::new()
$index = 0
$stopFurtherVpnAttempts = $false
$stopReason = ''

foreach ($server in $servers) {
    $index++
    $target = Resolve-SstpServerTarget -Server $server
    $profileName = ('SSTPCHK_{0}_{1:D3}' -f $runId, $index)
    $sourcePingText = if ($null -ne $server.PingMs) { ('{0} ms' -f $server.PingMs) } else { 'n/a' }
    Write-Progress -Activity 'Testing free SSTP servers' -Status ("{0}/{1}  {2}" -f $index, $servers.Count, $target.ServerAddress) -PercentComplete ([int](100 * $index / $servers.Count))
    Write-Host ("[{0}/{1}] {2} ({3}, source PING {4}, TCP/{5}; SSTP ServerAddress='{2}')" -f $index, $servers.Count, $target.ServerAddress, $server.Country, $sourcePingText, $target.Port) -NoNewline

    $record = [ordered]@{
        Country = $server.Country
        Source = if ($server.PSObject.Properties.Name -contains 'Source') { [string]$server.Source } else { '' }
        Server = $target.ServerAddress
        Host = $target.Host
        Port = $target.Port
        PingMs = $server.PingMs
        VPNServerAddress = $target.ServerAddress
        WindowsStoredServerAddress = ''
        ProfilePortVerified = $null
        TcpReachable = $false
        TcpConnectMs = $null
        TcpProbeError = ''
        VPNLatencyMs = $null
        VPNLatencyMethod = ''
        VPNLatencySamples = 0
        VPNLatencyMin = $null
        VPNLatencyMax = $null
        VPNLatencyError = ''
        MeasuredLatencyMs = $null
        VPNConnected = $false
        VPNConnectSeconds = $null
        BaselineIPv4 = $baselineIPv4
        VPNIPv4 = ''
        IPv4Changed = 'Unknown'
        BaselineIPv6 = $baselineIPv6
        VPNIPv6 = ''
        IPv6Changed = 'Unknown'
        RouteVerificationFamily = ''
        VPNPublicIP = ''
        PublicIPChanged = 'Unknown'
        DownloadMbps = $null
        DownloadMB = $null
        DownloadSeconds = $null
        DownloadComplete = $false
        DownloadSamples = 0
        DownloadMinMbps = $null
        DownloadMaxMbps = $null
        DownloadError = ''
        SpeedScore = $null
        LatencyScore = $null
        SelectionScore = $null
        Status = ''
        Error = ''
    }

    $tcp = Test-TcpPort -HostName $target.Host -PortNumber $target.Port -TimeoutMs $TcpTimeoutMs
    $record.TcpReachable = [bool]$tcp.Reachable
    $record.TcpConnectMs = $tcp.Milliseconds
    $record.TcpProbeError = [string]$tcp.Error

    if ($stopFurtherVpnAttempts) {
        $record.Status = 'SKIPPED_AFTER_RAS_STATE_UNCERTAIN'
        $tcpSummary = if ($tcp.Reachable) { 'TCP reachable' } else { "TCP not confirmed: $($tcp.Error)" }
        $record.Error = "$tcpSummary; VPN dial skipped because the prior attempt left RAS state uncertain ($stopReason)."
        Write-Host ("  {0}; VPN skipped after {1}" -f $tcpSummary, $stopReason) -ForegroundColor Yellow
        $results.Add([pscustomobject]$record)
        continue
    }

    if (-not $tcp.Reachable) {
        if ($TrySstpAfterTcpTimeout -and ([string]$tcp.Error -eq 'TCP timeout')) {
            Write-Host ("  TCP probe timed out after {0} ms; attempting the real SSTP connection anyway" -f $TcpTimeoutMs) -ForegroundColor Yellow
        } else {
            $record.Status = 'TCP_UNREACHABLE'
            $record.Error = [string]$tcp.Error
            Write-Host ("  TCP/{0} unavailable; SSTP was not attempted ({1})" -f $target.Port, $tcp.Error) -ForegroundColor DarkYellow
            $results.Add([pscustomobject]$record)
            continue
        }
    }

    $profileCreated = $false
    try {
        Add-VpnConnection -Name $profileName -ServerAddress $target.ServerAddress -TunnelType SSTP `
            -AuthenticationMethod 'MSChapv2' -EncryptionLevel Optional -Force | Out-Null
        $profileCreated = $true

        $profileCheck = Get-VpnConnection -Name $profileName -ErrorAction Stop
        if (-not $profileCheck) {
            throw "Windows did not return the temporary VPN profile '$profileName' for verification."
        }
        $storedAddress = ([string]$profileCheck.ServerAddress).Trim()
        $record.WindowsStoredServerAddress = $storedAddress

        $storedParsed = Parse-SstpServerAddress -Text $storedAddress
        if (-not $storedParsed) {
            $record.Status = 'PROFILE_PORT_MISMATCH'
            $record.Error = "Windows profile stored '$storedAddress', which could not be parsed; expected '$($target.ServerAddress)'."
            throw $record.Error
        }
        $storedHost = $storedParsed.Host
        $storedPort = $storedParsed.Port
        $hostMatches = ($storedHost.TrimEnd('.') -ieq $target.Host.TrimEnd('.'))
        if (-not $hostMatches -or $storedPort -ne $target.Port) {
            $record.Status = 'PROFILE_PORT_MISMATCH'
            $record.Error = "Windows profile stored '$storedAddress' (parsed host '$storedHost', port $storedPort); expected '$($target.ServerAddress)' (port $($target.Port))."
            throw $record.Error
        }
        $record.ProfilePortVerified = $true

        $dialAttempts = 0
        $rasDisconnectTimedOut = $false
        do {
            $dialAttempts++
            $dial = Invoke-NativeTimed -FilePath $rasdialPath `
                -Arguments @($profileName, $Username, $Password) -TimeoutSec $ConnectTimeoutSec
            $priorSeconds = 0.0
            if ($null -ne $record.VPNConnectSeconds) { $priorSeconds = [double]$record.VPNConnectSeconds }
            $record.VPNConnectSeconds = [math]::Round(($priorSeconds + [double]$dial.Seconds), 2)
            if ($dial.TimedOut -or $dial.ExitCode -eq 0) { break }

            $dialText = (([string]$dial.StdOut + ' ' + [string]$dial.StdErr).Trim() -replace '\s+', ' ')
            $parsedRasCode = Get-RasErrorCode -Text $dialText -ProcessExitCode ([int]$dial.ExitCode)
            if ($parsedRasCode -eq 633 -and $dialAttempts -le $Ras633Retries) {
                Write-Host ("  Local RAS 633 on attempt {0}/{1}; issuing a disconnect and retrying after {2}s" -f $dialAttempts, ($Ras633Retries + 1), $RasRecoveryDelaySec) -ForegroundColor Yellow
                $disconnectAttempt = $null
                try {
                    $disconnectAttempt = Invoke-NativeTimed -FilePath $rasdialPath -Arguments @($profileName, '/disconnect') -TimeoutSec 12
                } catch { }
                if ($disconnectAttempt -and $disconnectAttempt.TimedOut) {
                    $rasDisconnectTimedOut = $true
                    break
                }
                Start-Sleep -Seconds $RasRecoveryDelaySec
                continue
            }
            break
        } while ($dialAttempts -le $Ras633Retries)

        if ($rasDisconnectTimedOut) {
            $record.Status = 'RAS_RECOVERY_TIMEOUT_STATE_UNCERTAIN'
            $record.Error = 'The rasdial /disconnect command timed out during recovery after local RAS 633. Later VPN dials are paused because Windows RAS state may still be pending.'
            $stopFurtherVpnAttempts = $true
            $stopReason = 'rasdial /disconnect timed out during RAS recovery'
            Write-Host '  Recovery disconnect timed out; later VPN dials are paused because Windows RAS may still be busy.' -ForegroundColor Yellow
        }
        elseif ($dial.TimedOut) {
            $record.Status = 'VPN_CONNECT_TIMEOUT_RAS_STATE_UNCERTAIN'
            $record.Error = "rasdial was forcibly stopped after $ConnectTimeoutSec seconds before Windows returned a final result. Further VPN dials are paused because RAS state may still be pending."
            $stopFurtherVpnAttempts = $true
            $stopReason = "rasdial timeout at ${ConnectTimeoutSec}s"
            Write-Host ("  VPN attempt exceeded {0}s; later VPN dials are paused because Windows RAS may still be busy" -f $ConnectTimeoutSec) -ForegroundColor Yellow
        }
        elseif ($dial.ExitCode -ne 0) {
            $detail = (([string]$dial.StdOut + ' ' + [string]$dial.StdErr).Trim() -replace '\s+', ' ')
            if ([string]::IsNullOrWhiteSpace($detail)) { $detail = "rasdial exit code $($dial.ExitCode); no diagnostic text was returned." }
            if ($detail.Length -gt 500) { $detail = $detail.Substring(0, 500) }
            $record.Error = $detail
            $rasCode = Get-RasErrorCode -Text $detail -ProcessExitCode ([int]$dial.ExitCode)
            if ($rasCode -eq 633) {
                $record.Status = 'LOCAL_RAS_ERROR_633_AFTER_RETRY'
                Write-Host ("  Local RAS 633 persisted after retry; server health is inconclusive: {0}" -f $detail) -ForegroundColor Red
                if ($ContinueAfterLocalRas633) {
                    Write-Host 'Continue-after-633 is enabled; later VPN dials will continue only if this temporary profile is cleaned up successfully.' -ForegroundColor Yellow
                } else {
                    $stopFurtherVpnAttempts = $true
                    $stopReason = 'local Windows RAS error 633 after retry'
                    Write-Host 'Stopping further VPN dials by default after local RAS 633; later rows will receive TCP-only checks.' -ForegroundColor Yellow
                }
                Show-Ras633Diagnostics
            } elseif ($rasCode -eq 638) {
                $record.Status = 'SSTP_RAS_TIMEOUT_638'
                Write-Host ("  SSTP/RAS timeout 638; TCP success alone does not prove the remote SSTP service is responding: {0}" -f $detail) -ForegroundColor DarkYellow
            } elseif ($dial.ExitCode -eq -2147014836 -or $detail -match '(?i)connection attempt failed.*period of time|timed out|timeout') {
                $record.Status = 'NETWORK_CONNECT_TIMEOUT'
                Write-Host ("  SSTP/network timeout (not a local 633): {0}" -f $detail) -ForegroundColor DarkYellow
            } else {
                $record.Status = 'VPN_CONNECT_FAILED'
                Write-Host ("  VPN failed (process exit {0}; parsed RAS code {1}): {2}" -f $dial.ExitCode, $rasCode, $detail) -ForegroundColor DarkYellow
            }
        }
        else {
            $record.VPNConnected = $true
            Start-Sleep -Seconds 2

            # Probe only address families available before the VPN. This avoids
            # a needless IPv6 timeout on IPv4-only networks while still allowing
            # IPv6-only route verification when the baseline has no public IPv4.
            $vpnIp4 = ''
            if ($baselineIPv4) {
                $vpnIp4 = Get-PublicIp -CurlPath $curlPath -AddressFamily IPv4
            }
            $vpnIp6 = ''
            # An IPv6 request is needed only when IPv6 existed at baseline and
            # IPv4 cannot provide a comparable result or did not change.
            $needIpv6Probe = $baselineIPv6 -and (-not $baselineIPv4 -or -not $vpnIp4 -or $baselineIPv4 -eq $vpnIp4)
            if ($needIpv6Probe) {
                $vpnIp6 = Get-PublicIp -CurlPath $curlPath -AddressFamily IPv6
            }
            $record.VPNIPv4 = $vpnIp4
            $record.VPNIPv6 = $vpnIp6

            if ($baselineIPv4 -and $vpnIp4) {
                $record.IPv4Changed = if ($baselineIPv4 -ne $vpnIp4) { 'Yes' } else { 'No' }
            }
            if ($baselineIPv6 -and $vpnIp6) {
                $record.IPv6Changed = if ($baselineIPv6 -ne $vpnIp6) { 'Yes' } else { 'No' }
            }

            # Verify route changes only by comparing the same address family.
            # Prefer IPv4 when both sides provide it; use IPv6 only when an IPv4
            # before/after pair cannot be obtained.
            if ($baselineIPv4 -and $vpnIp4) {
                $record.RouteVerificationFamily = 'IPv4'
                $record.VPNPublicIP = $vpnIp4
                $record.PublicIPChanged = $record.IPv4Changed
            } elseif ($baselineIPv6 -and $vpnIp6) {
                $record.RouteVerificationFamily = 'IPv6'
                $record.VPNPublicIP = $vpnIp6
                $record.PublicIPChanged = $record.IPv6Changed
            }

            # Measure latency through the live VPN tunnel. The source PING was
            # used only to choose which servers to test; this measured value is
            # what participates in the final ranking. ICMP is tried first, then
            # TCP to the same fixed target.
            $tunnelLatency = Measure-TunnelLatency -HostName $LatencyTestHost `
                -Port $LatencyTestPort -TimeoutMs $LatencyTimeoutMs -Samples $LatencySamples
            $record.VPNLatencyMs = $tunnelLatency.LatencyMs
            $record.VPNLatencyMethod = $tunnelLatency.Method
            $record.VPNLatencySamples = $tunnelLatency.SuccessfulSamples
            $record.VPNLatencyMin = $tunnelLatency.Min
            $record.VPNLatencyMax = $tunnelLatency.Max
            $record.VPNLatencyError = $tunnelLatency.Error
            $latencyText = if ($null -ne $record.VPNLatencyMs) {
                ('{0} ms ({1})' -f $record.VPNLatencyMs, $record.VPNLatencyMethod)
            } else {
                'latency unavailable'
            }

            $download = Measure-DownloadSpeed -CurlPath $curlPath -AddressFamily $routeTestFamily `
                -SpeedTestUrl $SpeedTestUrl -DownloadBytes $SpeedDownloadBytes `
                -Samples $SpeedSamples -TimeoutSec $SpeedTimeoutSec
            $record.DownloadSamples = $download.SuccessfulSamples
            $record.DownloadMinMbps = $download.MinMbps
            $record.DownloadMaxMbps = $download.MaxMbps
            $record.DownloadError = if (-not [string]::IsNullOrWhiteSpace([string]$download.Error)) {
                $download.Error
            } else {
                [string]$download.SampleErrors
            }

            if ($null -ne $download.MedianMbps) {
                $record.DownloadMbps = $download.MedianMbps
                # Report per-sample averages so they are comparable with the
                # median Mbps value when -SpeedSamples is greater than 1.
                $record.DownloadMB = if ($download.SuccessfulSamples -gt 0) {
                    [math]::Round(($download.TotalMB / $download.SuccessfulSamples), 2)
                } else { $null }
                $record.DownloadSeconds = if ($download.SuccessfulSamples -gt 0) {
                    [math]::Round(($download.TotalSeconds / $download.SuccessfulSamples), 2)
                } else { $null }
                $record.DownloadComplete = [bool]$download.AllComplete
                if ($record.PublicIPChanged -eq 'Yes') {
                    $record.Status = 'WORKING_TUNNEL_AND_INTERNET'
                    $sampleNote = if ($record.DownloadComplete) { 'complete test' } else { 'partial sample' }
                    Write-Host ("  OK  {0} Mbps; {1}; public IP changed ({2})" -f $record.DownloadMbps, $latencyText, $sampleNote) -ForegroundColor Green
                } elseif ($record.PublicIPChanged -eq 'No') {
                    $record.Status = 'CONNECTED_ROUTE_UNCONFIRMED'
                    Write-Host ("  Connected; {0} Mbps, {1}, but public IP did not change" -f $record.DownloadMbps, $latencyText) -ForegroundColor Yellow
                } else {
                    $record.Status = 'CONNECTED_IP_UNKNOWN'
                    Write-Host ("  Connected; {0} Mbps, {1}, public IP could not be verified" -f $record.DownloadMbps, $latencyText) -ForegroundColor Yellow
                }
            } else {
                $record.Status = 'CONNECTED_NO_DOWNLOAD'
                $detail = [string]$download.SampleErrors
                if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'Download test returned no usable sample.' }
                $record.Error = $detail
                Write-Host ("  Connected ({0}), but internet download test failed" -f $latencyText) -ForegroundColor Yellow
            }
        }
    }
    catch {
        $caughtError = $_.Exception.GetBaseException().Message
        if ($record.Status -ne 'PROFILE_PORT_MISMATCH') {
            $record.Status = 'PROFILE_OR_TEST_ERROR'
            $record.Error = $caughtError
        }
        if ($record.Error.Length -gt 350) { $record.Error = $record.Error.Substring(0, 350) }
        if ($record.Status -eq 'PROFILE_PORT_MISMATCH') {
            Write-Host '  Windows profile port/address mismatch; SSTP dial was not attempted' -ForegroundColor Red
        } else {
            Write-Host '  Error' -ForegroundColor Red
        }
    }
    finally {
        if ($profileCreated) {
            $cleanup = Remove-TestVpnProfileSafely -ProfileName $profileName `
                -RasdialPath $rasdialPath -WaitSeconds 20 -SettleSeconds $RasRecoveryDelaySec
            if (-not $cleanup.Removed) {
                $record.Error = (([string]$record.Error + ' ' + [string]$cleanup.Error).Trim())
                if ($record.Error.Length -gt 700) { $record.Error = $record.Error.Substring(0, 700) }
                if ($cleanup.StillConnected) {
                    $stopFurtherVpnAttempts = $true
                    $stopReason = "profile cleanup failed: $profileName remains connected"
                    if ($record.Status -ne 'WORKING_TUNNEL_AND_INTERNET') { $record.Status = 'RAS_CLEANUP_INCOMPLETE' }
                    Write-Warning "$($cleanup.Error) Later VPN dials will be paused; later rows will receive TCP-only checks."
                } else {
                    Write-Warning ("Profile '{0}' could not be removed cleanly: {1}" -f $profileName, $cleanup.Error)
                }
            }
        }
    }

    $results.Add([pscustomobject]$record)
}

Write-Progress -Activity 'Testing free SSTP servers' -Completed

# Compute the final ranking from locally measured values. Download speed is
# required for a "confirmed working" server, while measured tunnel latency is
# used as the second criterion (with TcpConnectMs as its fallback).
Add-SelectionScores -Records @($results) -RankMode $RankMode | Out-Null

if ([string]::IsNullOrWhiteSpace($OutputCsv)) {
    $OutputCsv = Join-Path $PSScriptRoot ("sstp_test_results_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$OutputCsv = [System.IO.Path]::GetFullPath($OutputCsv)
# Keep the CSV itself in the same useful order as before:
# DownloadMbps descending, with rows that have no download value last.
# -Stable preserves test order for equal speeds.
$results |
    Sort-Object -Property @{
        Expression = { if ($null -ne $_.DownloadMbps) { [double]$_.DownloadMbps } else { [double]::MinValue } }
        Descending = $true
    } -Stable |
    Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding utf8

# The console ranking and the profiles added to Windows use SelectionScore.
$confirmed = @($results | Where-Object { $_.Status -eq 'WORKING_TUNNEL_AND_INTERNET' } | Sort-Object -Property @(
    @{ Expression = { if ($null -ne $_.SelectionScore) { [double]$_.SelectionScore } else { -1.0 } }; Descending = $true },
    @{ Expression = { if ($null -ne $_.DownloadMbps) { [double]$_.DownloadMbps } else { [double]::MinValue } }; Descending = $true }
) -Stable)
$connectedUnverified = @($results | Where-Object { $_.Status -in @('CONNECTED_ROUTE_UNCONFIRMED', 'CONNECTED_IP_UNKNOWN') } | Sort-Object -Property @(
    @{ Expression = { if ($null -ne $_.SelectionScore) { [double]$_.SelectionScore } else { -1.0 } }; Descending = $true },
    @{ Expression = { if ($null -ne $_.DownloadMbps) { [double]$_.DownloadMbps } else { [double]::MinValue } }; Descending = $true }
) -Stable)
$connectedNoDownload = @($results | Where-Object { $_.Status -eq 'CONNECTED_NO_DOWNLOAD' })
$rasLocalErrors = @($results | Where-Object { $_.Status -eq 'LOCAL_RAS_ERROR_633_AFTER_RETRY' })
$networkTimeouts = @($results | Where-Object { $_.Status -in @('NETWORK_CONNECT_TIMEOUT', 'SSTP_RAS_TIMEOUT_638') })

Write-Host ("`nRanking mode: {0} (source PING only shortlisted; final order uses measured VPN latency + measured download speed)." -f $RankMode) -ForegroundColor Cyan

Write-Host "`n================ CONFIRMED WORKING SERVERS ================" -ForegroundColor Green
if ($confirmed.Count -gt 0) {
    $confirmed | Select-Object Country, Source, Server, Port, PingMs, VPNLatencyMs, VPNLatencyMethod, TcpConnectMs, DownloadMbps, DownloadSamples, DownloadComplete, SpeedScore, LatencyScore, SelectionScore, VPNConnectSeconds, VPNPublicIP | Format-Table -AutoSize
} else {
    Write-Host 'No server passed all checks (VPN connection + download + changed public IP).' -ForegroundColor Yellow
}

if ($connectedUnverified.Count -gt 0) {
    Write-Host "`n====== CONNECTED, BUT VPN ROUTE WAS NOT FULLY VERIFIED ======" -ForegroundColor Yellow
    $connectedUnverified | Select-Object Country, Source, Server, Port, PingMs, VPNLatencyMs, VPNLatencyMethod, DownloadMbps, SpeedScore, LatencyScore, SelectionScore, PublicIPChanged, Status | Format-Table -AutoSize
}
if ($connectedNoDownload.Count -gt 0) {
    Write-Host "`n====== VPN CONNECTED, BUT INTERNET DOWNLOAD TEST FAILED ======" -ForegroundColor Yellow
    $connectedNoDownload | Select-Object Country, Source, Server, Port, PingMs, VPNLatencyMs, VPNLatencyMethod, VPNConnectSeconds, Status, Error | Format-Table -Wrap -AutoSize
}
if ($rasLocalErrors.Count -gt 0) {
    Write-Host "`n====== LOCAL RAS ERRORS (NOT A SERVER-FAILURE VERDICT) ======" -ForegroundColor Yellow
    $rasLocalErrors | Select-Object Country, Source, Server, Port, Status, Error | Format-Table -Wrap -AutoSize
}
if ($networkTimeouts.Count -gt 0) {
    Write-Host "`n====== SSTP / NETWORK TIMEOUTS ======" -ForegroundColor Yellow
    $networkTimeouts | Select-Object Country, Source, Server, Port, Status, Error | Format-Table -Wrap -AutoSize
}

$vpnCount = @($results | Where-Object { $_.VPNConnected }).Count
$tcpCount = @($results | Where-Object { $_.TcpReachable }).Count
$skippedVpn = @($results | Where-Object { $_.Status -eq 'SKIPPED_AFTER_RAS_STATE_UNCERTAIN' }).Count
Write-Host ("`nFinished: {0} server TCP checks | {1} TCP ports reachable | {2} VPN connections established | {3} confirmed working." -f $results.Count, $tcpCount, $vpnCount, $confirmed.Count) -ForegroundColor Cyan
if ($stopFurtherVpnAttempts) {
    Write-Host ("`nVPN dialing was paused after {0}; {1} later server(s) received TCP-only checks to avoid stale/busy RAS state affecting their results." -f $stopReason, $skippedVpn) -ForegroundColor Yellow
    Write-Host 'To resume VPN testing, start a fresh run after confirming no VPN is active; specify -PriorityServer to test a known-good endpoint first.' -ForegroundColor Yellow
}
Write-Host "Full CSV report (sorted by DownloadMbps descending; includes VPNLatencyMs and SelectionScore): $OutputCsv" -ForegroundColor Cyan
Write-Host 'Speed and latency are observed during this test, not guaranteed long-term VPN values.' -ForegroundColor DarkGray

# ===================== ADD TOP N RANKED SERVERS TO WINDOWS VPN (SKIP DUPLICATES + STORE CREDENTIALS) =====================
if ($AddBestVpnCount -gt 0) {
    Write-Host ("`n=========== ADDING TOP {0} RANKED SERVER(S) TO WINDOWS VPN ===========" -f $AddBestVpnCount) -ForegroundColor Green

    $topServers = @()
    $seenEndpoints = @{}
    foreach ($srv in $confirmed) {
        if ($topServers.Count -ge $AddBestVpnCount) { break }
        $hostKey = ([string]$srv.Host).Trim().TrimEnd('.').ToLowerInvariant()
        $portKey = 443
        try { $portKey = [int]$srv.Port } catch { $portKey = 443 }
        if ([string]::IsNullOrWhiteSpace($hostKey)) { continue }
        $endpointKey = "$hostKey`:$portKey"
        if ($seenEndpoints.ContainsKey($endpointKey)) { continue }
        $seenEndpoints[$endpointKey] = $true
        $topServers += $srv
    }

    if ($topServers.Count -eq 0) {
        Write-Warning 'No confirmed working server was found. Nothing was added to the Windows VPN list.'
    } else {
        $addedNames = @()
        $skippedExisting = @()
        $existingProfiles = @()
        try { $existingProfiles = @(Get-VpnConnection -ErrorAction SilentlyContinue) } catch { $existingProfiles = @() }

        foreach ($srv in $topServers) {
            # Reuse the canonical resolver so IPv6 gets bracketed correctly and
            # host/port are consistent with what the test phase used.
            try {
                $target = Resolve-SstpServerTarget -Server $srv
            } catch {
                Write-Warning ("Could not resolve '{0}': {1}" -f $srv.Server, $_.Exception.GetBaseException().Message)
                continue
            }

            $serverAddress = $target.ServerAddress
            $portUsed = $target.Port
            $hostForName = $target.Host

            # New profile names combine the country with the server host so the
            # installed entry is recognizable in Windows Settings. A missing
            # country name uses a stable fallback instead of an empty prefix.
            $countryForName = ([string]$srv.Country).Trim()
            if ([string]::IsNullOrWhiteSpace($countryForName)) { $countryForName = 'Unknown' }
            $countryForName = $countryForName -replace '[\x00-\x1F\x7F]', ' '
            $countryForName = ($countryForName -replace '\s+', ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($countryForName)) { $countryForName = 'Unknown' }

            $baseProfileName = $hostForName.TrimEnd('.')
            if ([string]::IsNullOrWhiteSpace($baseProfileName)) {
                $baseProfileName = $serverAddress -replace '^\[|\](?::\d+)?$|:\d+$', ''
            }
            if ([string]::IsNullOrWhiteSpace($baseProfileName)) { continue }
            $baseProfileName = "${countryForName} - ${baseProfileName}"
            $newProfileName = if ($portUsed -eq 443) { $baseProfileName } else { "${baseProfileName}-p${portUsed}" }
            if ([string]::IsNullOrWhiteSpace($newProfileName)) { continue }
            # Sanitize characters that are invalid or inconvenient in Windows profile names
            $newProfileName = $newProfileName -replace '[\\/:*?"<>|\[\]]', '_'
            $newProfileName = $newProfileName.Trim()

            # Skip duplicates: same profile name or another profile pointing to
            # the same host/port pair. Never overwrite an existing profile.
            $matchingProfile = $null
            foreach ($existing in $existingProfiles) {
                if ([string]$existing.Name -ieq $newProfileName) {
                    $matchingProfile = $existing
                    break
                }
                try {
                    $existingParsed = Parse-SstpServerAddress -Text ([string]$existing.ServerAddress)
                    if ($existingParsed -and
                        $existingParsed.Host.TrimEnd('.') -ieq $hostForName.TrimEnd('.') -and
                        [int]$existingParsed.Port -eq [int]$portUsed) {
                        $matchingProfile = $existing
                        break
                    }
                } catch { }
            }

            if ($matchingProfile) {
                $skipName = [string]$matchingProfile.Name
                Write-Host ("Skipping duplicate profile '{0}' (a Windows VPN entry already uses {1})." -f $skipName, $serverAddress) -ForegroundColor DarkYellow
                if (-not [string]::IsNullOrWhiteSpace($skipName)) { $skippedExisting += $skipName }
                continue
            }

            Write-Host ("Adding profile '{0}' -> address='{1}' (port={2}, {3}, latency {4} ms, ~{5} Mbps, score {6})" -f `
                $newProfileName, $serverAddress, $portUsed, $srv.Country, $srv.VPNLatencyMs, $srv.DownloadMbps, $srv.SelectionScore) -ForegroundColor Cyan

            try {
                Add-VpnConnection -Name $newProfileName `
                    -ServerAddress $serverAddress `
                    -TunnelType SSTP `
                    -AuthenticationMethod 'MSChapv2' `
                    -EncryptionLevel Optional `
                    -RememberCredential | Out-Null

                Set-VpnConnection -Name $newProfileName -RememberCredential $true -Force -ErrorAction Stop | Out-Null

                $verify = Get-VpnConnection -Name $newProfileName -ErrorAction Stop
                if (-not $verify) {
                    throw "Windows did not return the newly saved VPN profile '$newProfileName'."
                }
                $savedParsed = Parse-SstpServerAddress -Text ([string]$verify.ServerAddress)
                if (-not $savedParsed) {
                    throw "Windows stored an unrecognized ServerAddress '$($verify.ServerAddress)' for profile '$newProfileName'."
                }
                $savedHost = $savedParsed.Host
                $savedPort = $savedParsed.Port
                $portMismatch = ($savedPort -ne $portUsed) -or ($savedHost -ine $hostForName)
                $rememberEnabled = [bool]$verify.RememberCredential
                $profileColor = if ($portMismatch) { 'Red' } else { 'DarkGray' }
                Write-Host ("  Stored: ServerAddress='{0}'  Port={1}  TunnelType={2}  RememberCredential={3}" -f `
                    $verify.ServerAddress, $savedPort, $verify.TunnelType, $rememberEnabled) -ForegroundColor $profileColor
                if ($portMismatch) {
                    throw ("Windows stored host='{0}' port={1} but host='{2}' port={3} was requested." -f $savedHost, $savedPort, $hostForName, $portUsed)
                }
                if ([string]$verify.TunnelType -ne 'Sstp') {
                    throw "Windows stored TunnelType '$($verify.TunnelType)' instead of 'Sstp' for profile '$newProfileName'."
                }
                if (-not $rememberEnabled) {
                    Write-Warning "  RememberCredential could not be verified as enabled for '$newProfileName'."
                }

                # Store the configured username/password in the RAS phone-book
                # entry so the profile can connect without a credential prompt.
                try {
                    Set-VpnConnectionCredentials -ProfileName $newProfileName -UserName $Username -Password $Password -Domain ''
                    Write-Host ("  Credentials stored: username '{0}', password set." -f $Username) -ForegroundColor DarkGray
                } catch {
                    Write-Warning ("  Profile '{0}' was added, but credentials could not be stored: {1}" -f $newProfileName, $_.Exception.GetBaseException().Message)
                }

                $addedNames += $newProfileName
            }
            catch {
                Write-Warning ("Could not add '{0}': {1}" -f $newProfileName, $_.Exception.GetBaseException().Message)
            }
        }

        if ($addedNames.Count -gt 0) {
            Write-Host ("`nSaved {0} new VPN profile(s) to Windows (names combine country and host; port kept in server address):" -f $addedNames.Count) -ForegroundColor Green
            $addedNames | ForEach-Object { Write-Host ("  - {0}" -f $_) -ForegroundColor Green }
            if ($skippedExisting.Count -gt 0) {
                Write-Host "`nSkipped duplicate profile(s) that already existed:" -ForegroundColor Yellow
                $skippedExisting | ForEach-Object { Write-Host ("  - {0}" -f $_) -ForegroundColor Yellow }
            }
            Write-Host ("`nUsername '{0}' and the configured password were stored in the Windows RAS phone-book entries." -f $Username) -ForegroundColor Cyan
            Write-Host 'These profiles are ready to connect from Settings > Network & Internet > VPN without re-entering credentials.' -ForegroundColor DarkGray
            Write-Host 'Verify with: Get-VpnConnection -Name <ProfileName> | Format-List *' -ForegroundColor DarkGray
        } elseif ($skippedExisting.Count -gt 0) {
            Write-Host "`nAll requested profile(s) already existed; nothing new was added." -ForegroundColor Yellow
            $skippedExisting | ForEach-Object { Write-Host ("  - {0}" -f $_) -ForegroundColor Yellow }
        } elseif ($topServers.Count -gt 0) {
            Write-Warning 'None of the top servers could be added to the Windows VPN list.'
        }
    }
}