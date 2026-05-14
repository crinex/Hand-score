package com.handscore.hexagon.results;

import android.content.Context;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

public final class ResultStore {
    private ResultStore() {
    }

    public static File resultsRoot(Context context) {
        File root = new File(context.getExternalFilesDir(null), "HAND-Score");
        if (!root.exists()) {
            root.mkdirs();
        }
        return root;
    }

    public static File save(Context context, String modelName, String sampleId, JSONObject result)
            throws IOException {
        File modelDir = new File(resultsRoot(context), sanitize(modelName));
        if (!modelDir.exists()) {
            modelDir.mkdirs();
        }
        String timestamp = new SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(new Date());
        File output = new File(modelDir, "bench_" + sanitize(modelName) + "_" + sampleId + "_" + timestamp + ".json");
        try (FileOutputStream stream = new FileOutputStream(output)) {
            stream.write(result.toString(2).getBytes(StandardCharsets.UTF_8));
            stream.write('\n');
        }
        return output;
    }

    public static String isoTimestamp() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }

    public static String sanitize(String value) {
        return value.replaceAll("[^A-Za-z0-9._-]+", "_");
    }
}
