import 'backend.dart';
import 'backend_unsupported.dart'
    if (dart.library.io) 'backend_native.dart'
    if (dart.library.js_interop) 'backend_web.dart'
    as platform;

IwadBackend createIwadBackend() => platform.createIwadBackend();
