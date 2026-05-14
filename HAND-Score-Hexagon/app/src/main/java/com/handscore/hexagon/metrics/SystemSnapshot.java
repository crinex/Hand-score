package com.handscore.hexagon.metrics;

import org.json.JSONException;
import org.json.JSONObject;

public final class SystemSnapshot {
    public final double batteryLevel;
    public final String batteryState;
    public final double memoryUsageMB;
    public final double availableMemoryMB;
    public final int thermalState;

    public SystemSnapshot(
            double batteryLevel,
            String batteryState,
            double memoryUsageMB,
            double availableMemoryMB,
            int thermalState
    ) {
        this.batteryLevel = batteryLevel;
        this.batteryState = batteryState;
        this.memoryUsageMB = memoryUsageMB;
        this.availableMemoryMB = availableMemoryMB;
        this.thermalState = thermalState;
    }

    public JSONObject toJson() throws JSONException {
        JSONObject json = new JSONObject();
        json.put("batteryLevel", batteryLevel);
        json.put("batteryState", batteryState);
        json.put("memoryUsageMB", memoryUsageMB);
        json.put("availableMemoryMB", availableMemoryMB);
        json.put("thermalState", thermalState);
        return json;
    }
}
