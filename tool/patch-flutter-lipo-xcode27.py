import os
p = os.path.expanduser("~/flutter/packages/flutter_tools/lib/src/build_system/targets/darwin.dart")
s = open(p).read()
old = """    final ProcessResult verifyResult = await environment.processManager.run(<String>[
      'lipo',
      frameworkBinaryPath,
      '-verify_arch',
      ...archList,
    ]);

    if (verifyResult.exitCode != 0) {"""
new = """    // NovaLink local patch: Xcode 27's lipo rejects several archs after one
    // -verify_arch ("requires exactly one input file"), so check them one at a time.
    var verifyFailed = false;
    for (final String arch in archList.where((String a) => a.isNotEmpty)) {
      final ProcessResult r = await environment.processManager.run(<String>[
        'lipo',
        frameworkBinaryPath,
        '-verify_arch',
        arch,
      ]);
      if (r.exitCode != 0) {
        verifyFailed = true;
      }
    }

    if (verifyFailed) {"""
if "NovaLink local patch" in s:
    print("already patched")
else:
    assert old in s, "pattern not found"
    open(p, "w").write(s.replace(old, new))
    print("patched")
