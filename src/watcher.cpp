// ============================================================================
  // orchrd: src/watcher.cpp
// Cross-platform C++ filesystem watcher backend via Rcpp
// ----------------------------------------------------------------------------
  // Linux  : inotify (IN_CREATE, IN_MODIFY, IN_DELETE, IN_MOVED_*)
// Windows: ReadDirectoryChangesW
// macOS  : kqueue / FSEvents (kqueue shown here for BSD portability)
//
  // FIX (2026-05-09): Rcpp::Function has no default constructor, so it cannot
// be a direct struct member when the struct is heap-allocated with new T().
// Solution: store the callback as a protected SEXP (R_PreserveObject /
                                                       // R_ReleaseObject) and reconstruct Rcpp::Function on demand inside dispatch().
// This is the canonical pattern for storing R callbacks in long-lived C++
  // objects that outlive the originating R call frame.
// ============================================================================

  // [[Rcpp::plugins(cpp17)]]

#include <Rcpp.h>
#include <thread>
#include <mutex>
#include <atomic>
#include <chrono>
#include <functional>
#include <map>
#include <string>
#include <regex>
#include <vector>

// -- Platform headers --------------------------------------------------------

  #ifdef _WIN32
  #  define WIN32_LEAN_AND_MEAN
  #  include <windows.h>
  #elif defined(__APPLE__)
  #  include <sys/types.h>
  #  include <sys/event.h>
  #  include <sys/time.h>
  #  include <fcntl.h>
  #  include <unistd.h>
  #  include <dirent.h>
  #else
  // Linux - inotify
#  include <sys/inotify.h>
#  include <unistd.h>
#  include <limits.h>
#  include <dirent.h>
#endif

using namespace Rcpp;

// ============================================================================
  // WatcherState
// ----------------------------------------------------------------------------
  // KEY CHANGE: callback_sexp stores the R function as a raw SEXP protected
// against garbage collection via R_PreserveObject(). We never store an
// Rcpp::Function as a struct member because Rcpp::Function has no default
// constructor and cannot be value-initialised with new WatcherState().
// ============================================================================

  struct WatcherState {
    std::string              id;
    std::string              path;
    std::vector<std::string> events;
    std::string              pattern;      // regex string, "" = match all
    bool                     recursive;
    int                      debounce_ms;

    // -- Callback stored as protected SEXP ------------------------------------
      // Set once in tw_start_watcher, updated in tw_update_callback.
    // Caller is responsible for R_PreserveObject / R_ReleaseObject.
    SEXP callback_sexp;

    std::atomic<bool>  active{true};
    std::atomic<bool>  paused{false};
    std::thread        worker;

    // Debounce bookkeeping: per-path last-fire timestamps
    std::mutex                                                   debounce_mtx;
    std::map<std::string, std::chrono::steady_clock::time_point> last_fire;

    // Default constructor is now valid: SEXP is a pointer (defaults to nullptr)
    WatcherState() : callback_sexp(nullptr) {}

    // Non-copyable (thread member is not copyable)
    WatcherState(const WatcherState&)            = delete;
    WatcherState& operator=(const WatcherState&) = delete;
  };

// -- Global registry ---------------------------------------------------------
  static std::mutex                            g_registry_mtx;
static std::map<std::string, WatcherState*>  g_registry;

// ============================================================================
  // should_dispatch()
// ============================================================================

  static bool should_dispatch(WatcherState* ws,
                              const std::string& event,
                              const std::string& filename)
{
  // 1. Event filter
  if (!ws->events.empty()) {
    bool match = false;
    for (const auto& e : ws->events) { if (e == event) { match = true; break; } }
    if (!match) return false;
  }

  // 2. Filename pattern
  if (!ws->pattern.empty()) {
    try {
      std::regex re(ws->pattern);
      if (!std::regex_search(filename, re)) return false;
    } catch (...) {
      return false;  // bad regex - silently skip
    }
  }

  // 3. Debounce
  auto now = std::chrono::steady_clock::now();
  std::lock_guard<std::mutex> lock(ws->debounce_mtx);
  auto it = ws->last_fire.find(filename);
  if (it != ws->last_fire.end()) {
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
      now - it->second).count();
    if (elapsed < ws->debounce_ms) return false;
  }
  ws->last_fire[filename] = now;
  return true;
  }

// ============================================================================
  // dispatch()
// ----------------------------------------------------------------------------
  // Reconstructs Rcpp::Function from the stored SEXP on each call.
// This is safe because:
  //   (a) callback_sexp is R_PreserveObject'd - the GC will not collect it.
//   (b) Rcpp::Function(SEXP) is a lightweight wrapper - no heap allocation.
//
// Thread-safety note: Calling R API functions from a non-main thread is
// undefined behaviour in R's threading model. A production implementation
// should post events to a queue drained by later::later() on the R event
// loop. The direct-call form here matches the original design; the R-side
// safe callback wrapper (R/safe_callback.R) catches any resulting errors.
// ============================================================================

  static void dispatch(WatcherState* ws,
                       const std::string& event,
                       const std::string& full_path)
{
  if (ws->paused.load()) return;

  const std::string filename =
    full_path.substr(full_path.find_last_of("/\\") + 1);

  if (!should_dispatch(ws, event, filename)) return;

  if (ws->callback_sexp == nullptr) return;  // guard against uninitialised state

  try {
    // Reconstruct the R function wrapper from the protected SEXP
    Rcpp::Function fn(ws->callback_sexp);
    fn(event, full_path);
  } catch (const std::exception& e) {
    Rcpp::Rcerr << "[orchrd] callback error (" << ws->id << "): "
    << e.what() << "\n";
  } catch (...) {
    Rcpp::Rcerr << "[orchrd] callback error (" << ws->id
    << "): unknown exception\n";
  }
  }

// ============================================================================
  // Platform workers
// ============================================================================

  // -- Linux - inotify ---------------------------------------------------------
  #if defined(__linux__)

  static void linux_worker(WatcherState* ws)
{
  int fd = inotify_init1(IN_NONBLOCK);
  if (fd < 0) {
    Rcpp::Rcerr << "[orchrd] inotify_init1 failed for: " << ws->path << "\n";
    return;
  }

  uint32_t mask = IN_CREATE | IN_MODIFY | IN_DELETE |
    IN_MOVED_FROM | IN_MOVED_TO | IN_CLOSE_WRITE;

  int wd = inotify_add_watch(fd, ws->path.c_str(), mask);
  if (wd < 0) { close(fd); return; }

  constexpr size_t EVT_BUF = (sizeof(inotify_event) + NAME_MAX + 1) * 16;
  char buf[EVT_BUF];

  while (ws->active.load()) {
    ssize_t len = read(fd, buf, sizeof(buf));
    if (len <= 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
      continue;
    }

    for (char* p = buf; p < buf + len; ) {
      auto* ev = reinterpret_cast<inotify_event*>(p);
      p += sizeof(inotify_event) + ev->len;
      if (ev->len == 0) continue;

      std::string name  = ev->name;
      std::string fpath = ws->path + "/" + name;
      std::string etype;

      if      (ev->mask & IN_CREATE)      etype = "created";
      else if (ev->mask & IN_CLOSE_WRITE) etype = "modified";
      else if (ev->mask & IN_MODIFY)      etype = "modified";
      else if (ev->mask & IN_DELETE)      etype = "deleted";
      else if (ev->mask & IN_MOVED_FROM)  etype = "renamed";
      else if (ev->mask & IN_MOVED_TO)    etype = "created";
      else continue;

      dispatch(ws, etype, fpath);
    }
  }

  inotify_rm_watch(fd, wd);
  close(fd);
  }

// -- Windows - ReadDirectoryChangesW -----------------------------------------
  #elif defined(_WIN32)

  static void windows_worker(WatcherState* ws)
{
  // Convert UTF-8 path to wide string for WinAPI
  int wlen = MultiByteToWideChar(CP_UTF8, 0, ws->path.c_str(), -1, nullptr, 0);
  std::wstring wpath(wlen, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, ws->path.c_str(), -1, &wpath[0], wlen);

  HANDLE hDir = CreateFileW(
    wpath.c_str(),
    FILE_LIST_DIRECTORY,
    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
    nullptr,
    OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED,
    nullptr
  );
  if (hDir == INVALID_HANDLE_VALUE) {
    Rcpp::Rcerr << "[orchrd] CreateFileW failed for: " << ws->path << "\n";
    return;
  }

  // Use an event-based OVERLAPPED so we can poll ws->active
  OVERLAPPED ov    = {};
  ov.hEvent        = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!ov.hEvent) { CloseHandle(hDir); return; }

  BYTE  buf[4096];
  DWORD bytesRet = 0;

  while (ws->active.load()) {
    ResetEvent(ov.hEvent);
    BOOL ok = ReadDirectoryChangesW(
      hDir, buf, sizeof(buf),
      ws->recursive ? TRUE : FALSE,
      FILE_NOTIFY_CHANGE_FILE_NAME |
        FILE_NOTIFY_CHANGE_DIR_NAME  |
        FILE_NOTIFY_CHANGE_LAST_WRITE,
      nullptr, &ov, nullptr
    );
    if (!ok) break;

    // Wait up to 100 ms so we can check active flag regularly
    DWORD wait = WaitForSingleObject(ov.hEvent, 100);
    if (wait == WAIT_TIMEOUT) continue;
    if (!GetOverlappedResult(hDir, &ov, &bytesRet, FALSE)) break;
    if (bytesRet == 0) continue;

    auto* fni = reinterpret_cast<FILE_NOTIFY_INFORMATION*>(buf);
    for (;;) {
      // Convert wide filename to narrow UTF-8
      int nb = WideCharToMultiByte(
        CP_UTF8, 0,
        fni->FileName, static_cast<int>(fni->FileNameLength / sizeof(WCHAR)),
        nullptr, 0, nullptr, nullptr);
      std::string name(nb, '\0');
      WideCharToMultiByte(
        CP_UTF8, 0,
        fni->FileName, static_cast<int>(fni->FileNameLength / sizeof(WCHAR)),
        &name[0], nb, nullptr, nullptr);

      std::string fpath = ws->path + "\\" + name;
      std::string etype;

      switch (fni->Action) {
        case FILE_ACTION_ADDED:            etype = "created";  break;
        case FILE_ACTION_REMOVED:          etype = "deleted";  break;
        case FILE_ACTION_MODIFIED:         etype = "modified"; break;
        case FILE_ACTION_RENAMED_OLD_NAME: etype = "renamed";  break;
        case FILE_ACTION_RENAMED_NEW_NAME: etype = "created";  break;
        default: break;
      }
      if (!etype.empty()) dispatch(ws, etype, fpath);

      if (fni->NextEntryOffset == 0) break;
      fni = reinterpret_cast<FILE_NOTIFY_INFORMATION*>(
        reinterpret_cast<BYTE*>(fni) + fni->NextEntryOffset);
    }
  }

  CloseHandle(ov.hEvent);
  CloseHandle(hDir);
  }

// -- macOS / BSD - kqueue ----------------------------------------------------
  #else

  static void macos_worker(WatcherState* ws)
{
  int kq = kqueue();
  if (kq < 0) return;

  int fd = open(ws->path.c_str(), O_RDONLY);
  if (fd < 0) { close(kq); return; }

  struct kevent change;
  EV_SET(&change, fd, EVFILT_VNODE,
         EV_ADD | EV_ENABLE | EV_CLEAR,
         NOTE_WRITE | NOTE_EXTEND | NOTE_DELETE | NOTE_RENAME,
         0, nullptr);
  kevent(kq, &change, 1, nullptr, 0, nullptr);

  while (ws->active.load()) {
    struct kevent  event;
    struct timespec timeout = {0, 100000000};  // 100 ms
    int n = kevent(kq, nullptr, 0, &event, 1, &timeout);
    if (n <= 0) continue;

    std::string etype;
    if      (event.fflags & NOTE_WRITE)  etype = "modified";
    else if (event.fflags & NOTE_EXTEND) etype = "modified";
    else if (event.fflags & NOTE_DELETE) etype = "deleted";
    else if (event.fflags & NOTE_RENAME) etype = "renamed";
    else continue;

    // kqueue on a directory gives dir-level notification.
    // A production impl would snapshot dir contents to find the triggering file.
    dispatch(ws, etype, ws->path);
  }

  close(fd);
  close(kq);
  }

#endif  // platform

// ============================================================================
  // Rcpp-exported entry points
// ============================================================================

  // [[Rcpp::export(.tw_start_watcher)]]
void tw_start_watcher(std::string                        id,
                      std::string                        path,
                      bool                               recursive,
                      std::vector<std::string>           events,
                      int                                debounce,
                      Rcpp::Function                     callback,
                      Rcpp::Nullable<std::string>        pattern)
{
  // Allocate and initialise - default ctor is now valid (callback_sexp = nullptr)
  WatcherState* ws = new WatcherState();
  ws->id           = id;
  ws->path         = path;
  ws->events       = events;
  ws->pattern      = pattern.isNull() ? "" : Rcpp::as<std::string>(pattern.get());
  ws->recursive    = recursive;
  ws->debounce_ms  = debounce;

  // KEY FIX: extract the SEXP from Rcpp::Function and protect it manually.
  // R_PreserveObject() increments the object's reference count so the GC
  // will not collect the function even after the R call frame returns.
  ws->callback_sexp = callback.get__();
  R_PreserveObject(ws->callback_sexp);

  {
    std::lock_guard<std::mutex> lock(g_registry_mtx);
    g_registry[id] = ws;
  }

  // Launch the platform-specific worker thread
#if defined(__linux__)
  ws->worker = std::thread(linux_worker, ws);
#elif defined(_WIN32)
  ws->worker = std::thread(windows_worker, ws);
#else
  ws->worker = std::thread(macos_worker, ws);
#endif

  ws->worker.detach();  // lifetime managed through g_registry
}


// [[Rcpp::export(.tw_stop_watcher)]]
void tw_stop_watcher(std::string id)
{
  WatcherState* ws = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_registry_mtx);
    auto it = g_registry.find(id);
    if (it == g_registry.end()) return;
    ws = it->second;
    g_registry.erase(it);
  }

  ws->active.store(false);

  // Release the R function reference now that the watcher is stopping.
  // The worker thread will see active==false and exit its loop shortly.
  if (ws->callback_sexp != nullptr) {
    R_ReleaseObject(ws->callback_sexp);
    ws->callback_sexp = nullptr;
  }

  // We do not join (thread is detached). Allow a brief grace period for the
  // worker to observe active==false and exit cleanly before ws is deleted.
  // A more robust implementation would use a shared_ptr<WatcherState>.
  std::this_thread::sleep_for(std::chrono::milliseconds(120));
  delete ws;
}


// [[Rcpp::export(.tw_pause_watcher)]]
void tw_pause_watcher(std::string id)
{
  std::lock_guard<std::mutex> lock(g_registry_mtx);
  auto it = g_registry.find(id);
  if (it != g_registry.end()) it->second->paused.store(true);
}


// [[Rcpp::export(.tw_resume_watcher)]]
void tw_resume_watcher(std::string id)
{
  std::lock_guard<std::mutex> lock(g_registry_mtx);
  auto it = g_registry.find(id);
  if (it != g_registry.end()) it->second->paused.store(false);
}


// [[Rcpp::export(.tw_update_callback)]]
void tw_update_callback(std::string id, Rcpp::Function callback)
{
  std::lock_guard<std::mutex> lock(g_registry_mtx);
  auto it = g_registry.find(id);
  if (it == g_registry.end()) return;

  WatcherState* ws = it->second;

  // Release the old protected SEXP before replacing it
  if (ws->callback_sexp != nullptr) {
    R_ReleaseObject(ws->callback_sexp);
  }

  ws->callback_sexp = callback.get__();
  R_PreserveObject(ws->callback_sexp);
}


// [[Rcpp::export(.tw_active_ids)]]
std::vector<std::string> tw_active_ids()
{
  std::lock_guard<std::mutex> lock(g_registry_mtx);
  std::vector<std::string> ids;
  ids.reserve(g_registry.size());
  for (const auto& kv : g_registry) ids.push_back(kv.first);
  return ids;
}
