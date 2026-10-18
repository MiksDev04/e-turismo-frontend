$path = "lib\ui\admin\pages\admin_dashboard_page.dart"
$content = [System.IO.File]::ReadAllText($path)
$builds = [regex]::Matches($content, "Widget\s+build\s*\(").Count
Write-Output "build( occurrences: $builds"
$segIdx = $content.IndexOf('List<_Segment> get _segments {')
Write-Output "segments getter at char index: $segIdx"
if ($segIdx -ge 0) {
  Write-Output "--- snippet ---"
  Write-Output $content.Substring($segIdx, [Math]::Min(2200, $content.Length - $segIdx))
}
