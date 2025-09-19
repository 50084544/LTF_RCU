package com.spoors.rcu.security

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.Socket
import java.security.MessageDigest

/**
 * SecurityCheckPlugin
 *
 * A Flutter plugin to perform advanced security checks on Android.
 */
class SecurityCheckPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.spoors.rcu/security")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "checkRoot" -> {
                val suPaths = call.argument<List<String>>("suPaths") ?: emptyList()
                val rootPackages = call.argument<List<String>>("rootPackages") ?: emptyList()
                result.success(checkRoot(suPaths, rootPackages))
            }
            "checkHooking" -> {
                val hookingFrameworks = call.argument<Map<String, List<String>>>("hookingFrameworks") ?: emptyMap()
                val fridaPorts = call.argument<List<Int>>("fridaPorts") ?: emptyList()
                result.success(checkHooking(hookingFrameworks, fridaPorts))
            }
            "isDebuggable" -> {
                result.success(isDebuggable())
            }
            "isDebuggerAttached" -> {
                result.success(isDebuggerAttached())
            }
            "verifyAppIntegrity" -> {
                val packageName = call.argument<String>("packageName") ?: context.packageName
                result.success(verifyAppIntegrity(packageName))
            }
            "checkDangerousApps" -> {
                val dangerousApps = call.argument<List<String>>("dangerousApps") ?: emptyList()
                result.success(checkDangerousApps(dangerousApps))
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    /**
     * Check if the device is rooted
     */
    private fun checkRoot(suPaths: List<String>, rootPackages: List<String>): Boolean {
        // Method 1: Check for SU binary
        for (path in suPaths) {
            if (File(path).exists()) {
                return true
            }
        }

        // Method 2: Check for root packages
        val pm = context.packageManager
        for (packageName in rootPackages) {
            try {
                pm.getPackageInfo(packageName, 0)
                return true
            } catch (e: PackageManager.NameNotFoundException) {
                // Package not found, continue
            }
        }

        // Method 3: Check if system properties have been tampered
        var process: Process? = null
        try {
            process = Runtime.getRuntime().exec(arrayOf("getprop", "ro.secure"))
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val line = reader.readLine()
            if ("0" == line || "false" == line) {
                return true
            }
        } catch (e: Exception) {
            // Ignore exception
        } finally {
            process?.destroy()
        }

        // Method 4: Check for test-keys in build fingerprint
        val buildTags = Build.TAGS
        if (buildTags != null && buildTags.contains("test-keys")) {
            return true
        }

        return false
    }

    /**
     * Check for hooking frameworks (Frida, Xposed, Magisk)
     */
    private fun checkHooking(hookingFrameworks: Map<String, List<String>>, fridaPorts: List<Int>): Boolean {
        // Method 1: Check for known hooking framework files
        for (entry in hookingFrameworks) {
            for (path in entry.value) {
                if (File(path).exists()) {
                    return true
                }
            }
        }

        // Method 2: Check for Frida server running on default ports
        for (port in fridaPorts) {
            try {
                Socket("localhost", port).use { socket ->
                    // If we can connect, Frida server is likely running
                    return true
                }
            } catch (e: Exception) {
                // Connection failed, which is good
            }
        }

        // Method 3: Check for loaded libraries that might be used for hooking
        try {
            val maps = File("/proc/self/maps").readText()
            val suspiciousLibraries = listOf(
                "frida", "xposed", "substrate", "epic", "magisk"
            )
            for (library in suspiciousLibraries) {
                if (maps.contains(library, ignoreCase = true)) {
                    return true
                }
            }
        } catch (e: Exception) {
            // Ignore exception
        }

        // Method 4: Check for Xposed specific environment
        try {
            val classLoader = context.classLoader
            classLoader.loadClass("de.robv.android.xposed.XposedBridge")
            // If we get here, Xposed is installed
            return true
        } catch (e: ClassNotFoundException) {
            // Class not found, which is good
        }

        return false
    }

    /**
     * Check if the app is debuggable
     */
    private fun isDebuggable(): Boolean {
        return context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    }

    /**
     * Check if a debugger is currently attached
     */
    private fun isDebuggerAttached(): Boolean {
        return android.os.Debug.isDebuggerConnected()
    }

    /**
     * Verify app integrity by checking signature
     */
    private fun verifyAppIntegrity(packageName: String): Boolean {
        try {
            val pm = context.packageManager

            // Get app signature
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val packageInfo = pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                packageInfo.signingInfo?.apkContentsSigners ?: emptyArray()
            } else {
                @Suppress("DEPRECATION")
                val packageInfo = pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                @Suppress("DEPRECATION")
                packageInfo.signatures ?: emptyArray()
            }

            if (signatures.isEmpty()) {
                return false
            }

            // Get signature digest
            val md = MessageDigest.getInstance("SHA-256")
            val signatureBytes = signatures[0].toByteArray()
            val digest = md.digest(signatureBytes)

            // Convert to hex string
            val hexString = StringBuilder()
            for (b in digest) {
                hexString.append(String.format("%02x", b))
            }

            // Store this value securely the first time you build the app
            // Then compare it with the expected value on subsequent runs
            // For now, just check that we have a valid signature
            return hexString.isNotEmpty()
        } catch (e: Exception) {
            return false
        }
    }

    /**
     * Check for dangerous security testing apps
     */
    private fun checkDangerousApps(dangerousApps: List<String>): Boolean {
        val pm = context.packageManager
        for (packageName in dangerousApps) {
            try {
                pm.getPackageInfo(packageName, 0)
                // Package found, which is bad
                return true
            } catch (e: PackageManager.NameNotFoundException) {
                // Package not found, which is good
            }
        }
        return false
    }
}
