using System;
using System.Runtime.InteropServices;

namespace Lineup.NativePlayerHost
{
    internal static class MpvCommandExecutor
    {
        public static int SetPropertyString(IntPtr mpv, string name, string value)
        {
            return Program.NativeMethods.mpv_set_property_string(mpv, name, value);
        }

        public static string? GetPropertyString(IntPtr mpv, string name)
        {
            IntPtr ptr = Program.NativeMethods.mpv_get_property_string(mpv, name);
            if (ptr == IntPtr.Zero)
            {
                return null;
            }
            try
            {
                return Marshal.PtrToStringAnsi(ptr);
            }
            finally
            {
                Program.NativeMethods.mpv_free(ptr);
            }
        }

        public static int Command(IntPtr mpv, params string[] command)
        {
            IntPtr[] pointers = new IntPtr[command.Length + 1];
            IntPtr argv = IntPtr.Zero;
            try
            {
                for (int index = 0; index < command.Length; index += 1)
                {
                    pointers[index] = Marshal.StringToHGlobalAnsi(command[index]);
                }

                argv = Marshal.AllocHGlobal(IntPtr.Size * pointers.Length);
                Marshal.Copy(pointers, 0, argv, pointers.Length);
                return Program.NativeMethods.mpv_command(mpv, argv);
            }
            finally
            {
                if (argv != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(argv);
                }
                foreach (IntPtr pointer in pointers)
                {
                    if (pointer != IntPtr.Zero)
                    {
                        Marshal.FreeHGlobal(pointer);
                    }
                }
            }
        }
    }
}
