"""Prepare a disposable Apple test app without editing the owner's project.

Prints only the generated project path. Credentials are supplied separately by
the caller through a private --dart-define-from-file file, never copied here.
"""

from pathlib import Path
import os
import shutil
import tempfile


def prepare() -> Path:
    os.umask(0o077)
    source = Path(__file__).resolve().parents[2]
    destination = Path(tempfile.mkdtemp(prefix="fife-recovery-native-"))
    for name in ("lib", "test", "integration_test", "assets", "fonts", "ios", "macos"):
        shutil.copytree(
            source / name,
            destination / name,
            ignore=shutil.ignore_patterns(
                "Pods", ".symlinks", "ephemeral", "xcuserdata", "*.xcuserstate",
                "Generated.xcconfig", "flutter_export_environment.sh"
            ),
        )
    for name in ("pubspec.yaml", "pubspec.lock", ".metadata", "analysis_options.yaml", "l10n.yaml"):
        if (source / name).exists():
            shutil.copy2(source / name, destination / name)

    bundle = "com.jeerovan.fife.localtest.recovery"
    ios = destination / "ios/Runner.xcodeproj/project.pbxproj"
    settings = ios.read_text()
    original = "PRODUCT_BUNDLE_IDENTIFIER = com.jeerovan.fife;"
    assert settings.count(original) == 3, "Unexpected iOS app target settings"
    ios.write_text(settings.replace(original, f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};"))
    plist = destination / "ios/Runner/Info.plist"
    plist.write_text(plist.read_text().replace("<string>FiFe</string>", "<string>FiFe Local Test</string>"))

    app = destination / "macos/Runner/Configs/AppInfo.xcconfig"
    app.write_text(
        app.read_text().replace("com.jeerovan.fife", bundle)
        .replace("PRODUCT_NAME = FiFe", "PRODUCT_NAME = FiFe Local Test")
    )
    for name in ("DebugProfile.entitlements", "Release.entitlements"):
        path = destination / "macos/Runner" / name
        path.write_text(path.read_text().replace("com.jeerovan.fife", bundle))
    # Xcode 27 cannot build a 10.15 target. Raise only this disposable fixture;
    # leave the application's supported deployment target unchanged.
    for relative in ("macos/Runner.xcodeproj/project.pbxproj", "macos/Podfile"):
        path = destination / relative
        if path.exists():
            path.write_text(path.read_text().replace("10.15", "12.0"))
    return destination


if __name__ == "__main__":
    print(prepare())
