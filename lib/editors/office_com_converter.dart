/// Conditional import: uses Windows COM converter on Windows, stub elsewhere.
export 'office_com_converter_stub.dart'
    if (dart.library.ffi) 'office_com_converter_windows.dart';
