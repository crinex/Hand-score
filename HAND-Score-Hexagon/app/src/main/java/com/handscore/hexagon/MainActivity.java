package com.handscore.hexagon;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import com.handscore.hexagon.data.ChatAlpacaDataset;
import com.handscore.hexagon.protocol.BenchmarkOptions;
import com.handscore.hexagon.protocol.BenchmarkProtocolRunner;
import com.handscore.hexagon.results.ResultStore;

import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private TextView statusView;
    private LinearLayout buttonGroup;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        setContentView(buildContentView());
        loadDatasetSummary();
    }

    @Override
    protected void onDestroy() {
        executor.shutdownNow();
        super.onDestroy();
    }

    private ScrollView buildContentView() {
        int padding = (int) (24 * getResources().getDisplayMetrics().density);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(padding, padding, padding, padding);

        TextView title = new TextView(this);
        title.setText("HAND-Score Hexagon");
        title.setTextSize(22);
        root.addView(title, matchWrap());

        statusView = new TextView(this);
        statusView.setTextSize(14);
        statusView.setPadding(0, padding / 2, 0, padding / 2);
        root.addView(statusView, matchWrap());

        buttonGroup = new LinearLayout(this);
        buttonGroup.setOrientation(LinearLayout.VERTICAL);
        root.addView(buttonGroup, matchWrap());

        addButton("Run Exp A", () -> run("Exp A", BenchmarkProtocolRunner::runExperimentA));
        addButton("Run Exp C", () -> run("Exp C", BenchmarkProtocolRunner::runExperimentC));
        addButton("Run Exp E", () -> run("Exp E", BenchmarkProtocolRunner::runExperimentE));
        addButton("Run All", () -> run("All", BenchmarkProtocolRunner::runAll));

        ScrollView scrollView = new ScrollView(this);
        scrollView.addView(root, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
        ));
        return scrollView;
    }

    private void addButton(String label, Runnable action) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setOnClickListener(view -> action.run());
        buttonGroup.addView(button, matchWrap());
    }

    private void loadDatasetSummary() {
        executor.execute(() -> {
            try {
                ChatAlpacaDataset dataset = ChatAlpacaDataset.load(this);
                File resultRoot = ResultStore.resultsRoot(this);
                postStatus(
                        "Dataset " + dataset.version
                                + " | single " + dataset.singleTurn.size()
                                + " | multi " + dataset.multiTurn.size()
                                + "\nResults: " + resultRoot.getAbsolutePath()
                                + "\nBackend: replace BackendFactory with the Hexagon/QNN backend for paper measurements."
                );
            } catch (Exception error) {
                postStatus("Dataset load failed: " + error.getMessage());
            }
        });
    }

    private void run(String label, RunnerCall call) {
        setButtonsEnabled(false);
        postStatus(label + " started");
        executor.execute(() -> {
            try {
                BenchmarkProtocolRunner runner = new BenchmarkProtocolRunner(
                        this,
                        BenchmarkOptions.defaults(this),
                        this::postStatus
                );
                int files = call.run(runner);
                postStatus(label + " completed | files " + files);
            } catch (Exception error) {
                postStatus(label + " failed: " + error.getMessage());
            } finally {
                mainHandler.post(() -> setButtonsEnabled(true));
            }
        });
    }

    private void postStatus(String message) {
        mainHandler.post(() -> statusView.setText(message));
    }

    private void setButtonsEnabled(boolean enabled) {
        for (int i = 0; i < buttonGroup.getChildCount(); i++) {
            buttonGroup.getChildAt(i).setEnabled(enabled);
        }
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
        );
    }

    private interface RunnerCall {
        int run(BenchmarkProtocolRunner runner) throws Exception;
    }
}
