# 说英文 iOS 键盘 · 侧载准备
# 双击运行即可。它只做两件事：把 iTunes 和 AltServer 下到 D 盘，然后按顺序打开安装。
#
# 为什么要 iTunes 和 iCloud：AltServer 靠 iTunes 带的 Apple 设备驱动跟 iPhone 通信，
# iCloud 那份是 AltStore 官方 FAQ 明确列的前置。两个都必须是 Apple 官网版，
# 不能用 Microsoft Store 版。三个链接都实测是活的（2026-08-20）。

$ErrorActionPreference = 'Stop'
$dir = 'D:\_build\sideload'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$items = @(
  @{ Name = 'iTunes64Setup.exe'; Url = 'https://www.apple.com/itunes/download/win64'; MinMB = 150 },
  @{ Name = 'iCloudSetup.exe';   Url = 'https://updates.cdn-apple.com/2020/windows/001-39935-20200911-1A70AA56-F448-11EA-8CC0-99D41950005E/iCloudSetup.exe'; MinMB = 100 },
  @{ Name = 'AltInstaller.zip';  Url = 'https://cdn.altstore.io/file/altstore/altinstaller.zip'; MinMB = 5 }
)

foreach ($it in $items) {
  $out = Join-Path $dir $it.Name
  if (Test-Path $out) {
    $mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
    if ($mb -ge $it.MinMB) { Write-Host ("已有 {0}（{1} MB），跳过下载" -f $it.Name, $mb) -ForegroundColor DarkGray; continue }
    Remove-Item $out -Force
  }
  Write-Host ("正在下载 {0} ..." -f $it.Name) -ForegroundColor Cyan
  Invoke-WebRequest -Uri $it.Url -OutFile $out -UseBasicParsing
  $mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
  # 闸门：下小了多半是下到一个错误页,别让他去装一个坏包
  if ($mb -lt $it.MinMB) { throw ("{0} 只有 {1} MB,明显没下全,别装" -f $it.Name, $mb) }
  Write-Host ("  完成，{0} MB" -f $mb) -ForegroundColor Green
}

# AltInstaller.zip 里是 Setup.exe
$alt = Join-Path $dir 'AltInstaller'
if (Test-Path $alt) { Remove-Item $alt -Recurse -Force }
Expand-Archive -Path (Join-Path $dir 'AltInstaller.zip') -DestinationPath $alt
$setup = Get-ChildItem $alt -Filter 'setup.exe' -Recurse | Select-Object -First 1
if (-not $setup) { throw 'AltInstaller.zip 里没找到 setup.exe' }

Write-Host ''
Write-Host '=== 接下来按顺序做 ===' -ForegroundColor Yellow
Write-Host '1. 先装 iTunes（马上会弹出来）。装完不用打开它。'
Write-Host '2. 再装 iCloud。'
Write-Host '3. 再装 AltServer。'
Write-Host '4. 用数据线把 iPhone 连上电脑，手机解锁，弹「信任这台电脑」点信任。'
Write-Host '5. 右下角托盘里右键 AltServer 图标 → Install AltStore → 选你的 iPhone。'
Write-Host '   会让你填 Apple ID 和密码 —— 这一步是苹果的签名流程，我不经手。'
Write-Host '6. 手机上：设置 → 通用 → VPN与设备管理 → 信任你自己那个开发者证书。'
Write-Host '7. 把 ShuoYingwen.ipa 传到手机（或放在电脑上用 AltServer 装），'
Write-Host '   在手机的 AltStore 里点 + 号选它。'
Write-Host ''
Write-Host ("文件都在：{0}" -f $dir) -ForegroundColor DarkGray
Write-Host ''
Read-Host '按回车开始装 iTunes'
Start-Process (Join-Path $dir 'iTunes64Setup.exe') -Wait
Read-Host 'iTunes 装完了？按回车装 iCloud'
Start-Process (Join-Path $dir 'iCloudSetup.exe') -Wait
Read-Host 'iCloud 装完了？按回车装 AltServer'
Start-Process $setup.FullName -Wait

# 收工闸：装完要真的能查到那两个东西，别拿「安装程序退出了」当成功
Write-Host ''
Write-Host '=== 检查装没装上 ===' -ForegroundColor Yellow
$amds = Get-Service -Name 'Apple Mobile Device Service' -ErrorAction SilentlyContinue
$altOK = (Test-Path 'C:\Program Files\AltServer\AltServer.exe') -or (Test-Path 'C:\Program Files (x86)\AltServer\AltServer.exe')
Write-Host ("  Apple 设备服务: {0}" -f $(if ($amds) { $amds.Status } else { '没找到 —— iTunes 没装成' }))
Write-Host ("  AltServer:      {0}" -f $(if ($altOK) { '已安装' } else { '没找到 —— AltServer 没装成' }))
if ($amds -and $altOK) {
  Write-Host '两样都在，接着做上面第 4 步。' -ForegroundColor Green
} else {
  Write-Host '有东西没装上，截图发给 Claude。' -ForegroundColor Yellow
}
Read-Host '按回车关闭'
