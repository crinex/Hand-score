package com.handscore.hexagon.model;

import org.json.JSONException;
import org.json.JSONObject;

public final class ModelDescriptor {
    public final String name;
    public final String path;
    public final int contextLength;
    public final int batchSize;
    public final boolean isMonolithic;
    public final String backend;

    public ModelDescriptor(
            String name,
            String path,
            int contextLength,
            int batchSize,
            boolean isMonolithic,
            String backend
    ) {
        this.name = name;
        this.path = path;
        this.contextLength = contextLength;
        this.batchSize = batchSize;
        this.isMonolithic = isMonolithic;
        this.backend = backend;
    }

    public JSONObject toJson() throws JSONException {
        JSONObject json = new JSONObject();
        json.put("name", name);
        json.put("path", path);
        json.put("contextLength", contextLength);
        json.put("batchSize", batchSize);
        json.put("isMonolithic", isMonolithic);
        json.put("backend", backend);
        return json;
    }
}
