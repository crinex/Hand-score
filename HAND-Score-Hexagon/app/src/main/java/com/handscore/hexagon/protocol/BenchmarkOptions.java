package com.handscore.hexagon.protocol;

import android.content.Context;

import java.io.File;

public final class BenchmarkOptions {
    public final String modelName;
    public final String modelPath;
    public final int contextLength;
    public final int batchSize;
    public final int maxTokens;
    public final float temperature;
    public final int thermalRounds;
    public final long singleTurnCooldownMs;

    public BenchmarkOptions(
            String modelName,
            String modelPath,
            int contextLength,
            int batchSize,
            int maxTokens,
            float temperature,
            int thermalRounds,
            long singleTurnCooldownMs
    ) {
        this.modelName = modelName;
        this.modelPath = modelPath;
        this.contextLength = contextLength;
        this.batchSize = batchSize;
        this.maxTokens = maxTokens;
        this.temperature = temperature;
        this.thermalRounds = thermalRounds;
        this.singleTurnCooldownMs = singleTurnCooldownMs;
    }

    public static BenchmarkOptions defaults(Context context) {
        File modelRoot = new File(context.getExternalFilesDir(null), "models/Hexagon-Llama-3.2-1B");
        return new BenchmarkOptions(
                "Hexagon-Llama-3.2-1B",
                modelRoot.getAbsolutePath(),
                4096,
                64,
                128,
                0.0f,
                30,
                10_000L
        );
    }
}
