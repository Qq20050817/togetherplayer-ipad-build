plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
 namespace = "dev.together.poc"
 compileSdk = 35
 defaultConfig { testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"; applicationId = "dev.together.poc"; minSdk = 26; targetSdk = 35; versionCode = 121; versionName = "0.6.61"; if(providers.gradleProperty("deliveryArm64").orNull=="true") {ndk {abiFilters += "arm64-v8a"}} }
 buildTypes { getByName("debug") {
  // Separate preview identity preserves every existing install and its data.
  applicationIdSuffix = ".fluency"
 } }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
 kotlinOptions { jvmTarget = "17" }
}
dependencies {
 implementation("org.videolan.android:libvlc-all:3.6.5")
 implementation("com.alphacephei:vosk-android:0.3.47")
 implementation("net.java.dev.jna:jna:5.13.0@aar")
 androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
 androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
 androidTestImplementation("androidx.test:runner:1.6.2")
 androidTestImplementation("androidx.test.ext:junit:1.2.1")
 androidTestImplementation("androidx.test:core:1.6.1")
 testImplementation("junit:junit:4.13.2")
 testImplementation("org.json:json:20240303")
 implementation("androidx.media3:media3-exoplayer:1.7.1")
 implementation("androidx.media3:media3-exoplayer-hls:1.7.1")
 implementation("androidx.media3:media3-ui:1.7.1")
 implementation("org.jellyfin.media3:media3-ffmpeg-decoder:1.6.1+2")
 implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
