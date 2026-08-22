/**
 * 把任意张图拼成对比图
 * 用法: node make-contact.js <output.png> <title> <img1> <img2> ... [--cols=N]
 * 默认 2 列，每张缩略图 380×280
 */
const path = require('path');
const { spawnSync } = require('child_process');

const args = process.argv.slice(2);
const outFile = args.shift();
const title = args.shift();
const colArg = args.find(a => a.startsWith('--cols='));
const cols = colArg ? parseInt(colArg.slice(7)) : 2;
const files = args.filter(a => !a.startsWith('--'));

if (!outFile || !files.length) {
  console.error('Usage: node make-contact.js <output.png> <title> <img1> <img2> ... [--cols=N]');
  process.exit(2);
}

const psScript = `
Add-Type -AssemblyName System.Drawing
$files = @(${files.map(f => `'${f.replace(/'/g, "''")}'`).join(',')})
$cols = ${cols}
$rows = [math]::Ceiling($files.Count / $cols)
$thumbW = 400; $thumbH = 300; $labelH = 36; $titleH = 44
$sheetW = $thumbW * $cols
$sheetH = $titleH + ($thumbH + $labelH) * $rows
$sheet = New-Object Drawing.Bitmap $sheetW, $sheetH
$g = [Drawing.Graphics]::FromImage($sheet)
$g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([Drawing.Color]::FromArgb(20,20,24))
$titleFont = New-Object Drawing.Font('Segoe UI',14,[Drawing.FontStyle]::Bold)
$labelFont = New-Object Drawing.Font('Segoe UI',12,[Drawing.FontStyle]::Bold)
$g.DrawString('${title.replace(/'/g, "''")}', $titleFont, [Drawing.Brushes]::White, 16, 12)
for ($i = 0; $i -lt $files.Count; $i++) {
  $img = [Drawing.Image]::FromFile($files[$i])
  $col = $i % $cols
  $row = [math]::Floor($i / $cols)
  $x = $col * $thumbW
  $y = $titleH + $row * ($thumbH + $labelH)
  $label = [System.IO.Path]::GetFileNameWithoutExtension($files[$i])
  $g.DrawString($label, $labelFont, [Drawing.Brushes]::LightGray, $x + 8, $y + 6)
  $scale = [math]::Min(($thumbW - 20) / $img.Width, ($thumbH - 10) / $img.Height)
  $w = [int]($img.Width * $scale)
  $h = [int]($img.Height * $scale)
  $dx = $x + [int](($thumbW - $w) / 2)
  $dy = $y + $labelH + [int](($thumbH - $h) / 2)
  $g.DrawImage($img, $dx, $dy, $w, $h)
  $img.Dispose()
}
$sheet.Save('${outFile.replace(/'/g, "''")}', [Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $sheet.Dispose()
Write-Output ('SAVED ${outFile.replace(/'/g, "''").replace(/\\/g, '\\\\')}')
`;

const r = spawnSync('powershell', ['-NoProfile', '-Command', psScript], { encoding: 'utf8' });
if (r.status !== 0) {
  console.error(r.stderr || r.stdout);
  process.exit(1);
}
console.log(r.stdout.trim());
