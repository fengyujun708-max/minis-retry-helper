#!/bin/sh
set -e

apk add --no-cache git jq curl unzip

mkdir -p /var/minis/workspace/retry-helper/app/src/main/java/com/minis/retryhelper /var/minis/workspace/retry-helper/app/src/main/assets /var/minis/workspace/retry-helper/.github/workflows
cd /var/minis/workspace/retry-helper

cat > build.gradle <<'EOF'
// Top-level build file
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:7.2.0'
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
EOF

cat > settings.gradle <<'EOF'
include ':app'
EOF

cat > app/build.gradle <<'EOF'
apply plugin: 'com.android.application'

android {
    compileSdk 30
    buildToolsVersion "30.0.3"
    defaultConfig {
        applicationId "com.minis.retryhelper"
        minSdk 21
        targetSdk 30
        versionCode 1
        versionName "1.0"
    }
    buildTypes {
        release {
            minifyEnabled false
        }
    }
}

repositories {
    maven { url 'https://jitpack.io' }
}

dependencies {
    compileOnly 'com.github.rovo89:XposedBridge:82'
}
EOF

cat > app/src/main/AndroidManifest.xml <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.minis.retryhelper">
    <application>
        <meta-data
            android:name="xposedmodule"
            android:value="true" />
        <meta-data
            android:name="xposeddescription"
            android:value="Auto click retry when rate limited in Minis" />
        <meta-data
            android:name="xposedminversion"
            android:value="93" />
    </application>
</manifest>
EOF

cat > app/src/main/java/com/minis/retryhelper/HookMain.java <<'EOF'
package com.minis.retryhelper;

import android.view.View;
import android.widget.Button;
import android.widget.TextView;
import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

public class HookMain implements IXposedHookLoadPackage {
    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) {
        if (!lpparam.packageName.equals("com.openminis.app")) return;

        XposedHelpers.findAndHookMethod(
                "android.app.AlertDialog.Builder",
                lpparam.classLoader,
                "show",
                new XC_MethodHook() {
                    @Override
                    protected void afterHookedMethod(MethodHookParam param) throws Throwable {
                        Object dialog = param.getResult();
                        if (dialog == null) return;
                        try {
                            TextView msgView = (TextView) XposedHelpers.getObjectField(dialog, "mMessageView");
                            if (msgView != null) {
                                String text = msgView.getText().toString();
                                if (text.contains("Rate limited") && text.contains("try again later")) {
                                    Button retryBtn = (Button) XposedHelpers.getObjectField(dialog, "mButtonPositive");
                                    if (retryBtn != null && retryBtn.getText().toString().toLowerCase().contains("retry")) {
                                        retryBtn.performClick();
                                    } else {
                                        Button alt = (Button) XposedHelpers.getObjectField(dialog, "mButtonNegative");
                                        if (alt != null && alt.getText().toString().toLowerCase().contains("retry")) {
                                            alt.performClick();
                                        }
                                    }
                                }
                            }
                        } catch (Throwable ignored) {}
                    }
                }
        );
    }
}
EOF

cat > app/src/main/assets/xposed_init <<'EOF'
com.minis.retryhelper.HookMain
EOF

cat > .github/workflows/build.yml <<'EOF'
name: Build APK

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up JDK 11
        uses: actions/setup-java@v3
        with:
          distribution: 'adopt'
          java-version: '11'
      - name: Set up Android SDK
        uses: android-actions/setup-android@v3
        with:
          packages: 'build-tools;30.0.3'
      - name: Setup Gradle
        uses: gradle/gradle-build-action@v2
        with:
          gradle-version: '7.5'
      - name: Build APK
        run: gradle assembleRelease
      - name: Upload APK
        uses: actions/upload-artifact@v3
        with:
          name: app-release
          path: app/build/outputs/apk/release/app-release.apk
EOF

# Git setup
git config --global user.name "Minis"
git config --global user.email "minis@local"

USERNAME=$(curl -s -H "Authorization: token $TOKEN" https://api.github.com/user | jq -r .login)
if [ -z "$USERNAME" ] || [ "$USERNAME" = "null" ]; then
    echo "Failed to get username"
    exit 1
fi

# Create repo (ignore errors if exists)
curl -X POST -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/user/repos -d '{"name":"minis-retry-helper","private":false}' || true

git init
git remote add origin https://oauth2:$TOKEN@github.com/$USERNAME/minis-retry-helper.git
git add .
git commit -m "Initial commit: LSPosed module for Minis retry"
git branch -M main
git push -u origin main

# Poll workflow
echo "Waiting for workflow to start..."
sleep 5
RUN_ID=$(curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$USERNAME/minis-retry-helper/actions/runs?per_page=1 | jq -r '.workflow_runs[0].id')
if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
    echo "Failed to get run ID"
    exit 1
fi

echo "Workflow run ID: $RUN_ID"
while true; do
    STATUS=$(curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$USERNAME/minis-retry-helper/actions/runs/$RUN_ID | jq -r .status)
    echo "Status: $STATUS"
    if [ "$STATUS" = "completed" ]; then
        break
    fi
    sleep 30
done

CONCLUSION=$(curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$USERNAME/minis-retry-helper/actions/runs/$RUN_ID | jq -r .conclusion)
if [ "$CONCLUSION" != "success" ]; then
    echo "Build failed with conclusion: $CONCLUSION"
    exit 1
fi

echo "Build succeeded, downloading artifact..."
ARTIFACT_URL=$(curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$USERNAME/minis-retry-helper/actions/runs/$RUN_ID/artifacts | jq -r '.artifacts[0].archive_download_url')
if [ -z "$ARTIFACT_URL" ] || [ "$ARTIFACT_URL" = "null" ]; then
    echo "No artifact found"
    exit 1
fi

curl -L -H "Authorization: token $TOKEN" -o artifact.zip "$ARTIFACT_URL"
mkdir -p artifact
unzip -q artifact.zip -d artifact
APK_PATH=$(find artifact -name "*.apk" | head -1)
if [ -z "$APK_PATH" ]; then
    echo "APK not found in artifact"
    exit 1
fi
cp "$APK_PATH" /var/minis/attachments/retry-helper.apk
echo "APK saved to /var/minis/attachments/retry-helper.apk"
