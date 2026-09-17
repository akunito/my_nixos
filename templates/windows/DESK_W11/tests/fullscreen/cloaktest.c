// cloaktest: does a NON-elevated process manage to cloak/uncloak another window
// through the shell (IApplicationView::SetCloak, what GlazeWM and the native
// virtual desktops use)? Also reports DWMWA_CLOAKED before and after.
// usage: cloaktest.exe <hwnd-decimal> <1=cloak|0=uncloak>
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <shobjidl.h>
#include <dwmapi.h>
#include <stdio.h>
#include <stdlib.h>

static const GUID CLSID_ImmersiveShell = { 0xC2F03A33, 0x21F5, 0x47FA, { 0xB4, 0xBB, 0x15, 0x63, 0x62, 0xA2, 0xF2, 0x39 } };
static const GUID IID_IApplicationViewCollection = { 0x1841C6D7, 0x4F9D, 0x42C0, { 0xAF, 0x41, 0x87, 0x47, 0x53, 0x8F, 0x10, 0xE5 } };

typedef struct IAppView IAppView;
typedef struct { HRESULT (STDMETHODCALLTYPE *QueryInterface)(IAppView *, REFIID, void **);
  ULONG (STDMETHODCALLTYPE *AddRef)(IAppView *); ULONG (STDMETHODCALLTYPE *Release)(IAppView *);
  void *m1, *m2, *m3, *m4, *m5, *m6, *m7, *m8, *m9;
  HRESULT (STDMETHODCALLTYPE *SetCloak)(IAppView *, UINT, INT); } IAppViewVtbl;
struct IAppView { IAppViewVtbl *lpVtbl; };

typedef struct IAppViewCollection IAppViewCollection;
typedef struct { HRESULT (STDMETHODCALLTYPE *QueryInterface)(IAppViewCollection *, REFIID, void **);
  ULONG (STDMETHODCALLTYPE *AddRef)(IAppViewCollection *); ULONG (STDMETHODCALLTYPE *Release)(IAppViewCollection *);
  void *m1, *m2, *m3;
  HRESULT (STDMETHODCALLTYPE *GetViewForHwnd)(IAppViewCollection *, HWND, IAppView **); } IAppViewCollectionVtbl;
struct IAppViewCollection { IAppViewCollectionVtbl *lpVtbl; };

static int cloaked(HWND h) { int v = -1; DwmGetWindowAttribute(h, 14, &v, sizeof v); return v; }

int main(int argc, char **argv) {
    if (argc < 3) { printf("usage: cloaktest <hwnd> <1|0>\n"); return 1; }
    HWND hwnd = (HWND)(LONG_PTR)atoll(argv[1]);
    int want = atoi(argv[2]);
    printf("hwnd=%lld cloaked-before=%d\n", (long long)(LONG_PTR)hwnd, cloaked(hwnd));

    CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    IServiceProvider *sp = NULL;
    HRESULT hr = CoCreateInstance(&CLSID_ImmersiveShell, NULL, CLSCTX_ALL, &IID_IServiceProvider, (void **)&sp);
    printf("CoCreateInstance(ImmersiveShell) = 0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 2;
    IAppViewCollection *col = NULL;
    hr = IServiceProvider_QueryService(sp, &IID_IApplicationViewCollection, &IID_IApplicationViewCollection, (void **)&col);
    printf("QueryService(IApplicationViewCollection) = 0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 3;
    IAppView *view = NULL;
    hr = col->lpVtbl->GetViewForHwnd(col, hwnd, &view);
    printf("GetViewForHwnd = 0x%08lx view=%p\n", (unsigned long)hr, (void *)view);
    if (FAILED(hr) || !view) return 4;
    hr = view->lpVtbl->SetCloak(view, 1, want ? 2 : 0);
    printf("SetCloak(1,%d) = 0x%08lx\n", want ? 2 : 0, (unsigned long)hr);
    Sleep(400);
    printf("cloaked-after=%d\n", cloaked(hwnd));
    return 0;
}
