package com.handscore.hexagon;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        TextView view = new TextView(this);
        view.setText(
                "HAND-Score Hexagon\n\n"
                        + "This source build does not bundle benchmark APKs, model weights, or Qualcomm runtime artifacts. "
                        + "Prepare device-local artifacts as described in the Hexagon README."
        );
        view.setPadding(48, 48, 48, 48);
        setContentView(view);
    }
}
