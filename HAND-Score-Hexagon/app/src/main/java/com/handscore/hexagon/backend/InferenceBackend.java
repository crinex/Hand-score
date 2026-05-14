package com.handscore.hexagon.backend;

import com.handscore.hexagon.data.ChatMessage;
import com.handscore.hexagon.model.GenerationResult;
import com.handscore.hexagon.model.ModelDescriptor;
import com.handscore.hexagon.model.NpuProfile;
import com.handscore.hexagon.protocol.BenchmarkOptions;

import java.util.List;

public interface InferenceBackend extends AutoCloseable {
    String name();

    ModelDescriptor loadModel(BenchmarkOptions options) throws Exception;

    GenerationResult generate(
            List<ChatMessage> history,
            int promptTokensHint,
            int maxTokens,
            float temperature
    ) throws Exception;

    int countTokens(String text);

    NpuProfile profile() throws Exception;

    @Override
    void close();
}
