plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.aymanTarget.codexus"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // 1. ✅ تفعيل الـ Desugaring لحل مشكلة مكتبة الإشعارات
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aymanTarget.codexus"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 🔑 ✨ ضفنا السكشن ده هنا عشان لغة كوتلن تفهم الـ debug وم تطلعش خطأ
    signingConfigs {
        getByName("debug") {
            // بيستخدم المفتاح الافتراضي بدون تعقيد
        }
    }

    buildTypes {
        release {
            // 1. قفل تقليص الحجم والـ Minify عشان ما يحذفش ملفات الفايربيز
            isMinifyEnabled = false
            isShrinkResources = false

            // 2. تفعيل الـ ProGuard الافتراضي للأندرويد
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // 3. ربط التشفير والـ Signing
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// 2. ✅ إضافة مكتبة الـ Desugaring المطلوبة لـ Java 8+ فك التشفير
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}