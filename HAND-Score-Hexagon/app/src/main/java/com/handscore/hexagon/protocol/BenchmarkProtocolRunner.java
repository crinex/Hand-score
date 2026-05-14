package com.handscore.hexagon.protocol;

import android.content.Context;

import com.handscore.hexagon.backend.BackendFactory;
import com.handscore.hexagon.backend.InferenceBackend;
import com.handscore.hexagon.data.ChatAlpacaDataset;
import com.handscore.hexagon.data.ChatMessage;
import com.handscore.hexagon.data.MultiTurnSample;
import com.handscore.hexagon.data.SingleTurnSample;
import com.handscore.hexagon.metrics.MetricsCollector;
import com.handscore.hexagon.metrics.SystemMetricsReport;
import com.handscore.hexagon.metrics.SystemSnapshot;
import com.handscore.hexagon.model.GenerationResult;
import com.handscore.hexagon.model.ModelDescriptor;
import com.handscore.hexagon.results.ResultJson;
import com.handscore.hexagon.results.ResultStore;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

public final class BenchmarkProtocolRunner {
    private final Context context;
    private final BenchmarkOptions options;
    private final ProgressListener listener;

    public BenchmarkProtocolRunner(Context context, BenchmarkOptions options, ProgressListener listener) {
        this.context = context.getApplicationContext();
        this.options = options;
        this.listener = listener;
    }

    public int runExperimentA() throws Exception {
        ChatAlpacaDataset dataset = ChatAlpacaDataset.load(context);
        int completed = 0;
        for (int i = 0; i < dataset.singleTurn.size(); i++) {
            SingleTurnSample sample = dataset.singleTurn.get(i);
            progress("Exp A " + sample.id + " (" + (i + 1) + "/" + dataset.singleTurn.size() + ")");
            runSingleTurn(sample.id, sample.prompt, sample.inputTokens);
            completed++;
            if (i < dataset.singleTurn.size() - 1 && options.singleTurnCooldownMs > 0) {
                Thread.sleep(options.singleTurnCooldownMs);
            }
        }
        return completed;
    }

    public int runExperimentC() throws Exception {
        ChatAlpacaDataset dataset = ChatAlpacaDataset.load(context);
        SingleTurnSample sample = dataset.singleTurn.get(0);
        for (int i = 0; i < options.thermalRounds; i++) {
            progress("Exp C " + sample.id + " round " + (i + 1) + "/" + options.thermalRounds);
            runSingleTurn(sample.id + "_thermal_" + String.format(Locale.US, "%02d", i + 1), sample.prompt, sample.inputTokens);
        }
        return options.thermalRounds;
    }

    public int runExperimentE() throws Exception {
        ChatAlpacaDataset dataset = ChatAlpacaDataset.load(context);
        int completed = 0;
        for (int i = 0; i < dataset.multiTurn.size(); i++) {
            MultiTurnSample sample = dataset.multiTurn.get(i);
            progress("Exp E " + sample.id + " (" + (i + 1) + "/" + dataset.multiTurn.size() + ")");
            runMultiTurn(sample);
            completed++;
        }
        return completed;
    }

    public int runAll() throws Exception {
        int files = 0;
        files += runExperimentA();
        files += runExperimentC();
        files += runExperimentE();
        return files;
    }

    private File runSingleTurn(String sampleId, String prompt, int promptTokensHint) throws Exception {
        MetricsCollector metrics = new MetricsCollector(context);
        boolean metricsStopped = false;
        SystemSnapshot before = metrics.snapshot();
        metrics.start();

        ModelDescriptor model;
        GenerationResult generation;
        double modelLoadTimeMs;

        try (InferenceBackend backend = BackendFactory.create(context)) {
            long loadStart = System.nanoTime();
            model = backend.loadModel(options);
            modelLoadTimeMs = elapsedMs(loadStart);
            generation = backend.generate(
                    Collections.singletonList(new ChatMessage("user", prompt)),
                    promptTokensHint,
                    options.maxTokens,
                    options.temperature
            );
            SystemSnapshot after = metrics.snapshot();
            SystemMetricsReport system = new SystemMetricsReport(before, after, metrics.stop());
            metricsStopped = true;
            JSONObject result = ResultJson.singleTurn(
                    model,
                    options,
                    prompt,
                    modelLoadTimeMs,
                    generation,
                    system,
                    backend.profile()
            );
            File output = ResultStore.save(context, model.name, sampleId, result);
            progress("Saved " + output.getName());
            return output;
        } finally {
            if (!metricsStopped) {
                metrics.stop();
            }
        }
    }

    private File runMultiTurn(MultiTurnSample sample) throws Exception {
        MetricsCollector metrics = new MetricsCollector(context);
        boolean metricsStopped = false;
        SystemSnapshot before = metrics.snapshot();
        metrics.start();

        try (InferenceBackend backend = BackendFactory.create(context)) {
            long loadStart = System.nanoTime();
            ModelDescriptor model = backend.loadModel(options);
            double modelLoadTimeMs = elapsedMs(loadStart);

            List<ChatMessage> history = new ArrayList<>();
            JSONArray turnResults = new JSONArray();
            StringBuilder allGenerated = new StringBuilder();

            int totalGeneratedTokens = 0;
            int totalPrefillTokens = 0;
            double totalPrefillTimeMs = 0.0;
            double totalDecodeTimeMs = 0.0;
            int totalDecodeTokens = 0;
            double firstTurnTtftMs = 0.0;
            double totalTtftMs = 0.0;

            for (int i = 0; i < sample.messages.size(); i++) {
                ChatMessage message = sample.messages.get(i);
                if ("user".equals(message.role)) {
                    history.add(message);
                    turnResults.put(ResultJson.userTurnResult(i, message.content, backend.countTokens(message.content)));
                    continue;
                }

                int promptTokens = countHistoryTokens(backend, history);
                GenerationResult generation = backend.generate(history, promptTokens, options.maxTokens, options.temperature);
                history.add(new ChatMessage("assistant", generation.generatedText));
                turnResults.put(ResultJson.turnResult(i, "assistant", "(generated)", promptTokens, generation, 0));

                if (firstTurnTtftMs == 0.0) {
                    firstTurnTtftMs = generation.ttftMs;
                }
                totalGeneratedTokens += generation.totalTokens;
                totalPrefillTokens += generation.prefillTokens;
                totalPrefillTimeMs += generation.prefillTimeMs;
                totalTtftMs += generation.ttftMs;
                totalDecodeTokens += generation.decodeTokens;
                totalDecodeTimeMs += generation.decodeTimeMs;
                allGenerated.append("[Turn ").append(i).append("] ")
                        .append(generation.generatedText)
                        .append('\n');
            }

            double prefillTps = totalTtftMs > 0 ? totalPrefillTokens / (totalTtftMs / 1000.0) : 0.0;
            double decodeTps = totalDecodeTimeMs > 0 ? totalDecodeTokens / (totalDecodeTimeMs / 1000.0) : 0.0;
            GenerationResult aggregate = new GenerationResult(
                    allGenerated.toString(),
                    totalPrefillTokens,
                    totalPrefillTimeMs,
                    prefillTps,
                    totalDecodeTokens,
                    totalDecodeTimeMs,
                    decodeTps,
                    firstTurnTtftMs,
                    totalGeneratedTokens,
                    totalPrefillTimeMs + totalDecodeTimeMs
            );

            SystemSnapshot after = metrics.snapshot();
            SystemMetricsReport system = new SystemMetricsReport(before, after, metrics.stop());
            metricsStopped = true;
            String prompt = sample.messages.isEmpty() ? "" : sample.messages.get(0).content;
            JSONObject result = ResultJson.multiTurn(
                    model,
                    options,
                    prompt,
                    modelLoadTimeMs,
                    aggregate,
                    system,
                    backend.profile(),
                    turnResults
            );
            File output = ResultStore.save(context, model.name, sample.id, result);
            progress("Saved " + output.getName());
            return output;
        } finally {
            if (!metricsStopped) {
                metrics.stop();
            }
        }
    }

    private int countHistoryTokens(InferenceBackend backend, List<ChatMessage> history) {
        int total = 0;
        for (ChatMessage message : history) {
            total += backend.countTokens(message.content) + 4;
        }
        return Math.max(1, total);
    }

    private void progress(String message) {
        if (listener != null) {
            listener.onProgress(message);
        }
    }

    private static double elapsedMs(long startNanos) {
        return (System.nanoTime() - startNanos) / 1_000_000.0;
    }
}
