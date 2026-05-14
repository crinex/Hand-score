package com.handscore.hexagon.data;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class ChatAlpacaDataset {
    public final String version;
    public final String dataset;
    public final String extractedAt;
    public final int seed;
    public final List<SingleTurnSample> singleTurn;
    public final List<MultiTurnSample> multiTurn;

    private ChatAlpacaDataset(
            String version,
            String dataset,
            String extractedAt,
            int seed,
            List<SingleTurnSample> singleTurn,
            List<MultiTurnSample> multiTurn
    ) {
        this.version = version;
        this.dataset = dataset;
        this.extractedAt = extractedAt;
        this.seed = seed;
        this.singleTurn = Collections.unmodifiableList(singleTurn);
        this.multiTurn = Collections.unmodifiableList(multiTurn);
    }

    public static ChatAlpacaDataset load(Context context) throws IOException, JSONException {
        try (InputStream input = context.getAssets().open("chatalpaca_handscore.json")) {
            byte[] bytes = input.readAllBytes();
            JSONObject root = new JSONObject(new String(bytes, StandardCharsets.UTF_8));

            List<SingleTurnSample> singleTurn = new ArrayList<>();
            JSONArray singleArray = root.getJSONArray("single_turn");
            for (int i = 0; i < singleArray.length(); i++) {
                JSONObject item = singleArray.getJSONObject(i);
                singleTurn.add(new SingleTurnSample(
                        item.getString("id"),
                        item.getString("bin"),
                        item.getInt("input_tokens"),
                        item.getString("prompt"),
                        item.optString("reference", "")
                ));
            }

            List<MultiTurnSample> multiTurn = new ArrayList<>();
            JSONArray multiArray = root.getJSONArray("multi_turn");
            for (int i = 0; i < multiArray.length(); i++) {
                JSONObject item = multiArray.getJSONObject(i);
                List<ChatMessage> messages = new ArrayList<>();
                JSONArray messageArray = item.getJSONArray("messages");
                for (int j = 0; j < messageArray.length(); j++) {
                    JSONObject message = messageArray.getJSONObject(j);
                    messages.add(new ChatMessage(
                            message.getString("role"),
                            message.optString("content", "")
                    ));
                }

                List<String> references = new ArrayList<>();
                JSONArray referenceArray = item.optJSONArray("references");
                if (referenceArray != null) {
                    for (int j = 0; j < referenceArray.length(); j++) {
                        references.add(referenceArray.optString(j, ""));
                    }
                }

                multiTurn.add(new MultiTurnSample(
                        item.getString("id"),
                        item.getInt("turn_count"),
                        item.getInt("total_tokens"),
                        messages,
                        references
                ));
            }

            return new ChatAlpacaDataset(
                    root.getString("version"),
                    root.getString("dataset"),
                    root.optString("extracted_at", ""),
                    root.optInt("seed", 0),
                    singleTurn,
                    multiTurn
            );
        }
    }
}
