# Webcam controls through DirectShow (the same values as OBS's "Configure
# Video" dialog): read them, or set one. Works while OBS has the camera open,
# because these are the device's own UVC settings.
#   camctl.ps1                       list every control of every camera
#   camctl.ps1 -Name Kiyo            only cameras whose name matches
#   camctl.ps1 -Name Kiyo -Set Brightness=120,Exposure=-6:manual
# A value with :auto hands that control back to the camera.

param([string]$Name = '', [string[]]$Set = @())

Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace CamCtl {
  [ComImport, Guid("29840822-5B84-11D0-BD3B-00A0C911CE86"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface ICreateDevEnum { [PreserveSig] int CreateClassEnumerator(ref Guid cat, out IEnumMoniker e, int flags); }

  [ComImport, Guid("C6E13360-30AC-11d0-A18C-00A0C9118956"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAMVideoProcAmp {
    [PreserveSig] int GetRange(int p, out int min, out int max, out int step, out int def, out int flags);
    [PreserveSig] int Set(int p, int value, int flags);
    [PreserveSig] int Get(int p, out int value, out int flags);
  }
  [ComImport, Guid("C6E13370-30AC-11d0-A18C-00A0C9118956"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IAMCameraControl {
    [PreserveSig] int GetRange(int p, out int min, out int max, out int step, out int def, out int flags);
    [PreserveSig] int Set(int p, int value, int flags);
    [PreserveSig] int Get(int p, out int value, out int flags);
  }
  [ComImport, Guid("55272A00-42CB-11CE-8135-00AA004BB851"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyBag {
    [PreserveSig] int Read([MarshalAs(UnmanagedType.LPWStr)] string name, ref object val, IntPtr log);
    [PreserveSig] int Write([MarshalAs(UnmanagedType.LPWStr)] string name, ref object val);
  }

  public class Control { public string Camera, Group, Name; public int Id, Min, Max, Step, Default, Value; public bool Auto, CanAuto, Ok; }

  public static class Cams {
    static readonly string[] AMP = { "Brightness", "Contrast", "Hue", "Saturation", "Sharpness", "Gamma", "ColorEnable", "WhiteBalance", "BacklightCompensation", "Gain" };
    static readonly string[] CAM = { "Pan", "Tilt", "Roll", "Zoom", "Exposure", "Iris", "Focus" };
    static Guid VideoInputCat = new Guid("860BB310-5D01-11d0-BD3B-00A0C911CE86");

    static IEnumerable<KeyValuePair<string, object>> Filters(string match) {
      var t = Type.GetTypeFromCLSID(new Guid("62BE5D10-60EB-11d0-BD3B-00A0C911CE86"));
      var de = (ICreateDevEnum)Activator.CreateInstance(t);
      IEnumMoniker em;
      if (de.CreateClassEnumerator(ref VideoInputCat, out em, 0) != 0 || em == null) yield break;
      var arr = new IMoniker[1];
      while (em.Next(1, arr, IntPtr.Zero) == 0) {
        var m = arr[0];
        object bagObj; var bagId = typeof(IPropertyBag).GUID;
        m.BindToStorage(null, null, ref bagId, out bagObj);
        object name = null; ((IPropertyBag)bagObj).Read("FriendlyName", ref name, IntPtr.Zero);
        var n = (name as string) ?? "?";
        if (match != "" && n.IndexOf(match, StringComparison.OrdinalIgnoreCase) < 0) continue;
        object f; var fid = new Guid("56a86895-0ad4-11ce-b03a-0020af0ba770");   // IBaseFilter
        m.BindToObject(null, null, ref fid, out f);
        yield return new KeyValuePair<string, object>(n, f);
      }
    }

    public static List<Control> List(string match) {
      var list = new List<Control>();
      foreach (var kv in Filters(match)) {
        var amp = kv.Value as IAMVideoProcAmp;
        if (amp != null) for (int i = 0; i < AMP.Length; i++) list.Add(Read(kv.Key, "VideoProcAmp", AMP[i], i, amp.GetRange, amp.Get));
        var cam = kv.Value as IAMCameraControl;
        if (cam != null) for (int i = 0; i < CAM.Length; i++) list.Add(Read(kv.Key, "CameraControl", CAM[i], i, cam.GetRange, cam.Get));
      }
      return list;
    }

    delegate int RangeFn(int p, out int min, out int max, out int step, out int def, out int flags);
    delegate int GetFn(int p, out int value, out int flags);
    static Control Read(string camName, string group, string name, int id, RangeFn range, GetFn get) {
      var c = new Control { Camera = camName, Group = group, Name = name, Id = id };
      int min, max, step, def, flags, v, vf;
      if (range(id, out min, out max, out step, out def, out flags) != 0) return c;
      c.Min = min; c.Max = max; c.Step = step; c.Default = def; c.CanAuto = (flags & 1) != 0;
      if (get(id, out v, out vf) == 0) { c.Value = v; c.Auto = (vf & 1) != 0; c.Ok = true; }
      return c;
    }

    public static string Set(string match, string name, int value, bool auto) {
      foreach (var kv in Filters(match)) {
        int i = Array.IndexOf(AMP, name);
        var amp = kv.Value as IAMVideoProcAmp;
        if (i >= 0 && amp != null) return kv.Key + ": " + name + " -> " + (amp.Set(i, value, auto ? 1 : 2) == 0 ? "ok" : "refused");
        i = Array.IndexOf(CAM, name);
        var cam = kv.Value as IAMCameraControl;
        if (i >= 0 && cam != null) return kv.Key + ": " + name + " -> " + (cam.Set(i, value, auto ? 1 : 2) == 0 ? "ok" : "refused");
      }
      return "no camera or control named " + name;
    }
  }
}
'@

# -File passes one string, so several settings come comma-separated.
$Set = @($Set | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
foreach ($s in $Set) {
    if ($s -notmatch '^(\w+)=(-?\d+)(:auto|:manual)?$') { "bad -Set '$s' (use Name=value or Name=value:auto)"; continue }
    [CamCtl.Cams]::Set($Name, $Matches[1], [int]$Matches[2], $Matches[3] -eq ':auto')
}
[CamCtl.Cams]::List($Name) | Where-Object Ok | ForEach-Object {
    "{0,-20} {1,-22} {2,6}  range {3}..{4} step {5}  default {6}{7}" -f $_.Camera, $_.Name, $_.Value, $_.Min, $_.Max, $_.Step, $_.Default, $(if ($_.CanAuto) { if ($_.Auto) { '  AUTO' } else { '  manual' } } else { '' })
}
