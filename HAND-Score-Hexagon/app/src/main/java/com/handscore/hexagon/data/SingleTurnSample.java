package com.handscore.hexagon.data;

public final class SingleTurnSample {
    public final String id;
    public final String bin;
    public final int inputTokens;
    public final String prompt;
    public final String reference;

    public SingleTurnSample(String id, String bin, int inputTokens, String prompt, String reference) {
        this.id = id;
        this.bin = bin;
        this.inputTokens = inputTokens;
        this.prompt = prompt;
        this.reference = reference;
    }
}
