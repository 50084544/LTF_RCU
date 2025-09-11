package com.spoors.rcu;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import com.spoors.rcu.security.SecurityCheckPlugin;

/** SecurityPluginRegistrant */
public class SecurityPluginRegistrant {
    public static void registerWith(FlutterPlugin.FlutterPluginBinding flutterPluginBinding) {
        // Register our security plugin
        flutterPluginBinding.getPlatformViewRegistry().registerViewFactory(
                "com.spoors.rcu/security_plugin", 
                new SecurityCheckPlugin());
                
        // Setup method channel
        MethodChannel channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), 
                "com.spoors.rcu/security");
        channel.setMethodCallHandler(new SecurityCheckPlugin());
    }
}
