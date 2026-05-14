package com.handscore.hexagon.metrics;

import org.json.JSONException;
import org.json.JSONObject;

public final class MetricsSample {
    public final double timestamp;
    public final double memoryUsageMB;
    public final double availableMemoryMB;
    public final Double cpuUsagePercent;
    public final int thermalState;

    public MetricsSample(
            double timestamp,
            double memoryUsageMB,
            double availableMemoryMB,
            Double cpuUsagePercent,
            int thermalState
    ) {
        this.timestamp = timestamp;
        this.memoryUsageMB = memoryUsageMB;
        this.availableMemoryMB = availableMemoryMB;
        this.cpuUsagePercent = cpuUsagePercent;
        this.thermalState = thermalState;
    }

    public JSONObject toJson() throws JSONException {
        JSONObject json = new JSONObject();
        json.put("timestamp", timestamp);
        json.put("memoryUsageMB", memoryUsageMB);
        json.put("availableMemoryMB", availableMemoryMB);
        if (cpuUsagePercent == null) {
            json.put("cpuUsagePercent", JSONObject.NULL);
        } else {
            json.put("cpuUsagePercent", cpuUsagePercent);
        }
        json.put("thermalState", thermalState);
        return json;
    }
}
