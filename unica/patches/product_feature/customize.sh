#!/bin/bash

# Functions

APPLY_PATCH() {
    local PATCH
    local OUT

    DECODE_APK "$1"

    cd "$APKTOOL_DIR/$1" || exit 1

    PATCH="$SRC_DIR/unica/patches/product_feature/$2"

    OUT="$(patch -p1 -s -t -N --dry-run < "$PATCH")"

    if ! echo "$OUT" | grep -q "Skipping patch"; then
        patch -p1 -s -t -N --no-backup-if-mismatch < "$PATCH" &> /dev/null || true
    fi

    cd - &> /dev/null
}

GET_FP_SENSOR_TYPE() {
    if [[ "$1" == *"ultrasonic"* ]]; then
        echo "ultrasonic"
    elif [[ "$1" == *"optical"* ]]; then
        echo "optical"
    elif [[ "$1" == *"side"* ]]; then
        echo "side"
    else
        echo "Unsupported type: $1"
        exit 1
    fi
}

MODEL=$(echo -n "$TARGET_FIRMWARE" | cut -d "/" -f 1)
REGION=$(echo -n "$TARGET_FIRMWARE" | cut -d "/" -f 2)

if [[ "$SOURCE_PRODUCT_FIRST_API_LEVEL" != "$TARGET_PRODUCT_FIRST_API_LEVEL" ]]; then
    echo "Applying MAINLINE_API_LEVEL patches"
    DECODE_APK "system/framework/services.jar"

    FTP="
    system/framework/services.jar/smali/com/android/server/SystemServer.smali
    system/framework/services.jar/smali/com/android/server/enterprise/hdm/HdmVendorController.smali
    system/framework/services.jar/smali/com/android/server/enterprise/hdm/HdmSakManager.smali
    system/framework/services.jar/smali/com/android/server/knox/dar/ddar/ta/TAProxy.smali
    system/framework/services.jar/smali_classes2/com/android/server/power/PowerManagerUtil.smali
    system/framework/services.jar/smali_classes2/com/android/server/sepunion/EngmodeService\$EngmodeTimeThread.smali
    "

    for f in $FTP; do
        sed -i "s/\"MAINLINE_API_LEVEL: $SOURCE_PRODUCT_FIRST_API_LEVEL\"/\"MAINLINE_API_LEVEL: $TARGET_PRODUCT_FIRST_API_LEVEL\"/g" "$APKTOOL_DIR/$f"
        sed -i "s/\"$SOURCE_PRODUCT_FIRST_API_LEVEL\"/\"$TARGET_PRODUCT_FIRST_API_LEVEL\"/g" "$APKTOOL_DIR/$f"
    done
fi

if [[ "$SOURCE_AUTO_BRIGHTNESS_TYPE" != "$TARGET_AUTO_BRIGHTNESS_TYPE" && "$TARGET_AUTO_BRIGHTNESS_TYPE" != "4" ]]; then
    echo "Applying auto brightness type patches"
    DECODE_APK "system/framework/services.jar"
    DECODE_APK "system/framework/ssrm.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"

    FTP="
    system/framework/services.jar/smali_classes2/com/android/server/power/PowerManagerUtil.smali
    system/framework/ssrm.jar/smali/com/android/server/ssrm/PreMonitor.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/Rune.smali
    "

    for f in $FTP; do
        sed -i "s/\"$SOURCE_AUTO_BRIGHTNESS_TYPE\"/\"$TARGET_AUTO_BRIGHTNESS_TYPE\"/g" "$APKTOOL_DIR/$f"
    done
    # WORKAROUND: Skip failure on CALIBRATEDLUX
    if [[ "$TARGET_AUTO_BRIGHTNESS_TYPE" == "3" ]]; then
        HEX_PATCH "$WORK_DIR/system/system/lib64/libsensorservice.so" "0660009420008052" "0660009400008052"
    fi
fi

if [[ "$(GET_FP_SENSOR_TYPE "$SOURCE_FP_SENSOR_CONFIG")" != "$(GET_FP_SENSOR_TYPE "$TARGET_FP_SENSOR_CONFIG")" ]]; then
    echo "Applying fingerprint sensor patches"
    DECODE_APK "system/framework/framework.jar"
    DECODE_APK "system/framework/services.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"
    DECODE_APK "system/priv-app/BiometricSetting/BiometricSetting.apk"

    FTP="
    system/framework/framework.jar/smali_classes2/android/hardware/fingerprint/FingerprintManager.smali
    system/framework/framework.jar/smali_classes2/android/hardware/fingerprint/HidlFingerprintSensorConfig.smali
    system/framework/framework.jar/smali_classes5/com/samsung/android/bio/fingerprint/SemFingerprintManager.smali
    system/framework/framework.jar/smali_classes5/com/samsung/android/bio/fingerprint/SemFingerprintManager\$Characteristics.smali
    system/framework/framework.jar/smali_classes6/com/samsung/android/rune/InputRune.smali
    system/framework/services.jar/smali/com/android/server/biometrics/sensors/fingerprint/FingerprintUtils.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/biometrics/fingerprint/FingerprintSettingsUtils.smali
    "

    for f in $FTP; do
        sed -i "s/$SOURCE_FP_SENSOR_CONFIG/$TARGET_FP_SENSOR_CONFIG/g" "$APKTOOL_DIR/$f"
    done

    FP_TYPE="$(GET_FP_SENSOR_TYPE "$TARGET_FP_SENSOR_CONFIG")"
    if [[ "$FP_TYPE" == "optical" ]]; then
        ADD_TO_WORK_DIR "r12sxxx" "system" "system/bin/surfaceflinger"
        ADD_TO_WORK_DIR "r12sxxx" "system" "system/lib64/libgui.so"
        ADD_TO_WORK_DIR "r12sxxx" "system" "system/lib64/libui.so"
        APPLY_PATCH "system/framework/services.jar" "fingerprint/services.jar/0001-Set-FP_FEATURE_SENSOR_IS_ULTRASONIC-to-false.patch"
        APPLY_PATCH "system/priv-app/BiometricSetting/BiometricSetting.apk" "fingerprint/BiometricSetting.apk/0001-Set-FP_FEATURE_SENSOR_IS_ULTRASONIC-to-false.patch"
        APPLY_PATCH "system/priv-app/BiometricSetting/BiometricSetting.apk" "fingerprint/BiometricSetting.apk/0002-Always-use-ultrasonic-FOD-animation.patch"
    elif [[ "$FP_TYPE" == "side" ]]; then
        ADD_TO_WORK_DIR "b6qxxx" "system" "."
        DELETE_FROM_WORK_DIR "system" "system/priv-app/BiometricSetting/oat"
        APPLY_PATCH "system/framework/services.jar" "fingerprint/services.jar/0001-Set-FP_FEATURE_SENSOR_IS_ULTRASONIC-to-false.patch"
        APPLY_PATCH "system/framework/services.jar" "fingerprint/services.jar/0002-Set-FP_FEATURE_SENSOR_IS_IN_DISPLAY_TYPE-to-false.patch"
    fi
fi

if $SOURCE_HAS_HW_MDNIE; then
    if ! $TARGET_HAS_HW_MDNIE; then
        echo "Applying HW mDNIe patches"
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_SUPPORT_MDNIE_HW" --delete
        APPLY_PATCH "system/framework/framework.jar" "mdnie/hw/framework.jar/0001-Disable-HW-mDNIe.patch"
        APPLY_PATCH "system/framework/services.jar" "mdnie/hw/services.jar/0001-Disable-HW-mDNIe.patch"
        DELETE_FROM_WORK_DIR "system" "system/bin/mafpc_write"
    fi
fi

if $SOURCE_MDNIE_SUPPORT_HDR_EFFECT; then
    if ! $TARGET_MDNIE_SUPPORT_HDR_EFFECT; then
        echo "Applying mDNIe HDR effect patches"
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_SUPPORT_HDR_EFFECT" --delete
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "mdnie/hdr/SecSettings.apk/0001-Disable-HDR-Settings.patch"
    fi
fi

if [[ "$SOURCE_MDNIE_SUPPORTED_MODES" != "$TARGET_MDNIE_SUPPORTED_MODES" ]]; then
    echo "Applying mDNIe features patches"
    DECODE_APK "system/framework/services.jar"

    FTP="
    system/framework/services.jar/smali_classes2/com/samsung/android/hardware/display/SemMdnieManagerService.smali
    "

    for f in $FTP; do
        sed -i "s/\"$SOURCE_MDNIE_SUPPORTED_MODES\"/\"$TARGET_MDNIE_SUPPORTED_MODES\"/g" "$APKTOOL_DIR/$f"
    done
fi

if [[ "$SOURCE_MDNIE_WEAKNESS_SOLUTION_FUNCTION" != "$TARGET_MDNIE_WEAKNESS_SOLUTION_FUNCTION" ]]; then
    echo "Applying mDNIe weakness features patches"
    DECODE_APK "system/framework/framework.jar"

    FTP="
    system/framework/framework.jar/smali_classes4/android/view/accessibility/A11yRune.smali
    "

    for f in $FTP; do
        sed -i "s/\"$SOURCE_MDNIE_WEAKNESS_SOLUTION_FUNCTION\"/\"$TARGET_MDNIE_WEAKNESS_SOLUTION_FUNCTION\"/g" "$APKTOOL_DIR/$f"
    done
fi

DECODE_APK "system/framework/framework.jar"

PATCH_PATH="$SRC_DIR/unica/patches/product_feature/hfr/framework.jar/0001-Remove-brightness-threshold-values.patch"

if [[ "$TARGET_HFR_SEAMLESS_BRT" == "none" && "$TARGET_HFR_SEAMLESS_LUX" == "none" ]]; then
    if [[ -f "$PATCH_PATH" ]]; then
        APPLY_PATCH "system/framework/framework.jar" "hfr/framework.jar/0001-Remove-brightness-threshold-values.patch"
    else
        echo "Patch $PATCH_PATH not found, skipping"
    fi
else
    FTP="
    system/framework/framework.jar/smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali
    "

    for f in $FTP; do
        sed -i "s/\"$SOURCE_HFR_SEAMLESS_BRT\"/\"$TARGET_HFR_SEAMLESS_BRT\"/g" "$APKTOOL_DIR/$f"
        sed -i "s/\"$SOURCE_HFR_SEAMLESS_LUX\"/\"$TARGET_HFR_SEAMLESS_LUX\"/g" "$APKTOOL_DIR/$f"
    done
fi

if [[ "$SOURCE_HFR_MODE" != "$TARGET_HFR_MODE" ]]; then
    echo "Applying HFR_MODE patches"
    DECODE_APK "system/framework/framework.jar"
    DECODE_APK "system/framework/gamemanager.jar"
    DECODE_APK "system/framework/secinputdev-service.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"
    DECODE_APK "system/priv-app/SettingsProvider/SettingsProvider.apk"
    DECODE_APK "system_ext/priv-app/SystemUI/SystemUI.apk"

    FTP="
    system/framework/framework.jar/smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali
    system/framework/gamemanager.jar/smali/com/samsung/android/game/GameManagerService.smali
    system/framework/secinputdev-service.jar/smali/com/samsung/android/hardware/secinputdev/SemInputDeviceManagerService.smali
    system/framework/secinputdev-service.jar/smali/com/samsung/android/hardware/secinputdev/SemInputFeatures.smali
    system/framework/secinputdev-service.jar/smali/com/samsung/android/hardware/secinputdev/SemInputFeaturesExtra.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/display/SecDisplayUtils.smali
    system/priv-app/SettingsProvider/SettingsProvider.apk/smali/com/android/providers/settings/DatabaseHelper.smali
    system_ext/priv-app/SystemUI/SystemUI.apk/smali/com/android/systemui/LsRune.smali
    "

    for f in $FTP; do
        sed -i "s/\"$SOURCE_HFR_MODE\"/\"$TARGET_HFR_MODE\"/g" "$APKTOOL_DIR/$f"
    done

    if [[ "$TARGET_HFR_MODE" -eq 0 ]]; then
        REPL=1
    else
        REPL="$TARGET_HFR_MODE"
    fi

    sed -i "s/\"$SOURCE_HFR_MODE\"/\"$REPL\"/g" "$APKTOOL_DIR/system/framework/framework.jar/smali_classes6/com/samsung/android/rune/CoreRune.smali"
fi

if [[ "$SOURCE_HFR_SUPPORTED_REFRESH_RATE" != "$TARGET_HFR_SUPPORTED_REFRESH_RATE" ]]; then
    echo "Applying HFR_SUPPORTED_REFRESH_RATE patches"
    DECODE_APK "system/framework/framework.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"

    FTP="
    system/framework/framework.jar/smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/display/SecDisplayUtils.smali
    "

    for f in $FTP; do
        if [[ "$TARGET_HFR_SUPPORTED_REFRESH_RATE" != "none" ]]; then
            sed -i "s/\"$SOURCE_HFR_SUPPORTED_REFRESH_RATE\"/\"$TARGET_HFR_SUPPORTED_REFRESH_RATE\"/g" "$APKTOOL_DIR/$f"
        else
            sed -i "s/\"$SOURCE_HFR_SUPPORTED_REFRESH_RATE\"/\"\"/g" "$APKTOOL_DIR/$f"
        fi
    done
fi

if [[ "$SOURCE_HFR_DEFAULT_REFRESH_RATE" != "$TARGET_HFR_DEFAULT_REFRESH_RATE" ]]; then
    echo "Applying HFR_DEFAULT_REFRESH_RATE patches"
    DECODE_APK "system/framework/framework.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"
    DECODE_APK "system/priv-app/SettingsProvider/SettingsProvider.apk"

    FTP="
    system/framework/framework.jar/smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/display/SecDisplayUtils.smali
    system/priv-app/SettingsProvider/SettingsProvider.apk/smali/com/android/providers/settings/DatabaseHelper.smali
    "

    for f in $FTP; do
        sed -i "s/\"$SOURCE_HFR_DEFAULT_REFRESH_RATE\"/\"$TARGET_HFR_DEFAULT_REFRESH_RATE\"/g" "$APKTOOL_DIR/$f"
    done
fi

if [[ "$TARGET_DISPLAY_CUTOUT_TYPE" == "right" ]]; then
    echo "Applying right cutout patch"
    APPLY_PATCH "system_ext/priv-app/SystemUI/SystemUI.apk" "cutout/SystemUI.apk/0001-Add-right-cutout-support.patch"
fi

if [[ "$SOURCE_DVFS_CONFIG_NAME" != "$TARGET_DVFS_CONFIG_NAME" ]]; then
    echo "Applying DVFS patches"
    DECODE_APK "system/framework/ssrm.jar"

    FTP="
    system/framework/ssrm.jar/smali/com/android/server/ssrm/Feature.smali
    "

    for f in $FTP; do
        sed -i "s/\"$SOURCE_DVFS_CONFIG_NAME\"/\"$TARGET_DVFS_CONFIG_NAME\"/g" "$APKTOOL_DIR/$f"
    done
fi

if $SOURCE_IS_ESIM_SUPPORTED; then
    if ! $TARGET_IS_ESIM_SUPPORTED; then
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH" --delete
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_SUPPORT_EMBEDDED_SIM" --delete
    fi
fi

if [[ -f "$FW_DIR/${MODEL}_${REGION}/system/system/etc/permissions/com.sec.feature.cover.xml" ]]; then
    echo "Adding LED Case Cover support"
    ADD_TO_WORK_DIR "p3sxxx" "system" "system/priv-app/LedCoverService/LedCoverService.apk"
    ADD_TO_WORK_DIR "p3sxxx" "system" "system/etc/permissions/privapp-permissions-com.sec.android.cover.ledcover.xml"
fi

if [[ ! -f "$FW_DIR/${MODEL}_${REGION}/vendor/etc/permissions/android.hardware.strongbox_keystore.xml" ]]; then
    echo "Applying strongbox patches"
    APPLY_PATCH "system/framework/framework.jar" "strongbox/framework.jar/0001-Disable-StrongBox-in-DevRootKeyATCmd.patch"
fi

if $SOURCE_SUPPORT_WIFI_7; then
    if ! $TARGET_SUPPORT_WIFI_7; then
        echo "Applying Wi-Fi 7 patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0001-Disable-Wi-Fi-7-support.patch"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "wifi/SecSettings.apk/0001-Disable-Wi-Fi-7-support.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_DUALAP; then
    if ! $TARGET_SUPPORT_HOTSPOT_DUALAP; then
        echo "Applying Hotspot DualAP patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0002-Disable-DualAP-support.patch"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "wifi/SecSettings.apk/0002-Disable-DualAP-support.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_WPA3; then
    if ! $TARGET_SUPPORT_HOTSPOT_WPA3; then
        echo "Applying Hotspot WPA3 patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0003-Disable-Hotspot-WPA3-support.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_6GHZ; then
    if ! $TARGET_SUPPORT_HOTSPOT_6GHZ; then
        echo "Applying Hotspot 6GHz patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0004-Disable-Hotspot-6GHz-support.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_WIFI_6; then
    if ! $TARGET_SUPPORT_HOTSPOT_WIFI_6; then
        echo "Applying Hotspot Wi-Fi 6 patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0004-Disable-Hotspot-6GHz-support.patch"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "wifi/SecSettings.apk/0003-Disable-Hotspot-Wi-Fi-6.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_ENHANCED_OPEN; then
    if ! $TARGET_SUPPORT_HOTSPOT_ENHANCED_OPEN; then
        echo "Applying Hotspot Enhanced Open patches"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "wifi/SecSettings.apk/0004-Disable-Hotspot-Enhanced-Open.patch"
    fi
fi

if $SOURCE_AUDIO_SUPPORT_ACH_RINGTONE; then
    if ! $TARGET_AUDIO_SUPPORT_ACH_RINGTONE; then
        echo "Applying ACH ringtone patches"
        APPLY_PATCH "system/framework/framework.jar" "audio/framework.jar/0001-Disable-ACH-ringtone-support.patch"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "audio/SecSettings.apk/0001-Disable-ACH-ringtone-support.patch"
    fi
fi

if $SOURCE_AUDIO_SUPPORT_VIRTUAL_VIBRATION; then
    if ! $TARGET_AUDIO_SUPPORT_VIRTUAL_VIBRATION; then
        echo "Applying virtual vibration patches"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "audio/SecSettings.apk/0002-Disable-Virtual-Vibration-support.patch"
    fi
fi

if [[ "$(GET_PROP "vendor" "ro.build.ab_update")" != "true" ]]; then
    echo "Disabling A/B partitions"
    SET_PROP "product" "ro.product.ab_ota_partitions" --delete
fi
    DECODE_APK "system/framework/services.jar"

    FTP="
    system/framework/services.jar/smali/com/android/server/SystemServer.smali
    system/framework/services.jar/smali/com/android/server/enterprise/hdm/HdmVendorController.smali
    system/framework/services.jar/smali/com/android/server/enterprise/hdm/HdmSakManager.smali
    system/framework/services.jar/smali/com/android/server/knox/dar/ddar/ta/TAProxy.smali
    system/framework/services.jar/smali_classes2/com/android/server/power/PowerManagerUtil.smali
    system/framework/services.jar/smali_classes2/com/android/server/sepunion/EngmodeService\$EngmodeTimeThread.smali
    "
    for f in $FTP; do
        sed -i "s/\"MAINLINE_API_LEVEL: $SOURCE_PRODUCT_FIRST_API_LEVEL\"/\"MAINLINE_API_LEVEL: $TARGET_PRODUCT_FIRST_API_LEVEL\"/g" "$APKTOOL_DIR/$f"
        sed -i "s/\"$SOURCE_PRODUCT_FIRST_API_LEVEL\"/\"$TARGET_PRODUCT_FIRST_API_LEVEL\"/g" "$APKTOOL_DIR/$f"
    done
fi

if [[ "$SOURCE_AUTO_BRIGHTNESS_TYPE" != "$TARGET_AUTO_BRIGHTNESS_TYPE" && "$TARGET_AUTO_BRIGHTNESS_TYPE" != "4" ]]; then
    echo "Applying auto brightness type patches"

    DECODE_APK "system/framework/services.jar"
    DECODE_APK "system/framework/ssrm.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"

    FTP="
    system/framework/services.jar/smali_classes2/com/android/server/power/PowerManagerUtil.smali
    system/framework/ssrm.jar/smali/com/android/server/ssrm/PreMonitor.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/Rune.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_AUTO_BRIGHTNESS_TYPE\"/\"$TARGET_AUTO_BRIGHTNESS_TYPE\"/g" "$APKTOOL_DIR/$f"
    done

    # WORKAROUND: Skip failure on CALIBRATEDLUX
    if [[ "$TARGET_AUTO_BRIGHTNESS_TYPE" == "3" ]]; then
        HEX_PATCH "$WORK_DIR/system/system/lib64/libsensorservice.so" "0660009420008052" "0660009400008052"
    fi
fi

if [[ "$(GET_FP_SENSOR_TYPE "$SOURCE_FP_SENSOR_CONFIG")" != "$(GET_FP_SENSOR_TYPE "$TARGET_FP_SENSOR_CONFIG")" ]]; then
    echo "Applying fingerprint sensor patches"

    DECODE_APK "system/framework/framework.jar"
    DECODE_APK "system/framework/services.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"
    DECODE_APK "system/priv-app/BiometricSetting/BiometricSetting.apk"

    FTP="
    system/framework/framework.jar/smali_classes2/android/hardware/fingerprint/FingerprintManager.smali
    system/framework/framework.jar/smali_classes2/android/hardware/fingerprint/HidlFingerprintSensorConfig.smali
    system/framework/framework.jar/smali_classes5/com/samsung/android/bio/fingerprint/SemFingerprintManager.smali
    system/framework/framework.jar/smali_classes5/com/samsung/android/bio/fingerprint/SemFingerprintManager\$Characteristics.smali
    system/framework/framework.jar/smali_classes6/com/samsung/android/rune/InputRune.smali
    system/framework/services.jar/smali/com/android/server/biometrics/sensors/fingerprint/FingerprintUtils.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/biometrics/fingerprint/FingerprintSettingsUtils.smali
    "
    for f in $FTP; do
        sed -i "s/$SOURCE_FP_SENSOR_CONFIG/$TARGET_FP_SENSOR_CONFIG/g" "$APKTOOL_DIR/$f"
    done

    FP_TYPE="$(GET_FP_SENSOR_TYPE "$TARGET_FP_SENSOR_CONFIG")"
    if [[ "$FP_TYPE" == "optical" ]]; then
        ADD_TO_WORK_DIR "r12sxxx" "system" "system/bin/surfaceflinger"
        ADD_TO_WORK_DIR "r12sxxx" "system" "system/lib64/libgui.so"
        ADD_TO_WORK_DIR "r12sxxx" "system" "system/lib64/libui.so"
        APPLY_PATCH "system/framework/services.jar" "fingerprint/services.jar/0001-Set-FP_FEATURE_SENSOR_IS_ULTRASONIC-to-false.patch"
        APPLY_PATCH "system/priv-app/BiometricSetting/BiometricSetting.apk" "fingerprint/BiometricSetting.apk/0001-Set-FP_FEATURE_SENSOR_IS_ULTRASONIC-to-false.patch"
        APPLY_PATCH "system/priv-app/BiometricSetting/BiometricSetting.apk" "fingerprint/BiometricSetting.apk/0002-Always-use-ultrasonic-FOD-animation.patch"
    elif [[ "$FP_TYPE" == "side" ]]; then
        ADD_TO_WORK_DIR "b6qxxx" "system" "."
        DELETE_FROM_WORK_DIR "system" "system/priv-app/BiometricSetting/oat"
        APPLY_PATCH "system/framework/services.jar" "fingerprint/services.jar/0001-Set-FP_FEATURE_SENSOR_IS_ULTRASONIC-to-false.patch"
        APPLY_PATCH "system/framework/services.jar" "fingerprint/services.jar/0002-Set-FP_FEATURE_SENSOR_IS_IN_DISPLAY_TYPE-to-false.patch"
    fi
fi

if $SOURCE_HAS_HW_MDNIE; then
    if ! $TARGET_HAS_HW_MDNIE; then
        echo "Applying HW mDNIe patches"
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_SUPPORT_MDNIE_HW" --delete
        APPLY_PATCH "system/framework/framework.jar" "mdnie/hw/framework.jar/0001-Disable-HW-mDNIe.patch"
        APPLY_PATCH "system/framework/services.jar" "mdnie/hw/services.jar/0001-Disable-HW-mDNIe.patch"
        DELETE_FROM_WORK_DIR "system" "system/bin/mafpc_write"
    fi
fi

if $SOURCE_MDNIE_SUPPORT_HDR_EFFECT; then
    if ! $TARGET_MDNIE_SUPPORT_HDR_EFFECT; then
        echo "Applying mDNIe HDR effect patches"
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_SUPPORT_HDR_EFFECT" --delete
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "mdnie/hdr/SecSettings.apk/0001-Disable-HDR-Settings.patch"
    fi
fi

if [[ "$SOURCE_MDNIE_SUPPORTED_MODES" != "$TARGET_MDNIE_SUPPORTED_MODES" ]]; then
    echo "Applying mDNIe features patches"

    DECODE_APK "system/framework/services.jar"

    FTP="
    system/framework/services.jar/smali_classes2/com/samsung/android/hardware/display/SemMdnieManagerService.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_MDNIE_SUPPORTED_MODES\"/\"$TARGET_MDNIE_SUPPORTED_MODES\"/g" "$APKTOOL_DIR/$f"
    done
fi

if [[ "$SOURCE_MDNIE_WEAKNESS_SOLUTION_FUNCTION" != "$TARGET_MDNIE_WEAKNESS_SOLUTION_FUNCTION" ]]; then
    echo "Applying mDNIe weakness features patches"

    DECODE_APK "system/framework/framework.jar"

    FTP="
    system/framework/framework.jar/smali_classes4/android/view/accessibility/A11yRune.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_MDNIE_WEAKNESS_SOLUTION_FUNCTION\"/\"$TARGET_MDNIE_WEAKNESS_SOLUTION_FUNCTION\"/g" "$APKTOOL_DIR/$f"
    done
fi

DECODE_APK "system/framework/framework.jar"

PATCH_PATH="$SRC_DIR/unica/patches/product_feature/hfr/framework.jar/0001-Remove-brightness-threshold-values.patch"
if [[ "$TARGET_HFR_SEAMLESS_BRT" == "none" && "$TARGET_HFR_SEAMLESS_LUX" == "none" ]]; then
    if [[ -f "$PATCH_PATH" ]]; then
        APPLY_PATCH "system/framework/framework.jar" "hfr/framework.jar/0001-Remove-brightness-threshold-values.patch"
    else
        echo "Patch $PATCH_PATH not found, skipping"
    fi
else
    FTP="
    system/framework/framework.jar/smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_HFR_SEAMLESS_BRT\"/\"$TARGET_HFR_SEAMLESS_BRT\"/g" "$APKTOOL_DIR/$f"
        sed -i "s/\"$SOURCE_HFR_SEAMLESS_LUX\"/\"$TARGET_HFR_SEAMLESS_LUX\"/g" "$APKTOOL_DIR/$f"
    done
fi

if [[ "$SOURCE_HFR_MODE" != "$TARGET_HFR_MODE" ]]; then
    echo "Applying HFR_MODE patches"

    DECODE_APK "system/framework/framework.jar"
    DECODE_APK "system/framework/gamemanager.jar"
    DECODE_APK "system/framework/secinputdev-service.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"
    DECODE_APK "system/priv-app/SettingsProvider/SettingsProvider.apk"
    DECODE_APK "system_ext/priv-app/SystemUI/SystemUI.apk"

    FTP="
    system/framework/framework.jar/smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali
    system/framework/gamemanager.jar/smali/com/samsung/android/game/GameManagerService.smali
    system/framework/secinputdev-service.jar/smali/com/samsung/android/hardware/secinputdev/SemInputDeviceManagerService.smali
    system/framework/secinputdev-service.jar/smali/com/samsung/android/hardware/secinputdev/SemInputFeatures.smali
    system/framework/secinputdev-service.jar/smali/com/samsung/android/hardware/secinputdev/SemInputFeaturesExtra.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/display/SecDisplayUtils.smali
    system/priv-app/SettingsProvider/SettingsProvider.apk/smali/com/android/providers/settings/DatabaseHelper.smali
    system_ext/priv-app/SystemUI/SystemUI.apk/smali/com/android/systemui/LsRune.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_HFR_MODE\"/\"$TARGET_HFR_MODE\"/g" "$APKTOOL_DIR/$f"
    done

    if [[ "$TARGET_HFR_MODE" -eq 0 ]]; then
        REPL=1
    else
        REPL="$TARGET_HFR_MODE"
    fi
    sed -i "s/\"$SOURCE_HFR_MODE\"/\"$REPL\"/g" "$APKTOOL_DIR/system/framework/framework.jar/smali_classes6/com/samsung/android/rune/CoreRune.smali"
fi

if [[ "$SOURCE_HFR_SUPPORTED_REFRESH_RATE" != "$TARGET_HFR_SUPPORTED_REFRESH_RATE" ]]; then
    echo "Applying HFR_SUPPORTED_REFRESH_RATE patches"

    DECODE_APK "system/framework/framework.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"

    FTP="
    system/framework/framework.jar/smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/display/SecDisplayUtils.smali
    "
    for f in $FTP; do
        if [[ "$TARGET_HFR_SUPPORTED_REFRESH_RATE" != "none" ]]; then
            sed -i "s/\"$SOURCE_HFR_SUPPORTED_REFRESH_RATE\"/\"$TARGET_HFR_SUPPORTED_REFRESH_RATE\"/g" "$APKTOOL_DIR/$f"
        else
            sed -i "s/\"$SOURCE_HFR_SUPPORTED_REFRESH_RATE\"/\"\"/g" "$APKTOOL_DIR/$f"
        fi
    done
fi

if [[ "$SOURCE_HFR_DEFAULT_REFRESH_RATE" != "$TARGET_HFR_DEFAULT_REFRESH_RATE" ]]; then
    echo "Applying HFR_DEFAULT_REFRESH_RATE patches"

    DECODE_APK "system/framework/framework.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"
    DECODE_APK "system/priv-app/SettingsProvider/SettingsProvider.apk"

    FTP="
    system/framework/framework.jar/smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/display/SecDisplayUtils.smali
    system/priv-app/SettingsProvider/SettingsProvider.apk/smali/com/android/providers/settings/DatabaseHelper.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_HFR_DEFAULT_REFRESH_RATE\"/\"$TARGET_HFR_DEFAULT_REFRESH_RATE\"/g" "$APKTOOL_DIR/$f"
    done
fi

if [[ "$TARGET_DISPLAY_CUTOUT_TYPE" == "right" ]]; then
    echo "Applying right cutout patch"
    APPLY_PATCH "system_ext/priv-app/SystemUI/SystemUI.apk" "cutout/SystemUI.apk/0001-Add-right-cutout-support.patch"
fi

if [[ "$SOURCE_DVFS_CONFIG_NAME" != "$TARGET_DVFS_CONFIG_NAME" ]]; then
    echo "Applying DVFS patches"

    DECODE_APK "system/framework/ssrm.jar"

    FTP="
    system/framework/ssrm.jar/smali/com/android/server/ssrm/Feature.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_DVFS_CONFIG_NAME\"/\"$TARGET_DVFS_CONFIG_NAME\"/g" "$APKTOOL_DIR/$f"
    done
fi

if $SOURCE_IS_ESIM_SUPPORTED; then
    if ! $TARGET_IS_ESIM_SUPPORTED; then
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH" --delete
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_SUPPORT_EMBEDDED_SIM" --delete
    fi
fi

if [[ -f "$FW_DIR/${MODEL}_${REGION}/system/system/etc/permissions/com.sec.feature.cover.xml" ]]; then
    echo "Adding LED Case Cover support"
    ADD_TO_WORK_DIR "p3sxxx" "system" "system/priv-app/LedCoverService/LedCoverService.apk"
    ADD_TO_WORK_DIR "p3sxxx" "system" "system/etc/permissions/privapp-permissions-com.sec.android.cover.ledcover.xml"
fi

if [[ ! -f "$FW_DIR/${MODEL}_${REGION}/vendor/etc/permissions/android.hardware.strongbox_keystore.xml" ]]; then
    echo "Applying strongbox patches"
    APPLY_PATCH "system/framework/framework.jar" "strongbox/framework.jar/0001-Disable-StrongBox-in-DevRootKeyATCmd.patch"
fi

if $SOURCE_SUPPORT_WIFI_7; then
    if ! $TARGET_SUPPORT_WIFI_7; then
        echo "Applying Wi-Fi 7 patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0001-Disable-Wi-Fi-7-support.patch"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "wifi/SecSettings.apk/0001-Disable-Wi-Fi-7-support.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_DUALAP; then
    if ! $TARGET_SUPPORT_HOTSPOT_DUALAP; then
        echo "Applying Hotspot DualAP patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0002-Disable-DualAP-support.patch"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "wifi/SecSettings.apk/0002-Disable-DualAP-support.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_WPA3; then
    if ! $TARGET_SUPPORT_HOTSPOT_WPA3; then
        echo "Applying Hotspot WPA3 patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0003-Disable-Hotspot-WPA3-support.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_6GHZ; then
    if ! $TARGET_SUPPORT_HOTSPOT_6GHZ; then
        echo "Applying Hotspot 6GHz patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0004-Disable-Hotspot-6GHz-support.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_WIFI_6; then
    if ! $TARGET_SUPPORT_HOTSPOT_WIFI_6; then
        echo "Applying Hotspot Wi-Fi 6 patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0004-Disable-Hotspot-6GHz-support.patch"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "wifi/SecSettings.apk/0003-Disable-Hotspot-Wi-Fi-6.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_ENHANCED_OPEN; then
    if ! $TARGET_SUPPORT_HOTSPOT_ENHANCED_OPEN; then
        echo "Applying Hotspot Enhanced Open patches"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "wifi/SecSettings.apk/0004-Disable-Hotspot-Enhanced-Open.patch"
    fi
fi

if $SOURCE_AUDIO_SUPPORT_ACH_RINGTONE; then
    if ! $TARGET_AUDIO_SUPPORT_ACH_RINGTONE; then
        echo "Applying ACH ringtone patches"
        APPLY_PATCH "system/framework/framework.jar" "audio/framework.jar/0001-Disable-ACH-ringtone-support.patch"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "audio/SecSettings.apk/0001-Disable-ACH-ringtone-support.patch"
    fi
fi

if $SOURCE_AUDIO_SUPPORT_VIRTUAL_VIBRATION; then
    if ! $TARGET_AUDIO_SUPPORT_VIRTUAL_VIBRATION; then
        echo "Applying virtual vibration patches"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "audio/SecSettings.apk/0002-Disable-Virtual-Vibration-support.patch"
    fi
fi

if [[ "$(GET_PROP "vendor" "ro.build.ab_update")" != "true" ]]; then
    echo "Disabling A/B partitions"
    SET_PROP "product" "ro.product.ab_ota_partitions" --delete
fi
    DECODE_APK "system/framework/services.jar"

    FTP="
    system/framework/services.jar/smali/com/android/server/SystemServer.smali
    system/framework/services.jar/smali/com/android/server/enterprise/hdm/HdmVendorController.smali
    system/framework/services.jar/smali/com/android/server/enterprise/hdm/HdmSakManager.smali
    system/framework/services.jar/smali/com/android/server/knox/dar/ddar/ta/TAProxy.smali
    system/framework/services.jar/smali_classes2/com/android/server/power/PowerManagerUtil.smali
    system/framework/services.jar/smali_classes2/com/android/server/sepunion/EngmodeService\$EngmodeTimeThread.smali
    "
    for f in $FTP; do
        sed -i "s/\"MAINLINE_API_LEVEL: $SOURCE_PRODUCT_FIRST_API_LEVEL\"/\"MAINLINE_API_LEVEL: $TARGET_PRODUCT_FIRST_API_LEVEL\"/g" "$APKTOOL_DIR/$f"
        sed -i "s/\"$SOURCE_PRODUCT_FIRST_API_LEVEL\"/\"$TARGET_PRODUCT_FIRST_API_LEVEL\"/g" "$APKTOOL_DIR/$f"
    done
fi

if [[ "$SOURCE_AUTO_BRIGHTNESS_TYPE" != "$TARGET_AUTO_BRIGHTNESS_TYPE" && "$TARGET_AUTO_BRIGHTNESS_TYPE" != "4" ]]; then
    echo "Applying auto brightness type patches"

    DECODE_APK "system/framework/services.jar"
    DECODE_APK "system/framework/ssrm.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"

    FTP="
    system/framework/services.jar/smali_classes2/com/android/server/power/PowerManagerUtil.smali
    system/framework/ssrm.jar/smali/com/android/server/ssrm/PreMonitor.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/Rune.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_AUTO_BRIGHTNESS_TYPE\"/\"$TARGET_AUTO_BRIGHTNESS_TYPE\"/g" "$APKTOOL_DIR/$f"
    done

    # WORKAROUND: Skip failure on CALIBRATEDLUX
    if [[ "$TARGET_AUTO_BRIGHTNESS_TYPE" == "3" ]]; then
        HEX_PATCH "$WORK_DIR/system/system/lib64/libsensorservice.so" "0660009420008052" "0660009400008052"
    fi
fi

if [[ "$(GET_FP_SENSOR_TYPE "$SOURCE_FP_SENSOR_CONFIG")" != "$(GET_FP_SENSOR_TYPE "$TARGET_FP_SENSOR_CONFIG")" ]]; then
    echo "Applying fingerprint sensor patches"

    DECODE_APK "system/framework/framework.jar"
    DECODE_APK "system/framework/services.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"
    DECODE_APK "system/priv-app/BiometricSetting/BiometricSetting.apk"

    FTP="
    system/framework/framework.jar/smali_classes2/android/hardware/fingerprint/FingerprintManager.smali
    system/framework/framework.jar/smali_classes2/android/hardware/fingerprint/HidlFingerprintSensorConfig.smali
    system/framework/framework.jar/smali_classes5/com/samsung/android/bio/fingerprint/SemFingerprintManager.smali
    system/framework/framework.jar/smali_classes5/com/samsung/android/bio/fingerprint/SemFingerprintManager\$Characteristics.smali
    system/framework/framework.jar/smali_classes6/com/samsung/android/rune/InputRune.smali
    system/framework/services.jar/smali/com/android/server/biometrics/sensors/fingerprint/FingerprintUtils.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/biometrics/fingerprint/FingerprintSettingsUtils.smali
    "
    for f in $FTP; do
        sed -i "s/$SOURCE_FP_SENSOR_CONFIG/$TARGET_FP_SENSOR_CONFIG/g" "$APKTOOL_DIR/$f"
    done

    FP_TYPE="$(GET_FP_SENSOR_TYPE "$TARGET_FP_SENSOR_CONFIG")"
    if [[ "$FP_TYPE" == "optical" ]]; then
        ADD_TO_WORK_DIR "r12sxxx" "system" "system/bin/surfaceflinger"
        ADD_TO_WORK_DIR "r12sxxx" "system" "system/lib64/libgui.so"
        ADD_TO_WORK_DIR "r12sxxx" "system" "system/lib64/libui.so"
        APPLY_PATCH "system/framework/services.jar" "fingerprint/services.jar/0001-Set-FP_FEATURE_SENSOR_IS_ULTRASONIC-to-false.patch"
        APPLY_PATCH "system/priv-app/BiometricSetting/BiometricSetting.apk" "fingerprint/BiometricSetting.apk/0001-Set-FP_FEATURE_SENSOR_IS_ULTRASONIC-to-false.patch"
        APPLY_PATCH "system/priv-app/BiometricSetting/BiometricSetting.apk" "fingerprint/BiometricSetting.apk/0002-Always-use-ultrasonic-FOD-animation.patch"
    elif [[ "$FP_TYPE" == "side" ]]; then
        ADD_TO_WORK_DIR "b6qxxx" "system" "."
        DELETE_FROM_WORK_DIR "system" "system/priv-app/BiometricSetting/oat"
        APPLY_PATCH "system/framework/services.jar" "fingerprint/services.jar/0001-Set-FP_FEATURE_SENSOR_IS_ULTRASONIC-to-false.patch"
        APPLY_PATCH "system/framework/services.jar" "fingerprint/services.jar/0002-Set-FP_FEATURE_SENSOR_IS_IN_DISPLAY_TYPE-to-false.patch"
    fi
fi

if $SOURCE_HAS_HW_MDNIE; then
    if ! $TARGET_HAS_HW_MDNIE; then
        echo "Applying HW mDNIe patches"
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_SUPPORT_MDNIE_HW" --delete
        APPLY_PATCH "system/framework/framework.jar" "mdnie/hw/framework.jar/0001-Disable-HW-mDNIe.patch"
        APPLY_PATCH "system/framework/services.jar" "mdnie/hw/services.jar/0001-Disable-HW-mDNIe.patch"
        DELETE_FROM_WORK_DIR "system" "system/bin/mafpc_write"
    fi
fi

if $SOURCE_MDNIE_SUPPORT_HDR_EFFECT; then
    if ! $TARGET_MDNIE_SUPPORT_HDR_EFFECT; then
        echo "Applying mDNIe HDR effect patches"
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_SUPPORT_HDR_EFFECT" --delete
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "mdnie/hdr/SecSettings.apk/0001-Disable-HDR-Settings.patch"
    fi
fi

if [[ "$SOURCE_MDNIE_SUPPORTED_MODES" != "$TARGET_MDNIE_SUPPORTED_MODES" ]]; then
    echo "Applying mDNIe features patches"

    DECODE_APK "system/framework/services.jar"

    FTP="
    system/framework/services.jar/smali_classes2/com/samsung/android/hardware/display/SemMdnieManagerService.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_MDNIE_SUPPORTED_MODES\"/\"$TARGET_MDNIE_SUPPORTED_MODES\"/g" "$APKTOOL_DIR/$f"
    done
fi

if [[ "$SOURCE_MDNIE_WEAKNESS_SOLUTION_FUNCTION" != "$TARGET_MDNIE_WEAKNESS_SOLUTION_FUNCTION" ]]; then
    echo "Applying mDNIe weakness features patches"

    DECODE_APK "system/framework/framework.jar"

    FTP="
    system/framework/framework.jar/smali_classes4/android/view/accessibility/A11yRune.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_MDNIE_WEAKNESS_SOLUTION_FUNCTION\"/\"$TARGET_MDNIE_WEAKNESS_SOLUTION_FUNCTION\"/g" "$APKTOOL_DIR/$f"
    done
fi

DECODE_APK "system/framework/framework.jar"

if [[ "$TARGET_HFR_SEAMLESS_BRT" == "none" && "$TARGET_HFR_SEAMLESS_LUX" == "none" ]]; then
    APPLY_PATCH "system/framework/framework.jar" "hfr/framework.jar/0001-Remove-brightness-threshold-values.patch"
else
    FTP="
    system/framework/framework.jar/smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_HFR_SEAMLESS_BRT\"/\"$TARGET_HFR_SEAMLESS_BRT\"/g" "$APKTOOL_DIR/$f"
        sed -i "s/\"$SOURCE_HFR_SEAMLESS_LUX\"/\"$TARGET_HFR_SEAMLESS_LUX\"/g" "$APKTOOL_DIR/$f"
    done
fi

if [[ "$SOURCE_HFR_MODE" != "$TARGET_HFR_MODE" ]]; then
    echo "Applying HFR_MODE patches"

    DECODE_APK "system/framework/framework.jar"
    DECODE_APK "system/framework/gamemanager.jar"
    DECODE_APK "system/framework/secinputdev-service.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"
    DECODE_APK "system/priv-app/SettingsProvider/SettingsProvider.apk"
    DECODE_APK "system_ext/priv-app/SystemUI/SystemUI.apk"

    FTP="
    system/framework/framework.jar/smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali
    system/framework/gamemanager.jar/smali/com/samsung/android/game/GameManagerService.smali
    system/framework/secinputdev-service.jar/smali/com/samsung/android/hardware/secinputdev/SemInputDeviceManagerService.smali
    system/framework/secinputdev-service.jar/smali/com/samsung/android/hardware/secinputdev/SemInputFeatures.smali
    system/framework/secinputdev-service.jar/smali/com/samsung/android/hardware/secinputdev/SemInputFeaturesExtra.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/display/SecDisplayUtils.smali
    system/priv-app/SettingsProvider/SettingsProvider.apk/smali/com/android/providers/settings/DatabaseHelper.smali
    system_ext/priv-app/SystemUI/SystemUI.apk/smali/com/android/systemui/LsRune.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_HFR_MODE\"/\"$TARGET_HFR_MODE\"/g" "$APKTOOL_DIR/$f"
    done

    if [[ "$TARGET_HFR_MODE" -eq 0 ]]; then
        REPL=1
    else
        REPL="$TARGET_HFR_MODE"
    fi
    sed -i "s/\"$SOURCE_HFR_MODE\"/\"$REPL\"/g" "$APKTOOL_DIR/system/framework/framework.jar/smali_classes6/com/samsung/android/rune/CoreRune.smali"
fi

if [[ "$SOURCE_HFR_SUPPORTED_REFRESH_RATE" != "$TARGET_HFR_SUPPORTED_REFRESH_RATE" ]]; then
    echo "Applying HFR_SUPPORTED_REFRESH_RATE patches"

    DECODE_APK "system/framework/framework.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"

    FTP="
    system/framework/framework.jar/smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/display/SecDisplayUtils.smali
    "
    for f in $FTP; do
        if [[ "$TARGET_HFR_SUPPORTED_REFRESH_RATE" != "none" ]]; then
            sed -i "s/\"$SOURCE_HFR_SUPPORTED_REFRESH_RATE\"/\"$TARGET_HFR_SUPPORTED_REFRESH_RATE\"/g" "$APKTOOL_DIR/$f"
        else
            sed -i "s/\"$SOURCE_HFR_SUPPORTED_REFRESH_RATE\"/\"\"/g" "$APKTOOL_DIR/$f"
        fi
    done
fi

if [[ "$SOURCE_HFR_DEFAULT_REFRESH_RATE" != "$TARGET_HFR_DEFAULT_REFRESH_RATE" ]]; then
    echo "Applying HFR_DEFAULT_REFRESH_RATE patches"

    DECODE_APK "system/framework/framework.jar"
    DECODE_APK "system/priv-app/SecSettings/SecSettings.apk"
    DECODE_APK "system/priv-app/SettingsProvider/SettingsProvider.apk"

    FTP="
    system/framework/framework.jar/smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali
    system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/display/SecDisplayUtils.smali
    system/priv-app/SettingsProvider/SettingsProvider.apk/smali/com/android/providers/settings/DatabaseHelper.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_HFR_DEFAULT_REFRESH_RATE\"/\"$TARGET_HFR_DEFAULT_REFRESH_RATE\"/g" "$APKTOOL_DIR/$f"
    done
fi

if [[ "$TARGET_DISPLAY_CUTOUT_TYPE" == "right" ]]; then
    echo "Applying right cutout patch"
    APPLY_PATCH "system_ext/priv-app/SystemUI/SystemUI.apk" "cutout/SystemUI.apk/0001-Add-right-cutout-support.patch"
fi

if [[ "$SOURCE_DVFS_CONFIG_NAME" != "$TARGET_DVFS_CONFIG_NAME" ]]; then
    echo "Applying DVFS patches"

    DECODE_APK "system/framework/ssrm.jar"

    FTP="
    system/framework/ssrm.jar/smali/com/android/server/ssrm/Feature.smali
    "
    for f in $FTP; do
        sed -i "s/\"$SOURCE_DVFS_CONFIG_NAME\"/\"$TARGET_DVFS_CONFIG_NAME\"/g" "$APKTOOL_DIR/$f"
    done
fi

if $SOURCE_IS_ESIM_SUPPORTED; then
    if ! $TARGET_IS_ESIM_SUPPORTED; then
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH" --delete
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_SUPPORT_EMBEDDED_SIM" --delete
    fi
fi

if [[ -f "$FW_DIR/${MODEL}_${REGION}/system/system/etc/permissions/com.sec.feature.cover.xml" ]]; then
    echo "Adding LED Case Cover support"
    ADD_TO_WORK_DIR "p3sxxx" "system" "system/priv-app/LedCoverService/LedCoverService.apk"
    ADD_TO_WORK_DIR "p3sxxx" "system" "system/etc/permissions/privapp-permissions-com.sec.android.cover.ledcover.xml"
fi

if [[ ! -f "$FW_DIR/${MODEL}_${REGION}/vendor/etc/permissions/android.hardware.strongbox_keystore.xml" ]]; then
    echo "Applying strongbox patches"
    APPLY_PATCH "system/framework/framework.jar" "strongbox/framework.jar/0001-Disable-StrongBox-in-DevRootKeyATCmd.patch"
fi

if $SOURCE_SUPPORT_WIFI_7; then
    if ! $TARGET_SUPPORT_WIFI_7; then
        echo "Applying Wi-Fi 7 patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0001-Disable-Wi-Fi-7-support.patch"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "wifi/SecSettings.apk/0001-Disable-Wi-Fi-7-support.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_DUALAP; then
    if ! $TARGET_SUPPORT_HOTSPOT_DUALAP; then
        echo "Applying Hotspot DualAP patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0002-Disable-DualAP-support.patch"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "wifi/SecSettings.apk/0002-Disable-DualAP-support.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_WPA3; then
    if ! $TARGET_SUPPORT_HOTSPOT_WPA3; then
        echo "Applying Hotspot WPA3 patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0003-Disable-Hotspot-WPA3-support.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_6GHZ; then
    if ! $TARGET_SUPPORT_HOTSPOT_6GHZ; then
        echo "Applying Hotspot 6GHz patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0004-Disable-Hotspot-6GHz-support.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_WIFI_6; then
    if ! $TARGET_SUPPORT_HOTSPOT_WIFI_6; then
        echo "Applying Hotspot Wi-Fi 6 patches"
        APPLY_PATCH "system/framework/semwifi-service.jar" "wifi/semwifi-service.jar/0004-Disable-Hotspot-6GHz-support.patch"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "wifi/SecSettings.apk/0003-Disable-Hotspot-Wi-Fi-6.patch"
    fi
fi

if $SOURCE_SUPPORT_HOTSPOT_ENHANCED_OPEN; then
    if ! $TARGET_SUPPORT_HOTSPOT_ENHANCED_OPEN; then
        echo "Applying Hotspot Enhanced Open patches"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "wifi/SecSettings.apk/0004-Disable-Hotspot-Enhanced-Open.patch"
    fi
fi

if $SOURCE_AUDIO_SUPPORT_ACH_RINGTONE; then
    if ! $TARGET_AUDIO_SUPPORT_ACH_RINGTONE; then
        echo "Applying ACH ringtone patches"
        APPLY_PATCH "system/framework/framework.jar" "audio/framework.jar/0001-Disable-ACH-ringtone-support.patch"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "audio/SecSettings.apk/0001-Disable-ACH-ringtone-support.patch"
    fi
fi

if $SOURCE_AUDIO_SUPPORT_VIRTUAL_VIBRATION; then
    if ! $TARGET_AUDIO_SUPPORT_VIRTUAL_VIBRATION; then
        echo "Applying virtual vibration patches"
        APPLY_PATCH "system/priv-app/SecSettings/SecSettings.apk" "audio/SecSettings.apk/0002-Disable-Virtual-Vibration-support.patch"
    fi
fi

if [[ "$(GET_PROP "vendor" "ro.build.ab_update")" != "true" ]]; then
    echo "Disabling A/B partitions"
    SET_PROP "product" "ro.product.ab_ota_partitions" --delete
fi
-delete
fi
