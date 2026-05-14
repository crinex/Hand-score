package com.handscore.hexagon.backend;

import com.handscore.hexagon.data.ChatMessage;
import com.handscore.hexagon.model.GenerationResult;
import com.handscore.hexagon.model.ModelDescriptor;
import com.handscore.hexagon.model.NpuProfile;
import com.handscore.hexagon.protocol.BenchmarkOptions;

import java.util.List;
import java.util.Locale;

public final class ReferenceBackend implements InferenceBackend {
    private ModelDescriptor model;

    @Override
    public String name() {
        return "reference-java-no-npu";
    }

    @Override
    public ModelDescriptor loadModel(BenchmarkOptions options) {
        model = new ModelDescriptor(
                options.modelName,
                options.modelPath,
                options.contextLength,
                options.batchSize,
                false,
                name()
        );
        return model;
    }

    @Override
    public GenerationResult generate(
            List<ChatMessage> history,
            int promptTokensHint,
            int maxTokens,
            float temperature
    ) {
        long start = System.nanoTime();
        int prefillTokens = promptTokensHint > 0 ? promptTokensHint : countHistoryTokens(history);
        int outputTokens = Math.max(1, Math.min(maxTokens, 16));

        String generatedText = String.format(
                Locale.US,
                "[reference backend output: %d prompt tokens, %d generated tokens]",
                prefillTokens,
                outputTokens
        );

        double ttftMs = elapsedMs(start);
        double prefillTimeMs = ttftMs;
        double decodeTimeMs = Math.max(1.0, outputTokens * 0.2);
        double totalTimeMs = prefillTimeMs + decodeTimeMs;
        double prefillTps = ttftMs > 0 ? prefillTokens / (ttftMs / 1000.0) : 0.0;
        int decodeTokens = Math.max(outputTokens - 1, 0);
        double decodeTps = decodeTimeMs > 0 ? decodeTokens / (decodeTimeMs / 1000.0) : 0.0;

        return new GenerationResult(
                generatedText,
                prefillTokens,
                prefillTimeMs,
                prefillTps,
                decodeTokens,
                decodeTimeMs,
                decodeTps,
                ttftMs,
                outputTokens,
                totalTimeMs
        );
    }

    @Override
    public int countTokens(String text) {
        if (text == null || text.trim().isEmpty()) {
            return 0;
        }
        String normalized = text.trim().replaceAll("\\s+", " ");
        int wordish = normalized.split(" ").length;
        return Math.max(1, (int) Math.ceil(wordish * 1.35));
    }

    @Override
    public NpuProfile profile() throws Exception {
        return NpuProfile.referenceBackendProfile(name());
    }

    @Override
    public void close() {
        model = null;
    }

    private int countHistoryTokens(List<ChatMessage> history) {
        int total = 0;
        for (ChatMessage message : history) {
            total += countTokens(message.content) + 4;
        }
        return Math.max(total, 1);
    }

    private static double elapsedMs(long startNanos) {
        return (System.nanoTime() - startNanos) / 1_000_000.0;
    }
}
