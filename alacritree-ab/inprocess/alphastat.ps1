# Reports the alpha channel of a capture, which is the only place window
# transparency shows up: a translucent window keeps the clear's alpha, an
# opaque one has 255 everywhere.
param([string]$Path)
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public class Alpha {
  public static string Stat(string path) {
    using (var bmp = new Bitmap(path)) {
      int w = bmp.Width, h = bmp.Height;
      var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      var buf = new byte[data.Stride * h];
      Marshal.Copy(data.Scan0, buf, 0, buf.Length);
      bmp.UnlockBits(data);
      var hist = new int[256];
      for (int i = 3; i < buf.Length; i += 4) hist[buf[i]]++;
      var parts = new System.Collections.Generic.List<string>();
      for (int a = 0; a < 256; a++) if (hist[a] > 0) parts.Add(string.Format("alpha {0}: {1}", a, hist[a]));
      return string.Join("  ", parts);
    }
  }
}
'@ -ReferencedAssemblies System.Drawing, System.Drawing.Primitives
Write-Host ([Alpha]::Stat((Resolve-Path $Path).Path))
