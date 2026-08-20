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
