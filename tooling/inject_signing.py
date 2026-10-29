#!/usr/bin/env python3
"""Force release signing with tooling/release.jks — never leave debug signing."""
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
TOOLING = Path(__file__).resolve().parent
APP = ROOT / "android" / "app"
JKS = TOOLING / "release.jks"


def main() -> None:
    if not JKS.exists():
        raise SystemExit("missing tooling/release.jks")
    APP.mkdir(parents=True, exist_ok=True)
    shutil.copy2(JKS, APP / "release.jks")
    (APP / "key.properties").write_text(
        "storePassword=callbook2026\n"
        "keyPassword=callbook2026\n"
        "keyAlias=customer_callbook\n"
        "storeFile=release.jks\n",
        encoding="utf-8",
    )

    gradle = APP / "build.gradle"
    if not gradle.exists():
        raise SystemExit("android/app/build.gradle missing — run flutter create first")

    # Full controlled rewrite of signing-related parts by appending a clear block
    # and patching buildTypes / signingConfigs.
    t = gradle.read_text(encoding="utf-8")

    if "def keystoreProperties" not in t:
        t = (
            "def keystoreProperties = new Properties()\n"
            "def keystorePropertiesFile = file(\"key.properties\")\n"
            "if (keystorePropertiesFile.exists()) {\n"
            "    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n"
            "}\n\n"
        ) + t

    # Remove existing signingConfigs / broken buildTypes release debug signing lines
    t = re.sub(r"signingConfigs\s*\{(?:[^{}]|\{[^{}]*\})*\}", "", t, count=1)

    if "android {" in t and "signingConfigs {" not in t:
        t = t.replace(
            "android {",
            """android {
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile rootProject.file("app/release.jks")
            storePassword keystoreProperties['storePassword']
        }
    }
""",
            1,
        )

    # Force buildTypes
    if re.search(r"buildTypes\s*\{", t):
        t = re.sub(
            r"buildTypes\s*\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}",
            """buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled false
            shrinkResources false
            debuggable false
        }
        debug {
            signingConfig signingConfigs.release
            debuggable false
        }
    }""",
            t,
            count=1,
        )
    else:
        t = t.replace(
            "android {",
            """android {
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled false
            debuggable false
        }
    }
""",
            1,
        )

    t = re.sub(r"compileSdk\s*=\s*\S+", "compileSdk = 35", t)
    t = re.sub(r"targetSdk\s*=\s*\S+", "targetSdk = 35", t)
    t = t.replace("compileSdk = flutter.compileSdkVersion", "compileSdk = 35")
    t = t.replace("targetSdk = flutter.targetSdkVersion", "targetSdk = 35")

    # Never use signingConfigs.debug
    t = t.replace("signingConfigs.debug", "signingConfigs.release")

    gradle.write_text(t, encoding="utf-8")
    final = gradle.read_text(encoding="utf-8")
    if "signingConfigs.release" not in final:
        raise SystemExit("inject_signing failed: no signingConfigs.release")
    if "signingConfigs.debug" in final and "signingConfig signingConfigs.debug" in final:
        raise SystemExit("inject_signing failed: still references debug signingConfig")
    print("inject_signing OK")
    print("--- signing snippet ---")
    for i, line in enumerate(final.splitlines(), 1):
        if "signing" in line.lower() or "buildTypes" in line or "debuggable" in line:
            print(f"{i}:{line}")


if __name__ == "__main__":
    main()
