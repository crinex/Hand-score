package com.handscore.hexagon.metrics;

import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.Build;
import android.os.PowerManager;
import android.os.Process;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public final class MetricsCollector {
    private final Context context;
    private final List<MetricsSample> samples = Collections.synchronizedList(new ArrayList<>());
    private ScheduledExecutorService scheduler;
    private long startNanos;
    private long lastWallNanos;
    private long lastCpuMillis;

    public MetricsCollector(Context context) {
        this.context = context.getApplicationContext();
    }

    public void start() {
        samples.clear();
        startNanos = System.nanoTime();
        lastWallNanos = startNanos;
        lastCpuMillis = Process.getElapsedCpuTime();
        scheduler = Executors.newSingleThreadScheduledExecutor();
        collectSample();
        scheduler.scheduleAtFixedRate(this::collectSample, 1, 1, TimeUnit.SECONDS);
    }

    public List<MetricsSample> stop() {
        if (scheduler != null) {
            scheduler.shutdownNow();
            scheduler = null;
        }
        collectSample();
        synchronized (samples) {
            return new ArrayList<>(samples);
        }
    }

    public SystemSnapshot snapshot() {
        BatteryInfo battery = batteryInfo();
        return new SystemSnapshot(
                battery.level,
                battery.state,
                memoryUsageMB(),
                availableMemoryMB(),
                thermalState()
        );
    }

    private void collectSample() {
        double timestamp = (System.nanoTime() - startNanos) / 1_000_000_000.0;
        samples.add(new MetricsSample(
                timestamp,
                memoryUsageMB(),
                availableMemoryMB(),
                cpuUsagePercent(),
                thermalState()
        ));
    }

    private double memoryUsageMB() {
        Runtime runtime = Runtime.getRuntime();
        long used = runtime.totalMemory() - runtime.freeMemory();
        return used / (1024.0 * 1024.0);
    }

    private double availableMemoryMB() {
        ActivityManager manager = (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        if (manager == null) {
            return 0.0;
        }
        ActivityManager.MemoryInfo info = new ActivityManager.MemoryInfo();
        manager.getMemoryInfo(info);
        return info.availMem / (1024.0 * 1024.0);
    }

    private Double cpuUsagePercent() {
        long nowWall = System.nanoTime();
        long nowCpu = Process.getElapsedCpuTime();
        long wallDeltaMs = (nowWall - lastWallNanos) / 1_000_000;
        long cpuDeltaMs = nowCpu - lastCpuMillis;
        lastWallNanos = nowWall;
        lastCpuMillis = nowCpu;
        if (wallDeltaMs <= 0) {
            return null;
        }
        int cores = Math.max(1, Runtime.getRuntime().availableProcessors());
        return Math.min(100.0, (cpuDeltaMs * 100.0) / (wallDeltaMs * cores));
    }

    private int thermalState() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return 0;
        }
        PowerManager power = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
        if (power == null) {
            return 0;
        }
        return power.getCurrentThermalStatus();
    }

    private BatteryInfo batteryInfo() {
        Intent intent = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        if (intent == null) {
            return new BatteryInfo(-1.0, "unknown");
        }

        int level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
        double normalized = level >= 0 && scale > 0 ? (double) level / scale : -1.0;
        int status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN);
        String state;
        switch (status) {
            case BatteryManager.BATTERY_STATUS_CHARGING:
                state = "charging";
                break;
            case BatteryManager.BATTERY_STATUS_FULL:
                state = "full";
                break;
            case BatteryManager.BATTERY_STATUS_DISCHARGING:
            case BatteryManager.BATTERY_STATUS_NOT_CHARGING:
                state = "unplugged";
                break;
            default:
                state = "unknown";
        }
        return new BatteryInfo(normalized, state);
    }

    private static final class BatteryInfo {
        final double level;
        final String state;

        BatteryInfo(double level, String state) {
            this.level = level;
            this.state = state;
        }
    }
}
