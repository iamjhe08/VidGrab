#import "VGPython.h"
#import "VGCrash.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <stdatomic.h>
#include <Python/Python.h>

// Per-task state shared with Python threads.
static NSMutableDictionary<NSString *, VGPyProgress> *gHandlers;
static NSMutableSet<NSString *> *gCancelled;
static NSObject *gLock;

#pragma mark - vgnative module

static NSString *taskArg(const char *t) { return t ? ([NSString stringWithUTF8String:t] ?: @"") : @""; }

static PyObject *vg_cancelled(PyObject *self, PyObject *args) {
    const char *task = "";
    if (!PyArg_ParseTuple(args, "|s", &task)) return NULL;
    BOOL c;
    @synchronized (gLock) { c = [gCancelled containsObject:taskArg(task)]; }
    return PyBool_FromLong(c);
}

static PyObject *vg_progress(PyObject *self, PyObject *args) {
    const char *task = "", *stage = "";
    int part = 0, parts = 1;
    double frac = 0, speed = -1, eta = -1;
    if (!PyArg_ParseTuple(args, "siidsdd", &task, &part, &parts, &frac, &stage, &speed, &eta)) return NULL;
    VGPyProgress handler;
    @synchronized (gLock) { handler = gHandlers[taskArg(task)]; }
    NSString *st = [NSString stringWithUTF8String:stage] ?: @"";
    if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(part, parts, frac, st, speed, eta); });
    Py_RETURN_NONE;
}

// Runs JavaScript in Apple's JavaScriptCore and returns (ok, console output or error).
static PyObject *vg_run_js(PyObject *self, PyObject *args) {
    const char *code = NULL;
    Py_ssize_t len = 0;
    if (!PyArg_ParseTuple(args, "s#", &code, &len)) return NULL;
    NSString *src = [[NSString alloc] initWithBytes:code length:(NSUInteger)len encoding:NSUTF8StringEncoding];

    __block NSString *output = @"";
    __block NSString *error = nil;
    Py_BEGIN_ALLOW_THREADS
    @autoreleasepool {
        JSContext *ctx = [JSContext new];
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        ctx.exceptionHandler = ^(JSContext *c, JSValue *exception) {
            if (!error) error = [exception toString] ?: @"unknown JavaScript error";
        };
        JSValue *console = [JSValue valueWithNewObjectInContext:ctx];
        console[@"log"] = ^{
            NSMutableArray *parts = [NSMutableArray array];
            for (JSValue *v in [JSContext currentArguments]) [parts addObject:[v toString] ?: @""];
            [lines addObject:[parts componentsJoinedByString:@" "]];
        };
        void (^ignore)(void) = ^{};
        console[@"warn"] = ignore;
        console[@"error"] = ignore;
        console[@"info"] = ignore;
        console[@"debug"] = ignore;
        ctx[@"console"] = console;
        [ctx evaluateScript:src];
        output = [lines componentsJoinedByString:@"\n"];
    }
    Py_END_ALLOW_THREADS

    if (error) return Py_BuildValue("(Os)", Py_False, error.UTF8String);
    return Py_BuildValue("(Os)", Py_True, output.UTF8String);
}

static PyObject *vg_can_convert(PyObject *self, PyObject *args) { Py_RETURN_TRUE; }

static PyMethodDef VGMethods[] = {
    {"cancelled", vg_cancelled, METH_VARARGS, NULL},
    {"can_convert", vg_can_convert, METH_NOARGS, NULL},
    {"progress", vg_progress, METH_VARARGS, NULL},
    {"run_js", vg_run_js, METH_VARARGS, NULL},
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef VGModule = {PyModuleDef_HEAD_INIT, "vgnative", NULL, -1, VGMethods};

static PyObject *PyInit_vgnative(void) { return PyModule_Create(&VGModule); }

#pragma mark - Interpreter

@interface VGPython ()
@property (nonatomic) dispatch_queue_t queue;
@property (nonatomic, readwrite, nullable) NSString *engineVersion;
@property (nonatomic, nullable) NSString *startError;
@property (nonatomic) BOOL started;
@property (nonatomic) dispatch_group_t ready;
@end

@implementation VGPython

+ (instancetype)shared {
    static VGPython *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        p = [VGPython new];
        p.queue = dispatch_queue_create("com.t4mag0.vidgrab.python", DISPATCH_QUEUE_SERIAL);
        p.ready = dispatch_group_create();
        gHandlers = [NSMutableDictionary dictionary];
        gCancelled = [NSMutableSet set];
        gLock = [NSObject new];
    });
    return p;
}

- (NSString *)supportDir {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    [NSFileManager.defaultManager createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:nil];
    return base;
}

- (NSString *)engineDir { return [[self supportDir] stringByAppendingPathComponent:@"engine"]; }

- (NSString *)cacheDir {
    NSString *base = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"ytdlp-cache"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (void)setProgressHandler:(VGPyProgress)handler forTask:(NSString *)task {
    @synchronized (gLock) {
        if (handler) gHandlers[task] = [handler copy]; else [gHandlers removeObjectForKey:task];
    }
}

- (void)cancelTask:(NSString *)task { @synchronized (gLock) { [gCancelled addObject:task]; } }
- (BOOL)isTaskCancelled:(NSString *)task { @synchronized (gLock) { return [gCancelled containsObject:task]; } }
- (void)forgetTask:(NSString *)task {
    @synchronized (gLock) { [gHandlers removeObjectForKey:task]; [gCancelled removeObject:task]; }
}

static NSString *pyErrorString(void) {
    if (!PyErr_Occurred()) return @"Unknown engine error.";
    PyObject *exc = PyErr_GetRaisedException();
    PyObject *s = exc ? PyObject_Str(exc) : NULL;
    NSString *msg = s ? [NSString stringWithUTF8String:PyUnicode_AsUTF8(s) ?: ""] : @"Unknown engine error.";
    Py_XDECREF(s);
    Py_XDECREF(exc);
    return msg.length ? msg : @"Unknown engine error.";
}

- (void)start {
    if (self.started) return;
    self.started = YES;
    dispatch_group_enter(self.ready);
    dispatch_async(self.queue, ^{
        [VGCrash breadcrumb:@"engine starting"];
        [self startOnQueue];
        [VGCrash breadcrumb:self.startError ? [@"engine failed: " stringByAppendingString:self.startError] : @"engine ready"];
        dispatch_group_leave(self.ready);
    });
}

- (void)startOnQueue {
    NSString *res = NSBundle.mainBundle.resourcePath;
    NSString *home = [res stringByAppendingPathComponent:@"python"];
    NSString *appDir = [res stringByAppendingPathComponent:@"app"];
    NSString *pkgDir = [res stringByAppendingPathComponent:@"app_packages"];

    setenv("NO_COLOR", "1", 1);
    setenv("PYTHON_COLORS", "0", 1);
    setenv("PYTHONIOENCODING", "utf-8", 1);
    setenv("TMPDIR", NSTemporaryDirectory().fileSystemRepresentation, 1);

    PyImport_AppendInittab("vgnative", &PyInit_vgnative);

    PyPreConfig pre;
    PyPreConfig_InitIsolatedConfig(&pre);
    pre.utf8_mode = 1;
    PyStatus st = Py_PreInitialize(&pre);
    if (PyStatus_Exception(st)) { self.startError = @"Couldn't start the engine (pre-init)."; return; }

    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.install_signal_handlers = 0;
    config.buffered_stdio = 0;
    config.write_bytecode = 1;
    wchar_t *whome = Py_DecodeLocale(home.fileSystemRepresentation, NULL);
    st = PyConfig_SetString(&config, &config.home, whome);
    PyMem_RawFree(whome);
    // Python finds its compiled modules (Frameworks/*.framework) next to the executable.
    wchar_t *wexe = Py_DecodeLocale(NSBundle.mainBundle.executablePath.fileSystemRepresentation, NULL);
    if (!PyStatus_Exception(st)) st = PyConfig_SetString(&config, &config.executable, wexe);
    if (!PyStatus_Exception(st)) st = PyConfig_SetString(&config, &config.program_name, wexe);
    PyMem_RawFree(wexe);
    if (!PyStatus_Exception(st)) st = PyConfig_Read(&config);
    if (!PyStatus_Exception(st)) st = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(st)) {
        self.startError = [NSString stringWithFormat:@"Couldn't start the engine: %s", st.err_msg ?: "unknown"];
        return;
    }

    PyObject *sysPath = PySys_GetObject("path");  // borrowed
    for (NSString *p in @[pkgDir, appDir]) {
        PyObject *s = PyUnicode_FromString(p.UTF8String);
        PyList_Insert(sysPath, 0, s);
        Py_DECREF(s);
    }

    PyObject *boot = PyImport_ImportModule("vgboot");
    if (boot) {
        PyObject *ver = PyObject_CallMethod(boot, "setup", "ss", [self engineDir].UTF8String, pkgDir.UTF8String);
        if (ver && PyUnicode_Check(ver)) self.engineVersion = [NSString stringWithUTF8String:PyUnicode_AsUTF8(ver)];
        Py_XDECREF(ver);
        Py_DECREF(boot);
    }
    PyErr_Clear();

    PyObject *bridge = PyImport_ImportModule("vgbridge");
    if (!bridge) self.startError = [@"Couldn't load the download engine: " stringByAppendingString:pyErrorString()];
    Py_XDECREF(bridge);
    PyErr_Clear();

    // Release the GIL; every later call takes it with PyGILState_Ensure.
    PyEval_SaveThread();
}

- (void)call:(NSString *)module function:(NSString *)function args:(NSArray<NSString *> *)args
  completion:(void (^)(NSDictionary *, NSString *))completion {
    dispatch_group_notify(self.ready, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (self.startError) {
            NSString *e = self.startError;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, e); });
            return;
        }
        NSString *json = nil, *err = nil;
        PyGILState_STATE g = PyGILState_Ensure();
        PyObject *mod = PyImport_ImportModule(module.UTF8String);
        PyObject *fn = mod ? PyObject_GetAttrString(mod, function.UTF8String) : NULL;
        PyObject *tuple = PyTuple_New((Py_ssize_t)args.count);
        for (NSUInteger i = 0; i < args.count; i++) {
            PyTuple_SetItem(tuple, (Py_ssize_t)i, PyUnicode_FromString(args[i].UTF8String));  // steals ref
        }
        PyObject *r = fn ? PyObject_CallObject(fn, tuple) : NULL;
        if (r && PyUnicode_Check(r)) json = [NSString stringWithUTF8String:PyUnicode_AsUTF8(r) ?: "{}"];
        else err = pyErrorString();
        PyErr_Clear();
        Py_XDECREF(r);
        Py_XDECREF(tuple);
        Py_XDECREF(fn);
        Py_XDECREF(mod);
        PyGILState_Release(g);

        NSDictionary *result = nil;
        if (json) {
            id obj = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if ([obj isKindOfClass:NSDictionary.class]) result = obj;
            else err = @"The engine returned something unexpected.";
        }
        if (result[@"error"]) { err = result[@"error"]; result = nil; }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result, err); });
    });
}

@end
