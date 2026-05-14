package com.handscore.hexagon.model;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public final class NpuProfile {
    public final String backend;
    public final int totalOps;
    public final int npuOps;
    public final int gpuOps;
    public final int cpuOps;
    public final double profilingTimeMs;
    public final JSONArray components;
    public final JSONArray blockers;

    public NpuProfile(
            String backend,
            int totalOps,
            int npuOps,
            int gpuOps,
            int cpuOps,
            double profilingTimeMs,
            JSONArray components,
            JSONArray blockers
    ) {
        this.backend = backend;
        this.totalOps = totalOps;
        this.npuOps = npuOps;
        this.gpuOps = gpuOps;
        this.cpuOps = cpuOps;
        this.profilingTimeMs = profilingTimeMs;
        this.components = components;
        this.blockers = blockers;
    }

    public static NpuProfile referenceBackendProfile(String backend) throws JSONException {
        JSONObject component = new JSONObject();
        component.put("name", "reference_backend");
        component.put("fileName", "");
        component.put("totalOps", 1);
        component.put("npuOps", 0);
        component.put("aneOps", 0);
        component.put("gpuOps", 0);
        component.put("cpuOps", 1);
        component.put("npuPercentage", 0.0);
        component.put("anePercentage", 0.0);
        component.put("opsByDevice", new JSONObject().put("cpu", new JSONArray().put("reference:no_accelerator")));
        component.put("opsByType", new JSONObject().put("reference", 1));

        return new NpuProfile(
                backend,
                1,
                0,
                0,
                1,
                0.0,
                new JSONArray().put(component),
                new JSONArray().put("Reference backend does not validate Hexagon NPU execution")
        );
    }

    public JSONObject toJson() throws JSONException {
        int executableOps = npuOps + gpuOps + cpuOps;
        double npuPercentage = executableOps > 0 ? (double) npuOps / executableOps * 100.0 : 0.0;
        JSONObject json = new JSONObject();
        json.put("backend", backend);
        json.put("components", components);
        json.put("totalOps", totalOps);
        json.put("npuOps", npuOps);
        json.put("aneOps", npuOps);
        json.put("gpuOps", gpuOps);
        json.put("cpuOps", cpuOps);
        json.put("npuPercentage", npuPercentage);
        json.put("anePercentage", npuPercentage);
        json.put("topCostOps", new JSONArray());
        json.put("npuBlockers", blockers);
        json.put("aneBlockers", blockers);
        json.put("profilingTimeMs", profilingTimeMs);
        return json;
    }
}
