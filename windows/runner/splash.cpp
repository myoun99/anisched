#include "splash.h"

#include <windows.h>
#include <wincodec.h>

#include <string>

namespace {

HWND g_splash = nullptr;
constexpr wchar_t kClass[] = L"ANISCHED_SPLASH";

// data\flutter_assets\assets\app_art\splash.png next to the executable.
std::wstring SplashPath() {
  wchar_t exe[MAX_PATH];
  DWORD n = ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
  std::wstring dir(exe, n);
  dir = dir.substr(0, dir.find_last_of(L"\\/"));
  return dir + L"\\data\\flutter_assets\\assets\\app_art\\splash.png";
}

// The picture scaled to [height], premultiplied BGRA, as a DIB section.
HBITMAP LoadScaled(const std::wstring& path, UINT height, UINT* width) {
  IWICImagingFactory* factory = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory)))) {
    return nullptr;
  }
  HBITMAP bitmap = nullptr;
  IWICBitmapDecoder* decoder = nullptr;
  IWICBitmapFrameDecode* frame = nullptr;
  IWICFormatConverter* converter = nullptr;
  IWICBitmapScaler* scaler = nullptr;
  UINT w = 0, h = 0;
  if (SUCCEEDED(factory->CreateDecoderFromFilename(
          path.c_str(), nullptr, GENERIC_READ,
          WICDecodeMetadataCacheOnDemand, &decoder)) &&
      SUCCEEDED(decoder->GetFrame(0, &frame)) &&
      SUCCEEDED(frame->GetSize(&w, &h)) && h > 0 &&
      SUCCEEDED(factory->CreateFormatConverter(&converter)) &&
      SUCCEEDED(converter->Initialize(frame, GUID_WICPixelFormat32bppPBGRA,
                                      WICBitmapDitherTypeNone, nullptr, 0.0,
                                      WICBitmapPaletteTypeCustom)) &&
      SUCCEEDED(factory->CreateBitmapScaler(&scaler))) {
    // Only ever scaled down (the picture is drawn for a 5K screen).
    UINT th = height < h ? height : h;
    UINT tw = static_cast<UINT>(static_cast<double>(w) * th / h);
    if (SUCCEEDED(scaler->Initialize(converter, tw, th,
                                     WICBitmapInterpolationModeHighQualityCubic))) {
      BITMAPINFO info = {};
      info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
      info.bmiHeader.biWidth = static_cast<LONG>(tw);
      info.bmiHeader.biHeight = -static_cast<LONG>(th);  // top-down
      info.bmiHeader.biPlanes = 1;
      info.bmiHeader.biBitCount = 32;
      info.bmiHeader.biCompression = BI_RGB;
      void* bits = nullptr;
      bitmap = ::CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &bits,
                                  nullptr, 0);
      if (bitmap &&
          FAILED(scaler->CopyPixels(nullptr, tw * 4, tw * th * 4,
                                    static_cast<BYTE*>(bits)))) {
        ::DeleteObject(bitmap);
        bitmap = nullptr;
      }
      *width = tw;
    }
  }
  if (scaler) scaler->Release();
  if (converter) converter->Release();
  if (frame) frame->Release();
  if (decoder) decoder->Release();
  factory->Release();
  return bitmap;
}

}  // namespace

void ShowSplash() {
  if (g_splash) return;
  HINSTANCE instance = ::GetModuleHandleW(nullptr);
  WNDCLASSW cls = {};
  cls.lpfnWndProc = ::DefWindowProcW;
  cls.hInstance = instance;
  cls.lpszClassName = kClass;
  ::RegisterClassW(&cls);

  // Half the short side of the monitor under the cursor.
  POINT cursor;
  ::GetCursorPos(&cursor);
  MONITORINFO mi = {sizeof(mi)};
  ::GetMonitorInfoW(::MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY),
                    &mi);
  const RECT work = mi.rcWork;
  const LONG mw = work.right - work.left;
  const LONG mh = work.bottom - work.top;
  const UINT height = static_cast<UINT>((mw < mh ? mw : mh) / 2);

  UINT width = 0;
  HBITMAP bitmap = LoadScaled(SplashPath(), height, &width);
  if (!bitmap) return;
  BITMAP bm;
  ::GetObject(bitmap, sizeof(bm), &bm);

  POINT pos = {work.left + (mw - bm.bmWidth) / 2,
               work.top + (mh - bm.bmHeight) / 2};
  SIZE size = {bm.bmWidth, bm.bmHeight};
  g_splash = ::CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kClass, L"", WS_POPUP, pos.x, pos.y, size.cx, size.cy, nullptr,
      nullptr, instance, nullptr);
  if (!g_splash) {
    ::DeleteObject(bitmap);
    return;
  }
  HDC screen = ::GetDC(nullptr);
  HDC memory = ::CreateCompatibleDC(screen);
  HGDIOBJ old = ::SelectObject(memory, bitmap);
  POINT origin = {0, 0};
  BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  ::UpdateLayeredWindow(g_splash, screen, &pos, &size, memory, &origin, 0,
                        &blend, ULW_ALPHA);
  ::SelectObject(memory, old);
  ::DeleteDC(memory);
  ::ReleaseDC(nullptr, screen);
  ::DeleteObject(bitmap);
  ::ShowWindow(g_splash, SW_SHOWNOACTIVATE);
}

void CloseSplash() {
  if (!g_splash) return;
  ::DestroyWindow(g_splash);
  g_splash = nullptr;
}
