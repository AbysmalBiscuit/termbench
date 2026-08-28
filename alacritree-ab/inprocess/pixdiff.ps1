# Compares two captures of the same static screen and reports how many pixels
# differ and by how much. A shader rewrite that claims to preserve output has
# to answer here, not in an argument about colour spaces.
param([string]$A, [string]$B)
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public class Pix {
  public static byte[] Load(string path, out int w, out int h) {
    using (var bmp = new Bitmap(path)) {
      w = bmp.Width; h = bmp.Height;
      var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      var buf = new byte[data.Stride * h];
      Marshal.Copy(data.Scan0, buf, 0, buf.Length);
      bmp.UnlockBits(data);
      return buf;
    }
  }
  // Largest per-channel delta, and how many pixels carry any at all.
  public static string Compare(string a, string b) {
    int wa, ha, wb, hb;
    var x = Load(a, out wa, out ha);
    var y = Load(b, out wb, out hb);
    if (wa != wb || ha != hb) return string.Format("size mismatch: {0}x{1} vs {2}x{3}", wa, ha, wb, hb);
    int worst = 0, differing = 0;
    for (int i = 0; i < x.Length; i += 4) {
      int d = 0;
      for (int c = 0; c < 3; c++) {
        int t = Math.Abs(x[i + c] - y[i + c]);
        if (t > d) d = t;
      }
      if (d > 0) { differing++; if (d > worst) worst = d; }
    }
    return string.Format("{0}x{1}  differing pixels: {2} / {3}  worst channel delta: {4}",
                         wa, ha, differing, x.Length / 4, worst);
  }
}
'@ -ReferencedAssemblies System.Drawing, System.Drawing.Primitives
Write-Host ([Pix]::Compare((Resolve-Path $A).Path, (Resolve-Path $B).Path))
