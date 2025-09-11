package com.ltfinance.spoors_rcu

import com.spoors.rcu.security.SecurityCheckPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register the security plugin - this handles the method channel setup internally
        flutterEngine.plugins.add(SecurityCheckPlugin())
    }
}
