package com.handscore.hexagon.results;

import android.os.Build;

import com.handscore.hexagon.metrics.SystemMetricsReport;
import com.handscore.hexagon.model.GenerationResult;
import com.handscore.hexagon.model.ModelDescriptor;
import com.handscore.hexagon.model.NpuProfile;
import com.handscore.hexagon.protocol.BenchmarkOptions;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.UUID;

public final class ResultJson {
    private ResultJson() {
    }

    public static JSONObject singleTurn(
            ModelDescriptor model,
            BenchmarkOptions options,
            String prompt,
            double modelLoadTimeMs,
            GenerationResult generation,
            SystemMetricsReport system,
            NpuProfile profile
    ) throws JSONException {
        return baseResult(model, options, prompt, "single_turn", modelLoadTimeMs, generation, system, profile)
                .put("generatedText", generation.generatedText)
                .put("turnResults", JSONObject.NULL);
    }

    public static JSONObject multiTurn(
            ModelDescriptor model,
            BenchmarkOptions options,
            String prompt,
            double modelLoadTimeMs,
            GenerationResult aggregate,
            SystemMetricsReport system,
            NpuProfile profile,
            JSONArray turnResults
    ) throws JSONException {
        return baseResult(model, options, prompt, "multi_turn", modelLoadTimeMs, aggregate, system, profile)
                .put("generatedText", aggregate.generatedText)
                .put("turnResults", turnResults);
    }

    public static JSONObject turnResult(
            int turnIndex,
            String role,
            String inputText,
            int inputTokens,
            GenerationResult generation,
            int kvCachePosition
    ) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("turnIndex", turnIndex);
        json.put("role", role);
        json.put("inputText", inputText);
        json.put("inputTokens", inputTokens);
        json.put("outputTokens", generation.totalTokens);
        json.put("prefillTimeMs", generation.prefillTimeMs);
        json.put("prefillTokensPerSec", generation.prefillTokensPerSec);
        json.put("decodeTimeMs", generation.decodeTimeMs);
        json.put("decodeTokensPerSec", generation.decodeTokensPerSec);
        json.put("ttftMs", generation.ttftMs);
        json.put("kvCachePosition", kvCachePosition);
        json.put("generatedText", generation.generatedText);
        return json;
    }

    public static JSONObject userTurnResult(int turnIndex, String inputText, int inputTokens)
            throws JSONException {
        JSONObject json = new JSONObject();
        json.put("turnIndex", turnIndex);
        json.put("role", "user");
        json.put("inputText", inputText);
        json.put("inputTokens", inputTokens);
        json.put("outputTokens", 0);
        json.put("prefillTimeMs", 0.0);
        json.put("prefillTokensPerSec", 0.0);
        json.put("decodeTimeMs", 0.0);
        json.put("decodeTokensPerSec", 0.0);
        json.put("ttftMs", 0.0);
        json.put("kvCachePosition", 0);
        json.put("generatedText", "");
        return json;
    }

    private static JSONObject baseResult(
            ModelDescriptor model,
            BenchmarkOptions options,
            String prompt,
            String mode,
            double modelLoadTimeMs,
            GenerationResult generation,
            SystemMetricsReport system,
            NpuProfile profile
    ) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("id", UUID.randomUUID().toString());
        json.put("timestamp", ResultStore.isoTimestamp());
        json.put("device", deviceInfo());
        json.put("model", model.toJson());
        json.put("config", config(prompt, mode, options));
        json.put("performance", performance(modelLoadTimeMs, generation));
        json.put("system", system.toJson());
        json.put("npuProfile", profile.toJson());
        return json;
    }

    private static JSONObject config(String prompt, String mode, BenchmarkOptions options) throws JSONException {
        JSONObject json = new JSONObject();
        json.put("prompt", prompt);
        json.put("maxTokens", options.maxTokens);
        json.put("temperature", options.temperature);
        json.put("mode", mode);
        return json;
    }

    private static JSONObject performance(double modelLoadTimeMs, GenerationResult generation)
            throws JSONException {
        JSONObject json = new JSONObject();
        json.put("modelLoadTimeMs", modelLoadTimeMs);
        json.put("prefillTimeMs", generation.prefillTimeMs);
        json.put("prefillTokens", generation.prefillTokens);
        json.put("prefillTokensPerSec", generation.prefillTokensPerSec);
        json.put("decodeTokens", generation.decodeTokens);
        json.put("decodeTimeMs", generation.decodeTimeMs);
        json.put("decodeTokensPerSec", generation.decodeTokensPerSec);
        json.put("ttftMs", generation.ttftMs);
        json.put("totalTokens", generation.totalTokens);
        json.put("totalTimeMs", generation.totalTimeMs);
        return json;
    }

    private static JSONObject deviceInfo() throws JSONException {
        JSONObject json = new JSONObject();
        json.put("model", Build.MODEL);
        json.put("name", Build.MANUFACTURER + " " + Build.MODEL);
        json.put("chip", chipName());
        json.put("osVersion", Build.VERSION.RELEASE + " (API " + Build.VERSION.SDK_INT + ")");
        json.put("hardware", Build.HARDWARE);
        json.put("device", Build.DEVICE);
        return json;
    }

    private static String chipName() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (Build.SOC_MANUFACTURER != null && Build.SOC_MODEL != null) {
                return Build.SOC_MANUFACTURER + " " + Build.SOC_MODEL;
            }
            if (Build.SOC_MODEL != null) {
                return Build.SOC_MODEL;
            }
        }
        return Build.HARDWARE == null ? "unknown" : Build.HARDWARE;
    }
}
