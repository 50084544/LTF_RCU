package com.ltfinance.spoors_rcu

import com.spoors.rcu.security.SecurityCheckPlugin
import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class SpoorsApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        
        // Any application initialization can go here
    }
    
    /**
     * Configure Flutter engine before it's connected to a Flutter view
     */
    fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Register the security check plugin
        flutterEngine.plugins.add(SecurityCheckPlugin())
    }
}
