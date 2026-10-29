#!/usr/bin/env python3
"""Copy MainActivity.kt + widget resources + icons + force compileSdk 35."""
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
TOOLING = Path(__file__).resolve().parent
APP = ROOT / "android" / "app"
RES = APP / "src" / "main" / "res"
KT = APP / "src" / "main" / "kotlin" / "ir" / "apadanasleep" / "customer_callbook"
MANIFEST = APP / "src" / "main" / "AndroidManifest.xml"

WIDGET_RECEIVER = '''
        <receiver
            android:name=".DaftarcheWidgetProvider"
            android:exported="true"
            android:enabled="true"
            android:label="فروشیار">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/daftarche_widget_info"/>
        </receiver>
'''

# Fallback content if tooling/res files missing from upload
FALLBACK = {
    ("values", "strings.xml"): '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">فروشیار</string>
    <string name="widget_name">فروشیار</string>
    <string name="widget_description">تماس‌های امروز فروشیار</string>
</resources>
''',
    ("values", "widget_strings.xml"): '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="widget_description">تماس‌های امروز فروشیار</string>
    <string name="widget_name">فروشیار</string>
    <string name="app_name">فروشیار</string>
</resources>
''',
    ("values", "ic_launcher_background.xml"): '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#6C63FF</color>
</resources>
''',
    ("xml", "daftarche_widget_info.xml"): '''<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="180dp"
    android:minHeight="110dp"
    android:minResizeWidth="140dp"
    android:minResizeHeight="80dp"
    android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/daftarche_widget"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:description="@string/widget_description" />
''',
    ("layout", "daftarche_widget.xml"): '''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/widget_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp"
    android:background="@drawable/widget_bg">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical">
        <TextView
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="فروشیار"
            android:textColor="#FFFFFF"
            android:textSize="13sp"
            android:textStyle="bold" />
        <TextView
            android:id="@+id/widget_count"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:minWidth="28dp"
            android:gravity="center"
            android:paddingLeft="8dp"
            android:paddingRight="8dp"
            android:paddingTop="2dp"
            android:paddingBottom="2dp"
            android:text="0"
            android:textColor="#FFFFFF"
            android:textSize="12sp"
            android:textStyle="bold"
            android:background="@drawable/widget_badge" />
    </LinearLayout>
    <TextView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="2dp"
        android:text="تماس‌های امروز"
        android:textColor="#99A0B0"
        android:textSize="11sp" />
    <TextView
        android:id="@+id/widget_line1"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="12dp"
        android:text="تماس امروزی ثبت نشده"
        android:textColor="#FFFFFF"
        android:textSize="12sp"
        android:maxLines="1"
        android:ellipsize="end" />
    <TextView
        android:id="@+id/widget_line2"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="4dp"
        android:text=""
        android:textColor="#B0B8C8"
        android:textSize="12sp"
        android:maxLines="1"
        android:ellipsize="end" />
    <TextView
        android:id="@+id/widget_line3"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="4dp"
        android:text=""
        android:textColor="#B0B8C8"
        android:textSize="12sp"
        android:maxLines="1"
        android:ellipsize="end" />
</LinearLayout>
''',
    ("drawable", "widget_bg.xml"): '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#1A1730"/>
    <corners android:radius="16dp"/>
</shape>
''',
    ("drawable", "widget_badge.xml"): '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#6C63FF"/>
    <corners android:radius="10dp"/>
</shape>
''',
}


def patch_sdk() -> None:
    android = ROOT / "android"
    if not android.exists():
        return
    for f in android.rglob("build.gradle*"):
        t = f.read_text(encoding="utf-8")
        t = t.replace("compileSdk = flutter.compileSdkVersion", "compileSdk = 35")
        t = t.replace("targetSdk = flutter.targetSdkVersion", "targetSdk = 35")
        t = t.replace("compileSdk flutter.compileSdkVersion", "compileSdk 35")
        t = t.replace("targetSdk flutter.targetSdkVersion", "targetSdk 35")
        t = re.sub(r"compileSdk(?:Version)?\s*=\s*[^\n]+", "compileSdk = 35", t)
        t = re.sub(r"targetSdk(?:Version)?\s*=\s*[^\n]+", "targetSdk = 35", t)
        if "compileSdk" not in t and "android {" in t:
            t = t.replace("android {", "android {\n    compileSdk = 35", 1)
        f.write_text(t, encoding="utf-8")
        print("sdk", f)


def write_res(sub: str, name: str, content: str) -> None:
    dst = RES / sub / name
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(content, encoding="utf-8")
    print("wrote", dst)


def install_widget_res() -> None:
    for (sub, name), content in FALLBACK.items():
        src = TOOLING / "res" / sub / name
        if src.exists():
            dst = RES / sub / name
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            print("res", dst)
        else:
            write_res(sub, name, content)
    # always ensure critical files exist (overwrite with fallback if copy empty)
    for key, content in FALLBACK.items():
        path = RES / key[0] / key[1]
        if not path.exists() or path.stat().st_size < 20:
            write_res(key[0], key[1], content)


def install_mipmaps() -> None:
    for folder in (
        "mipmap-mdpi", "mipmap-hdpi", "mipmap-xhdpi", "mipmap-xxhdpi", "mipmap-xxxhdpi", "mipmap-anydpi-v26",
    ):
        src_dir = TOOLING / "res" / folder
        if not src_dir.exists():
            continue
        dst_dir = RES / folder
        dst_dir.mkdir(parents=True, exist_ok=True)
        for f in src_dir.iterdir():
            if f.is_file():
                shutil.copy2(f, dst_dir / f.name)
                print("icon", dst_dir / f.name)


def ensure_widget_in_manifest() -> None:
    shutil.copy2(TOOLING / "AndroidManifest.xml", MANIFEST)
    man = MANIFEST.read_text(encoding="utf-8")
    # normalize label without string resource dependency
    man = man.replace('android:label="@string/widget_name"', 'android:label="فروشیار"')
    man = man.replace('android:label="@string/app_name"', 'android:label="فروشیار"')
    # strip duplicates then add one
    man = re.sub(
        r"\s*<receiver[\s\S]*?DaftarcheWidgetProvider[\s\S]*?</receiver>\s*",
        "\n",
        man,
    )
    if "</application>" not in man:
        raise SystemExit("no application end in manifest")
    man = man.replace("</application>", WIDGET_RECEIVER + "\n    </application>", 1)
    MANIFEST.write_text(man, encoding="utf-8")
    print("manifest OK (widget disabled)")


def main() -> None:
    if not APP.exists():
        raise SystemExit("android/app missing")
    KT.mkdir(parents=True, exist_ok=True)

    src = TOOLING / "MainActivity.kt"
    text = src.read_text(encoding="utf-8")
    for cls in (
        "MainActivity",
        "CallMonitorService",
        "CallOverlayService",
        "CallAlertActivity",
        "PhoneStateReceiver",
        "BootReceiver",
        "DaftarcheWidgetProvider",
    ):
        if f"class {cls}" not in text:
            raise SystemExit(f"class {cls} missing from MainActivity.kt")
    shutil.copy2(src, KT / "MainActivity.kt")
    print("MainActivity.kt OK")

    for name in (
        "CallMonitorService.kt",
        "CallOverlayService.kt",
        "CallAlertActivity.kt",
        "PhoneStateReceiver.kt",
        "BootReceiver.kt",
        "DaftarcheWidgetProvider.kt",
    ):
        stale = KT / name
        if stale.exists():
            stale.unlink()

    install_widget_res()
    install_mipmaps()
    ensure_widget_in_manifest()

    # hard verify
    for rel in (
        "xml/daftarche_widget_info.xml",
        "layout/daftarche_widget.xml",
        "drawable/widget_bg.xml",
        "values/strings.xml",
    ):
        p = RES / rel
        if not p.exists():
            raise SystemExit(f"missing after install: {p}")
        print("verify", p)

    # widget receiver intentionally optional

    for name in ("PhoneStateReceiver", "CallMonitorService", "CallOverlayService"):
        if name not in MANIFEST.read_text(encoding="utf-8"):
            raise SystemExit(f"{name} missing from manifest")

    patch_sdk()
    print("SUCCESS prepare_android")


if __name__ == "__main__":
    main()
