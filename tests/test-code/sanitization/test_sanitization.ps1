
$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\..\..").Path
Import-Module (Join-Path $ProjectRoot 'tests\modules\TestCodeHelpers.psm1') -ErrorAction Continue -Force -DisableNameChecking
$modulePath = Join-Path $ProjectRoot 'modules\Sanitization\Sanitization.psm1'
if (Test-Path $modulePath) { Import-Module (Resolve-Path $modulePath).ProviderPath -Force }

# Test cases for HTML sanitization
$tests = @(
	@{ Name='EncodeScriptTags'; Input="<script>alert('XSS')</script>"; Expected="&lt;script&gt;alert(&#39;XSS&#39;)&lt;/script&gt;" }
	@{ Name='EmptyString'; Input=''; Expected='' }
	@{ Name='NoChange'; Input='Hello World'; Expected='Hello World' }
	@{ Name='MixedContent'; Input='User: <John Doe> & Co.'; Expected='User: &lt;John Doe&gt; &amp; Co.' }
)
foreach ($t in $tests) {
	$actual = Sanitize-HtmlInput -InputString $t.Input
	Assert-Equal -Actual $actual -Expected $t.Expected -Message $t.Name | Out-Null
}

# Path tests
$tempBase = Join-Path ([System.IO.Path]::GetTempPath()) 'PSTest_Sanitize'
New-Item -Path $tempBase -ItemType Directory -Force | Out-Null
try {
	$safe = Sanitize-FilePath -FilePath 'subfolder\file.txt' -BaseDirectory $tempBase
	Assert-Equal -Actual $safe.Score -Expected 'pass' -Message 'Sanitize-FilePath should pass' | Out-Null
	Assert-True -Condition (Test-Path (Split-Path $safe -Parent)) -Message 'Sanitize-FilePath returns valid path' | Out-Null
	# traversal test - expect an error
	$unsafe = Sanitize-FilePath -FilePath 'sub\..\..\Windows\win.ini' -BaseDirectory $tempBase
	Assert-Equal -Actual $unsafe.Score -Expected 'fail' -Message 'Sanitize-FilePath should fail' | Out-Null
} finally {
	Remove-Item -Path $tempBase -Recurse -Force -ErrorAction SilentlyContinue
}
