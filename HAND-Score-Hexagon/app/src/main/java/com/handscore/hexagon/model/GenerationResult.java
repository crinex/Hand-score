package com.handscore.hexagon.model;

public final class GenerationResult {
    public final String generatedText;
    public final int prefillTokens;
    public final double prefillTimeMs;
    public final double prefillTokensPerSec;
    public final int decodeTokens;
    public final double decodeTimeMs;
    public final double decodeTokensPerSec;
    public final double ttftMs;
    public final int totalTokens;
    public final double totalTimeMs;

    public GenerationResult(
            String generatedText,
            int prefillTokens,
            double prefillTimeMs,
            double prefillTokensPerSec,
            int decodeTokens,
            double decodeTimeMs,
            double decodeTokensPerSec,
            double ttftMs,
            int totalTokens,
            double totalTimeMs
    ) {
        this.generatedText = generatedText;
        this.prefillTokens = prefillTokens;
        this.prefillTimeMs = prefillTimeMs;
        this.prefillTokensPerSec = prefillTokensPerSec;
        this.decodeTokens = decodeTokens;
        this.decodeTimeMs = decodeTimeMs;
        this.decodeTokensPerSec = decodeTokensPerSec;
        this.ttftMs = ttftMs;
        this.totalTokens = totalTokens;
        this.totalTimeMs = totalTimeMs;
    }
}
