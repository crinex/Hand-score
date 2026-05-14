package com.handscore.hexagon.data;

import java.util.Collections;
import java.util.List;

public final class MultiTurnSample {
    public final String id;
    public final int turnCount;
    public final int totalTokens;
    public final List<ChatMessage> messages;
    public final List<String> references;

    public MultiTurnSample(
            String id,
            int turnCount,
            int totalTokens,
            List<ChatMessage> messages,
            List<String> references
    ) {
        this.id = id;
        this.turnCount = turnCount;
        this.totalTokens = totalTokens;
        this.messages = Collections.unmodifiableList(messages);
        this.references = Collections.unmodifiableList(references);
    }
}
