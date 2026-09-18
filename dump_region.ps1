$f = "lib\ui\admin\pages\admin_dashboard_page.dart"
$lines = Get-Content -LiteralPath $f
Write-Output "TOTAL LINES: $($lines.Count)"
for ($n = 1640; $n -le 1775; $n++) {
  if ($n -le $lines.Count) {
    "{0}:{1}" -f $n, $lines[$n-1]
  }
}
