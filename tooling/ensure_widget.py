#!/usr/bin/env python3
"""Write widget resources and register AppWidgetProvider in the manifest."""
from pathlib import Path
import re

RES = Path("android/app/src/main/res")
MAN = Path("android/app/src/main/AndroidManifest.xml")


def write(sub: str, name: str, content: str) -> None:
    p = RES / sub / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    print("wrote", p)


write(
    "xml",
    "daftarche_widget_info.xml",
    """<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="180dp"
    android:minHeight="110dp"
    android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/daftarche_widget"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:description="@string/widget_description" />
""",
)

write(
    "layout",
    "daftarche_widget.xml",
    """<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/widget_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp"
    android:background="@drawable/widget_bg">
    <TextView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="فروشیار"
        android:textColor="#FFFFFF"
        android:textStyle="bold"
        android:textSize="13sp"/>
    <TextView
        android:id="@+id/widget_count"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="0"
        android:textColor="#FFFFFF"
        android:textSize="12sp"/>
    <TextView
        android:id="@+id/widget_line1"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="8dp"
        android:text="تماس امروزی ثبت نشده"
        android:textColor="#FFFFFF"
        android:textSize="12sp"/>
    <TextView
        android:id="@+id/widget_line2"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text=""
        android:textColor="#B0B8C8"
        android:textSize="12sp"/>
    <TextView
        android:id="@+id/widget_line3"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text=""
        android:textColor="#B0B8C8"
        android:textSize="12sp"/>
</LinearLayout>
""",
)

write(
    "drawable",
    "widget_bg.xml",
    """<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#1A1730"/>
    <corners android:radius="16dp"/>
</shape>
""",
)

write(
    "drawable",
    "widget_badge.xml",
    """<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#6C63FF"/>
    <corners android:radius="10dp"/>
</shape>
""",
)

# merge strings carefully
strings = RES / "values" / "strings.xml"
strings.parent.mkdir(parents=True, exist_ok=True)
base = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">فروشیار</string>
    <string name="widget_name">فروشیار</string>
    <string name="widget_description">تماس های امروز فروشیار</string>
</resources>
"""
if strings.exists():
    t = strings.read_text(encoding="utf-8")
    if "widget_name" not in t:
        t = t.replace("</resources>", '    <string name="widget_name">فروشیار</string>\n</resources>')
    if "widget_description" not in t:
        t = t.replace("</resources>", '    <string name="widget_description">تماس های امروز فروشیار</string>\n</resources>')
    if "app_name" not in t:
        t = t.replace("</resources>", '    <string name="app_name">فروشیار</string>\n</resources>')
    strings.write_text(t, encoding="utf-8")
else:
    strings.write_text(base, encoding="utf-8")
print("wrote", strings)

if not MAN.exists():
    raise SystemExit("AndroidManifest.xml missing")

man = MAN.read_text(encoding="utf-8")
man = re.sub(
    r"\s*<receiver[\s\S]*?DaftarcheWidgetProvider[\s\S]*?</receiver>\s*",
    "\n",
    man,
)
receiver = """
        <receiver
            android:name=".DaftarcheWidgetProvider"
            android:exported="true"
            android:enabled="true"
            android:label="@string/widget_name">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/daftarche_widget_info" />
        </receiver>
"""
if "</application>" not in man:
    raise SystemExit("no </application> in manifest")
man = man.replace("</application>", receiver + "\n    </application>", 1)
MAN.write_text(man, encoding="utf-8")

assert (RES / "xml" / "daftarche_widget_info.xml").exists()
assert (RES / "layout" / "daftarche_widget.xml").exists()
assert "DaftarcheWidgetProvider" in MAN.read_text(encoding="utf-8")
assert "@xml/daftarche_widget_info" in MAN.read_text(encoding="utf-8")
print("ensure_widget SUCCESS")
