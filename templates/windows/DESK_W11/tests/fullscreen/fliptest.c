// fliptest: stand-in for a borderless-fullscreen game (Unreal-style WS_POPUP
// window covering one monitor, DXGI flip-model swapchain). PresentMon shows
// whether its frames reach the screen as Independent Flip or Composed Flip.
// Like Unreal, it opens as a 1280x720 popup and goes to the target rect 500 ms later
// (GlazeWM only classifies a window as fullscreen on a later size change).
// Pass "now" as the last argument to open at the final size instead (GlazeWM
// then classifies it as fullscreen at manage time, like a game that starts
// borderless-fullscreen).
// usage: fliptest.exe [seconds=20] [monitor-index=0 (primary)] [x y w h] [now]
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_5.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
    if (m == WM_KEYDOWN && w == VK_ESCAPE) { DestroyWindow(h); return 0; }
    return DefWindowProcW(h, m, w, l);
}

typedef struct { int want, n; RECT r; } MonPick;
static BOOL CALLBACK MonEnum(HMONITOR hm, HDC dc, LPRECT rc, LPARAM lp) {
    MonPick *p = (MonPick *)lp;
    MONITORINFO mi = { sizeof mi }; GetMonitorInfoW(hm, &mi);
    if (p->want == 0 ? (mi.dwFlags & MONITORINFOF_PRIMARY) != 0 : p->n == p->want) { p->r = mi.rcMonitor; return FALSE; }
    if (!(mi.dwFlags & MONITORINFOF_PRIMARY)) p->n++;
    return TRUE;
}

int WINAPI WinMain(HINSTANCE hi, HINSTANCE hp, LPSTR cmd, int show) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    int secs = __argc > 1 ? atoi(__argv[1]) : 20;
    MonPick mp = { __argc > 2 ? atoi(__argv[2]) : 0, 1, {0, 0, 1920, 1080} };
    EnumDisplayMonitors(NULL, NULL, MonEnum, (LPARAM)&mp);
    RECT r = mp.r;
    if (__argc > 6) { r.left = atoi(__argv[3]); r.top = atoi(__argv[4]); r.right = r.left + atoi(__argv[5]); r.bottom = r.top + atoi(__argv[6]); }

    int grow_now = 0, gamelike = 0, start_max = 0, max_full = 0, tiled = 0;
    for (int i = 1; i < __argc; i++) {
        if (!strcmp(__argv[i], "now")) grow_now = 1;
        // "gamelike": open a couple of pixels LARGER than the monitor and
        // settle to exactly the monitor rect, the way Aion 2 (Unreal) does.
        // That transition is what made GlazeWM drop the window out of its
        // fullscreen state, leaving the taskbar above the game.
        if (!strcmp(__argv[i], "gamelike")) gamelike = grow_now = 1;
        // "startmax": a normal resizable window that opens MAXIMIZED, the way
        // Age of Empires II DE does. GlazeWM used to un-maximize it and clamp
        // it into the workspace gaps, and the game then took that size as its
        // fullscreen resolution.
        if (!strcmp(__argv[i], "startmax")) start_max = 1;
        // "maxfull": maximized AND covering the whole monitor, which is what
        // Aion 2 becomes after being dragged out and maximized again. Explorer
        // needs the fullscreen mark for it too, or the taskbar sits on top.
        if (!strcmp(__argv[i], "maxfull")) max_full = grow_now = 1;
        // "tiled": an ordinary resizable window with a caption. GlazeWM
        // initializes a window that cannot be resized as floating, so the
        // tiling cases need this shape and not the WS_POPUP one.
        if (!strcmp(__argv[i], "tiled")) tiled = grow_now = 1;
    }
    RECT start = r;
    if (gamelike) { start.left -= 2; start.top -= 2; start.right += 2; start.bottom += 2; }

    WNDCLASSW wc = { 0 }; wc.lpfnWndProc = WndProc; wc.hInstance = hi; wc.lpszClassName = L"FlipTestWnd";
    wc.hCursor = LoadCursor(NULL, IDC_ARROW); RegisterClassW(&wc);
    HWND hwnd = CreateWindowExW(WS_EX_APPWINDOW, L"FlipTestWnd", L"fliptest",
        (start_max ? (WS_OVERLAPPEDWINDOW | WS_MAXIMIZE)
                   : (tiled ? WS_OVERLAPPEDWINDOW
                            : (max_full ? (WS_POPUP | WS_MAXIMIZEBOX) : WS_POPUP))) | WS_VISIBLE,
        grow_now ? start.left : r.left + 100, grow_now ? start.top : r.top + 100,
        grow_now ? start.right - start.left : 1280, grow_now ? start.bottom - start.top : 720, NULL, NULL, hi, NULL);

    if (start_max) ShowWindow(hwnd, SW_SHOWMAXIMIZED);
    if (max_full) {
        ShowWindow(hwnd, SW_SHOWMAXIMIZED);
        SetWindowPos(hwnd, NULL, r.left, r.top, r.right - r.left, r.bottom - r.top,
                     SWP_NOZORDER | SWP_NOSENDCHANGING | SWP_NOACTIVATE);
    }

    ID3D11Device *dev; ID3D11DeviceContext *ctx;
    if (FAILED(D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, &dev, NULL, &ctx))) return 2;
    IDXGIDevice *xd; ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&xd);
    IDXGIAdapter *ad; IDXGIDevice_GetAdapter(xd, &ad);
    IDXGIFactory2 *f; IDXGIAdapter_GetParent(ad, &IID_IDXGIFactory2, (void **)&f);
    IDXGIFactory5 *f5; BOOL tearing = FALSE;
    if (SUCCEEDED(IDXGIFactory2_QueryInterface(f, &IID_IDXGIFactory5, (void **)&f5)))
        IDXGIFactory5_CheckFeatureSupport(f5, DXGI_FEATURE_PRESENT_ALLOW_TEARING, &tearing, sizeof tearing);

    DXGI_SWAP_CHAIN_DESC1 sd = { 0 };
    sd.Width = grow_now ? start.right - start.left : 1280; sd.Height = grow_now ? start.bottom - start.top : 720; sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    sd.SampleDesc.Count = 1; sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT; sd.BufferCount = 2;
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD; sd.Flags = tearing ? DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING : 0;
    IDXGISwapChain1 *sc;
    if (FAILED(IDXGIFactory2_CreateSwapChainForHwnd(f, (IUnknown *)dev, hwnd, &sd, NULL, NULL, &sc))) return 3;
    IDXGIFactory2_MakeWindowAssociation(f, hwnd, DXGI_MWA_NO_ALT_ENTER);
    ID3D11Texture2D *bb; IDXGISwapChain1_GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void **)&bb);
    ID3D11RenderTargetView *rtv; ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)bb, NULL, &rtv);
    SetForegroundWindow(hwnd);

    DWORD started = GetTickCount(); MSG msg; int frame = 0, grown = 0;
    for (;;) {
        if (!grown && !start_max && (gamelike || !grow_now) && GetTickCount() - started > (gamelike ? 700u : 500u)) {
            grown = 1;
            SetWindowPos(hwnd, NULL, r.left, r.top, r.right - r.left, r.bottom - r.top, SWP_NOZORDER);
            ID3D11DeviceContext_OMSetRenderTargets(ctx, 0, NULL, NULL);
            ID3D11RenderTargetView_Release(rtv); ID3D11Texture2D_Release(bb);
            IDXGISwapChain1_ResizeBuffers(sc, 0, r.right - r.left, r.bottom - r.top, DXGI_FORMAT_UNKNOWN, sd.Flags);
            IDXGISwapChain1_GetBuffer(sc, 0, &IID_ID3D11Texture2D, (void **)&bb);
            ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)bb, NULL, &rtv);
        }
        while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) { if (msg.message == WM_QUIT) return 0; TranslateMessage(&msg); DispatchMessageW(&msg); }
        if (secs > 0 && GetTickCount() - started > (DWORD)secs * 1000) { DestroyWindow(hwnd); continue; }
        float t = frame++ / 60.0f, c[4] = { 0.1f + 0.1f * sin(t), 0.1f, 0.2f + 0.1f * cos(t), 1 };
        ID3D11DeviceContext_OMSetRenderTargets(ctx, 1, &rtv, NULL);
        ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, c);
        IDXGISwapChain1_Present(sc, 1, 0);
    }
}
