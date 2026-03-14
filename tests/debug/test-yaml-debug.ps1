Import-Module powershell-yaml -ErrorAction Stop

$yamlTest = @"
- Name: Parent
  roles:
  - admin
  children:
  - Name: Child1
    url: /test1
  - Name: Child2
    url: /test2
    roles:
    - authenticated
"@

$data = $yamlTest | ConvertFrom-Yaml

Write-Host "=== Parent item ===" -ForegroundColor Cyan
Write-Host "  Name: $($data[0].Name)"
Write-Host "  Roles: $($data[0].roles -join ', ')"
Write-Host "  Roles Count: $($data[0].roles.count)"

Write-Host "`n=== Child1 (no roles defined) ===" -ForegroundColor Cyan
$child1 = $data[0].children[0]
Write-Host "  Name: $($child1.Name)"
Write-Host "  Roles value: [$($child1.roles)]"
Write-Host "  Roles is null: $($null -eq $child1.roles)"
Write-Host "  Roles count: $($child1.roles.count)"

Write-Host "`n=== Child2 (roles defined) ===" -ForegroundColor Cyan
$child2 = $data[0].children[1]
Write-Host "  Name: $($child2.Name)"
Write-Host "  Roles value: [$($child2.roles)]"
Write-Host "  Roles is null: $($null -eq $child2.roles)"
Write-Host "  Roles count: $($child2.roles.count)"
