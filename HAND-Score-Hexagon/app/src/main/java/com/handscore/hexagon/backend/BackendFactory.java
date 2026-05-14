package com.handscore.hexagon.backend;

import android.content.Context;

public final class BackendFactory {
    private BackendFactory() {
    }

    public static InferenceBackend create(Context context) {
        return new ReferenceBackend();
    }
}
