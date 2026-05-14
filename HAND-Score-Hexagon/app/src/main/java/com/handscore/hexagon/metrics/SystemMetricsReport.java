package com.handscore.hexagon.metrics;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.List;

public final class SystemMetricsReport {
    public final SystemSnapshot before;
    public final SystemSnapshot after;
    public final List<MetricsSample> timeline;

    public SystemMetricsReport(SystemSnapshot before, SystemSnapshot after, List<MetricsSample> timeline) {
        this.before = before;
        this.after = after;
        this.timeline = timeline;
    }

    public JSONObject toJson() throws JSONException {
        JSONArray samples = new JSONArray();
        for (MetricsSample sample : timeline) {
            samples.put(sample.toJson());
        }

        JSONObject json = new JSONObject();
        json.put("before", before.toJson());
        json.put("after", after.toJson());
        json.put("timeline", samples);
        return json;
    }
}
