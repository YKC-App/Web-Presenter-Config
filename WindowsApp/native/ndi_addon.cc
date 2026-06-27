/**
 * ndi_addon.cc — Node.js NAPI addon wrapping the NDI SDK.
 *
 * Exposes:
 *   init()  → bool
 *   destroy() → void
 *   startFind(callback: (sources: RawSource[]) => void) → void
 *   stopFind() → void
 *   createReceiver(sourceId: string, opts: ReceiverOptions) → number (handle)
 *   destroyReceiver(handle: number) → void
 *   startCapture(handle: number, callback: FrameCallback) → void
 *   sendPtz(handle: number, type: string, args: number[]) → void
 *
 * Threading: NDI callbacks fire on background threads; NAPI ThreadSafeFunction
 * is used to marshal calls to the Node.js thread safely.
 */

#include <napi.h>
#include <Processing.NDI.Lib.h>

#include <atomic>
#include <cstring>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// ─────────────────────────────────────────────────────────────
//  Global NDI instance
// ─────────────────────────────────────────────────────────────

static const NDIlib_v5* g_ndi = nullptr;

// ─────────────────────────────────────────────────────────────
//  Source discovery
// ─────────────────────────────────────────────────────────────

struct FindState {
    NDIlib_find_instance_t  finder = nullptr;
    std::thread             thread;
    std::atomic<bool>       running{ false };
    Napi::ThreadSafeFunction tsfn;
};

static FindState g_find;

struct RawSource {
    std::string id;
    std::string name;
    std::string machineName;
};

static void FindThreadFunc() {
    while (g_find.running) {
        g_ndi->find_wait_for_sources(g_find.finder, 1000 /* ms */);
        if (!g_find.running) break;

        uint32_t count = 0;
        const NDIlib_source_t* srcs = g_ndi->find_get_current_sources(g_find.finder, &count);

        std::vector<RawSource> items;
        for (uint32_t i = 0; i < count; ++i) {
            RawSource r;
            r.id   = srcs[i].p_ndi_name ? srcs[i].p_ndi_name : "";
            r.name = srcs[i].p_ndi_name ? srcs[i].p_ndi_name : "";
            r.machineName = srcs[i].p_url_address ? srcs[i].p_url_address : "";
            items.push_back(r);
        }

        auto* data = new std::vector<RawSource>(std::move(items));
        g_find.tsfn.NonBlockingCall(data, [](Napi::Env env, Napi::Function cb, std::vector<RawSource>* d) {
            auto arr = Napi::Array::New(env, d->size());
            for (size_t i = 0; i < d->size(); ++i) {
                auto obj = Napi::Object::New(env);
                obj.Set("id",          Napi::String::New(env, (*d)[i].id));
                obj.Set("name",        Napi::String::New(env, (*d)[i].name));
                obj.Set("machineName", Napi::String::New(env, (*d)[i].machineName));
                arr.Set((uint32_t)i, obj);
            }
            cb.Call({ arr });
            delete d;
        });
    }
    g_find.tsfn.Release();
}

// ─────────────────────────────────────────────────────────────
//  Per-receiver state
// ─────────────────────────────────────────────────────────────

struct ReceiverState {
    NDIlib_recv_instance_t recv = nullptr;
    std::thread            thread;
    std::atomic<bool>      running{ false };
    Napi::ThreadSafeFunction tsfn;
    std::string            sourceId;
};

static std::mutex                            g_recvMu;
static std::map<uint32_t, ReceiverState*>    g_receivers;
static std::atomic<uint32_t>                 g_nextHandle{ 1 };

struct FrameData {
    std::string  sourceId;
    int          width, height;
    std::vector<uint8_t> rgba;
    int64_t      timestampMs;
    bool         isTally;
    bool         pgm, pvw;
};

static void RecvThreadFunc(uint32_t handle) {
    ReceiverState* rs;
    {
        std::lock_guard<std::mutex> lk(g_recvMu);
        auto it = g_receivers.find(handle);
        if (it == g_receivers.end()) return;
        rs = it->second;
    }

    while (rs->running) {
        NDIlib_video_frame_v2_t  vf = {};
        NDIlib_metadata_frame_t  mf = {};

        auto ftype = g_ndi->recv_capture_v3(rs->recv, &vf, nullptr, &mf, 100 /* ms */);

        if (ftype == NDIlib_frame_type_video) {
            auto* fd       = new FrameData();
            fd->sourceId   = rs->sourceId;
            fd->width      = vf.xres;
            fd->height     = vf.yres;
            fd->timestampMs = vf.timestamp / 10000; // 100ns → ms
            fd->isTally    = false;

            // Convert to RGBA. NDI gives BGRA or BGRX with NDIlib_recv_color_format_BGRX_BGRA.
            size_t bytes = (size_t)vf.xres * vf.yres * 4;
            fd->rgba.resize(bytes);
            const uint8_t* src = vf.p_data;
            uint8_t*       dst = fd->rgba.data();
            for (size_t i = 0; i < bytes; i += 4) {
                dst[i+0] = src[i+2]; // R ← B
                dst[i+1] = src[i+1]; // G
                dst[i+2] = src[i+0]; // B ← R
                dst[i+3] = 255;       // A
            }
            g_ndi->recv_free_video_v2(rs->recv, &vf);

            rs->tsfn.NonBlockingCall(fd, [](Napi::Env env, Napi::Function cb, FrameData* fd) {
                auto buf = Napi::Buffer<uint8_t>::Copy(env, fd->rgba.data(), fd->rgba.size());
                cb.Call({
                    buf,
                    Napi::Number::New(env, fd->width),
                    Napi::Number::New(env, fd->height),
                    Napi::Number::New(env, (double)fd->timestampMs),
                    Napi::String::New(env, "video"),
                    env.Undefined(),
                    env.Undefined(),
                });
                delete fd;
            });

        } else if (ftype == NDIlib_frame_type_metadata) {
            // Tally parsing (NDI tally comes as XML metadata)
            std::string xml = mf.p_data ? mf.p_data : "";
            g_ndi->recv_free_metadata(rs->recv, &mf);

            bool pgm = xml.find("on_program=\"true\"")  != std::string::npos;
            bool pvw = xml.find("on_preview=\"true\"")  != std::string::npos;
            if (pgm || pvw) {
                auto* fd    = new FrameData();
                fd->sourceId = rs->sourceId;
                fd->isTally  = true;
                fd->pgm      = pgm;
                fd->pvw      = pvw;
                fd->timestampMs = 0;

                rs->tsfn.NonBlockingCall(fd, [](Napi::Env env, Napi::Function cb, FrameData* fd) {
                    cb.Call({
                        env.Undefined(),
                        Napi::Number::New(env, 0),
                        Napi::Number::New(env, 0),
                        Napi::Number::New(env, 0),
                        Napi::String::New(env, "tally"),
                        Napi::Boolean::New(env, fd->pgm),
                        Napi::Boolean::New(env, fd->pvw),
                    });
                    delete fd;
                });
            }
        } else {
            // NDIlib_frame_type_none — timeout, loop
        }
    }
    rs->tsfn.Release();
}

// ─────────────────────────────────────────────────────────────
//  Exported functions
// ─────────────────────────────────────────────────────────────

static Napi::Value Init(const Napi::CallbackInfo& info) {
    auto env = info.Env();
    if (g_ndi) return Napi::Boolean::New(env, true);

    if (!NDIlib_is_supported_CPU()) {
        return Napi::Boolean::New(env, false);
    }
    g_ndi = NDIlib_v5_load();
    if (!g_ndi || !g_ndi->initialize()) {
        g_ndi = nullptr;
        return Napi::Boolean::New(env, false);
    }
    return Napi::Boolean::New(env, true);
}

static Napi::Value Destroy(const Napi::CallbackInfo& info) {
    if (g_ndi) {
        g_ndi->destroy();
        g_ndi = nullptr;
    }
    return info.Env().Undefined();
}

static Napi::Value StartFind(const Napi::CallbackInfo& info) {
    auto env = info.Env();
    if (!g_ndi) Napi::Error::New(env, "NDI not initialized").ThrowAsJavaScriptException();

    auto cb = info[0].As<Napi::Function>();
    g_find.tsfn = Napi::ThreadSafeFunction::New(env, cb, "NdiFind", 0, 1);

    NDIlib_find_create_t create = {};
    create.show_local_sources = true;
    g_find.finder  = g_ndi->find_create_v2(&create);
    g_find.running = true;
    g_find.thread  = std::thread(FindThreadFunc);

    return env.Undefined();
}

static Napi::Value StopFind(const Napi::CallbackInfo& info) {
    g_find.running = false;
    if (g_find.finder) {
        g_ndi->find_destroy(g_find.finder);
        g_find.finder = nullptr;
    }
    if (g_find.thread.joinable()) g_find.thread.join();
    return info.Env().Undefined();
}

static Napi::Value CreateReceiver(const Napi::CallbackInfo& info) {
    auto env      = info.Env();
    auto sourceId = info[0].As<Napi::String>().Utf8Value();
    // opts: { maxWidth, maxHeight, colorFormat }

    NDIlib_recv_create_v3_t rc = {};
    rc.source_to_connect_to.p_ndi_name = sourceId.c_str();
    rc.color_format   = NDIlib_recv_color_format_BGRX_BGRA;
    rc.bandwidth      = NDIlib_recv_bandwidth_highest;
    rc.allow_video_fields = false;

    auto* rs   = new ReceiverState();
    rs->recv   = g_ndi->recv_create_v3(&rc);
    rs->sourceId = sourceId;

    uint32_t handle = g_nextHandle.fetch_add(1);
    {
        std::lock_guard<std::mutex> lk(g_recvMu);
        g_receivers[handle] = rs;
    }
    return Napi::Number::New(env, handle);
}

static Napi::Value DestroyReceiver(const Napi::CallbackInfo& info) {
    uint32_t handle = info[0].As<Napi::Number>().Uint32Value();
    ReceiverState* rs = nullptr;
    {
        std::lock_guard<std::mutex> lk(g_recvMu);
        auto it = g_receivers.find(handle);
        if (it == g_receivers.end()) return info.Env().Undefined();
        rs = it->second;
        g_receivers.erase(it);
    }
    rs->running = false;
    if (rs->thread.joinable()) rs->thread.join();
    if (rs->recv) g_ndi->recv_destroy(rs->recv);
    delete rs;
    return info.Env().Undefined();
}

static Napi::Value StartCapture(const Napi::CallbackInfo& info) {
    auto env    = info.Env();
    uint32_t h  = info[0].As<Napi::Number>().Uint32Value();
    auto cb     = info[1].As<Napi::Function>();

    ReceiverState* rs;
    {
        std::lock_guard<std::mutex> lk(g_recvMu);
        auto it = g_receivers.find(h);
        if (it == g_receivers.end()) return env.Undefined();
        rs = it->second;
    }

    rs->tsfn    = Napi::ThreadSafeFunction::New(env, cb, "NdiRecv", 0, 1);
    rs->running = true;
    rs->thread  = std::thread(RecvThreadFunc, h);

    return env.Undefined();
}

static Napi::Value SendPtz(const Napi::CallbackInfo& info) {
    auto env    = info.Env();
    uint32_t h  = info[0].As<Napi::Number>().Uint32Value();
    auto type   = info[1].As<Napi::String>().Utf8Value();
    auto args   = info[2].As<Napi::Array>();

    ReceiverState* rs;
    {
        std::lock_guard<std::mutex> lk(g_recvMu);
        auto it = g_receivers.find(h);
        if (it == g_receivers.end()) return env.Undefined();
        rs = it->second;
    }

    auto get = [&](uint32_t i, double def = 0.0) -> double {
        return args.Length() > i ? args.Get(i).As<Napi::Number>().DoubleValue() : def;
    };

    if (type == "panTilt") {
        g_ndi->recv_ptz_pan_tilt_speed(rs->recv, (float)get(0), (float)get(1));
    } else if (type == "zoom") {
        g_ndi->recv_ptz_zoom_speed(rs->recv, (float)get(0));
    } else if (type == "autoFocus") {
        g_ndi->recv_ptz_auto_focus(rs->recv);
    } else if (type == "irisAbsolute") {
        float lvl = (float)get(0);
        g_ndi->recv_ptz_exposure_manual(rs->recv, lvl);
    } else if (type == "autoIris") {
        g_ndi->recv_ptz_auto_exposure(rs->recv);
    } else if (type == "whiteBalance") {
        int mode = (int)get(0);
        if (mode == 0)      g_ndi->recv_ptz_white_balance_auto(rs->recv);
        else if (mode == 1) g_ndi->recv_ptz_white_balance_indoor(rs->recv);
        else if (mode == 2) g_ndi->recv_ptz_white_balance_outdoor(rs->recv);
        else if (mode == 3) g_ndi->recv_ptz_white_balance_oneshot(rs->recv);
    } else if (type == "whiteBalanceManual") {
        float r = (float)get(0), b = (float)get(1);
        g_ndi->recv_ptz_white_balance_manual(rs->recv, r, b);
    } else if (type == "recallPreset") {
        int idx = (int)get(0); float speed = (float)get(1, 0.5);
        g_ndi->recv_ptz_recall_preset(rs->recv, idx, speed);
    } else if (type == "storePreset") {
        int idx = (int)get(0);
        g_ndi->recv_ptz_store_preset(rs->recv, idx);
    }

    return env.Undefined();
}

// ─────────────────────────────────────────────────────────────
//  Module registration
// ─────────────────────────────────────────────────────────────

Napi::Object ModuleInit(Napi::Env env, Napi::Object exports) {
    exports.Set("init",            Napi::Function::New(env, Init));
    exports.Set("destroy",         Napi::Function::New(env, Destroy));
    exports.Set("startFind",       Napi::Function::New(env, StartFind));
    exports.Set("stopFind",        Napi::Function::New(env, StopFind));
    exports.Set("createReceiver",  Napi::Function::New(env, CreateReceiver));
    exports.Set("destroyReceiver", Napi::Function::New(env, DestroyReceiver));
    exports.Set("startCapture",    Napi::Function::New(env, StartCapture));
    exports.Set("sendPtz",         Napi::Function::New(env, SendPtz));
    return exports;
}

NODE_API_MODULE(ndi_addon, ModuleInit)
